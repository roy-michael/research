"""
Offline DSP feature extraction module (`drl.dsp.feature_extractor`):
Combines high-resolution Welch PSD + macro-lobe segmentation, 0.5-second slice
topographic watershed bandwidth tracking, multiscale Time-in-Band (TiB) & Jain's
Fairness scale-uniformity analysis, Hilbert envelope analysis, and per-0.5s
2nd-order quadrature Digital PLL phase-lock tracking.
"""

import numpy as np
import scipy.signal as signal

from config import DSPConfig
from dsp.watershed_tracker import (
    DEFAULT_BW_CONFIG,
    compute_welch_psd,
    segment_macro_lobes,
    compute_single_slice_watershed_bandwidth,
)


class OfflineFeatureExtractor:
    """
    Runs once per 60-second (1-minute) real audio recording prior to RL training.
    Matches the exact `research-clean` MATLAB pipeline:
      1. High-resolution Welch PSD + Topographic Macro-Lobe Segmentation (`dom_lobe`)
      2. 0.5-second Slice Windowed-FFT Topographic Watershed Bandwidth (`main_f`, `main_bw`)
      3. Multiscale Time-in-Band (TiB) & Jain's Fairness Scale-Uniformity across W = 2s..60s
      4. Per-0.5-second Segment Dominant-Frequency 2nd-Order Digital PLL Phase Lock:
         - Phase Locking Value R in [0, 1] (`plv_r`)
         - PLL Instantaneous Frequency Spread sigma_f (`inst_freq_std`, Hz)
         - Instantaneous Frequency Verification Error |f_PLL - f_FFT| (`freq_verif_err`, Hz)
         - Hilbert Envelope MASD & Coherence Time T_c
    """

    def __init__(self, dsp_cfg: DSPConfig = None):
        if dsp_cfg is None:
            dsp_cfg = DSPConfig()
        self.cfg = dsp_cfg
        self.fs = dsp_cfg.target_fs
        self.buffer_sec = dsp_cfg.buffer_sec
        self.samples_per_buf = int(round(self.fs * self.buffer_sec))
        self.tol_hz = dsp_cfg.tib_tolerance_hz

    @staticmethod
    def compute_jains_index(values: np.ndarray) -> float:
        x = np.asarray(values, dtype=np.float64)
        x = x[np.isfinite(x) & (x >= 0)]
        if len(x) == 0:
            return 1.0
        s_val = float(np.sum(x))
        s_sq = float(np.sum(x ** 2))
        return float((s_val ** 2) / (len(x) * s_sq)) if s_sq > 0 else 1.0

    @staticmethod
    def medfilt1_matlab(x: np.ndarray, k: int) -> np.ndarray:
        """
        Matches MATLAB's `medfilt1(x, k)` (1D median filter supporting even or odd
        window length `k`, e.g., `k = round(5 / 0.5) = 10`).
        """
        arr = np.asarray(x, dtype=np.float64)
        n = len(arr)
        if n == 0 or k <= 1:
            return arr.copy()
        half_left = k // 2
        half_right = k - half_left
        out = np.empty(n, dtype=np.float64)
        for i in range(n):
            i0 = max(0, i - half_left)
            i1 = min(n, i + half_right)
            out[i] = float(np.median(arr[i0:i1]))
        return out

    def compute_multiscale_tib_fairness(
        self,
        bw_array: np.ndarray,
        max_window_sec: float = None,
        pre_filtered: bool = False,
    ) -> dict:
        r"""
        Exact Python port of `BandwidthTracker.compute_stability_vs_window` +
        `FileResult.getMinuteTiBStatsResult` used by:
          - `PlotGenerator.minuteTiBChangeComparison` (`comparison_minute_tib_change.png`)
          - `PlotGenerator.minuteTiBHistograms` (`comparison_minute_tib_histograms.png`)

        Sweeps window scale W from 2s to `max_window_sec` (up to 60s) in 2s increments,
        partitions `bw_array` into non-overlapping blocks of size W, computes Time-in-Band
        TiB(W) per block (within +/- `tol_hz` of block median), and derives:
          - `tib_2s`:          Start TiB at W = 2s
          - `tib_end`:         End TiB at W = max_window_sec (e.g. 60s)
          - `delta_tib`:       Scale drift \DeltaTiB = TiB(W_max) - TiB(2s)
          - `minute_mean_tib`: Per-minute Mean TiB across scales (\mu_{TiB})
          - `minute_std_tib`:  Per-minute Std TiB across scales (\sigma_{TiB}, scale dispersion)
          - `minute_fair_tib`: Per-minute Jain's Fairness Index of TiB across scales (J_{TiB}, scale uniformity)
        """
        bws = np.asarray(bw_array, dtype=np.float64)
        bws = bws[np.isfinite(bws) & (bws > 0)]
        if len(bws) == 0:
            return {
                "window_sizes_sec": np.array([2.0]),
                "tib_curve": np.array([1.0]),
                "tib_2s": 1.0,
                "tib_end": 1.0,
                "delta_tib": 0.0,
                "minute_mean_tib": 1.0,
                "minute_std_tib": 0.0,
                "minute_fair_tib": 1.0,
            }

        if not pre_filtered:
            med_k = max(3, int(round(5.0 / self.buffer_sec)))
            bws = self.medfilt1_matlab(bws, med_k)

        total_time_sec = len(bws) * self.buffer_sec
        if max_window_sec is None:
            max_win = float(np.floor(min(self.cfg.tib_max_win_sec, total_time_sec)))
        else:
            max_win = float(np.floor(min(max_window_sec, total_time_sec)))

        min_win = float(self.cfg.tib_min_win_sec)
        step_win = float(self.cfg.tib_win_step_sec)

        if max_win < min_win:
            med_val = float(np.median(bws))
            tib_single = float(np.mean(np.abs(bws - med_val) <= self.tol_hz))
            return {
                "window_sizes_sec": np.array([min_win]),
                "tib_curve": np.array([tib_single]),
                "tib_2s": tib_single,
                "tib_end": tib_single,
                "delta_tib": 0.0,
                "minute_mean_tib": tib_single,
                "minute_std_tib": 0.0,
                "minute_fair_tib": 1.0,
            }

        window_sizes_sec = np.arange(min_win, max_win + 0.5 * step_win, step_win, dtype=np.float64)
        fs_samples = 1.0 / self.buffer_sec
        T = len(bws)
        tib_curve = []
        valid_wins = []

        for win_sec in window_sizes_sec:
            N = max(1, int(round(win_sec * fs_samples)))
            num_blocks = T // N
            if num_blocks < 1:
                continue
            tib_blocks = np.empty(num_blocks, dtype=np.float64)
            for b in range(num_blocks):
                block_data = bws[b * N: (b + 1) * N]
                med_val = float(np.median(block_data))
                tib_blocks[b] = float(np.sum(np.abs(block_data - med_val) <= self.tol_hz)) / float(len(block_data))
            tib_curve.append(float(np.mean(tib_blocks)))
            valid_wins.append(win_sec)

        tib_arr = np.asarray(tib_curve, dtype=np.float64)
        if len(tib_arr) == 0:
            tib_arr = np.array([1.0], dtype=np.float64)
            valid_wins = [min_win]

        tib_2s = float(tib_arr[0])
        tib_end = float(tib_arr[-1])
        delta_tib = float(tib_end - tib_2s)
        minute_mean_tib = float(np.mean(tib_arr))
        minute_std_tib = float(np.std(tib_arr, ddof=1)) if len(tib_arr) > 1 else 0.0
        minute_fair_tib = self.compute_jains_index(tib_arr)

        return {
            "window_sizes_sec": np.asarray(valid_wins, dtype=np.float64),
            "tib_curve": tib_arr,
            "tib_2s": tib_2s,
            "tib_end": tib_end,
            "delta_tib": delta_tib,
            "minute_mean_tib": minute_mean_tib,
            "minute_std_tib": minute_std_tib,
            "minute_fair_tib": minute_fair_tib,
        }

    @staticmethod
    def compute_masd(env: np.ndarray) -> float:
        return float(np.mean(np.abs(np.diff(env))))

    def compute_coherence_time(self, env: np.ndarray) -> float:
        env_zm = env - np.mean(env)
        norm = np.sum(env_zm ** 2)
        if norm < 1e-10:
            return self.buffer_sec
        acf = np.correlate(env_zm, env_zm, mode="full")[len(env_zm) - 1:] / norm
        below_half = np.where(acf < 0.5)[0]
        if len(below_half) == 0:
            return self.buffer_sec
        return float(below_half[0] / self.fs)

    def run_slice_digital_pll(self, full_sig: np.ndarray, slice_start: int, slice_len: int,
                              f_dom: float, bw_m: float, f_low: float, f_high: float):
        """
        Runs the 2nd-order quadrature Digital PLL on a single 0.5-second segment locked to
        that 0.5-second segment's dominant frequency `f_dom` (matching BandwidthTracker.m).
        """
        n_total = len(full_sig)
        nyq = 0.5 * self.fs
        f_low_lim = max(5.0, float(f_low))
        f_high_lim = min(nyq - 10.0, float(f_high))
        f_dom_clamped = float(np.clip(f_dom, f_low_lim + 5.0, f_high_lim - 5.0))

        pad_len = min(int(round(0.05 * self.fs)), slice_len // 4)
        i_pad1 = max(0, slice_start - pad_len)
        i_pad2 = min(n_total, slice_start + slice_len + pad_len)
        sig_pad = full_sig[i_pad1:i_pad2]

        bp_margin_hz = self.cfg.pll_bandpass_margin_hz
        eff_margin = min(bp_margin_hz, max(16.0, 0.70 * bw_m))
        max_sym_margin = min(max(12.0, f_dom_clamped - f_low_lim), max(12.0, f_high_lim - f_dom_clamped))
        eff_margin = min(eff_margin, max_sym_margin)

        bp_low = max(f_low_lim, f_dom_clamped - eff_margin)
        bp_high = min(f_high_lim, f_dom_clamped + eff_margin)
        if bp_low >= bp_high - 2.0:
            bp_low = max(5.0, f_dom_clamped - 25.0)
            bp_high = min(nyq - 5.0, f_dom_clamped + 25.0)

        try:
            b_bp, a_bp = signal.butter(2, [bp_low / nyq, bp_high / nyq], btype="bandpass")
            filt_pad = signal.filtfilt(b_bp, a_bp, sig_pad)
        except Exception:
            filt_pad = sig_pad

        z_pad = signal.hilbert(filt_pad)
        env_raw = np.abs(z_pad)
        env_win = max(16, int(round(0.08 * self.fs)))
        local_env = np.convolve(env_raw, np.ones(env_win) / env_win, mode="same")
        rms_floor = 0.20 * float(np.median(env_raw)) + 1e-12
        z_norm = z_pad / np.maximum(local_env, rms_floor)

        trim_start = slice_start - i_pad1
        z_slice = z_norm[trim_start: trim_start + slice_len]
        env_slice = env_raw[trim_start: trim_start + slice_len]
        real_sig = np.clip(np.real(z_slice), -1.5, 1.5)
        imag_sig = np.clip(np.imag(z_slice), -1.5, 1.5)

        loop_bw_hz = self.cfg.pll_loop_bw_hz
        zeta = self.cfg.pll_damping_zeta
        max_freq_dev_hz = self.cfg.pll_max_freq_dev_hz
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

    def extract_recording_features(self, audio_sig: np.ndarray, f_low: float = 0.0, f_high: float = 2000.0):
        """
        Extracts 120 steps (0.5s each) of exact Watershed Bandwidth, Multiscale TiB Fairness,
        and Digital PLL features from a 60-second recording.
        """
        bw_cfg = dict(DEFAULT_BW_CONFIG)
        bw_cfg["f_low"] = float(f_low)
        bw_cfg["f_high"] = float(min(f_high, 0.5 * self.fs - 10.0))
        bw_cfg["slice_dur_sec"] = self.buffer_sec
        bw_cfg["tib_tolerance_hz"] = self.tol_hz

        psd_db, f_grid, df, _ = compute_welch_psd(
            audio_sig, self.fs, bw_cfg["f_low"], bw_cfg["f_high"], bw_cfg["twin_welch"], bw_cfg["df_eval"]
        )
        _, dom_lobe, _, ocean_ambient_db = segment_macro_lobes(psd_db, f_grid, df, bw_cfg["prom_split_db"])
        dom_lobe["ocean_ambient_db"] = float(ocean_ambient_db)
        snr_peak_db = float(dom_lobe["peak_psd"] - ocean_ambient_db)
        dom_lobe["snr_peak"] = snr_peak_db
        snr_norm = float((snr_peak_db - 8.0) / 6.0)

        num_buffers = len(audio_sig) // self.samples_per_buf
        buffer_features = []

        for j in range(num_buffers):
            slice_start = j * self.samples_per_buf
            seg = audio_sig[slice_start: slice_start + self.samples_per_buf]

            s_out = compute_single_slice_watershed_bandwidth(seg, self.fs, dom_lobe, bw_cfg)
            if s_out["found"] and np.isfinite(s_out["main_bw"]) and s_out["main_bw"] > 0:
                f_dom = float(s_out["main_f"])
                bw_measured = float(s_out["main_bw"])
            else:
                f_dom = float(dom_lobe["peak_freq"])
                bw_measured = float(max(10.0, dom_lobe["bandwidth"]))

            plv_r, f_pll_mean, f_pll_std, verif_err, phase_std_rad, env_slice = self.run_slice_digital_pll(
                audio_sig, slice_start, self.samples_per_buf, f_dom, bw_measured, bw_cfg["f_low"], bw_cfg["f_high"]
            )

            env_norm = env_slice / (np.mean(env_slice) + 1e-8)
            masd_val = self.compute_masd(env_norm)
            tc_val = self.compute_coherence_time(env_norm)

            buffer_features.append({
                "f_dom": f_dom,
                "f_pll": f_pll_mean,
                "bw_measured": bw_measured,
                "plv_r": plv_r,
                "inst_freq_std": f_pll_std,
                "freq_verif_err": verif_err,
                "phase_std_rad": phase_std_rad,
                "masd": masd_val,
                "coherence_time": tc_val,
            })

        f_doms = np.array([b["f_dom"] for b in buffer_features], dtype=np.float64)
        bws = np.array([b["bw_measured"] for b in buffer_features], dtype=np.float64)
        plvs = np.array([b["plv_r"] for b in buffer_features], dtype=np.float64)
        f_stds = np.array([b["inst_freq_std"] for b in buffer_features], dtype=np.float64)

        med_k_matlab = max(3, int(round(5.0 / self.buffer_sec)))
        bws_med = self.medfilt1_matlab(bws, med_k_matlab)
        plvs_med = self.medfilt1_matlab(plvs, med_k_matlab)

        minute_tib_stats = self.compute_multiscale_tib_fairness(
            bws_med, max_window_sec=self.cfg.tib_max_win_sec, pre_filtered=True
        )

        state_sequence = []
        prev_jain = 1.0
        for j in range(num_buffers):
            win_start = max(0, j - 11)
            bw_win = bws_med[win_start: j + 1]
            plv_win = plvs_med[win_start: j + 1]
            fstd_win = f_stds[win_start: j + 1]
            df_dt = float(abs(f_doms[j] - f_doms[j - 1])) if j > 0 else 0.0

            causal_end = max(min(num_buffers, 12), j + 1)
            step_tib_stats = self.compute_multiscale_tib_fairness(
                bws_med[:causal_end], max_window_sec=self.cfg.tib_max_win_sec, pre_filtered=True
            )

            med_bw = float(np.median(bw_win))
            time_in_band = float(np.mean(np.abs(bw_win - med_bw) <= self.tol_hz))

            jain_bw = self.compute_jains_index(bw_win)
            jain_tib_fairness = float(step_tib_stats["minute_fair_tib"])
            mean_tib_multiscale = float(step_tib_stats["minute_mean_tib"])
            std_tib_multiscale = float(step_tib_stats["minute_std_tib"])
            delta_tib_multiscale = float(step_tib_stats["delta_tib"])
            tib_2s_val = float(step_tib_stats["tib_2s"])
            tib_end_val = float(step_tib_stats["tib_end"])

            djain_dt = float(abs(jain_tib_fairness - prev_jain)) if j > 0 else 0.0
            prev_jain = jain_tib_fairness

            bw_mean = float(np.mean(bw_win))
            bw_std = float(np.std(bw_win))
            plv_mean = float(np.mean(plv_win))
            fstd_mean = float(np.mean(fstd_win))

            s_t = np.array([
                (mean_tib_multiscale - 0.78) * 4.5,
                (jain_tib_fairness - 0.96) * 22.0,
                (delta_tib_multiscale + 0.18) * 4.5,
                (std_tib_multiscale - 0.065) * 18.0,
                (bw_mean - 55.0) / 35.0,
                (buffer_features[j]["masd"] - 0.15) * 8.0,
                (plv_mean - 0.36) * 5.0,
                (fstd_mean - 11.5) / 3.5,
                snr_norm,
            ], dtype=np.float32)

            state_sequence.append({
                "s_t": s_t,
                "tib": time_in_band,
                "jain": jain_bw,
                "minute_mean_tib": float(minute_tib_stats["minute_mean_tib"]),
                "minute_std_tib": float(minute_tib_stats["minute_std_tib"]),
                "minute_fair_tib": float(minute_tib_stats["minute_fair_tib"]),
                "minute_delta_tib": float(minute_tib_stats["delta_tib"]),
                "minute_tib_2s": float(minute_tib_stats["tib_2s"]),
                "minute_tib_60s": float(minute_tib_stats["tib_end"]),
                "step_mean_tib": mean_tib_multiscale,
                "step_std_tib": std_tib_multiscale,
                "step_fair_tib": jain_tib_fairness,
                "step_delta_tib": delta_tib_multiscale,
                "step_tib_2s": tib_2s_val,
                "step_tib_end": tib_end_val,
                "djain_dt": djain_dt,
                "df_dt": df_dt,
                "bw_measured": buffer_features[j]["bw_measured"],
                "bw_mean": bw_mean,
                "f_dom": buffer_features[j]["f_dom"],
                "f_pll": buffer_features[j]["f_pll"],
                "plv_r": buffer_features[j]["plv_r"],
                "inst_freq_std": buffer_features[j]["inst_freq_std"],
                "freq_verif_err": buffer_features[j]["freq_verif_err"],
                "phase_std_rad": buffer_features[j]["phase_std_rad"],
                "coherence_time": buffer_features[j]["coherence_time"],
                "masd": buffer_features[j]["masd"],
                "snr_peak": snr_peak_db,
                "ocean_ambient_db": float(ocean_ambient_db),
            })

        return state_sequence, dom_lobe, minute_tib_stats

