"""
Audio dataset loader and disjoint file-level Train / Held-Out Test splitter (`drl.data.loader`)
for the real HaifaBay, Croatia, and AUV hydrophone datasets.
"""

import os
import glob
import pickle
import random
from collections import defaultdict
from typing import Tuple, List, Dict, Any
from concurrent.futures import ThreadPoolExecutor
import numpy as np
import scipy.signal as signal
from scipy.io import wavfile

from config import (
    DSPConfig,
    REAL_DATASET_CONFIGS,
    CLASS_AMBIENT,
    CLASS_UNDERWATER,
    CLASS_SURFACE,
    CLASS_NAMES,
    NUM_CLASSES,
    FEATURE_CACHE_PATH,
)
from dsp.feature_extractor import OfflineFeatureExtractor


def load_real_wav_segment(
    filepath: str,
    start_sec: float,
    duration_sec: float = 60.0,
    target_fs: float = 4800.0,
) -> Tuple[np.ndarray, float]:
    """
    Reads a WAV file on disk (using mmap when compatible, or direct read for 24-bit PCM),
    extracts a `duration_sec` slice starting at `start_sec`, normalizes to zero-mean unit-variance,
    and resamples to `target_fs`.
    """
    try:
        fs, data = wavfile.read(filepath, mmap=True)
    except Exception:
        fs, data = wavfile.read(filepath, mmap=False)

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


def generate_bellhop_multipath_rays(
    tx_depth: float,
    rx_depth: float = 30.0,
    rx_range: float = 1000.0,
    max_depth: float = 100.0,
    c_water: float = 1500.0,
) -> List[Dict[str, Any]]:
    """Computes physical eigenray multipath arrivals (direct, surface reflection, bottom reflection)."""
    rays = []
    # 1. Direct path
    l_dir = np.sqrt(rx_range**2 + (rx_depth - tx_depth)**2)
    rays.append({
        "time_of_arrival": l_dir / c_water,
        "amplitude": (1.0 / l_dir) + 0j,
        "surface_bounces": 0,
        "bottom_bounces": 0,
        "grazing_angle_rad": float(np.arctan2(abs(rx_depth - tx_depth), rx_range)),
    })
    # 2. Surface reflected path with -1 phase inversion
    l_surf = np.sqrt(rx_range**2 + (rx_depth + tx_depth)**2)
    rays.append({
        "time_of_arrival": l_surf / c_water,
        "amplitude": (-0.95 / l_surf) + 0j,
        "surface_bounces": 1,
        "bottom_bounces": 0,
        "grazing_angle_rad": float(np.arctan2(rx_depth + tx_depth, rx_range)),
    })
    # 3. Bottom reflected path
    l_bot = np.sqrt(rx_range**2 + ((2.0 * max_depth - tx_depth) - rx_depth)**2)
    rays.append({
        "time_of_arrival": l_bot / c_water,
        "amplitude": (0.50 / l_bot) + 0j,
        "surface_bounces": 0,
        "bottom_bounces": 1,
        "grazing_angle_rad": float(np.arctan2((2.0 * max_depth - tx_depth) - rx_depth, rx_range)),
    })
    return rays


def generate_pierson_moskowitz_sea(wind_speed: float = 8.5, duration: float = 60.0, fs_env: float = 50.0):
    """Generates physical Pierson-Moskowitz wave height h(t) and orbital velocity v(t)."""
    g, alpha, beta_pm = 9.81, 0.0081, 0.74
    f = np.linspace(0.08, 1.2, 200)
    df = f[1] - f[0]
    omega = 2.0 * np.pi * f
    omega_0 = g / max(1.0, wind_speed)
    s_omega = (alpha * g**2 / omega**5) * np.exp(-beta_pm * (omega_0 / omega)**4)
    amps = np.sqrt(2.0 * s_omega * (2.0 * np.pi) * df)
    phases = np.random.uniform(0, 2.0 * np.pi, size=len(f))
    t_env = np.arange(0, duration, 1.0 / fs_env)
    h_t = np.sum(amps[:, None] * np.cos(omega[:, None] * t_env[None, :] + phases[:, None]), axis=0)
    v_orbital = np.sum((amps * omega)[:, None] * np.sin(omega[:, None] * t_env[None, :] + phases[:, None]), axis=0)
    return t_env, h_t, v_orbital


def synthesize_bellhop_acoustic_signal(
    arrivals: List[Dict[str, Any]],
    f0: float = 400.0,
    duration: float = 60.0,
    fs_audio: float = 4800.0,
    is_surface_boat: bool = True,
    wind_speed: float = 8.5,
) -> np.ndarray:
    """
    Synthesizes acoustic signal combining BELLHOP multipath ray arrivals,
    Pierson-Moskowitz sea waves, air-water cavity fading, and acoustic micro-scattering.
    """
    c = 1500.0
    k = 2.0 * np.pi * f0 / c
    t = np.arange(0, duration, 1.0 / fs_audio)
    t_env, h_env, v_env = generate_pierson_moskowitz_sea(wind_speed=wind_speed, duration=duration)
    h_t = np.interp(t, t_env, h_env)
    v_wave = np.interp(t, t_env, v_env)
    wave_rms = float(np.std(h_t))

    if is_surface_boat:
        inst_freq_dev = 3.5 * v_wave + 2.0 * np.random.randn(len(t))
        smooth_win = int(fs_audio * 0.15)
        inst_freq_dev = np.convolve(inst_freq_dev, np.ones(smooth_win) / smooth_win, mode="same")
        source_phase_fm = 2.0 * np.pi * np.cumsum(inst_freq_dev) / fs_audio
        fading_env = np.clip(1.0 + 0.7 * h_t + 0.4 * np.random.randn(len(t)), 0.05, 2.5)
        env_win = int(fs_audio * 0.08)
        fading_env = np.convolve(fading_env, np.ones(env_win) / env_win, mode="same")
    else:
        inst_freq_dev = 0.15 * np.sin(2.0 * np.pi * 0.05 * t)
        source_phase_fm = 2.0 * np.pi * np.cumsum(inst_freq_dev) / fs_audio
        fading_env = np.ones_like(t)

    p_rx = np.zeros_like(t)
    for ray in arrivals:
        tau_i = ray["time_of_arrival"]
        amp_i = float(np.abs(ray["amplitude"]))
        phase_i = float(np.angle(ray["amplitude"]))
        n_surf = ray["surface_bounces"]
        theta_g = ray["grazing_angle_rad"]
        t_delayed = t - tau_i

        if n_surf > 0:
            rayleigh_g = 2.0 * k * wave_rms * np.sin(theta_g)
            coherent_loss = float(np.exp(-0.5 * (n_surf * rayleigh_g)**2))
            if not is_surface_boat:
                amp_i *= 0.25 * coherent_loss
            micro_scattering = np.cumsum(np.random.normal(0, 0.08, size=len(t)))
            surface_mod = n_surf * (4.0 * np.pi * f0 / c) * h_t * np.sin(theta_g) + micro_scattering
        else:
            surface_mod = 0.0

        total_phase = 2.0 * np.pi * f0 * t_delayed + source_phase_fm + surface_mod + phase_i
        p_rx += amp_i * np.cos(total_phase)

    p_rx = p_rx * fading_env
    std_p = np.std(p_rx)
    if std_p > 1e-12:
        p_rx = p_rx / std_p

    noise = np.random.normal(0, 0.35, size=len(t))
    sig = p_rx + noise
    sig -= np.mean(sig)
    sig /= (np.std(sig) + 1e-12)
    return sig.astype(np.float32)


def synthesize_ambient_ocean_audio(
    duration: float = 60.0,
    fs: float = 4800.0,
) -> Tuple[np.ndarray, float]:
    """Synthesizes realistic Wenz-Knudsen ambient marine noise with 1/f spectral slope."""
    n_samples = int(duration * fs)
    white = np.random.randn(n_samples)
    b, a = signal.butter(1, 40.0 / (0.5 * fs), btype="high")
    filtered = signal.lfilter(b, a, white)
    b_pink, a_pink = [0.049922035, -0.095993537, 0.050612699, -0.004408786], [1.0, -2.494956002, 2.017265875, -0.522189400]
    pink = signal.lfilter(b_pink, a_pink, filtered)
    pink -= np.mean(pink)
    pink /= (np.std(pink) + 1e-8)
    return pink.astype(np.float32), float(fs)


def synthesize_vessel_audio(
    f0: float = 400.0,
    duration: float = 60.0,
    fs: float = 4800.0,
    is_surface_boat: bool = True,
) -> Tuple[np.ndarray, float]:
    """Fallback synthetic audio generator if hydrophone directories are unavailable."""
    t = np.arange(0, duration, 1.0 / fs)
    if is_surface_boat:
        inst_freq_dev = 18.0 * np.sin(2 * np.pi * 0.22 * t) + 14.0 * np.random.randn(len(t))
        win = int(fs * 0.05)
        inst_freq_dev = np.convolve(inst_freq_dev, np.ones(win) / win, mode="same")
        phase = 2 * np.pi * f0 * t + 2 * np.pi * np.cumsum(inst_freq_dev) / fs
        env = np.clip(1.0 + 0.65 * np.sin(2 * np.pi * 0.22 * t) + 0.35 * np.random.randn(len(t)), 0.1, 2.5)
    else:
        inst_freq_dev = 0.5 * np.sin(2 * np.pi * 0.08 * t) + 1.2 * np.random.randn(len(t))
        win = int(fs * 0.10)
        inst_freq_dev = np.convolve(inst_freq_dev, np.ones(win) / win, mode="same")
        phase = 2 * np.pi * f0 * t + 2 * np.pi * np.cumsum(inst_freq_dev) / fs
        env = np.ones_like(t)
    sig = env * np.cos(phase) + 0.25 * np.random.randn(len(t))
    sig = (sig - np.mean(sig)) / (np.std(sig) + 1e-8)
    return sig.astype(np.float32), float(fs)


def build_train_test_real_datasets(
    dsp_cfg: DSPConfig = None,
    dataset_configs: List[Dict[str, Any]] = None,
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    """
    Builds a strict FILE-LEVEL Train / Held-Out Test split across real hydrophone datasets:
      - WAV files in each dataset are partitioned into disjoint Train WAV files (~75%)
        and Held-Out Test WAV files (~25%).
      - Assigns each 60-second episode its true physical 3-class target:
          * CLASS_AMBIENT (0):    Pure ocean ambient noise or low-SNR noise floor
          * CLASS_UNDERWATER (1): Underwater Scooter / DPV / submerged vehicle
          * CLASS_SURFACE (2):    Surface vessel (cavitation, multipath spreading)
    """
    if dsp_cfg is None:
        dsp_cfg = DSPConfig()
    if dataset_configs is None:
        dataset_configs = REAL_DATASET_CONFIGS

    # Check disk cache first if enabled
    if getattr(dsp_cfg, "use_cache", True) and os.path.exists(FEATURE_CACHE_PATH):
        try:
            with open(FEATURE_CACHE_PATH, "rb") as f:
                cached_data = pickle.load(f)
            if "train_dataset" in cached_data and "test_dataset" in cached_data:
                print(f"  [Cache Hit] Loaded pre-extracted features from {FEATURE_CACHE_PATH}")
                return cached_data["train_dataset"], cached_data["test_dataset"]
        except Exception as e:
            print(f"  [Cache Warning] Failed to read cache ({e}), re-extracting features...")

    extractor = OfflineFeatureExtractor(dsp_cfg)
    train_dataset: List[Dict[str, Any]] = []
    test_dataset: List[Dict[str, Any]] = []

    def _process_single_episode(k: int, file_list: List[str], num_eps: int, cfg: Dict[str, Any], split_label: str):
        wf = file_list[k % len(file_list)]
        try:
            fs_hdr, data_mmap = wavfile.read(wf, mmap=True)
        except Exception:
            fs_hdr, data_mmap = wavfile.read(wf, mmap=False)

        total_sec = len(data_mmap) / float(fs_hdr)
        usable_sec = max(1.0, total_sec - dsp_cfg.segment_duration_sec - 10.0)
        n_per_file = max(1, (num_eps + len(file_list) - 1) // len(file_list))
        slot = k // len(file_list)
        frac = (slot + 0.5) / float(n_per_file)
        start_sec = 5.0 + frac * usable_sec

        sig, _ = load_real_wav_segment(
            wf, start_sec=start_sec, duration_sec=dsp_cfg.segment_duration_sec, target_fs=dsp_cfg.target_fs
        )
        steps, dom_lobe, minute_tib_stats = extractor.extract_recording_features(
            sig, f_low=cfg["f_low"], f_high=cfg["f_high"]
        )

        bw_mean = float(np.mean([s["bw_measured"] for s in steps]))
        plv_mean = float(np.mean([s["plv_r"] for s in steps]))
        dtib = float(minute_tib_stats["delta_tib"])
        masd_mean = float(np.mean([s["masd"] for s in steps]))
        snr_peak_db = float(dom_lobe.get("snr_peak", dom_lobe["peak_psd"] - dom_lobe.get("ocean_ambient_db", 0.0)))

        # Determine 3-class physical acoustic ground truth:
        # 0: CLASS_AMBIENT, 1: CLASS_UNDERWATER, 2: CLASS_SURFACE
        if cfg["name"] == "HaifaBay":
            # Haifa Bay is a shallow commercial shipping fairway.
            # Segments with significant spectral energy (SNR >= 12 dB or broad BW >= 40 Hz or negative TiB drift)
            # are commercial surface vessels. Calm baseline intervals (SNR < 12 dB and narrow BW < 40 Hz) are ambient.
            if snr_peak_db >= 12.0 or bw_mean >= 40.0 or dtib < -0.15:
                target_class = CLASS_SURFACE
            else:
                target_class = CLASS_AMBIENT
        elif cfg["name"] == "HearMyShip":
            target_class = CLASS_SURFACE
        elif cfg["name"] == "Croatia":
            if plv_mean >= 0.25 or snr_peak_db >= 4.0:
                target_class = CLASS_UNDERWATER
            else:
                target_class = CLASS_AMBIENT
        elif cfg["name"] == "AUV":
            if (bw_mean < 45.0 and plv_mean >= 0.28) or snr_peak_db >= 5.0:
                target_class = CLASS_UNDERWATER
            else:
                target_class = CLASS_AMBIENT
        elif cfg["name"] in ("BuoyAmbient", "Ambient"):
            # Buoy recordings contain ambient baseline intervals as well as nearby passing surface vessels.
            # Active vessel pass: high SNR (>=13 dB) or strong cavitation rumble (BW >= 60 Hz with SNR >= 11 dB)
            if snr_peak_db >= 13.0 or (bw_mean >= 60.0 and snr_peak_db >= 11.0 and dtib < -0.20):
                target_class = CLASS_SURFACE
            elif bw_mean < 35.0 and plv_mean >= 0.28 and snr_peak_db >= 10.0:
                target_class = CLASS_UNDERWATER
            else:
                target_class = CLASS_AMBIENT
        else:
            target_class = cfg.get("default_class", CLASS_UNDERWATER)

        meta = {
            "dataset_name": cfg["name"],
            "dataset_id": cfg["dataset_id"],
            "target_class": target_class,
            "target_class_name": CLASS_NAMES[target_class],
            "is_surface": int(target_class == CLASS_SURFACE),
            "is_underwater": int(target_class == CLASS_UNDERWATER),
            "is_ambient": int(target_class == CLASS_AMBIENT),
            "f0_true": float(dom_lobe["peak_freq"]),
            "fw_est": cfg["fw_est"],
            "theta_g": cfg["theta_g"],
            "max_vz": cfg["max_vz"],
            "source_file": os.path.basename(wf),
            "start_sec": start_sec,
            "split": split_label,
            "minute_tib_stats": minute_tib_stats,
            "bw_mean": bw_mean,
            "plv_mean": plv_mean,
            "snr_peak": snr_peak_db,
        }
        return {"steps": steps, "metadata": meta}

    def _sample_from_files(file_list: List[str], num_eps: int, cfg: Dict[str, Any], split_label: str):
        workers = max(1, getattr(dsp_cfg, "num_workers", 4))
        if workers > 1 and num_eps > 1:
            with ThreadPoolExecutor(max_workers=workers) as executor:
                recs = list(executor.map(
                    lambda k: _process_single_episode(k, file_list, num_eps, cfg, split_label),
                    range(num_eps)
                ))
            return recs
        return [_process_single_episode(k, file_list, num_eps, cfg, split_label) for k in range(num_eps)]

    for cfg in dataset_configs:
        ds_dir = os.path.join(dsp_cfg.base_dir, cfg["rel_path"])
        wav_files = sorted(glob.glob(os.path.join(ds_dir, "**", "*.wav"), recursive=True))

        if not wav_files:
            print(f"  [Warning] No WAV files found in {ds_dir}; using synthetic fallback for {cfg['name']}.")
            for split_label, num_eps, target_list in [
                ("train", dsp_cfg.train_eps_per_dataset, train_dataset),
                ("test", dsp_cfg.test_eps_per_dataset, test_dataset),
            ]:
                for _ in range(num_eps):
                    def_cls = cfg.get("default_class", CLASS_UNDERWATER)
                    if def_cls == CLASS_AMBIENT:
                        sig, _ = synthesize_ambient_ocean_audio(
                            duration=dsp_cfg.segment_duration_sec, fs=dsp_cfg.target_fs
                        )
                        target_class = CLASS_AMBIENT
                    elif def_cls == CLASS_SURFACE:
                        sig, _ = synthesize_vessel_audio(
                            f0=170.0, duration=dsp_cfg.segment_duration_sec, fs=dsp_cfg.target_fs, is_surface_boat=True
                        )
                        target_class = CLASS_SURFACE
                    else:
                        sig, _ = synthesize_vessel_audio(
                            f0=720.0, duration=dsp_cfg.segment_duration_sec, fs=dsp_cfg.target_fs, is_surface_boat=False
                        )
                        target_class = CLASS_UNDERWATER

                    steps, dom_lobe, minute_tib_stats = extractor.extract_recording_features(
                        sig, f_low=cfg["f_low"], f_high=cfg["f_high"]
                    )
                    meta = {
                        "dataset_name": cfg["name"],
                        "dataset_id": cfg["dataset_id"],
                        "target_class": target_class,
                        "target_class_name": CLASS_NAMES[target_class],
                        "is_surface": int(target_class == CLASS_SURFACE),
                        "is_underwater": int(target_class == CLASS_UNDERWATER),
                        "is_ambient": int(target_class == CLASS_AMBIENT),
                        "f0_true": float(dom_lobe["peak_freq"]),
                        "fw_est": cfg["fw_est"],
                        "theta_g": cfg["theta_g"],
                        "max_vz": cfg["max_vz"],
                        "split": split_label,
                        "minute_tib_stats": minute_tib_stats,
                        "bw_mean": float(np.mean([s["bw_measured"] for s in steps])),
                        "plv_mean": float(np.mean([s["plv_r"] for s in steps])),
                        "snr_peak": float(dom_lobe.get("snr_peak", 10.0)),
                    }
                    target_list.append({"steps": steps, "metadata": meta})
            continue

        if cfg["name"] == "HearMyShip":
            # Exclude unmotorized sailing boats so the network learns motorized commercial/vessel cavitation
            wav_files = [f for f in wav_files if "Sail Boat" not in f]
            # Stratified sampling across vessel categories (Motor Boats, Yachts, Ferries, Aux)
            by_cat = defaultdict(list)
            for f in wav_files:
                cat = os.path.basename(os.path.dirname(f))
                by_cat[cat].append(f)
            train_files = []
            test_files = []
            rng_split = random.Random(42)
            for cat, flist in sorted(by_cat.items()):
                rng_split.shuffle(flist)
                n_te = max(1, int(round(dsp_cfg.test_file_fraction * len(flist)))) if len(flist) >= 4 else 1
                n_tr = max(1, len(flist) - n_te)
                train_files.extend(flist[:n_tr])
                test_files.extend(flist[n_tr:])
            n_files = len(wav_files)
        else:
            n_files = len(wav_files)
            n_test_files = max(2, int(round(dsp_cfg.test_file_fraction * n_files))) if n_files >= 4 else 1
            n_train_files = max(1, n_files - n_test_files)
            train_files = wav_files[:n_train_files]
            test_files = wav_files[n_train_files:]

        print(
            f"  -> {cfg['name']:<11}: {n_files:2d} WAV files split into "
            f"{len(train_files):2d} Train files ({dsp_cfg.train_eps_per_dataset} eps) & "
            f"{len(test_files):2d} Held-Out Test files ({dsp_cfg.test_eps_per_dataset} eps)..."
        )
        train_dataset.extend(_sample_from_files(train_files, dsp_cfg.train_eps_per_dataset, cfg, "train"))
        test_dataset.extend(_sample_from_files(test_files, dsp_cfg.test_eps_per_dataset, cfg, "test"))

    # Optional: BELLHOP Physics-Informed Synthetic Augmentation for Training
    if getattr(dsp_cfg, "use_bellhop_synthetic", True):
        eps_per_cls = getattr(dsp_cfg, "bellhop_train_eps_per_class", 12)
        print(f"\n  [BELLHOP Augmentation] Generating {eps_per_cls * 3} physics-calibrated synthetic training episodes ({eps_per_cls} per class)...")
        bellhop_recs: List[Dict[str, Any]] = []

        # 1. Surface Vessel episodes (shallow source, wave heave, cavitation smearing)
        for i in range(eps_per_cls):
            tx_d = float(np.random.uniform(0.3, 1.8))
            f0 = float(np.random.uniform(120.0, 380.0))
            wind = float(np.random.uniform(5.0, 11.0))
            rng = float(np.random.uniform(400.0, 1800.0))
            rays = generate_bellhop_multipath_rays(tx_depth=tx_d, rx_range=rng)
            sig = synthesize_bellhop_acoustic_signal(
                rays, f0=f0, duration=dsp_cfg.segment_duration_sec, fs_audio=dsp_cfg.target_fs,
                is_surface_boat=True, wind_speed=wind
            )
            steps, dom_lobe, minute_tib_stats = extractor.extract_recording_features(sig, f_low=20.0, f_high=1000.0)
            meta = {
                "dataset_name": "BELLHOP_Surface",
                "dataset_id": 0,
                "target_class": CLASS_SURFACE,
                "target_class_name": CLASS_NAMES[CLASS_SURFACE],
                "is_surface": 1,
                "is_underwater": 0,
                "is_ambient": 0,
                "f0_true": float(dom_lobe["peak_freq"]),
                "fw_est": 0.22,
                "theta_g": float(np.deg2rad(2.5)),
                "max_vz": 1.85,
                "source_file": f"bellhop_surface_synth_{i:02d}.sim",
                "start_sec": 0.0,
                "split": "train",
                "minute_tib_stats": minute_tib_stats,
                "bw_mean": float(np.mean([s["bw_measured"] for s in steps])),
                "plv_mean": float(np.mean([s["plv_r"] for s in steps])),
                "snr_peak": float(dom_lobe.get("snr_peak", 14.0)),
            }
            bellhop_recs.append({"steps": steps, "metadata": meta})

        # 2. Underwater Scooter / Submerged vehicle episodes (deep source, stable electric motor, high phase lock)
        for i in range(eps_per_cls):
            tx_d = float(np.random.uniform(15.0, 45.0))
            f0 = float(np.random.uniform(450.0, 850.0))
            wind = float(np.random.uniform(3.0, 8.0))
            rng = float(np.random.uniform(300.0, 1400.0))
            rays = generate_bellhop_multipath_rays(tx_depth=tx_d, rx_range=rng)
            sig = synthesize_bellhop_acoustic_signal(
                rays, f0=f0, duration=dsp_cfg.segment_duration_sec, fs_audio=dsp_cfg.target_fs,
                is_surface_boat=False, wind_speed=wind
            )
            steps, dom_lobe, minute_tib_stats = extractor.extract_recording_features(sig, f_low=300.0, f_high=1600.0)
            meta = {
                "dataset_name": "BELLHOP_Underwater",
                "dataset_id": 1,
                "target_class": CLASS_UNDERWATER,
                "target_class_name": CLASS_NAMES[CLASS_UNDERWATER],
                "is_surface": 0,
                "is_underwater": 1,
                "is_ambient": 0,
                "f0_true": float(dom_lobe["peak_freq"]),
                "fw_est": 0.12,
                "theta_g": float(np.deg2rad(12.0)),
                "max_vz": 0.35,
                "source_file": f"bellhop_underwater_synth_{i:02d}.sim",
                "start_sec": 0.0,
                "split": "train",
                "minute_tib_stats": minute_tib_stats,
                "bw_mean": float(np.mean([s["bw_measured"] for s in steps])),
                "plv_mean": float(np.mean([s["plv_r"] for s in steps])),
                "snr_peak": float(dom_lobe.get("snr_peak", 12.0)),
            }
            bellhop_recs.append({"steps": steps, "metadata": meta})

        # 3. Ambient Marine Noise episodes (Wenz-Knudsen 1/f noise floor)
        for i in range(eps_per_cls):
            sig, _ = synthesize_ambient_ocean_audio(
                duration=dsp_cfg.segment_duration_sec, fs=dsp_cfg.target_fs
            )
            steps, dom_lobe, minute_tib_stats = extractor.extract_recording_features(sig, f_low=20.0, f_high=1200.0)
            meta = {
                "dataset_name": "BELLHOP_Ambient",
                "dataset_id": 3,
                "target_class": CLASS_AMBIENT,
                "target_class_name": CLASS_NAMES[CLASS_AMBIENT],
                "is_surface": 0,
                "is_underwater": 0,
                "is_ambient": 1,
                "f0_true": float(dom_lobe["peak_freq"]),
                "fw_est": 0.10,
                "theta_g": float(np.deg2rad(5.0)),
                "max_vz": 0.10,
                "source_file": f"bellhop_ambient_synth_{i:02d}.sim",
                "start_sec": 0.0,
                "split": "train",
                "minute_tib_stats": minute_tib_stats,
                "bw_mean": float(np.mean([s["bw_measured"] for s in steps])),
                "plv_mean": float(np.mean([s["plv_r"] for s in steps])),
                "snr_peak": float(dom_lobe.get("snr_peak", 4.0)),
            }
            bellhop_recs.append({"steps": steps, "metadata": meta})

        train_dataset.extend(bellhop_recs)
        print(f"  [BELLHOP Augmentation] Successfully injected {len(bellhop_recs)} episodes into training set (Total Train: {len(train_dataset)}).")

    if getattr(dsp_cfg, "use_cache", True):
        try:
            os.makedirs(os.path.dirname(FEATURE_CACHE_PATH), exist_ok=True)
            with open(FEATURE_CACHE_PATH, "wb") as f:
                pickle.dump({"train_dataset": train_dataset, "test_dataset": test_dataset}, f, protocol=pickle.HIGHEST_PROTOCOL)
            print(f"  [Cache Saved] Saved pre-extracted features to {FEATURE_CACHE_PATH}")
        except Exception as e:
            print(f"  [Cache Warning] Could not save cache to {FEATURE_CACHE_PATH}: {e}")

    return train_dataset, test_dataset

