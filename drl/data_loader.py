"""
Audio dataset loader and disjoint file-level Train / Held-Out Test splitter
for the real HaifaBay, Croatia, and AUV hydrophone datasets.
"""

import os
import glob
from typing import Tuple, List, Dict, Any
import numpy as np
import scipy.signal as signal
from scipy.io import wavfile

from config import DSPConfig, REAL_DATASET_CONFIGS
from feature_extractor import OfflineFeatureExtractor


def load_real_wav_segment(filepath: str, start_sec: float, duration_sec: float = 30.0,
                          target_fs: float = 4800.0) -> Tuple[np.ndarray, float]:
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


def synthesize_vessel_audio(f0: float = 400.0, duration: float = 30.0, fs: float = 4800.0,
                            is_surface_boat: bool = True) -> Tuple[np.ndarray, float]:
    """Fallback synthetic audio generator if `D:\\RoyStudies\\Recordings` is not mounted."""
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
    Builds a strict FILE-LEVEL Train / Held-Out Test split across HaifaBay, Croatia, and AUV:
      - WAV files in each dataset are partitioned into disjoint Train WAV files (~75%)
        and Held-Out Test WAV files (~25%).
      - No WAV file is shared between `train_dataset` and `test_dataset`, preventing
        any temporal or file-level data leakage.
    """
    if dsp_cfg is None:
        dsp_cfg = DSPConfig()
    if dataset_configs is None:
        dataset_configs = REAL_DATASET_CONFIGS

    extractor = OfflineFeatureExtractor(dsp_cfg)
    train_dataset: List[Dict[str, Any]] = []
    test_dataset: List[Dict[str, Any]] = []

    def _sample_from_files(file_list: List[str], num_eps: int, cfg: Dict[str, Any], split_label: str):
        recs = []
        for k in range(num_eps):
            wf = file_list[k % len(file_list)]
            fs_hdr, data_mmap = wavfile.read(wf, mmap=True)
            total_sec = len(data_mmap) / float(fs_hdr)
            usable_sec = max(1.0, total_sec - dsp_cfg.segment_duration_sec - 10.0)
            n_per_file = max(1, (num_eps + len(file_list) - 1) // len(file_list))
            slot = k // len(file_list)
            frac = (slot + 0.5) / float(n_per_file)
            start_sec = 5.0 + frac * usable_sec

            sig, _ = load_real_wav_segment(
                wf, start_sec=start_sec, duration_sec=dsp_cfg.segment_duration_sec, target_fs=dsp_cfg.target_fs
            )
            steps, dom_lobe = extractor.extract_recording_features(sig, f_low=cfg["f_low"], f_high=cfg["f_high"])

            meta = {
                "dataset_name": cfg["name"],
                "dataset_id": cfg["dataset_id"],
                "is_surface": cfg["is_surface"],
                "f0_true": float(dom_lobe["peak_freq"]),
                "fw_est": cfg["fw_est"],
                "theta_g": cfg["theta_g"],
                "max_vz": cfg["max_vz"],
                "source_file": os.path.basename(wf),
                "start_sec": start_sec,
                "split": split_label,
            }
            recs.append({"steps": steps, "metadata": meta})
        return recs

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
                    sig, _ = synthesize_vessel_audio(
                        f0=170.0 if cfg["is_surface"] else 720.0,
                        duration=dsp_cfg.segment_duration_sec,
                        fs=dsp_cfg.target_fs,
                        is_surface_boat=bool(cfg["is_surface"]),
                    )
                    steps, dom_lobe = extractor.extract_recording_features(sig, f_low=cfg["f_low"], f_high=cfg["f_high"])
                    meta = {
                        "dataset_name": cfg["name"],
                        "dataset_id": cfg["dataset_id"],
                        "is_surface": cfg["is_surface"],
                        "f0_true": float(dom_lobe["peak_freq"]),
                        "fw_est": cfg["fw_est"],
                        "theta_g": cfg["theta_g"],
                        "max_vz": cfg["max_vz"],
                        "split": split_label,
                    }
                    target_list.append({"steps": steps, "metadata": meta})
            continue

        n_files = len(wav_files)
        n_test_files = max(2, int(round(dsp_cfg.test_file_fraction * n_files))) if n_files >= 4 else 1
        n_train_files = max(1, n_files - n_test_files)
        train_files = wav_files[:n_train_files]
        test_files = wav_files[n_train_files:]

        print(
            f"  -> {cfg['name']:<9}: {n_files:2d} WAV files split into "
            f"{len(train_files):2d} Train files ({dsp_cfg.train_eps_per_dataset} eps) & "
            f"{len(test_files):2d} Held-Out Test files ({dsp_cfg.test_eps_per_dataset} eps)..."
        )
        train_dataset.extend(_sample_from_files(train_files, dsp_cfg.train_eps_per_dataset, cfg, "train"))
        test_dataset.extend(_sample_from_files(test_files, dsp_cfg.test_eps_per_dataset, cfg, "test"))

    return train_dataset, test_dataset

