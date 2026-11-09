"""
Console statistical reporting and static figure generation (`drl.visualization.reporting`).
"""

from typing import List, Dict, Any
import numpy as np
import matplotlib.pyplot as plt

from config import (
    REAL_DATASET_CONFIGS,
    OUTPUT_PLOT_PATH,
    OUTPUT_FAIRNESS_PLOT_PATH,
    OUTPUT_FAIRNESS_HIST_PATH,
    OUTPUT_FAIRNESS_CHANGE_PATH,
)


def print_feature_summary(
    train_dataset: List[Dict[str, Any]],
    test_dataset: List[Dict[str, Any]],
    dataset_configs: List[Dict[str, Any]] = None,
) -> None:
    """
    Prints the extracted DSP, Watershed Bandwidth, 0.5s Digital PLL, and
    Per-Minute Multiscale TiB & Scale-Uniformity Fairness summary
    matching `comparison_minute_tib_change.png` and `comparison_minute_tib_histograms.png`.
    """
    if dataset_configs is None:
        dataset_configs = REAL_DATASET_CONFIGS

    n_tr_eps = len(train_dataset)
    n_te_eps = len(test_dataset)
    n_slices_tr = sum(len(d["steps"]) for d in train_dataset)
    n_slices_te = sum(len(d["steps"]) for d in test_dataset)

    print("\n" + "-" * 118)
    print(
        f"EXTRACTED REAL DATASET FEATURE & MULTISCALE TiB FAIRNESS SUMMARY "
        f"(TRAIN: {n_tr_eps} mins [{n_slices_tr} sl] | TEST: {n_te_eps} mins [{n_slices_te} sl])"
    )
    print("-" * 118)
    for cfg in dataset_configs:
        ds_name = cfg["name"]
        tr_recs = [d for d in train_dataset if d["metadata"]["dataset_name"] == ds_name]
        te_recs = [d for d in test_dataset if d["metadata"]["dataset_name"] == ds_name]
        all_recs = tr_recs + te_recs
        all_steps = [s for d in all_recs for s in d["steps"]]

        f_dom_m = np.mean([s["f_dom"] for s in all_steps])
        bw_m = np.mean([s["bw_measured"] for s in all_steps])
        plv_m = np.mean([s["plv_r"] for s in all_steps])

        min_mean_tib = np.mean([d["metadata"]["minute_tib_stats"]["minute_mean_tib"] for d in all_recs])
        min_std_tib = np.mean([d["metadata"]["minute_tib_stats"]["minute_std_tib"] for d in all_recs])
        min_fair_tib = np.mean([d["metadata"]["minute_tib_stats"]["minute_fair_tib"] for d in all_recs])
        min_delta_tib = np.mean([d["metadata"]["minute_tib_stats"]["delta_tib"] for d in all_recs])
        min_delta_std = np.std([d["metadata"]["minute_tib_stats"]["delta_tib"] for d in all_recs])

        print(
            f"  {ds_name:<9} (Train={len(tr_recs):2d}m, Test={len(te_recs):2d}m): "
            f"f_dom={f_dom_m:5.1f} Hz | BW={bw_m:5.1f} Hz | PLL R={plv_m:.3f} | "
            f"MeanTiB={min_mean_tib:.2f} | StdTiB={min_std_tib:.3f} | "
            f"JainFair={min_fair_tib:.3f} | dTiB(60s-2s)={min_delta_tib:+.3f}+/-{min_delta_std:.3f}"
        )
    print("-" * 118)


def print_evaluation_summary(
    ppo_train_eval: Dict[str, Dict[str, float]],
    cpo_train_eval: Dict[str, Dict[str, float]],
    ppo_test_eval: Dict[str, Dict[str, float]],
    cpo_test_eval: Dict[str, Dict[str, float]],
    dataset_configs: List[Dict[str, Any]] = None,
) -> None:
    """Prints the disjoint Train vs. Held-Out Test evaluation comparison table with Multiscale TiB Fairness reward breakdown."""
    if dataset_configs is None:
        dataset_configs = REAL_DATASET_CONFIGS

    print("\n" + "=" * 118)
    print("DISJOINT TRAIN vs. HELD-OUT TEST EVALUATION RESULTS (MULTISCALE TiB & JAIN'S FAIRNESS REWARD)")
    print("=" * 118)
    print(
        f"{'Dataset':<10} | {'Policy':<8} | {'Train Acc':<10} | {'Test Acc':<10} | "
        f"{'Test Cost':<10} | {'Test Reward':<11} | {'Fairness R_f':<12} | {'BW Gate':<10} | {'Target BW':<10}"
    )
    print("-" * 118)
    for cfg in dataset_configs:
        ds_name = cfg["name"]
        p_tr, p_te = ppo_train_eval[ds_name], ppo_test_eval[ds_name]
        c_tr, c_te = cpo_train_eval[ds_name], cpo_test_eval[ds_name]
        print(
            f"{ds_name:<10} | {'PIML-PPO':<8} | {p_tr['accuracy']:9.1f}% | {p_te['accuracy']:9.1f}% | "
            f"{p_te['cost']:10.3f} | {p_te['reward']:+11.3f} | {p_te['fairness_regime_reward']:+12.3f} | "
            f"{p_te['bw_gate_hz']:7.1f} Hz | {p_te['target_bw_hz']:7.1f} Hz"
        )
        print(
            f"{ds_name:<10} | {'PIML-CPO':<8} | {c_tr['accuracy']:9.1f}% | {c_te['accuracy']:9.1f}% | "
            f"{c_te['cost']:10.3f} | {c_te['reward']:+11.3f} | {c_te['fairness_regime_reward']:+12.3f} | "
            f"{c_te['bw_gate_hz']:7.1f} Hz | {c_te['target_bw_hz']:7.1f} Hz"
        )
        print("-" * 118)


def plot_training_and_eval_results(
    ppo_hist: Dict[str, list],
    cpo_hist: Dict[str, list],
    ppo_test_eval: Dict[str, Dict[str, float]],
    cpo_test_eval: Dict[str, Dict[str, float]],
    cost_limit: float = 0.05,
    dataset_configs: List[Dict[str, Any]] = None,
    out_fig_path: str = OUTPUT_FAIRNESS_PLOT_PATH,
    train_dataset: List[Dict[str, Any]] = None,
    test_dataset: List[Dict[str, Any]] = None,
) -> str:
    """
    Renders and saves the 4-panel training and held-out test evaluation figure,
    plus the 2 diagnostic figures matching `comparison_minute_tib_histograms.png`
    and `comparison_minute_tib_change.png`.
    """
    if dataset_configs is None:
        dataset_configs = REAL_DATASET_CONFIGS

    fig, axes = plt.subplots(2, 2, figsize=(15, 9.5))

    axes[0, 0].plot(ppo_hist["reward"], label="PIML-PPO (TiB-Fairness Reward)", color="royalblue", lw=2)
    axes[0, 0].plot(cpo_hist["reward"], label="PIML-CPO (TiB-Fairness Reward)", color="darkorange", lw=2)
    axes[0, 0].set_title(
        "Multiscale TiB & Jain's Fairness Reward ($R_t$) on Train Split", fontweight="bold"
    )
    axes[0, 0].set_xlabel("Epoch")
    axes[0, 0].set_ylabel("Mean Step Reward ($R_{\\mathrm{BW}} + R_{\\mathrm{Fairness}} + R_{\\mathrm{Class}}$)")
    axes[0, 0].legend()
    axes[0, 0].grid(alpha=0.3)

    axes[0, 1].plot(ppo_hist["cost"], label="PIML-PPO Violations", color="royalblue", lw=2)
    axes[0, 1].plot(cpo_hist["cost"], label="PIML-CPO Violations", color="darkorange", lw=2)
    axes[0, 1].axhline(cost_limit, color="crimson", linestyle="--", label=f"Hard Constraint Limit ($d={cost_limit}$)")
    axes[0, 1].set_title("Physical Constraint Violations ($C_t$) — Doppler & TiB Scale Fairness", fontweight="bold")
    axes[0, 1].set_xlabel("Epoch")
    axes[0, 1].set_ylabel("Violation Frequency")
    axes[0, 1].legend()
    axes[0, 1].grid(alpha=0.3)

    axes[1, 0].plot(ppo_hist["accuracy"], label="PIML-PPO (Train)", color="royalblue", lw=2)
    axes[1, 0].plot(cpo_hist["accuracy"], label="PIML-CPO (Train)", color="darkorange", lw=2)
    axes[1, 0].set_title("Surface vs. Submerged Training Accuracy (%)", fontweight="bold")
    axes[1, 0].set_xlabel("Epoch")
    axes[1, 0].set_ylabel("Classification Accuracy (%)")
    axes[1, 0].set_ylim(40, 105)
    axes[1, 0].legend()
    axes[1, 0].grid(alpha=0.3)

    ds_names = [c["name"] for c in dataset_configs]
    x = np.arange(len(ds_names))
    width = 0.34
    ppo_te_accs = [ppo_test_eval[n]["accuracy"] for n in ds_names]
    cpo_te_accs = [cpo_test_eval[n]["accuracy"] for n in ds_names]
    bars1 = axes[1, 1].bar(x - width / 2, ppo_te_accs, width, label="PIML-PPO Held-Out Test (%)", color="royalblue", alpha=0.85)
    bars2 = axes[1, 1].bar(x + width / 2, cpo_te_accs, width, label="PIML-CPO Held-Out Test (%)", color="darkorange", alpha=0.85)
    axes[1, 1].set_xticks(x)
    axes[1, 1].set_xticklabels([
        f"{n}\n({'Surface' if c['is_surface'] else 'Submerged'})\n"
        f"J={cpo_test_eval[n]['minute_fair_tib']:.3f}, dTiB={cpo_test_eval[n]['minute_delta_tib']:+.2f}"
        for n, c in zip(ds_names, dataset_configs)
    ])
    axes[1, 1].set_ylim(0, 115)
    axes[1, 1].set_ylabel("Held-Out Test Accuracy (%)")
    axes[1, 1].set_title("Held-Out Test Accuracy & Multiscale TiB Fairness (Unseen WAVs)", fontweight="bold")
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
    if out_fig_path != OUTPUT_PLOT_PATH:
        plt.savefig(OUTPUT_PLOT_PATH, dpi=300)
    plt.close(fig)
    print(f"\n[Saved] DRL Multiscale TiB Fairness Train/Test Plot: {out_fig_path}")

    if train_dataset is not None and test_dataset is not None:
        plot_minute_tib_fairness_diagnostics(
            train_dataset + test_dataset,
            dataset_configs=dataset_configs,
            out_hist_path=OUTPUT_FAIRNESS_HIST_PATH,
            out_change_path=OUTPUT_FAIRNESS_CHANGE_PATH,
        )

    return out_fig_path


def plot_minute_tib_fairness_diagnostics(
    all_recordings: List[Dict[str, Any]],
    dataset_configs: List[Dict[str, Any]] = None,
    out_hist_path: str = OUTPUT_FAIRNESS_HIST_PATH,
    out_change_path: str = OUTPUT_FAIRNESS_CHANGE_PATH,
) -> None:
    r"""
    Renders the DRL pipeline's extracted per-minute Multiscale TiB & Scale-Uniformity
    Fairness distributions in the exact 3-panel and 4-panel formats of:
      - `comparison_minute_tib_histograms.png` (Mean TiB, Std TiB, Jain's Fairness Index)
      - `comparison_minute_tib_change.png` (\DeltaTiB = TiB(60s) - TiB(2s) KDE, Trajectory, 2s vs 60s Scatter, Summary Bar)
    """
    if dataset_configs is None:
        dataset_configs = REAL_DATASET_CONFIGS

    colors = {"HaifaBay": "#00b4d8", "Croatia": "#f77f00", "AUV": "#a855f7"}

    fig_h, axes_h = plt.subplots(1, 3, figsize=(15.5, 4.8))
    for cfg in dataset_configs:
        ds_name = cfg["name"]
        c = colors.get(ds_name, "steelblue")
        recs = [r for r in all_recordings if r["metadata"]["dataset_name"] == ds_name]
        if not recs:
            continue
        means = np.array([r["metadata"]["minute_tib_stats"]["minute_mean_tib"] for r in recs])
        stds = np.array([r["metadata"]["minute_tib_stats"]["minute_std_tib"] for r in recs])
        fairs = np.array([r["metadata"]["minute_tib_stats"]["minute_fair_tib"] for r in recs])

        axes_h[0].hist(
            means, bins=10, density=True, alpha=0.40, color=c, edgecolor=c, lw=1.2,
            label=f"{ds_name} ($\\mu$: {np.mean(means):.2f}, $\\sigma$: {np.std(means):.2f})"
        )
        axes_h[0].axvline(np.mean(means), color=c, ls="--", lw=1.5)

        axes_h[1].hist(
            stds, bins=10, density=True, alpha=0.40, color=c, edgecolor=c, lw=1.2,
            label=f"{ds_name} ($\\mu$: {np.mean(stds):.3f}, $\\sigma$: {np.std(stds):.3f})"
        )
        axes_h[1].axvline(np.mean(stds), color=c, ls="--", lw=1.5)

        axes_h[2].hist(
            fairs, bins=10, density=True, alpha=0.40, color=c, edgecolor=c, lw=1.2,
            label=f"{ds_name} ($\\mu$: {np.mean(fairs):.3f}, $\\sigma$: {np.std(fairs):.3f})"
        )
        axes_h[2].axvline(np.mean(fairs), color=c, ls="--", lw=1.5)

    axes_h[0].set_title("Per-Minute Mean TiB Distribution (2s to 60s)", fontweight="bold")
    axes_h[0].set_xlabel("Mean TiB per Minute")
    axes_h[0].set_ylabel("Probability Density")
    axes_h[0].set_xlim(0.0, 1.05)
    axes_h[0].legend(fontsize=8.5)
    axes_h[0].grid(alpha=0.3)

    axes_h[1].set_title("Per-Minute TiB Std Distribution (Scale Dispersion)", fontweight="bold")
    axes_h[1].set_xlabel("Std TiB per Minute ($\\sigma_{\\mathrm{TiB}}$)")
    axes_h[1].set_ylabel("Probability Density")
    axes_h[1].legend(fontsize=8.5)
    axes_h[1].grid(alpha=0.3)

    axes_h[2].set_title("Per-Minute Jain's Fairness Index (Scale Uniformity)", fontweight="bold")
    axes_h[2].set_xlabel("Jain's Fairness Index per Minute ($\\mathcal{J}_{\\mathrm{TiB}}$)")
    axes_h[2].set_ylabel("Probability Density")
    axes_h[2].set_xlim(0.70, 1.02)
    axes_h[2].legend(fontsize=8.5)
    axes_h[2].grid(alpha=0.3)

    plt.tight_layout()
    plt.savefig(out_hist_path, dpi=300)
    plt.close(fig_h)
    print(f"[Saved] DRL Per-Minute TiB Fairness Histograms: {out_hist_path}")

    fig_c, axes_c = plt.subplots(2, 2, figsize=(14.5, 8.8))
    axes_c[0, 0].axvline(0.0, color="gray", ls="--", lw=1.2, label="Zero Change ($\\Delta = 0$)")
    axes_c[0, 1].axhline(0.0, color="gray", ls="--", lw=1.2, label="Zero Drift ($\\Delta = 0$)")
    axes_c[1, 0].plot([0, 1], [0, 1], color="gray", ls="--", lw=1.2, label="Identity Line (No Drift)")
    axes_c[1, 1].axhline(0.0, color="gray", ls="--", lw=1.2)

    ds_names = [c["name"] for c in dataset_configs]
    for k, cfg in enumerate(dataset_configs):
        ds_name = cfg["name"]
        c = colors.get(ds_name, "steelblue")
        recs = [r for r in all_recordings if r["metadata"]["dataset_name"] == ds_name]
        if not recs:
            continue
        deltas = np.array([r["metadata"]["minute_tib_stats"]["delta_tib"] for r in recs])
        starts = np.array([r["metadata"]["minute_tib_stats"]["tib_2s"] for r in recs])
        ends = np.array([r["metadata"]["minute_tib_stats"]["tib_end"] for r in recs])
        t_idx = np.arange(1, len(deltas) + 1)

        m_d = float(np.mean(deltas))
        s_d = float(np.std(deltas))

        axes_c[0, 0].hist(
            deltas, bins=10, density=True, alpha=0.35, color=c, edgecolor=c, lw=1.4,
            label=f"{ds_name} ($\\mu$: {m_d:+.2f}, $\\sigma$: {s_d:.2f})"
        )
        axes_c[0, 0].axvline(m_d, color=c, ls=":", lw=1.5)

        axes_c[0, 1].plot(t_idx, deltas, ".-", color=c, lw=1.4, markersize=7, label=ds_name)
        axes_c[1, 0].scatter(starts, ends, s=42, color=c, alpha=0.70, label=f"{ds_name} (N={len(deltas)})")

        axes_c[1, 1].bar(k, m_d, width=0.52, color=c, edgecolor=c, alpha=0.75, label=ds_name)
        axes_c[1, 1].errorbar(k, m_d, yerr=s_d, color="black", lw=1.5, capsize=8)
        offset = (0.04 + s_d) if m_d >= 0 else -(0.06 + s_d)
        axes_c[1, 1].text(
            k, m_d + offset, f"{m_d:+.3f}\n$\\pm${s_d:.3f}",
            ha="center", va="bottom" if m_d >= 0 else "top", fontsize=8.5, fontweight="bold"
        )

    axes_c[0, 0].set_title("Distribution of Per-Minute $\\Delta\\mathrm{TiB}$ (60s - 2s)", fontweight="bold")
    axes_c[0, 0].set_xlabel("$\\Delta\\mathrm{TiB} = \\mathrm{TiB}(60\\mathrm{s}) - \\mathrm{TiB}(2\\mathrm{s})$")
    axes_c[0, 0].set_ylabel("Probability Density")
    axes_c[0, 0].legend(fontsize=8.5)
    axes_c[0, 0].grid(alpha=0.3)

    axes_c[0, 1].set_title("Per-Minute $\\Delta\\mathrm{TiB}$ Trajectory Across Episodes", fontweight="bold")
    axes_c[0, 1].set_xlabel("Episode Index (1-Minute Segments)")
    axes_c[0, 1].set_ylabel("$\\Delta\\mathrm{TiB}$ (Change in TiB)")
    axes_c[0, 1].legend(fontsize=8.5)
    axes_c[0, 1].grid(alpha=0.3)

    axes_c[1, 0].set_title("Start (2s) vs End (60s) TiB Scale Drift", fontweight="bold")
    axes_c[1, 0].set_xlabel("Start TiB (Window $W = 2$ s)")
    axes_c[1, 0].set_ylabel("End TiB (Window $W = 60$ s)")
    axes_c[1, 0].set_xlim(0.0, 1.05)
    axes_c[1, 0].set_ylim(0.0, 1.05)
    axes_c[1, 0].legend(fontsize=8.5)
    axes_c[1, 0].grid(alpha=0.3)

    axes_c[1, 1].set_title("Dataset Scale Stability Summary (Mean $\\Delta\\mathrm{TiB} \\pm$ SD)", fontweight="bold")
    axes_c[1, 1].set_xticks(range(len(ds_names)))
    axes_c[1, 1].set_xticklabels(ds_names)
    axes_c[1, 1].set_ylabel("Mean $\\Delta\\mathrm{TiB} \\pm$ SD")
    axes_c[1, 1].set_ylim(-0.85, 0.35)
    axes_c[1, 1].legend(fontsize=8.5)
    axes_c[1, 1].grid(axis="y", alpha=0.3)

    plt.tight_layout()
    plt.savefig(out_change_path, dpi=300)
    plt.close(fig_c)
    print(f"[Saved] DRL Per-Minute TiB Change Comparison: {out_change_path}")

