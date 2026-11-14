"""
Compute Jain's Fairness Index across multiscale features (W = 2s..60s) for each minute
and plot minute-by-minute across all 24 chronological minutes per dataset from
`drl/output/extracted_features_cache.pkl`.
"""

import os
import sys
import pickle
import numpy as np
import matplotlib.pyplot as plt

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import FEATURE_CACHE_PATH, OUTPUT_DIR
from dsp.feature_extractor import OfflineFeatureExtractor


DATASET_STYLES = [
    ("BuoyAmbient", "BuoyAmbient (Ambient)", "#4C72B0"),
    ("Croatia", "Croatia (Underwater)", "#55A868"),
    ("AUV", "AUV (Underwater)", "#1B9E77"),
    ("HaifaBay", "HaifaBay (Surface)", "#C44E52"),
    ("HearMyShip", "HearMyShip (Surface)", "#DD8452"),
]


def jains_index(values: np.ndarray) -> float:
    x = np.asarray(values, dtype=np.float64)
    x = x[np.isfinite(x) & (x >= 0)]
    if len(x) == 0:
        return 1.0
    s_val = float(np.sum(x))
    s_sq = float(np.sum(x ** 2))
    return float((s_val ** 2) / (len(x) * s_sq)) if s_sq > 0 else 1.0


def multiscale_block_means(series: np.ndarray, buffer_sec: float = 0.5, min_win: float = 2.0,
                           max_win: float = 60.0, step_win: float = 2.0) -> np.ndarray:
    """
    Partition a 1-minute `series` into non-overlapping blocks of size W (2s..max_win in 2s steps),
    compute the mean at each scale W, and return the multiscale curve.
    """
    arr = np.asarray(series, dtype=np.float64)
    arr = arr[np.isfinite(arr) & (arr >= 0)]
    T = len(arr)
    if T == 0:
        return np.array([1.0], dtype=np.float64)

    total_time = T * buffer_sec
    eff_max = float(np.floor(min(max_win, total_time)))
    if eff_max < min_win:
        return np.array([float(np.mean(arr))], dtype=np.float64)

    wins = np.arange(min_win, eff_max + 0.5 * step_win, step_win, dtype=np.float64)
    fs_samples = 1.0 / buffer_sec
    curve = []
    for w in wins:
        N = max(1, int(round(w * fs_samples)))
        num_blocks = T // N
        if num_blocks < 1:
            continue
        blocks = arr[: num_blocks * N].reshape(num_blocks, N)
        curve.append(float(np.mean(np.mean(blocks, axis=1))))
    return np.asarray(curve, dtype=np.float64) if curve else np.array([float(np.mean(arr))], dtype=np.float64)


def multiscale_bw_fairness_and_entropy(bws: np.ndarray, buffer_sec: float = 0.5, min_win: float = 2.0,
                                       max_win: float = 60.0, step_win: float = 2.0, max_bins: int = 20):
    """
    Matches `BandwidthTracker.compute_stability_vs_window`:
    Returns (mean_fairness(W), mean_entropy(W)) curves across W = 2s..max_win for a 1-minute segment.
    """
    arr = np.asarray(bws, dtype=np.float64)
    arr = arr[np.isfinite(arr) & (arr > 0)]
    T = len(arr)
    if T == 0:
        return np.array([1.0]), np.array([0.0])

    total_time = T * buffer_sec
    eff_max = float(np.floor(min(max_win, total_time)))
    if eff_max < min_win:
        return np.array([jains_index(arr)]), np.array([0.0])

    wins = np.arange(min_win, eff_max + 0.5 * step_win, step_win, dtype=np.float64)
    fs_samples = 1.0 / buffer_sec
    fair_curve = []
    ent_curve = []
    for w in wins:
        N = max(1, int(round(w * fs_samples)))
        num_blocks = T // N
        if num_blocks < 1:
            continue
        f_blocks = np.empty(num_blocks, dtype=np.float64)
        e_blocks = np.empty(num_blocks, dtype=np.float64)
        for b in range(num_blocks):
            blk = arr[b * N: (b + 1) * N]
            M = len(blk)
            f_blocks[b] = jains_index(blk)
            if M < 2:
                e_blocks[b] = 0.0
            else:
                nb = min(max_bins, M, max(2, int(round(np.sqrt(M) * 1.8))))
                counts, _ = np.histogram(blk, bins=nb)
                s_c = np.sum(counts)
                if s_c <= 0:
                    e_blocks[b] = 0.0
                else:
                    p = counts / s_c
                    p = p[p > 0]
                    if len(p) <= 1:
                        e_blocks[b] = 0.0
                    else:
                        H = -np.sum(p * np.log2(p))
                        e_blocks[b] = float(H / np.log2(len(counts)))
        fair_curve.append(float(np.mean(f_blocks)))
        ent_curve.append(float(np.mean(e_blocks)))
    return np.asarray(fair_curve, dtype=np.float64), np.asarray(ent_curve, dtype=np.float64)


def compute_minute_fairness_summary(rec: dict, extractor: OfflineFeatureExtractor) -> dict:
    """Compute one multiscale fairness summary per 1-minute recording."""
    steps = rec["steps"]
    bws_raw = np.array([float(st["bw_measured"]) for st in steps], dtype=np.float64)
    plvs_raw = np.array([float(st["plv_r"]) for st in steps], dtype=np.float64)
    masds = np.array([float(st["masd"]) for st in steps], dtype=np.float64)
    fstds = np.array([float(st["inst_freq_std"]) for st in steps], dtype=np.float64)

    med_k = max(3, int(round(5.0 / 0.5)))  # 10 samples (5s)
    bws_med = extractor.medfilt1_matlab(bws_raw, med_k)
    plvs_med = extractor.medfilt1_matlab(plvs_raw, med_k)

    # 1. Full-minute TiB multiscale fairness
    j_tib = float(steps[0]["minute_fair_tib"])

    # 2. Bandwidth block fairness & entropy across scales W=2s..60s
    bw_fair_curve, bw_ent_curve = multiscale_bw_fairness_and_entropy(bws_med)
    j_bw = jains_index(bw_fair_curve)
    j_ent = jains_index(1.0 - bw_ent_curve)

    # 3. PLV, MASD, and PLL inst_freq_std across scales W=2s..60s
    j_plv = jains_index(multiscale_block_means(plvs_med))
    j_masd = jains_index(multiscale_block_means(masds))
    j_fstd = jains_index(multiscale_block_means(fstds))

    # 4. Cross-feature Jain's Fairness across all 6 multiscale fairness indices
    j_cross = jains_index([j_tib, j_bw, j_ent, j_plv, j_masd, j_fstd])

    # 5. Jain's Fairness across the full-minute TiB summary vector
    tib_vec = [
        float(steps[0]["minute_mean_tib"]),
        float(steps[0]["minute_fair_tib"]),
        float(steps[0]["minute_tib_2s"]),
        float(steps[0]["minute_tib_60s"]),
        max(0.0, 1.0 - float(steps[0]["minute_std_tib"])),
    ]
    j_tib_vec = jains_index(tib_vec)

    return {
        "fair_tib": j_tib,
        "fair_bw_scale": j_bw,
        "fair_entropy_scale": j_ent,
        "fair_plv_scale": j_plv,
        "fair_masd_scale": j_masd,
        "fair_fstd_scale": j_fstd,
        "fair_cross_multiscale": j_cross,
        "fair_tib_summary_vec": j_tib_vec,
    }


def main():
    if not os.path.exists(FEATURE_CACHE_PATH):
        raise FileNotFoundError(f"Feature cache not found: {FEATURE_CACHE_PATH}")

    with open(FEATURE_CACHE_PATH, "rb") as f:
        cached = pickle.load(f)
    all_recs = list(cached.get("train_dataset", [])) + list(cached.get("test_dataset", []))

    by_ds = {name: [] for name, _, _ in DATASET_STYLES}
    for rec in all_recs:
        ds_name = rec["metadata"]["dataset_name"]
        if ds_name in by_ds:
            by_ds[ds_name].append(rec)

    # Sort each dataset's minutes chronologically by (source_file, start_sec)
    extractor = OfflineFeatureExtractor()
    series_by_ds = {}
    for ds_name, recs in by_ds.items():
        recs_sorted = sorted(
            recs,
            key=lambda r: (str(r["metadata"].get("source_file", "")), float(r["metadata"].get("start_sec", 0.0))),
        )
        series_by_ds[ds_name] = [compute_minute_fairness_summary(r, extractor) for r in recs_sorted]

    panels = [
        ("fair_tib", "Jain Fairness of TiB(W) per Minute"),
        ("fair_bw_scale", "Jain Fairness of BW Fairness(W) per Minute"),
        ("fair_entropy_scale", "Jain Fairness of [1 - Entropy(W)] per Minute"),
        ("fair_plv_scale", "Jain Fairness of PLV(W) per Minute"),
        ("fair_masd_scale", "Jain Fairness of MASD(W) per Minute"),
        ("fair_fstd_scale", "Jain Fairness of PLL Freq Std(W) per Minute"),
        ("fair_cross_multiscale", "Cross-Feature Jain Fairness (6 Multiscale Indices)"),
        ("fair_tib_summary_vec", "Jain Fairness Across Minute TiB Summary Vector"),
    ]

    fig, axes = plt.subplots(2, 4, figsize=(21, 9), sharex=True)
    axes_flat = axes.ravel()

    print("\n=== Per-Minute Multiscale Fairness Summary Across Dataset Timeline ===")
    for p_idx, (key, title) in enumerate(panels):
        ax = axes_flat[p_idx]
        print(f"\n[{title}]")
        for ds_name, label, color in DATASET_STYLES:
            summaries = series_by_ds.get(ds_name, [])
            if not summaries:
                continue
            vals = np.array([s[key] for s in summaries], dtype=np.float64)
            mins = np.arange(1, len(vals) + 1)

            ax.plot(mins, vals, marker="o", markersize=3.5, color=color, linewidth=1.6, label=label, alpha=0.9)
            print(f"  {ds_name:12s} ({len(vals)} mins): mean={np.mean(vals):.4f} +/- {np.std(vals):.4f}, min={np.min(vals):.4f}, max={np.max(vals):.4f}")

        ax.set_title(title, fontsize=10.5, fontweight="bold")
        ax.set_ylabel("Jain's Fairness Index", fontsize=9)
        ax.grid(True, linestyle="--", alpha=0.35)
        if p_idx >= 4:
            ax.set_xlabel("Time (Minute Index)", fontsize=9)

    handles, labels = axes_flat[0].get_legend_handles_labels()
    fig.legend(
        handles,
        labels,
        loc="upper center",
        bbox_to_anchor=(0.5, 0.96),
        ncol=len(DATASET_STYLES),
        frameon=True,
        fontsize=10,
    )
    fig.suptitle(
        "Per-Minute Multiscale Fairness Over Time (W = 2s..60s per Minute, 24 Minutes per Dataset)",
        fontsize=14,
        fontweight="bold",
        y=0.995,
    )
    plt.tight_layout(rect=[0, 0, 1, 0.92])

    out_path = os.path.join(OUTPUT_DIR, "drl_multiscale_feature_fairness_over_time.png")
    fig.savefig(out_path, dpi=180, bbox_inches="tight")
    plt.close(fig)
    print(f"\nSaved: {out_path}")


if __name__ == "__main__":
    main()
