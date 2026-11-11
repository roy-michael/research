"""
Main entry point for the Physics-Informed Deep Reinforcement Learning (DRL) pipeline
on the real HaifaBay, Croatia, and AUV hydrophone datasets.

Package structure organized by module and real usage:
  - `config.py`:                    Dataset definitions, DSP/PLL parameters, and RL training hyperparameters.
  - `data/loader.py`:               Memory-mapped WAV segment loading and disjoint file-level Train/Test splitting.
  - `dsp/watershed_tracker.py`:     Welch PSD, macro-lobe segmentation, and 0.5s topographic watershed bandwidth tracker.
  - `dsp/feature_extractor.py`:     Multiscale TiB & Jain's Fairness [2s..60s], Hilbert envelope, and 0.5s Digital PLL extractor.
  - `rl/env.py`:                    Gymnasium RL environment (`AcousticPIMLEnv`) with PIML rewards and CPO constraints.
  - `rl/agent.py`:                  Dual-critic Actor-Critic network (`PIMLActorCritic`), PPO/CPO trainer, and evaluator.
  - `visualization/live_dashboard.py`: Real-time 6-panel Matplotlib dashboard (`LiveTrainingDashboard`) over all datasets.
  - `visualization/reporting.py`:   Console statistical tables and static figure generation into `output/`.
"""

import argparse
import warnings

from config import DSPConfig, TrainConfig, OUTPUT_FAIRNESS_PLOT_PATH, OUTPUT_LIVE_DASHBOARD_PATH
from data import build_train_test_real_datasets
from rl import AcousticPIMLEnv, train_piml_agent, evaluate_agent_by_dataset
from visualization import (
    LiveTrainingDashboard,
    print_feature_summary,
    print_evaluation_summary,
    plot_training_and_eval_results,
)

warnings.filterwarnings("ignore")


def main(
    reward_mode: str = "tib_fairness",
    epochs: int = None,
    eval_interval: int = None,
    no_cache: bool = False,
    no_bellhop: bool = False,
    live_plot: bool = True,
    enable_gui: bool = True,
    block_on_finish: bool = False,
):
    dsp_cfg = DSPConfig(use_cache=not no_cache, use_bellhop_synthetic=not no_bellhop)
    train_cfg = TrainConfig(reward_mode=reward_mode)
    if epochs is not None:
        train_cfg.epochs = int(epochs)
    if eval_interval is not None:
        train_cfg.eval_interval = int(eval_interval)

    print("=" * 118)
    print(
        f"PHYSICS-INFORMED DRL PIPELINE ON REAL ACOUSTIC DATASETS "
        f"(REWARD MODE: {train_cfg.reward_mode.upper()} | DISJOINT TRAIN / TEST SPLIT)"
    )
    print("=" * 118)
    print(
        "[1/4] Building Disjoint Train (75%) & Held-Out Test (25%) 1-Minute Datasets "
        "(Watershed + Multiscale TiB Fairness [2s..60s] + Digital PLL)..."
    )

    train_dataset, test_dataset = build_train_test_real_datasets(dsp_cfg, train_cfg.dataset_configs)
    print_feature_summary(train_dataset, test_dataset, train_cfg.dataset_configs)

    train_env = AcousticPIMLEnv(train_dataset, balanced_sampling=True, reward_mode=train_cfg.reward_mode)
    test_env = AcousticPIMLEnv(test_dataset, balanced_sampling=False, reward_mode=train_cfg.reward_mode)

    dashboard = None
    if live_plot:
        dashboard = LiveTrainingDashboard(
            epochs=train_cfg.epochs,
            cost_limit=train_cfg.cost_limit,
            dataset_configs=train_cfg.dataset_configs,
            out_path=OUTPUT_LIVE_DASHBOARD_PATH,
            enable_gui=enable_gui,
        )

    print(
        f"\n[2/4] Training Physics-Informed PPO Agent ({train_cfg.reward_mode} reward, Soft Constraints) "
        f"with Live Per-Dataset Verification..."
    )
    ppo_model, ppo_hist = train_piml_agent(
        train_env,
        mode="PPO",
        train_cfg=train_cfg,
        eval_env=test_env,
        epoch_callback=dashboard.on_epoch_end if dashboard else None,
    )

    print(
        f"\n[3/4] Training Physics-Informed CPO Agent ({train_cfg.reward_mode} reward, Hard Constraints C(pi) <= d) "
        f"with Live Per-Dataset Verification..."
    )
    cpo_model, cpo_hist = train_piml_agent(
        train_env,
        mode="CPO",
        train_cfg=train_cfg,
        eval_env=test_env,
        epoch_callback=dashboard.on_epoch_end if dashboard else None,
    )

    if dashboard is not None:
        dashboard.finalize(block=block_on_finish)

    print("\n[4/4] Evaluating Final Trained Policies on Disjoint HELD-OUT TEST Files vs. TRAIN Files...")
    ppo_train_eval = evaluate_agent_by_dataset(train_env, ppo_model)
    cpo_train_eval = evaluate_agent_by_dataset(train_env, cpo_model)
    ppo_test_eval = evaluate_agent_by_dataset(test_env, ppo_model)
    cpo_test_eval = evaluate_agent_by_dataset(test_env, cpo_model)

    print_evaluation_summary(
        ppo_train_eval, cpo_train_eval, ppo_test_eval, cpo_test_eval, train_cfg.dataset_configs
    )
    plot_training_and_eval_results(
        ppo_hist,
        cpo_hist,
        ppo_test_eval,
        cpo_test_eval,
        cost_limit=train_cfg.cost_limit,
        dataset_configs=train_cfg.dataset_configs,
        out_fig_path=OUTPUT_FAIRNESS_PLOT_PATH,
        train_dataset=train_dataset,
        test_dataset=test_dataset,
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Physics-Informed DRL Pipeline with Live Training & Verification Plot")
    parser.add_argument("--reward-mode", type=str, default="tib_fairness", choices=["tib_fairness", "pll_watershed"])
    parser.add_argument("--epochs", type=int, default=None, help="Number of training epochs")
    parser.add_argument("--eval-interval", type=int, default=None, help="Evaluation interval in epochs (default: 2)")
    parser.add_argument("--no-cache", action="store_true", help="Force recomputing extracted features without reading disk cache")
    parser.add_argument("--no-bellhop", action="store_true", help="Disable BELLHOP synthetic physics augmentation in training")
    parser.add_argument("--no-gui", action="store_true", help="Disable interactive GUI window while still streaming live plot snapshots")
    parser.add_argument("--block", action="store_true", help="Keep the interactive live dashboard window open after completion")
    args = parser.parse_args()
    main(
        reward_mode=args.reward_mode,
        epochs=args.epochs,
        eval_interval=args.eval_interval,
        no_cache=args.no_cache,
        no_bellhop=args.no_bellhop,
        live_plot=True,
        enable_gui=not args.no_gui,
        block_on_finish=args.block,
    )
