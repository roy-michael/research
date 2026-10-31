import os
import sys
import glob
import warnings
import numpy as np
import scipy.signal as signal
from scipy.io import wavfile
import torch
import torch.nn as nn
import torch.optim as optim
from torch.distributions import Normal
import gymnasium as gym
from gymnasium import spaces
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

# Import the exact Python port of SpectralEngine.m & BandwidthTracker.m
SIM_BELLHOP_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'research', 'simulate_bellhop'))
if SIM_BELLHOP_DIR not in sys.path:
    sys.path.insert(0, SIM_BELLHOP_DIR)

from bandwidth_tracker import (
    DEFAULT_BW_CONFIG,
    compute_welch_psd,
    segment_macro_lobes,
    compute_single_slice_watershed_bandwidth,
)

warnings.filterwarnings('ignore')

# Set random seeds for reproducibility
np.random.seed(42)
torch.manual_seed(42)


# ==============================================================================
# 1. REAL DATASET CONFIGURATION & FAST MEMORY-MAPPED WAV LOADER
# ==============================================================================
REAL_DATASET_CONFIGS = [
    {
        'name': 'HaifaBay',
        'rel_path': r'20250805_Haifa_bay_LME\extracted-2',
        'is_surface': 1,
        'dataset_id': 0,
        'f_low': 0.0,
        'f_high': 2000.0,
        'theta_g': np.deg2rad(2.5),
        'max_vz': 1.85,
        'fw_est': 0.22,
    },
    {
        'name': 'Croatia',
        'rel_path': r'Croatia\wav\merged',
        'is_surface': 0,
        'dataset_id': 1,
        'f_low': 400.0,
        'f_high': 2000.0,
        'theta_g': np.deg2rad(12.0),
        'max_vz': 0.35,
        'fw_est': 0.15,
    },
    {
        'name': 'AUV',
        'rel_path': r'AUVExp_1_26',
        'is_surface': 0,
        'dataset_id': 2,
        'f_low': 400.0,
        'f_high': 2000.0,
        'theta_g': np.deg2rad(14.0),
        'max_vz': 0.25,
        'fw_est': 0.12,
    },
]


def load_real_wav_segment(filepath, start_sec, duration_sec=30.0, target_fs=4800.0):
    """
    Memory-maps a WAV file on disk, extracts a `duration_sec` slice starting at
    `start_sec`, normalizes to zero-mean unit-variance, and resamples to `target_fs`.
    """
    fs, data = wavfile.read(filepath, mmap=True)
    n_samples = int(duration_sec * fs)
    max_start = max(0, len(data) - n_samples)
    start_idx = min(max(0, int(start_sec * fs)), max_start)

    chunk = data[start_idx: start_idx + n_samples]
    if chunk.ndim > 1:
        chunk = chunk[:, 0]

    sig = chunk.astype(np.float64)
    sig -= np.mean(sig)
    std = np.std(sig)
    if std > 1e-12:
        sig /= std

    if abs(fs - target_fs) > 1.0:
        gcd = np.gcd(int(target_fs), int(fs))
        up = int(target_fs) // gcd
        down = int(fs) // gcd
        sig = signal.resample_poly(sig, up, down)

    sig -= np.mean(sig)
    sig /= (np.std(sig) + 1e-12)
    return sig.astype(np.float32), float(target_fs)


def synthesize_vessel_audio(f0=400.0, duration=30.0, fs=4800.0, is_surface_boat=True):
    """Fallback synthetic audio generator if `D:\\RoyStudies\\Recordings` is not mounted."""
    t = np.arange(0, duration, 1.0 / fs)
    if is_surface_boat:
        inst_freq_dev = 18.0 * np.sin(2 * np.pi * 0.22 * t) + 14.0 * np.random.randn(len(t))
        win = int(fs * 0.05)
        inst_freq_dev = np.convolve(inst_freq_dev, np.ones(win) / win, mode='same')
        phase = 2 * np.pi * f0 * t + 2 * np.pi * np.cumsum(inst_freq_dev) / fs
        env = np.clip(1.0 + 0.65 * np.sin(2 * np.pi * 0.22 * t) + 0.35 * np.random.randn(len(t)), 0.1, 2.5)
    else:
        inst_freq_dev = 0.5 * np.sin(2 * np.pi * 0.08 * t) + 1.2 * np.random.randn(len(t))
        win = int(fs * 0.10)
        inst_freq_dev = np.convolve(inst_freq_dev, np.ones(win) / win, mode='same')
        phase = 2 * np.pi * f0 * t + 2 * np.pi * np.cumsum(inst_freq_dev) / fs
        env = np.ones_like(t)
    sig = env * np.cos(phase) + 0.25 * np.random.randn(len(t))
    sig = (sig - np.mean(sig)) / (np.std(sig) + 1e-8)
    return sig.astype(np.float32), float(fs)


# ==============================================================================
# 2. OFFLINE DSP (WATERSHED BW + 0.5s DIGITAL PLL PHASE LOCK) FEATURE PIPELINE
# ==============================================================================
class OfflineFeatureExtractor:
    """
    Runs once per 30-second real audio recording prior to RL training.
    Matches the exact `research-clean` MATLAB pipeline:
      1. High-resolution Welch PSD + Topographic Macro-Lobe Segmentation (`dom_lobe`)
      2. 0.5-second Slice Windowed-FFT Topographic Watershed Bandwidth (`main_f`, `main_bw`)
      3. Per-0.5-second Segment Dominant-Frequency 2nd-Order Digital PLL Phase Lock:
         - Phase Locking Value R in [0, 1] (`plv_r`)
         - PLL Instantaneous Frequency Spread sigma_f (`inst_freq_std`, Hz)
         - Instantaneous Frequency Verification Error |f_PLL - f_FFT| (`freq_verif_err`, Hz)
         - Hilbert Envelope MASD & Coherence Time T_c
    """

    def __init__(self, fs=4800.0, buffer_sec=0.5, tol_hz=15.0):
        self.fs = fs
        self.buffer_sec = buffer_sec
        self.samples_per_buf = int(round(fs * buffer_sec))
        self.tol_hz = tol_hz

    @staticmethod
    def compute_jains_index(values):
        x = np.asarray(values, dtype=np.float64)
        x = x[np.isfinite(x) & (x > 0)]
        if len(x) == 0:
            return 1.0
        s_val = np.sum(x)
        s_sq = np.sum(x ** 2)
        return float((s_val ** 2) / (len(x) * s_sq)) if s_sq > 0 else 1.0

    @staticmethod
    def compute_masd(env):
        return float(np.mean(np.abs(np.diff(env))))

    def compute_coherence_time(self, env):
        env_zm = env - np.mean(env)
        norm = np.sum(env_zm ** 2)
        if norm < 1e-10:
            return self.buffer_sec
        acf = np.correlate(env_zm, env_zm, mode='full')[len(env_zm) - 1:] / norm
        below_half = np.where(acf < 0.5)[0]
        if len(below_half) == 0:
            return self.buffer_sec
        return float(below_half[0] / self.fs)

    def run_slice_digital_pll(self, full_sig, slice_start, slice_len, f_dom, bw_m, f_low, f_high):
        """
        Runs the 2nd-order quadrature Digital PLL on a single 0.5-second segment locked to
        that 0.5-second segment's dominant frequency `f_dom` (matching BandwidthTracker.m).
        """
        N_total = len(full_sig)
        nyq = 0.5 * self.fs
        f_low_lim = max(5.0, float(f_low))
        f_high_lim = min(nyq - 10.0, float(f_high))
        f_dom_clamped = float(np.clip(f_dom, f_low_lim + 5.0, f_high_lim - 5.0))

        pad_len = min(int(round(0.05 * self.fs)), slice_len // 4)
        i_pad1 = max(0, slice_start - pad_len)
        i_pad2 = min(N_total, slice_start + slice_len + pad_len)
        sig_pad = full_sig[i_pad1:i_pad2]

        bp_margin_hz = 80.0
        eff_margin = min(bp_margin_hz, max(16.0, 0.70 * bw_m))
        max_sym_margin = min(max(12.0, f_dom_clamped - f_low_lim), max(12.0, f_high_lim - f_dom_clamped))
        eff_margin = min(eff_margin, max_sym_margin)

        bp_low = max(f_low_lim, f_dom_clamped - eff_margin)
        bp_high = min(f_high_lim, f_dom_clamped + eff_margin)
        if bp_low >= bp_high - 2.0:
            bp_low = max(5.0, f_dom_clamped - 25.0)
            bp_high = min(nyq - 5.0, f_dom_clamped + 25.0)

        try:
            b_bp, a_bp = signal.butter(2, [bp_low / nyq, bp_high / nyq], btype='bandpass')
            filt_pad = signal.filtfilt(b_bp, a_bp, sig_pad)
        except Exception:
            filt_pad = sig_pad

        z_pad = signal.hilbert(filt_pad)
        env_raw = np.abs(z_pad)
        env_win = max(16, int(round(0.08 * self.fs)))
        local_env = np.convolve(env_raw, np.ones(env_win) / env_win, mode='same')
        rms_floor = 0.20 * float(np.median(env_raw)) + 1e-12
        z_norm = z_pad / np.maximum(local_env, rms_floor)

        trim_start = slice_start - i_pad1
        z_slice = z_norm[trim_start: trim_start + slice_len]
        env_slice = env_raw[trim_start: trim_start + slice_len]
        real_sig = np.clip(np.real(z_slice), -1.5, 1.5)
        imag_sig = np.clip(np.imag(z_slice), -1.5, 1.5)

        loop_bw_hz = 18.0
        zeta = 0.707
        max_freq_dev_hz = 60.0
        wn = 2.0 * np.pi * loop_bw_hz / (zeta + 1.0 / (4.0 * zeta))
        kp = (2.0 * zeta * wn) / self.fs
        ki = (wn * wn) / (self.fs * self.fs)

        two_pi = 2.0 * np.pi
        w_center_m = two_pi * f_dom_clamped / self.fs
        max_dev_rad = two_pi * max_freq_dev_hz / self.fs
        fs_over_2pi = self.fs / two_pi

        phase_raw = np.zeros(slice_len, dtype=np.float64)
        pe_track = np.zeros(slice_len, dtype=np.float64)
        freq_out = np.zeros(slice_len, dtype=np.float64)

        phase = float(np.arctan2(imag_sig[0], real_sig[0]))
        freq_integrator = 0.0

        for i in range(slice_len):
            c_p = np.cos(phase)
            s_p = np.sin(phase)
            err_sin = imag_sig[i] * c_p - real_sig[i] * s_p
            err_cos = real_sig[i] * c_p + imag_sig[i] * s_p
            pe = err_sin
            pe_track[i] = np.arctan2(err_sin, err_cos)

            freq_integrator = np.clip(freq_integrator + ki * pe, -max_dev_rad, max_dev_rad)
            freq_ctrl = np.clip(kp * pe + freq_integrator, -max_dev_rad, max_dev_rad)

            phase += w_center_m + freq_ctrl
            phase_raw[i] = phase
            freq_out[i] = (w_center_m + freq_ctrl) * fs_over_2pi

        f_mean_slice = float(np.mean(freq_out))
        f_std_slice = float(np.std(freq_out))
        freq_verif_err = abs(f_mean_slice - f_dom_clamped)

        local_t_idx = np.arange(slice_len, dtype=np.float64)
        w_slice = two_pi * f_mean_slice / self.fs
        phi_nco_dev = (phase_raw - phase_raw[0]) - w_slice * local_t_idx
        phi_seg = np.mod(phi_nco_dev + pe_track + np.pi, two_pi) - np.pi

        mc = float(np.mean(np.cos(phi_seg)))
        ms = float(np.mean(np.sin(phi_seg)))
        plv_r = float(np.hypot(mc, ms))
        phi_mean = float(np.arctan2(ms, mc))
        phi_centered = np.mod(phi_seg - phi_mean + np.pi, two_pi) - np.pi
        phase_std_rad = float(np.std(phi_centered))

        return plv_r, f_mean_slice, f_std_slice, freq_verif_err, phase_std_rad, env_slice

    def extract_recording_features(self, audio_sig, f_low=0.0, f_high=2000.0):
        """
        Extracts 60 steps (0.5s each) of exact Watershed Bandwidth + Digital PLL features
        from a 30-second recording.
        """
        cfg = dict(DEFAULT_BW_CONFIG)
        cfg['f_low'] = float(f_low)
        cfg['f_high'] = float(min(f_high, 0.5 * self.fs - 10.0))
        cfg['slice_dur_sec'] = self.buffer_sec
        cfg['tib_tolerance_hz'] = self.tol_hz

        psd_db, f_grid, df, _ = compute_welch_psd(
            audio_sig, self.fs, cfg['f_low'], cfg['f_high'], cfg['twin_welch'], cfg['df_eval']
        )
        _, dom_lobe, _, _ = segment_macro_lobes(psd_db, f_grid, df, cfg['prom_split_db'])

        num_buffers = len(audio_sig) // self.samples_per_buf
        buffer_features = []

        for j in range(num_buffers):
            slice_start = j * self.samples_per_buf
            seg = audio_sig[slice_start: slice_start + self.samples_per_buf]

            s_out = compute_single_slice_watershed_bandwidth(seg, self.fs, dom_lobe, cfg)
            if s_out['found'] and np.isfinite(s_out['main_bw']) and s_out['main_bw'] > 0:
                f_dom = float(s_out['main_f'])
                bw_measured = float(s_out['main_bw'])
            else:
                f_dom = float(dom_lobe['peak_freq'])
                bw_measured = float(max(10.0, dom_lobe['bandwidth']))

            plv_r, f_pll_mean, f_pll_std, verif_err, phase_std_rad, env_slice = self.run_slice_digital_pll(
                audio_sig, slice_start, self.samples_per_buf, f_dom, bw_measured, cfg['f_low'], cfg['f_high']
            )

            env_norm = env_slice / (np.mean(env_slice) + 1e-8)
            masd_val = self.compute_masd(env_norm)
            tc_val = self.compute_coherence_time(env_norm)

            buffer_features.append({
                'f_dom': f_dom,
                'f_pll': f_pll_mean,
                'bw_measured': bw_measured,
                'plv_r': plv_r,
                'inst_freq_std': f_pll_std,
                'freq_verif_err': verif_err,
                'phase_std_rad': phase_std_rad,
                'masd': masd_val,
                'coherence_time': tc_val,
            })

        f_doms = np.array([b['f_dom'] for b in buffer_features], dtype=np.float64)
        bws = np.array([b['bw_measured'] for b in buffer_features], dtype=np.float64)
        plvs = np.array([b['plv_r'] for b in buffer_features], dtype=np.float64)
        f_stds = np.array([b['inst_freq_std'] for b in buffer_features], dtype=np.float64)

        med_k = min(9, len(bws) if len(bws) % 2 == 1 else max(1, len(bws) - 1))
        bws_med = signal.medfilt(bws, kernel_size=med_k) if med_k >= 3 else bws.copy()
        plvs_med = signal.medfilt(plvs, kernel_size=med_k) if med_k >= 3 else plvs.copy()

        state_sequence = []
        prev_jain = 1.0
        for j in range(num_buffers):
            win_start = max(0, j - 11)
            bw_win = bws_med[win_start: j + 1]
            plv_win = plvs_med[win_start: j + 1]
            fstd_win = f_stds[win_start: j + 1]
            df_dt = float(abs(f_doms[j] - f_doms[j - 1])) if j > 0 else 0.0

            med_bw = float(np.median(bw_win))
            time_in_band = float(np.mean(np.abs(bw_win - med_bw) <= self.tol_hz))

            jain_val = self.compute_jains_index(bw_win)
            djain_dt = float(abs(jain_val - prev_jain)) if j > 0 else 0.0
            prev_jain = jain_val

            bw_mean = float(np.mean(bw_win))
            bw_std = float(np.std(bw_win))
            plv_mean = float(np.mean(plv_win))
            fstd_mean = float(np.mean(fstd_win))

            s_t = np.array([
                (time_in_band - 0.75) * 4.0,
                (jain_val - 0.94) * 15.0,
                djain_dt * 20.0,
                (bw_mean - 55.0) / 35.0,
                (bw_std - 20.0) / 20.0,
                (buffer_features[j]['masd'] - 0.15) * 8.0,
                (plv_mean - 0.36) * 5.0,
                (fstd_mean - 11.5) / 3.5
            ], dtype=np.float32)

            state_sequence.append({
                's_t': s_t,
                'tib': time_in_band,
                'jain': jain_val,
                'df_dt': df_dt,
                'bw_measured': buffer_features[j]['bw_measured'],
                'bw_mean': bw_mean,
                'f_dom': buffer_features[j]['f_dom'],
                'f_pll': buffer_features[j]['f_pll'],
                'plv_r': buffer_features[j]['plv_r'],
                'inst_freq_std': buffer_features[j]['inst_freq_std'],
                'freq_verif_err': buffer_features[j]['freq_verif_err'],
                'phase_std_rad': buffer_features[j]['phase_std_rad'],
                'coherence_time': buffer_features[j]['coherence_time'],
            })

        return state_sequence, dom_lobe


def build_train_test_real_datasets(base_dir=r'D:\RoyStudies\Recordings',
                                   train_eps_per_dataset=18,
                                   test_eps_per_dataset=6,
                                   duration_sec=30.0,
                                   target_fs=4800.0):
    """
    Builds a strict FILE-LEVEL Train / Test split across HaifaBay, Croatia, and AUV:
      - WAV files in each dataset are partitioned into disjoint Train WAV files (~70-75%)
        and Held-Out Test WAV files (~25-30%).
      - No WAV file is shared between `train_dataset` and `test_dataset`, preventing
        any temporal or file-level data leakage.
    """
    extractor = OfflineFeatureExtractor(fs=target_fs, buffer_sec=0.5, tol_hz=15.0)
    train_dataset = []
    test_dataset = []

    def _sample_from_files(file_list, num_eps, cfg, split_label):
        recs = []
        for k in range(num_eps):
            wf = file_list[k % len(file_list)]
            fs_hdr, data_mmap = wavfile.read(wf, mmap=True)
            total_sec = len(data_mmap) / float(fs_hdr)
            usable_sec = max(1.0, total_sec - duration_sec - 10.0)
            n_per_file = max(1, (num_eps + len(file_list) - 1) // len(file_list))
            slot = k // len(file_list)
            frac = (slot + 0.5) / float(n_per_file)
            start_sec = 5.0 + frac * usable_sec

            sig, _ = load_real_wav_segment(wf, start_sec=start_sec, duration_sec=duration_sec, target_fs=target_fs)
            steps, dom_lobe = extractor.extract_recording_features(sig, f_low=cfg['f_low'], f_high=cfg['f_high'])

            meta = {
                'dataset_name': cfg['name'],
                'dataset_id': cfg['dataset_id'],
                'is_surface': cfg['is_surface'],
                'f0_true': float(dom_lobe['peak_freq']),
                'fw_est': cfg['fw_est'],
                'theta_g': cfg['theta_g'],
                'max_vz': cfg['max_vz'],
                'source_file': os.path.basename(wf),
                'start_sec': start_sec,
                'split': split_label,
            }
            recs.append({'steps': steps, 'metadata': meta})
        return recs

    for cfg in REAL_DATASET_CONFIGS:
        ds_dir = os.path.join(base_dir, cfg['rel_path'])
        wav_files = sorted(glob.glob(os.path.join(ds_dir, '**', '*.wav'), recursive=True))

        if not wav_files:
            print(f"  [Warning] No WAV files found in {ds_dir}; using synthetic fallback for {cfg['name']}.")
            for split_label, num_eps, target_list in [
                ('train', train_eps_per_dataset, train_dataset),
                ('test', test_eps_per_dataset, test_dataset),
            ]:
                for _ in range(num_eps):
                    sig, _ = synthesize_vessel_audio(
                        f0=170.0 if cfg['is_surface'] else 720.0,
                        duration=duration_sec,
                        fs=target_fs,
                        is_surface_boat=bool(cfg['is_surface'])
                    )
                    steps, dom_lobe = extractor.extract_recording_features(sig, f_low=cfg['f_low'], f_high=cfg['f_high'])
                    meta = {
                        'dataset_name': cfg['name'],
                        'dataset_id': cfg['dataset_id'],
                        'is_surface': cfg['is_surface'],
                        'f0_true': float(dom_lobe['peak_freq']),
                        'fw_est': cfg['fw_est'],
                        'theta_g': cfg['theta_g'],
                        'max_vz': cfg['max_vz'],
                        'split': split_label,
                    }
                    target_list.append({'steps': steps, 'metadata': meta})
            continue

        # Partition WAV files strictly into disjoint Train files (75%) and Test files (25%)
        n_files = len(wav_files)
        n_test_files = max(2, int(round(0.25 * n_files))) if n_files >= 4 else 1
        n_train_files = max(1, n_files - n_test_files)
        train_files = wav_files[:n_train_files]
        test_files = wav_files[n_train_files:]

        print(
            f"  -> {cfg['name']:<9}: {n_files:2d} WAV files split into "
            f"{len(train_files):2d} Train files ({train_eps_per_dataset} eps) & "
            f"{len(test_files):2d} Held-Out Test files ({test_eps_per_dataset} eps)..."
        )
        train_dataset.extend(_sample_from_files(train_files, train_eps_per_dataset, cfg, 'train'))
        test_dataset.extend(_sample_from_files(test_files, test_eps_per_dataset, cfg, 'test'))

    return train_dataset, test_dataset


# ==============================================================================
# 3. GYMNASIUM RL ENVIRONMENT (PIML REWARD & CPO HARD CONSTRAINTS ON REAL DATA)
# ==============================================================================
class AcousticPIMLEnv(gym.Env):
    """
    RL Environment operating on real pre-extracted DSP + 0.5s Digital PLL feature vectors s_t
    from HaifaBay (Surface), Croatia (Submerged DPV), and AUV (Submerged AUV).
    Action a_t = [delta_fc_track, bw_gate_scaled, surface_vs_submerged_logit]
    """

    def __init__(self, dataset, balanced_sampling=True):
        super().__init__()
        self.dataset = dataset
        self.balanced_sampling = balanced_sampling
        self.surface_indices = [i for i, d in enumerate(dataset) if d['metadata']['is_surface'] == 1]
        self.submerged_indices = [i for i, d in enumerate(dataset) if d['metadata']['is_surface'] == 0]

        self.current_rec = None
        self.step_idx = 0

        self.action_space = spaces.Box(
            low=np.array([-5.0, -5.0, -5.0], dtype=np.float32),
            high=np.array([5.0, 5.0, 5.0], dtype=np.float32)
        )

        self.observation_space = spaces.Box(
            low=-np.inf, high=np.inf, shape=(8,), dtype=np.float32
        )

    def reset(self, seed=None, options=None):
        super().reset(seed=seed)
        if options and 'rec_idx' in options:
            idx = options['rec_idx']
        elif self.balanced_sampling and self.surface_indices and self.submerged_indices:
            if np.random.rand() < 0.5:
                idx = int(np.random.choice(self.surface_indices))
            else:
                idx = int(np.random.choice(self.submerged_indices))
        else:
            idx = np.random.randint(0, len(self.dataset))

        self.current_rec = self.dataset[idx]
        self.step_idx = 0
        return self.current_rec['steps'][0]['s_t'], {}

    def step(self, action):
        step_data = self.current_rec['steps'][self.step_idx]
        meta = self.current_rec['metadata']
        s_t = step_data['s_t']

        delta_f_action = float(np.clip(action[0], -5.0, 5.0))
        bw_act_norm = float(np.clip(action[1], -5.0, 5.0))
        bw_action_hz = 70.0 + 12.0 * bw_act_norm
        class_logit = float(np.clip(action[2], -5.0, 5.0))
        pred_is_surface = 1 if class_logit > 0.0 else 0

        # ------------------------------------------------------------------
        # A. PHYSICS-INFORMED REWARD (R_t) USING REAL WATERSHED + PLL METRICS
        # ------------------------------------------------------------------
        plv_r = float(step_data['plv_r'])
        sigma_f_hz = float(step_data['inst_freq_std'])
        bw_sliding_hz = float(step_data['bw_mean'])
        tib_val = float(step_data['tib'])

        carson_pll_hz = 2.0 * (sigma_f_hz / max(0.20, plv_r) + meta['fw_est'])
        target_bw_hz = float(np.clip(0.75 * bw_sliding_hz + 0.25 * carson_pll_hz, 12.0, 125.0))
        bw_fit_reward = float(np.exp(-0.04 * abs(bw_action_hz - target_bw_hz)))

        phys_surface_score = float(s_t[3]) - 0.35 * float(s_t[6]) - 0.25 * float(s_t[0])
        physics_alignment = 1.0 if (
            (phys_surface_score >= 0.0 and pred_is_surface == 1) or
            (phys_surface_score < 0.0 and pred_is_surface == 0)
        ) else -0.5

        y_sign = 1.0 if meta['is_surface'] == 1 else -1.0
        margin_reward = 0.5 * float(np.tanh(y_sign * class_logit))
        class_reward = (2.0 if pred_is_surface == meta['is_surface'] else -2.0) + margin_reward

        reward = float(bw_fit_reward + physics_alignment + class_reward)

        # ------------------------------------------------------------------
        # B. CPO HARD PHYSICAL CONSTRAINTS (Cost C_t <= d)
        # ------------------------------------------------------------------
        c_sound = 1500.0
        max_doppler_shift = (2.0 * max(150.0, meta['f0_true']) / c_sound) * np.sin(meta['theta_g']) * meta['max_vz'] + 2.2
        kinematic_violation = 1.0 if abs(delta_f_action) > max_doppler_shift else 0.0

        coherence_violation = 1.0 if (
            (bw_sliding_hz < 45.0 and bw_action_hz > 68.0) or
            (bw_sliding_hz > 75.0 and bw_action_hz < 35.0)
        ) else 0.0

        cost = float(max(kinematic_violation, coherence_violation))

        self.step_idx += 1
        terminated = self.step_idx >= len(self.current_rec['steps'])
        next_state = (
            self.current_rec['steps'][self.step_idx]['s_t']
            if not terminated else np.zeros(8, dtype=np.float32)
        )

        info = {
            'cost': cost,
            'correct': int(pred_is_surface == meta['is_surface']),
            'dataset_name': meta['dataset_name'],
            'bw_action_hz': bw_action_hz,
            'target_bw_hz': target_bw_hz,
            'plv_r': plv_r,
            'tib': tib_val,
            'freq_verif_err': float(step_data['freq_verif_err']),
        }
        return next_state, reward, terminated, False, info


# ==============================================================================
# 4. PPO / LAGRANGIAN-CPO AGENT ARCHITECTURE
# ==============================================================================
class PIMLActorCritic(nn.Module):
    def __init__(self, state_dim=8, action_dim=3, hidden_dim=64):
        super().__init__()
        self.shared = nn.Sequential(
            nn.Linear(state_dim, hidden_dim),
            nn.Tanh(),
            nn.Linear(hidden_dim, hidden_dim),
            nn.Tanh()
        )
        self.actor_mu = nn.Linear(hidden_dim, action_dim)
        nn.init.zeros_(self.actor_mu.bias)
        self.actor_log_std = nn.Parameter(torch.zeros(1, action_dim) - 0.35)

        self.reward_critic = nn.Sequential(
            nn.Linear(state_dim, hidden_dim),
            nn.Tanh(),
            nn.Linear(hidden_dim, 1)
        )
        self.cost_critic = nn.Sequential(
            nn.Linear(state_dim, hidden_dim),
            nn.Tanh(),
            nn.Linear(hidden_dim, 1)
        )

    def get_action_and_values(self, state, action=None, deterministic=False):
        features = self.shared(state)
        mu = self.actor_mu(features)
        std = torch.exp(self.actor_log_std)
        dist = Normal(mu, std)

        if action is None:
            action = mu if deterministic else dist.sample()

        log_prob = dist.log_prob(action).sum(dim=-1)
        entropy = dist.entropy().sum(dim=-1)
        v_r = self.reward_critic(state).squeeze(-1)
        v_c = self.cost_critic(state).squeeze(-1)
        return action, log_prob, entropy, v_r, v_c


def train_piml_agent(env, mode='CPO', epochs=45, steps_per_epoch=480, cost_limit=0.05, seed=42):
    np.random.seed(seed)
    torch.manual_seed(seed)

    model = PIMLActorCritic()
    optimizer = optim.Adam(model.parameters(), lr=8e-4)

    log_lambda = torch.tensor(-0.5, requires_grad=True)
    lambda_optimizer = optim.Adam([log_lambda], lr=8e-2)

    clip_eps = 0.2
    gamma = 0.99

    history = {'reward': [], 'cost': [], 'accuracy': []}

    for epoch in range(epochs):
        states, actions, log_probs, rewards, costs, dones, accs = [], [], [], [], [], [], []
        state, _ = env.reset()

        for _ in range(steps_per_epoch):
            s_tensor = torch.FloatTensor(state).unsqueeze(0)
            with torch.no_grad():
                action, log_prob, _, _, _ = model.get_action_and_values(s_tensor)

            act_np = action.squeeze(0).numpy()
            next_state, reward, terminated, truncated, info = env.step(act_np)
            done = terminated or truncated

            states.append(state)
            actions.append(act_np)
            log_probs.append(log_prob.item())
            rewards.append(reward)
            costs.append(info['cost'])
            dones.append(done)
            accs.append(info['correct'])

            state = next_state if not done else env.reset()[0]

        returns_r, returns_c = [], []
        R_acc, C_acc = 0.0, 0.0
        for r, c, d in zip(reversed(rewards), reversed(costs), reversed(dones)):
            if d:
                R_acc, C_acc = 0.0, 0.0
            R_acc = r + gamma * R_acc
            C_acc = c + gamma * C_acc
            returns_r.insert(0, R_acc)
            returns_c.insert(0, C_acc)

        states_t = torch.FloatTensor(np.array(states))
        actions_t = torch.FloatTensor(np.array(actions))
        old_log_probs_t = torch.FloatTensor(np.array(log_probs))
        returns_r_t = torch.FloatTensor(returns_r)
        returns_c_t = torch.FloatTensor(returns_c)

        with torch.no_grad():
            _, _, _, v_r_old, v_c_old = model.get_action_and_values(states_t, actions_t)
            adv_r = returns_r_t - v_r_old
            adv_r = (adv_r - adv_r.mean()) / (adv_r.std() + 1e-8)

            adv_c = returns_c_t - v_c_old
            adv_c = (adv_c - adv_c.mean()) / (adv_c.std() + 1e-8)

        avg_ep_cost = float(np.mean(costs))

        if mode == 'CPO':
            lambda_loss = -log_lambda.exp() * (avg_ep_cost - cost_limit)
            lambda_optimizer.zero_grad()
            lambda_loss.backward()
            lambda_optimizer.step()
            with torch.no_grad():
                log_lambda.clamp_(-4.0, 3.0)
            lam = float(log_lambda.exp().item())
        else:
            lam = 0.05

        for _ in range(8):
            _, new_log_probs, entropy, v_r_pred, v_c_pred = model.get_action_and_values(states_t, actions_t)
            ratio = torch.exp(new_log_probs - old_log_probs_t)

            surr1_r = ratio * adv_r
            surr2_r = torch.clamp(ratio, 1.0 - clip_eps, 1.0 + clip_eps) * adv_r
            policy_reward_loss = -torch.min(surr1_r, surr2_r).mean()

            policy_cost_loss = (ratio * adv_c).mean()

            actor_loss = (policy_reward_loss + lam * policy_cost_loss) / (1.0 + lam)
            critic_loss = 0.5 * ((v_r_pred - returns_r_t) ** 2).mean() + 0.5 * ((v_c_pred - returns_c_t) ** 2).mean()
            total_loss = actor_loss + critic_loss - 0.01 * entropy.mean()

            optimizer.zero_grad()
            total_loss.backward()
            nn.utils.clip_grad_norm_(model.parameters(), 0.5)
            optimizer.step()

        history['reward'].append(float(np.mean(rewards)))
        history['cost'].append(avg_ep_cost)
        history['accuracy'].append(float(np.mean(accs) * 100.0))

    return model, history


def evaluate_agent_by_dataset(env, model):
    """Evaluates a trained policy deterministically across every recording in `env`."""
    per_ds = {}
    for rec_idx, rec in enumerate(env.dataset):
        ds_name = rec['metadata']['dataset_name']
        if ds_name not in per_ds:
            per_ds[ds_name] = {'correct': [], 'cost': [], 'reward': [], 'bw_gate_hz': [], 'target_bw_hz': []}

        state, _ = env.reset(options={'rec_idx': rec_idx})
        done = False
        while not done:
            s_tensor = torch.FloatTensor(state).unsqueeze(0)
            with torch.no_grad():
                action, _, _, _, _ = model.get_action_and_values(s_tensor, deterministic=True)
            act_np = action.squeeze(0).numpy()
            state, reward, terminated, truncated, info = env.step(act_np)
            done = terminated or truncated

            per_ds[ds_name]['correct'].append(info['correct'])
            per_ds[ds_name]['cost'].append(info['cost'])
            per_ds[ds_name]['reward'].append(reward)
            per_ds[ds_name]['bw_gate_hz'].append(info['bw_action_hz'])
            per_ds[ds_name]['target_bw_hz'].append(info['target_bw_hz'])

    summary = {}
    for ds_name, vals in per_ds.items():
        summary[ds_name] = {
            'accuracy': float(np.mean(vals['correct']) * 100.0),
            'cost': float(np.mean(vals['cost'])),
            'reward': float(np.mean(vals['reward'])),
            'bw_gate_hz': float(np.mean(vals['bw_gate_hz'])),
            'target_bw_hz': float(np.mean(vals['target_bw_hz'])),
        }
    return summary


# ==============================================================================
# 5. MAIN EXECUTION: DISJOINT FILE-LEVEL TRAIN/TEST SPLIT, TRAIN & EVALUATE
# ==============================================================================
if __name__ == '__main__':
    print("=" * 100)
    print("PHYSICS-INFORMED DRL PIPELINE ON REAL ACOUSTIC DATASETS (DISJOINT FILE-LEVEL TRAIN / TEST SPLIT)")
    print("=" * 100)
    print("[1/4] Building Disjoint Train (75%) & Held-Out Test (25%) Datasets (0.5s Watershed + Digital PLL)...")

    train_dataset, test_dataset = build_train_test_real_datasets(
        base_dir=r'D:\RoyStudies\Recordings',
        train_eps_per_dataset=18,
        test_eps_per_dataset=6,
        duration_sec=30.0,
        target_fs=4800.0
    )

    print("\n" + "-" * 100)
    print("EXTRACTED REAL DATASET FEATURE SUMMARY (TRAIN: 54 eps / 3240 slices | TEST: 18 eps / 1080 slices)")
    print("-" * 100)
    for cfg in REAL_DATASET_CONFIGS:
        ds_name = cfg['name']
        tr_recs = [d for d in train_dataset if d['metadata']['dataset_name'] == ds_name]
        te_recs = [d for d in test_dataset if d['metadata']['dataset_name'] == ds_name]
        all_steps = [s for d in (tr_recs + te_recs) for s in d['steps']]
        f_dom_m = np.mean([s['f_dom'] for s in all_steps])
        bw_m = np.mean([s['bw_measured'] for s in all_steps])
        plv_m = np.mean([s['plv_r'] for s in all_steps])
        fstd_m = np.mean([s['inst_freq_std'] for s in all_steps])
        verr_m = np.mean([s['freq_verif_err'] for s in all_steps])
        tib_m = np.mean([s['tib'] for s in all_steps])
        jain_m = np.mean([s['jain'] for s in all_steps])
        print(
            f"  {ds_name:<9} (Train={len(tr_recs):2d} eps [{len(tr_recs)*60:4d} sl], Test={len(te_recs):2d} eps [{len(te_recs)*60:3d} sl]): "
            f"f_dom={f_dom_m:6.1f} Hz | BW={bw_m:5.1f} Hz | PLL R={plv_m:.3f} | "
            f"sigma_f={fstd_m:4.1f} Hz | |f_PLL-f_FFT|={verr_m:4.2f} Hz | TiB={tib_m:.2f} | Jain={jain_m:.3f}"
        )
    print("-" * 100)

    train_env = AcousticPIMLEnv(train_dataset, balanced_sampling=True)
    test_env = AcousticPIMLEnv(test_dataset, balanced_sampling=False)

    print("\n[2/4] Training Physics-Informed PPO Agent (Soft Constraints) on TRAIN Split Only...")
    ppo_model, ppo_hist = train_piml_agent(train_env, mode='PPO', epochs=45, steps_per_epoch=480, cost_limit=0.05, seed=42)

    print("[3/4] Training Physics-Informed CPO Agent (Hard Constraints C(pi) <= d) on TRAIN Split Only...")
    cpo_model, cpo_hist = train_piml_agent(train_env, mode='CPO', epochs=45, steps_per_epoch=480, cost_limit=0.05, seed=42)

    print("\n[4/4] Evaluating Trained Policies on Disjoint HELD-OUT TEST Files vs. TRAIN Files...")
    ppo_train_eval = evaluate_agent_by_dataset(train_env, ppo_model)
    cpo_train_eval = evaluate_agent_by_dataset(train_env, cpo_model)
    ppo_test_eval = evaluate_agent_by_dataset(test_env, ppo_model)
    cpo_test_eval = evaluate_agent_by_dataset(test_env, cpo_model)

    print("\n" + "=" * 100)
    print("DISJOINT TRAIN vs. HELD-OUT TEST EVALUATION RESULTS (UNSEEN WAV FILES)")
    print("=" * 100)
    print(f"{'Dataset':<10} | {'Policy':<8} | {'Train Acc (%)':<13} | {'Test Acc (%)':<13} | {'Test Viol. Rate':<15} | {'Test BW Gate':<14} | {'Target BW':<10}")
    print("-" * 100)
    for cfg in REAL_DATASET_CONFIGS:
        ds_name = cfg['name']
        p_tr, p_te = ppo_train_eval[ds_name], ppo_test_eval[ds_name]
        c_tr, c_te = cpo_train_eval[ds_name], cpo_test_eval[ds_name]
        print(f"{ds_name:<10} | {'PIML-PPO':<8} | {p_tr['accuracy']:12.1f}% | {p_te['accuracy']:12.1f}% | {p_te['cost']:15.3f} | {p_te['bw_gate_hz']:11.1f} Hz | {p_te['target_bw_hz']:7.1f} Hz")
        print(f"{ds_name:<10} | {'PIML-CPO':<8} | {c_tr['accuracy']:12.1f}% | {c_te['accuracy']:12.1f}% | {c_te['cost']:15.3f} | {c_te['bw_gate_hz']:11.1f} Hz | {c_te['target_bw_hz']:7.1f} Hz")
        print("-" * 100)

    # Plot Training & Held-Out Test Evaluation Comparison
    fig, axes = plt.subplots(2, 2, figsize=(15, 9.5))

    axes[0, 0].plot(ppo_hist['reward'], label='PIML-PPO (Train)', color='royalblue', lw=2)
    axes[0, 0].plot(cpo_hist['reward'], label='PIML-CPO (Train)', color='darkorange', lw=2)
    axes[0, 0].set_title('Physics-Informed Reward ($R_t$) on Train Split', fontweight='bold')
    axes[0, 0].set_xlabel('Epoch')
    axes[0, 0].set_ylabel('Mean Step Reward')
    axes[0, 0].legend()
    axes[0, 0].grid(alpha=0.3)

    axes[0, 1].plot(ppo_hist['cost'], label='PIML-PPO Violations', color='royalblue', lw=2)
    axes[0, 1].plot(cpo_hist['cost'], label='PIML-CPO Violations', color='darkorange', lw=2)
    axes[0, 1].axhline(0.05, color='crimson', linestyle='--', label='Hard Constraint Limit ($d=0.05$)')
    axes[0, 1].set_title('Physical Constraint Violations ($C_t$) — Doppler & PLL Coherence', fontweight='bold')
    axes[0, 1].set_xlabel('Epoch')
    axes[0, 1].set_ylabel('Violation Frequency')
    axes[0, 1].legend()
    axes[0, 1].grid(alpha=0.3)

    axes[1, 0].plot(ppo_hist['accuracy'], label='PIML-PPO (Train)', color='royalblue', lw=2)
    axes[1, 0].plot(cpo_hist['accuracy'], label='PIML-CPO (Train)', color='darkorange', lw=2)
    axes[1, 0].set_title('Surface vs. Submerged Training Accuracy (%)', fontweight='bold')
    axes[1, 0].set_xlabel('Epoch')
    axes[1, 0].set_ylabel('Classification Accuracy (%)')
    axes[1, 0].set_ylim(40, 105)
    axes[1, 0].legend()
    axes[1, 0].grid(alpha=0.3)

    # Panel 4: Held-Out Test Set Evaluation Breakdown (Unseen WAV Files)
    ds_names = [c['name'] for c in REAL_DATASET_CONFIGS]
    x = np.arange(len(ds_names))
    width = 0.34
    ppo_te_accs = [ppo_test_eval[n]['accuracy'] for n in ds_names]
    cpo_te_accs = [cpo_test_eval[n]['accuracy'] for n in ds_names]
    bars1 = axes[1, 1].bar(x - width / 2, ppo_te_accs, width, label='PIML-PPO Held-Out Test (%)', color='royalblue', alpha=0.85)
    bars2 = axes[1, 1].bar(x + width / 2, cpo_te_accs, width, label='PIML-CPO Held-Out Test (%)', color='darkorange', alpha=0.85)
    axes[1, 1].set_xticks(x)
    axes[1, 1].set_xticklabels([f"{n}\n({'Surface' if c['is_surface'] else 'Submerged'})" for n, c in zip(ds_names, REAL_DATASET_CONFIGS)])
    axes[1, 1].set_ylim(0, 115)
    axes[1, 1].set_ylabel('Held-Out Test Accuracy (%)')
    axes[1, 1].set_title('Held-Out Test Set Accuracy on Unseen WAV Files (25% Split)', fontweight='bold')
    for b in list(bars1) + list(bars2):
        h = b.get_height()
        axes[1, 1].annotate(f'{h:.1f}%', xy=(b.get_x() + b.get_width() / 2, h),
                            xytext=(0, 3), textcoords='offset points', ha='center', va='bottom', fontsize=9, fontweight='bold')
    axes[1, 1].legend(loc='lower right')
    axes[1, 1].grid(axis='y', alpha=0.3)

    plt.tight_layout()
    out_fig_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'drl_real_datasets_results.png')
    plt.savefig(out_fig_path, dpi=300)
    print(f"\n[Saved] DRL Disjoint Train/Test Plot: {out_fig_path}")
