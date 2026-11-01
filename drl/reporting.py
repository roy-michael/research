"""
Console reporting and 4-panel Matplotlib figure generation for the DRL pipeline.
"""

from typing import List, Dict, Any
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

from config import REAL_DATASET_CONFIGS, OUTPUT_PLOT_PATH


def print_feature_summary(
    train_dataset: List[Dict[str, Any]],
    test_dataset: List[Dict[str, Any]],
    dataset_configs: List[Dict[str, Any]] = None,
) -> None:
    """Prints the extracted DSP, Watershed Bandwidth, and 0.5s Digital PLL feature summary."""
    if dataset_configs is None:
        dataset_configs = REAL_DATASET_CONFIGS

    n_tr_eps = len(train_dataset)
    n_te_eps = len(test_dataset)
    print("\n" + "-" * 100)
    print(
        f"EXTRACTED REAL DATASET FEATURE SUMMARY "
        f"(TRAIN: {n_tr_eps} eps / {n_tr_eps * 60} slices | TEST: {n_te_eps} eps / {n_te_eps * 60} slices)"
    )
    print("-" * 100)
    for cfg in dataset_configs:
        ds_name = cfg["name"]
        tr_recs = [d for d in train_dataset if d["metadata"]["dataset_name"] == ds_name]
        te_recs = [d for d in test_dataset if d["metadata"]["dataset_name"] == ds_name]
        all_steps = [s for d in (tr_recs + te_recs) for s in d["steps"]]
        f_dom_m = np.mean([s["f_dom"] for s in all_steps])
        bw_m = np.mean([s["bw_measured"] for s in all_steps])
        plv_m = np.mean([s["plv_r"] for s in all_steps])
        fstd_m = np.mean([s["inst_freq_std"] for s in all_steps])
        verr_m = np.mean([s["freq_verif_err"] for s in all_steps])
        tib_m = np.mean([s["tib"] for s in all_steps])
        jain_m = np.mean([s["jain"] for s in all_steps])
        print(
            f"  {ds_name:<9} (Train={len(tr_recs):2d} eps [{len(tr_recs)*60:4d} sl], "
            f"Test={len(te_recs):2d} eps [{len(te_recs)*60:3d} sl]): "
            f"f_dom={f_dom_m:6.1f} Hz | BW={bw_m:5.1f} Hz | PLL R={plv_m:.3f} | "
            f"sigma_f={fstd_m:4.1f} Hz | |f_PLL-f_FFT|={verr_m:4.2f} Hz | TiB={tib_m:.2f} | Jain={jain_m:.3f}"
        )
    print("-" * 100)


def print_evaluation_summary(
    ppo_train_eval: Dict[str, Dict[str, float]],
    cpo_train_eval: Dict[str, Dict[str, float]],
    ppo_test_eval: Dict[str, Dict[str, float]],
    cpo_test_eval: Dict[str, Dict[str, float]],
    dataset_configs: List[Dict[str, Any]] = None,
) -> None:
    """Prints the disjoint Train vs. Held-Out Test evaluation comparison table."""
    if dataset_configs is None:
        dataset_configs = REAL_DATASET_CONFIGS

    print("\n" + "=" * 100)
    print("DISJOINT TRAIN vs. HELD-OUT TEST EVALUATION RESULTS (UNSEEN WAV FILES)")
    print("=" * 100)
    print(
        f"{'Dataset':<10} | {'Policy':<8} | {'Train Acc (%)':<13} | {'Test Acc (%)':<13} | "
        f"{'Test Viol. Rate':<15} | {'Test BW Gate':<14} | {'Target BW':<10}"
    )
    print("-" * 100)
    for cfg in dataset_configs:
        ds_name = cfg["name"]
        p_tr, p_te = ppo_train_eval[ds_name], ppo_test_eval[ds_name]
        c_tr, c_te = cpo_train_eval[ds_name], cpo_test_eval[ds_name]
        print(
            f"{ds_name:<10} | {'PIML-PPO':<8} | {p_tr['accuracy']:12.1f}% | {p_te['accuracy']:12.1f}% | "
            f"{p_te['cost']:15.3f} | {p_te['bw_gate_hz']:11.1f} Hz | {p_te['target_bw_hz']:7.1f} Hz"
        )
        print(
            f"{ds_name:<10} | {'PIML-CPO':<8} | {c_tr['accuracy']:12.1f}% | {c_te['accuracy']:12.1f}% | "
            f"{c_te['cost']:15.3f} | {c_te['bw_gate_hz']:11.1f} Hz | {c_te['target_bw_hz']:7.1f} Hz"
        )
        print("-" * 100)


def plot_training_and_eval_results(
    ppo_hist: Dict[str, list],
    cpo_hist: Dict[str, list],
    ppo_test_eval: Dict[str, Dict[str, float]],
    cpo_test_eval: Dict[str, Dict[str, float]],
    cost_limit: float = 0.05,
    dataset_configs: List[Dict[str, Any]] = None,
    out_fig_path: str = OUTPUT_PLOT_PATH,
) -> str:
    """Renders and saves the 4-panel training and held-out test evaluation figure."""
    if dataset_configs is None:
        dataset_configs = REAL_DATASET_CONFIGS

    fig, axes = plt.subplots(2, 2, figsize=(15, 9.5))

    # Panel 1: Physics-Informed Reward
    axes[0, 0].plot(ppo_hist["reward"], label="PIML-PPO (Train)", color="royalblue", lw=2)
    axes[0, 0].plot(cpo_hist["reward"], label="PIML-CPO (Train)", color="darkorange", lw=2)
    axes[0, 0].set_title("Physics-Informed Reward ($R_t$) on Train Split", fontweight="bold")
    axes[0, 0].set_xlabel("Epoch")
    axes[0, 0].set_ylabel("Mean Step Reward")
    axes[0, 0].legend()
    axes[0, 0].grid(alpha=0.3)

    # Panel 2: Physical Constraint Violations
    axes[0, 1].plot(ppo_hist["cost"], label="PIML-PPO Violations", color="royalblue", lw=2)
    axes[0, 1].plot(cpo_hist["cost"], label="PIML-CPO Violations", color="darkorange", lw=2)
    axes[0, 1].axhline(cost_limit, color="crimson", linestyle="--", label=f"Hard Constraint Limit ($d={cost_limit}$)")
    axes[0, 1].set_title("Physical Constraint Violations ($C_t$) — Doppler & PLL Coherence", fontweight="bold")
    axes[0, 1].set_xlabel("Epoch")
    axes[0, 1].set_ylabel("Violation Frequency")
    axes[0, 1].legend()
    axes[0, 1].grid(alpha=0.3)

    # Panel 3: Surface vs. Submerged Training Accuracy
    axes[1, 0].plot(ppo_hist["accuracy"], label="PIML-PPO (Train)", color="royalblue", lw=2)
    axes[1, 0].plot(cpo_hist["accuracy"], label="PIML-CPO (Train)", color="darkorange", lw=2)
    axes[1, 0].set_title("Surface vs. Submerged Training Accuracy (%)", fontweight="bold")
    axes[1, 0].set_xlabel("Epoch")
    axes[1, 0].set_ylabel("Classification Accuracy (%)")
    axes[1, 0].set_ylim(40, 105)
    axes[1, 0].legend()
    axes[1, 0].grid(alpha=0.3)

    # Panel 4: Held-Out Test Set Evaluation Breakdown (Unseen WAV Files)
    ds_names = [c["name"] for c in dataset_configs]
    x = np.arange(len(ds_names))
    width = 0.34
    ppo_te_accs = [ppo_test_eval[n]["accuracy"] for n in ds_names]
    cpo_te_accs = [cpo_test_eval[n]["accuracy"] for n in ds_names]
    bars1 = axes[1, 1].bar(x - width / 2, ppo_te_accs, width, label="PIML-PPO Held-Out Test (%)", color="royalblue", alpha=0.85)
    bars2 = axes[1, 1].bar(x + width / 2, cpo_te_accs, width, label="PIML-CPO Held-Out Test (%)", color="darkorange", alpha=0.85)
    axes[1, 1].set_xticks(x)
    axes[1, 1].set_xticklabels([f"{n}\n({'Surface' if c['is_surface'] else 'Submerged'})" for n, c in zip(ds_names, dataset_configs)])
    axes[1, 1].set_ylim(0, 115)
    axes[1, 1].set_ylabel("Held-Out Test Accuracy (%)")
    axes[1, 1].set_title("Held-Out Test Set Accuracy on Unseen WAV Files (25% Split)", fontweight="bold")
    for b in list(bars1) + list(bars2):
        h = b.get_height()
        axes[1, 1].annotate(
            f"{h:.1f}%",
            xy=(b.get_x() + b.get_width() / 2, h),
            xytext=(0, 3),
            textcoords="offset points",
            ha="center",
            va="bottom",
            fontsize=9,
            fontweight="bold",
        )
    axes[1, 1].legend(loc="lower right")
    axes[1, 1].grid(axis="y", alpha=0.3)

    plt.tight_layout()
    plt.savefig(out_fig_path, dpi=300)
    plt.close(fig)
    print(f"\n[Saved] DRL Disjoint Train/Test Plot: {out_fig_path}")
    return out_fig_path

