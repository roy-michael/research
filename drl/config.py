"""
Centralized configuration for the Physics-Informed Deep Reinforcement Learning (DRL)
pipeline on the real HaifaBay, Croatia, and AUV acoustic datasets.
"""

import os
from dataclasses import dataclass, field
from typing import List, Dict, Any
import numpy as np

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(PROJECT_ROOT, "output")
os.makedirs(OUTPUT_DIR, exist_ok=True)

DEFAULT_RECORDINGS_DIR = r"D:\RoyStudies\Recordings"
# DEFAULT_RECORDINGS_DIR = r"C:\Users\Roy\Recordings"
OUTPUT_PLOT_PATH = os.path.join(OUTPUT_DIR, "drl_real_datasets_results.png")
OUTPUT_FAIRNESS_PLOT_PATH = os.path.join(OUTPUT_DIR, "drl_tib_fairness_reward_results.png")
OUTPUT_FAIRNESS_HIST_PATH = os.path.join(OUTPUT_DIR, "drl_minute_tib_fairness_histograms.png")
OUTPUT_FAIRNESS_CHANGE_PATH = os.path.join(OUTPUT_DIR, "drl_minute_tib_change_comparison.png")
OUTPUT_LIVE_DASHBOARD_PATH = os.path.join(OUTPUT_DIR, "drl_live_training_verification.png")
FEATURE_CACHE_PATH = os.path.join(OUTPUT_DIR, "extracted_features_cache.pkl")

# 3-Class Classification Constants
CLASS_AMBIENT = 0
CLASS_UNDERWATER = 1
CLASS_SURFACE = 2
CLASS_NAMES = ["Ambient Noise", "Underwater Scooter", "Surface Vessel"]
NUM_CLASSES = 3

REAL_DATASET_CONFIGS: List[Dict[str, Any]] = [
    {
        "name": "HaifaBay",
        "rel_path": r"20250805_Haifa_bay_LME\extracted-2",
        "default_class": CLASS_SURFACE,
        "dataset_id": 0,
        "f_low": 20.0,
        "f_high": 1000.0,
        "theta_g": float(np.deg2rad(2.5)),
        "max_vz": 1.85,
        "fw_est": 0.22,
    },
    {
        "name": "Croatia",
        "rel_path": r"Croatia\wav\merged",
        "default_class": CLASS_UNDERWATER,
        "dataset_id": 1,
        "f_low": 400.0,
        "f_high": 1600.0,
        "theta_g": float(np.deg2rad(12.0)),
        "max_vz": 0.35,
        "fw_est": 0.15,
    },
    {
        "name": "AUV",
        "rel_path": r"AUVExp_1_26",
        "default_class": CLASS_UNDERWATER,
        "dataset_id": 2,
        "f_low": 300.0,
        "f_high": 1400.0,
        "theta_g": float(np.deg2rad(14.0)),
        "max_vz": 0.25,
        "fw_est": 0.12,
    },
    {
        "name": "BuoyAmbient",
        "rel_path": r"buoy_02_07_2025\records",
        "default_class": CLASS_AMBIENT,
        "dataset_id": 3,
        "f_low": 20.0,
        "f_high": 1200.0,
        "theta_g": float(np.deg2rad(5.0)),
        "max_vz": 0.10,
        "fw_est": 0.10,
    },
    {
        "name": "HearMyShip",
        "rel_path": r"hear_my_ship\V1",
        "default_class": CLASS_SURFACE,
        "dataset_id": 4,
        "f_low": 20.0,
        "f_high": 1200.0,
        "theta_g": float(np.deg2rad(4.0)),
        "max_vz": 1.50,
        "fw_est": 0.20,
    },
]


@dataclass
class DSPConfig:
    """Parameters for 60s (1-minute) segment loading, 0.5s watershed slicing, multiscale TiB Fairness, and Digital PLL."""
    base_dir: str = DEFAULT_RECORDINGS_DIR
    target_fs: float = 4800.0
    segment_duration_sec: float = 60.0
    buffer_sec: float = 0.5
    tib_tolerance_hz: float = 10.0
    tib_min_win_sec: float = 2.0
    tib_max_win_sec: float = 60.0
    tib_win_step_sec: float = 2.0
    pll_bandpass_margin_hz: float = 80.0
    pll_loop_bw_hz: float = 18.0
    pll_damping_zeta: float = 0.707
    pll_max_freq_dev_hz: float = 60.0
    train_eps_per_dataset: int = 18
    test_eps_per_dataset: int = 6
    test_file_fraction: float = 0.25
    use_cache: bool = True
    num_workers: int = 4
    use_bellhop_synthetic: bool = True
    bellhop_train_eps_per_class: int = 12


@dataclass
class TrainConfig:
    """Hyperparameters for 3-Class Physics-Informed PPO and CPO agent training."""
    reward_mode: str = "tib_fairness"  # "tib_fairness" or "pll_watershed"
    state_dim: int = 9  # [mu_tib, jain_tib, delta_tib, std_tib, bw, masd, plv_r, inst_freq_std, snr_peak]
    action_dim: int = 5  # [delta_f, bw_action_norm, logit_ambient, logit_underwater, logit_surface]
    num_classes: int = NUM_CLASSES
    hidden_dim: int = 64
    epochs: int = 45
    steps_per_epoch: int = 480
    update_iters: int = 8
    lr_actor_critic: float = 8e-4
    lr_lambda: float = 8e-2
    gamma: float = 0.99
    clip_eps: float = 0.2
    entropy_coef: float = 0.01
    max_grad_norm: float = 0.5
    cost_limit: float = 0.05
    ppo_soft_lambda: float = 0.05
    eval_interval: int = 2
    seed: int = 42
    dataset_configs: List[Dict[str, Any]] = field(default_factory=lambda: REAL_DATASET_CONFIGS)
