"""
Main entry point for the Physics-Informed Deep Reinforcement Learning (DRL) pipeline
on the real HaifaBay, Croatia, and AUV hydrophone datasets.

Module structure by responsibility:
  - `config.py`:            Dataset definitions, DSP/PLL parameters, and RL training hyperparameters.
  - `data_loader.py`:       Memory-mapped WAV segment loading and disjoint file-level Train/Test splitting.
  - `feature_extractor.py`: Topographic watershed bandwidth, Hilbert envelope, and 0.5s Digital PLL phase-lock extractor.
  - `env.py`:               Gymnasium RL environment (`AcousticPIMLEnv`) with PIML rewards and CPO constraints.
  - `agent.py`:             Dual-critic Actor-Critic network (`PIMLActorCritic`), PPO/CPO trainer, and evaluator.
  - `reporting.py`:         Console statistical tables and 4-panel figure generation.
"""

import warnings
from config import DSPConfig, TrainConfig, OUTPUT_PLOT_PATH
from data_loader import build_train_test_real_datasets
from env import AcousticPIMLEnv
from agent import train_piml_agent, evaluate_agent_by_dataset
from reporting import (
    print_feature_summary,
    print_evaluation_summary,
    plot_training_and_eval_results,
)

warnings.filterwarnings("ignore")


def main():
    dsp_cfg = DSPConfig()
    train_cfg = TrainConfig()

    print("=" * 100)
    print("PHYSICS-INFORMED DRL PIPELINE ON REAL ACOUSTIC DATASETS (DISJOINT FILE-LEVEL TRAIN / TEST SPLIT)")
    print("=" * 100)
    print("[1/4] Building Disjoint Train (75%) & Held-Out Test (25%) Datasets (0.5s Watershed + Digital PLL)...")

    train_dataset, test_dataset = build_train_test_real_datasets(dsp_cfg, train_cfg.dataset_configs)
    print_feature_summary(train_dataset, test_dataset, train_cfg.dataset_configs)

    train_env = AcousticPIMLEnv(train_dataset, balanced_sampling=True)
    test_env = AcousticPIMLEnv(test_dataset, balanced_sampling=False)

    print("\n[2/4] Training Physics-Informed PPO Agent (Soft Constraints) on TRAIN Split Only...")
    ppo_model, ppo_hist = train_piml_agent(train_env, mode="PPO", train_cfg=train_cfg)

    print("[3/4] Training Physics-Informed CPO Agent (Hard Constraints C(pi) <= d) on TRAIN Split Only...")
    cpo_model, cpo_hist = train_piml_agent(train_env, mode="CPO", train_cfg=train_cfg)

    print("\n[4/4] Evaluating Trained Policies on Disjoint HELD-OUT TEST Files vs. TRAIN Files...")
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
        out_fig_path=OUTPUT_PLOT_PATH,
    )


if __name__ == "__main__":
    main()
