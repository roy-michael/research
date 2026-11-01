"""
Configuration module for the Physics-Informed Deep Reinforcement Learning (DRL)
pipeline on the real HaifaBay, Croatia, and AUV acoustic datasets.
"""

import os
from dataclasses import dataclass, field
from typing import List, Dict, Any
import numpy as np


DEFAULT_RECORDINGS_DIR = r"D:\RoyStudies\Recordings"
OUTPUT_PLOT_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "drl_real_datasets_results.png")


REAL_DATASET_CONFIGS: List[Dict[str, Any]] = [
    {
        "name": "HaifaBay",
        "rel_path": r"20250805_Haifa_bay_LME\extracted-2",
        "is_surface": 1,
        "dataset_id": 0,
        "f_low": 0.0,
        "f_high": 2000.0,
        "theta_g": float(np.deg2rad(2.5)),
        "max_vz": 1.85,
        "fw_est": 0.22,
    },
    {
        "name": "Croatia",
        "rel_path": r"Croatia\wav\merged",
        "is_surface": 0,
        "dataset_id": 1,
        "f_low": 400.0,
        "f_high": 2000.0,
        "theta_g": float(np.deg2rad(12.0)),
        "max_vz": 0.35,
        "fw_est": 0.15,
    },
    {
        "name": "AUV",
        "rel_path": r"AUVExp_1_26",
        "is_surface": 0,
        "dataset_id": 2,
        "f_low": 400.0,
        "f_high": 2000.0,
        "theta_g": float(np.deg2rad(14.0)),
        "max_vz": 0.25,
        "fw_est": 0.12,
    },
]


@dataclass
class DSPConfig:
    """Parameters for 30s segment loading, 0.5s watershed slicing, and 2nd-order Digital PLL."""
    base_dir: str = DEFAULT_RECORDINGS_DIR
    target_fs: float = 4800.0
    segment_duration_sec: float = 30.0
    buffer_sec: float = 0.5
    tib_tolerance_hz: float = 15.0
    pll_bandpass_margin_hz: float = 80.0
    pll_loop_bw_hz: float = 18.0
    pll_damping_zeta: float = 0.707
    pll_max_freq_dev_hz: float = 60.0
    train_eps_per_dataset: int = 18
    test_eps_per_dataset: int = 6
    test_file_fraction: float = 0.25


@dataclass
class TrainConfig:
    """Hyperparameters for PIML-PPO and PIML-CPO agent training."""
    state_dim: int = 8
    action_dim: int = 3
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
    seed: int = 42
    dataset_configs: List[Dict[str, Any]] = field(default_factory=lambda: REAL_DATASET_CONFIGS)

