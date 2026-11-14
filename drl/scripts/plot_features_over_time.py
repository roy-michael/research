"""
Plot every exported DRL feature value minute-by-minute across all 24 chronological
minutes per dataset in `drl/output/extracted_features_cache.pkl`.
"""

import os
import sys
import pickle
import numpy as np
import matplotlib.pyplot as plt

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import FEATURE_CACHE_PATH, OUTPUT_DIR


DATASET_STYLES = [
    ("BuoyAmbient", "BuoyAmbient (Ambient)", "#4C72B0"),
    ("Croatia", "Croatia (Underwater)", "#55A868"),
    ("AUV", "AUV (Underwater)", "#1B9E77"),
    ("HaifaBay", "HaifaBay (Surface)", "#C44E52"),
    ("HearMyShip", "HearMyShip (Surface)", "#DD8452"),
]


def load_real_recordings_sorted(cache_path: str):
    with open(cache_path, "rb") as f:
        cached = pickle.load(f)
    all_recs = list(cached.get("train_dataset", [])) + list(cached.get("test_dataset", []))
    by_ds = {name: [] for name, _, _ in DATASET_STYLES}
    for rec in all_recs:
        ds_name = rec["metadata"]["dataset_name"]
        if ds_name in by_ds:
            by_ds[ds_name].append(rec)
    for ds_name in by_ds:
        by_ds[ds_name] = sorted(
            by_ds[ds_name],
            key=lambda r: (str(r["metadata"].get("source_file", "")), float(r["metadata"].get("start_sec", 0.0))),
        )
    return by_ds


def minute_summary_value(rec, spec) -> float:
    steps = rec["steps"]
    if spec.get("agg") == "first":
        return float(steps[0][spec["key"]])
    vals = np.array([float(st[spec["key"]]) for st in steps], dtype=np.float64)
    return float(np.nanmean(vals))


def plot_feature_grid(by_ds, feature_specs, title, out_path, ncols=3):
    n_feat = len(feature_specs)
    nrows = int(np.ceil(n_feat / ncols))
    fig, axes = plt.subplots(nrows, ncols, figsize=(5.6 * ncols, 3.6 * nrows), sharex=True)
    axes_flat = np.atleast_1d(axes).ravel()

    for ax_idx, spec in enumerate(feature_specs):
        ax = axes_flat[ax_idx]
        for ds_name, label, color in DATASET_STYLES:
            recs = by_ds.get(ds_name, [])
            if not recs:
                continue
            vals = np.array([minute_summary_value(r, spec) for r in recs], dtype=np.float64)
            mins = np.arange(1, len(vals) + 1)
            ax.plot(mins, vals, marker="o", markersize=3.2, color=color, linewidth=1.6, label=label, alpha=0.9)

        ax.set_title(spec["title"], fontsize=10.5, fontweight="bold")
        ax.set_ylabel(spec["ylabel"], fontsize=9)
        ax.grid(True, linestyle="--", alpha=0.35)
        if ax_idx >= (nrows - 1) * ncols:
            ax.set_xlabel("Time (Minute Index)", fontsize=9)

    for ax_idx in range(n_feat, len(axes_flat)):
        axes_flat[ax_idx].set_visible(False)

    handles, labels = axes_flat[0].get_legend_handles_labels()
    fig.legend(
        handles,
        labels,
        loc="upper center",
        bbox_to_anchor=(0.5, 0.965),
        ncol=len(DATASET_STYLES),
        frameon=True,
        fontsize=9.5,
    )
    fig.suptitle(title, fontsize=13.5, fontweight="bold", y=0.995)
    plt.tight_layout(rect=[0, 0, 1, 0.935])
    fig.savefig(out_path, dpi=180, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved: {out_path}")


def main():
    if not os.path.exists(FEATURE_CACHE_PATH):
        raise FileNotFoundError(f"Feature cache not found: {FEATURE_CACHE_PATH}")

    by_ds = load_real_recordings_sorted(FEATURE_CACHE_PATH)

    # 1. The 9 DRL state features (minute-level / minute-mean in physical units)
    drl_state_minute_specs = [
        {"key": "minute_mean_tib", "agg": "first", "title": "s_t[0]: Minute Mean TiB (minute_mean_tib)", "ylabel": "Ratio [0, 1]"},
        {"key": "minute_fair_tib", "agg": "first", "title": "s_t[1]: Minute Jain Fairness (minute_fair_tib)", "ylabel": "Index [0, 1]"},
        {"key": "minute_delta_tib", "agg": "first", "title": "s_t[2]: Minute TiB Drift (minute_delta_tib)", "ylabel": "Delta TiB"},
        {"key": "minute_std_tib", "agg": "first", "title": "s_t[3]: Minute Std TiB (minute_std_tib)", "ylabel": "Std"},
        {"key": "bw_mean", "agg": "mean", "title": "s_t[4]: Minute Mean BW (bw_mean)", "ylabel": "Bandwidth (Hz)"},
        {"key": "masd", "agg": "mean", "title": "s_t[5]: Minute Mean MASD (masd)", "ylabel": "MASD"},
        {"key": "plv_r", "agg": "mean", "title": "s_t[6]: Minute Mean PLL PLV (plv_r)", "ylabel": "PLV R [0, 1]"},
        {"key": "inst_freq_std", "agg": "mean", "title": "s_t[7]: Minute Mean PLL Freq Std (inst_freq_std)", "ylabel": "Std (Hz)"},
        {"key": "snr_peak", "agg": "first", "title": "s_t[8]: Net Macro-Lobe SNR (snr_peak)", "ylabel": "SNR (dB)"},
    ]
    out_state = os.path.join(OUTPUT_DIR, "drl_state_features_over_time.png")
    plot_feature_grid(
        by_ds,
        drl_state_minute_specs,
        "DRL 9-D State Features Minute-by-Minute (24 Minutes per Dataset)",
        out_state,
        ncols=3,
    )

    # 2. All additional exported DSP, PLL, and TiB features minute-by-minute
    extra_specs = [
        {"key": "bw_measured", "agg": "mean", "title": "Minute Mean Slice BW (bw_measured)", "ylabel": "Hz"},
        {"key": "tib", "agg": "mean", "title": "Minute Mean 6s TiB (tib)", "ylabel": "Ratio [0, 1]"},
        {"key": "jain", "agg": "mean", "title": "Minute Mean 6s Jain BW (jain)", "ylabel": "Index [0, 1]"},
        {"key": "minute_tib_2s", "agg": "first", "title": "Minute TiB at W=2s (minute_tib_2s)", "ylabel": "Ratio [0, 1]"},
        {"key": "minute_tib_60s", "agg": "first", "title": "Minute TiB at W=60s (minute_tib_60s)", "ylabel": "Ratio [0, 1]"},
        {"key": "djain_dt", "agg": "mean", "title": "Minute Mean |dJ/dt| (djain_dt)", "ylabel": "|dJ/dt|"},
        {"key": "f_dom", "agg": "mean", "title": "Minute Mean Dominant Freq (f_dom)", "ylabel": "Hz"},
        {"key": "f_pll", "agg": "mean", "title": "Minute Mean PLL Freq (f_pll)", "ylabel": "Hz"},
        {"key": "df_dt", "agg": "mean", "title": "Minute Mean |df/dt| (df_dt)", "ylabel": "Hz / 0.5s"},
        {"key": "freq_verif_err", "agg": "mean", "title": "Minute Mean PLL Error (freq_verif_err)", "ylabel": "Hz"},
        {"key": "phase_std_rad", "agg": "mean", "title": "Minute Mean PLL Phase Std (phase_std_rad)", "ylabel": "Radians"},
        {"key": "coherence_time", "agg": "mean", "title": "Minute Mean Coherence Time (coherence_time)", "ylabel": "Seconds"},
        {"key": "ocean_ambient_db", "agg": "first", "title": "Ocean Ambient Floor (ocean_ambient_db)", "ylabel": "PSD (dB)"},
    ]
    out_extra = os.path.join(OUTPUT_DIR, "drl_extra_exported_features_over_time.png")
    plot_feature_grid(
        by_ds,
        extra_specs,
        "Additional Exported DSP, PLL, and TiB Features Minute-by-Minute (24 Minutes per Dataset)",
        out_extra,
        ncols=3,
    )


if __name__ == "__main__":
    main()
