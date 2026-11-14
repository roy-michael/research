"""
Classify the `croatia-2026` dataset using the saved Physics-Informed DRL model
(`drl/output/cpo_model.pt` or `drl/output/ppo_model.pt`) trained by `drl/main.py`.

For each WAV file in `INPUT_DIR`:
  1. Splits the recording into non-overlapping 60-second (1-minute) segments via
     `data.loader.load_wav_segment_mmap` (channel 0, zero-mean unit-variance, 4800 Hz).
  2. Extracts the 0.5-second step feature sequence using `OfflineFeatureExtractor`.
  3. Slices each step's `s_t` to the checkpoint's `state_indices` (default 6-D stable features)
     and runs deterministic policy inference (`PIMLActorCritic.get_action_and_values`).
  4. Saves per-file classification timeline plots and a CSV summary in
     `drl/output/croatia_2026_drl_detection/`.
"""

import argparse
import csv
import glob
import os
import sys
import numpy as np
import torch
from scipy.io import wavfile
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Patch

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import (
    CLASS_NAMES,
    CPO_MODEL_PATH,
    DSPConfig,
    OUTPUT_DIR,
    PPO_MODEL_PATH,
    STABLE_STATE_INDICES,
)
from data.loader import load_real_wav_segment
from dsp.feature_extractor import OfflineFeatureExtractor
from rl.agent import PIMLActorCritic


DEFAULT_INPUT_DIR = r"D:\RoyStudies\Recordings\croatia-2026"
DEFAULT_OUT_DIR = os.path.join(OUTPUT_DIR, "croatia_2026_drl_detection")


def load_trained_model(checkpoint_path: str):
    if not os.path.exists(checkpoint_path):
        raise FileNotFoundError(
            f"Trained DRL checkpoint not found: {checkpoint_path}\n"
            f"Run `python drl/main.py` first to train and save the model."
        )
    ckpt = torch.load(checkpoint_path, map_location="cpu")
    state_indices = list(ckpt.get("state_indices", STABLE_STATE_INDICES))
    state_dim = int(ckpt.get("state_dim", len(state_indices)))
    action_dim = int(ckpt.get("action_dim", 5))
    hidden_dim = int(ckpt.get("hidden_dim", 64))

    model = PIMLActorCritic(state_dim=state_dim, action_dim=action_dim, hidden_dim=hidden_dim)
    model.load_state_dict(ckpt["state_dict"])
    model.eval()
    return model, state_indices


def get_wav_duration_sec(filepath: str) -> float:
    try:
        fs, data = wavfile.read(filepath, mmap=True)
    except Exception:
        fs, data = wavfile.read(filepath, mmap=False)
    return float(len(data)) / float(fs)


def classify_file_with_drl(
    filepath: str,
    model: PIMLActorCritic,
    state_indices: list,
    extractor: OfflineFeatureExtractor,
    dsp_cfg: DSPConfig,
    f_low: float,
    f_high: float,
    out_dir: str,
):
    filename = os.path.basename(filepath)
    stem = os.path.splitext(filename)[0]
    total_sec = get_wav_duration_sec(filepath)
    seg_dur = float(dsp_cfg.segment_duration_sec)
    num_mins = max(1, int(np.floor(total_sec / seg_dur)))

    print(f"\n=======================================================")
    print(f"DRL Classification of: {filename} ({total_sec:.1f}s -> {num_mins} x {int(seg_dur)}s segments)")
    print(f"=======================================================")

    step_times_min = []
    step_classes = []
    step_probs = []
    step_bw_pred = []
    minute_rows = []

    for m_idx in range(num_mins):
        start_sec = m_idx * seg_dur
        dur_sec = min(seg_dur, max(2.0, total_sec - start_sec))
        sig, _ = load_real_wav_segment(
            filepath,
            start_sec=start_sec,
            duration_sec=dur_sec,
            target_fs=dsp_cfg.target_fs,
        )
        steps, _, minute_tib_stats = extractor.extract_recording_features(
            sig, f_low=f_low, f_high=f_high
        )
        if not steps:
            continue

        states_mat = np.stack(
            [np.asarray(st["s_t"], dtype=np.float32)[state_indices] for st in steps],
            axis=0,
        )
        with torch.no_grad():
            s_tensor = torch.from_numpy(states_mat)
            actions, _, _, _, _ = model.get_action_and_values(s_tensor, deterministic=True)
            actions_np = actions.cpu().numpy()

        logits = np.clip(actions_np[:, 2:5], -5.0, 5.0)
        shift = logits - np.max(logits, axis=1, keepdims=True)
        exp_l = np.exp(shift)
        probs = exp_l / (np.sum(exp_l, axis=1, keepdims=True) + 1e-8)
        preds = np.argmax(logits, axis=1)
        bw_preds = 70.0 + 12.0 * np.clip(actions_np[:, 1], -5.0, 5.0)

        for j in range(len(steps)):
            t_min = (start_sec + (j + 0.5) * dsp_cfg.buffer_sec) / 60.0
            step_times_min.append(t_min)
            step_classes.append(int(preds[j]))
            step_probs.append(probs[j])
            step_bw_pred.append(float(bw_preds[j]))

        mean_probs = np.mean(probs, axis=0)
        min_pred = int(np.argmax(np.bincount(preds, minlength=len(CLASS_NAMES))))
        minute_rows.append({
            "filename": filename,
            "minute": m_idx + 1,
            "pred_class": min_pred,
            "pred_class_name": CLASS_NAMES[min_pred],
            "p_ambient": float(mean_probs[0]),
            "p_underwater": float(mean_probs[1]),
            "p_surface": float(mean_probs[2]),
            "mean_bw_pred_hz": float(np.mean(bw_preds)),
            "minute_mean_tib": float(minute_tib_stats["minute_mean_tib"]),
            "minute_fair_tib": float(minute_tib_stats["minute_fair_tib"]),
            "snr_peak_db": float(steps[0]["snr_peak"]),
        })
        print(
            f"  Min {m_idx + 1:2d}: {CLASS_NAMES[min_pred]:18s} "
            f"(P=[Amb:{mean_probs[0]:.2f}, UW:{mean_probs[1]:.2f}, Surf:{mean_probs[2]:.2f}] | "
            f"BW_pred={np.mean(bw_preds):5.1f} Hz | TiB={minute_tib_stats['minute_mean_tib']:.3f}, "
            f"Fair={minute_tib_stats['minute_fair_tib']:.3f}, SNR={steps[0]['snr_peak']:5.1f} dB)"
        )

    step_times_min = np.asarray(step_times_min, dtype=np.float64)
    step_classes = np.asarray(step_classes, dtype=np.int32)
    step_probs = np.asarray(step_probs, dtype=np.float64)

    n_total = max(1, len(step_classes))
    n_amb = int(np.sum(step_classes == 0))
    n_uw = int(np.sum(step_classes == 1))
    n_surf = int(np.sum(step_classes == 2))
    print(f"Summary for {filename} ({n_total} x 0.5s steps):")
    print(f"  - Ambient Noise      : {n_amb:4d} ({n_amb / n_total * 100:5.1f}%)")
    print(f"  - Underwater Scooter : {n_uw:4d} ({n_uw / n_total * 100:5.1f}%)")
    print(f"  - Surface Vessel     : {n_surf:4d} ({n_surf / n_total * 100:5.1f}%)")

    # Save 2-panel classification & probability plot
    fig, (ax1, ax2) = plt.subplots(
        2, 1, figsize=(14, 7.5), sharex=True, gridspec_kw={"height_ratios": [1.1, 0.9]}
    )
    ax1.plot(step_times_min, step_probs[:, 0], color="#4C72B0", linewidth=1.3, label="P(Ambient Noise)")
    ax1.plot(step_times_min, step_probs[:, 1], color="#238636", linewidth=1.5, label="P(Underwater Scooter)")
    ax1.plot(step_times_min, step_probs[:, 2], color="#da3633", linewidth=1.5, label="P(Surface Vessel)")
    ax1.set_ylim(-0.02, 1.05)
    ax1.set_ylabel("Policy Class Probability", fontsize=10, fontweight="bold")
    ax1.set_title(f"DRL Classification Over Time: {filename}", fontsize=12.5, fontweight="bold")
    ax1.grid(True, linestyle="--", alpha=0.35)
    ax1.legend(loc="upper right", fontsize=9)

    bar_w = dsp_cfg.buffer_sec / 60.0
    for t_m, c in zip(step_times_min, step_classes):
        if c == 1:
            ax2.bar(t_m, 1.0, width=bar_w, color="#238636", alpha=0.85)
        elif c == 2:
            ax2.bar(t_m, 2.0, width=bar_w, color="#da3633", alpha=0.85)
        else:
            ax2.bar(t_m, 0.25, width=bar_w, color="#6e7681", alpha=0.55)

    ax2.set_ylim(-0.2, 2.4)
    ax2.set_yticks([0.25, 1.0, 2.0])
    ax2.set_yticklabels(["Ambient Noise", "Underwater Scooter", "Surface Vessel"], fontsize=9.5, fontweight="bold")
    ax2.set_xlabel("Elapsed Time (Minutes)", fontsize=10, fontweight="bold")
    ax2.grid(True, axis="x", linestyle="--", alpha=0.35)
    ax2.legend(
        handles=[
            Patch(facecolor="#6e7681", label=f"Ambient ({n_amb / n_total * 100:.1f}%)"),
            Patch(facecolor="#238636", label=f"Underwater ({n_uw / n_total * 100:.1f}%)"),
            Patch(facecolor="#da3633", label=f"Surface ({n_surf / n_total * 100:.1f}%)"),
        ],
        loc="upper right",
        fontsize=9,
    )

    plt.tight_layout()
    out_plot = os.path.join(out_dir, f"{stem}_drl_detection.png")
    fig.savefig(out_plot, dpi=180, bbox_inches="tight")
    plt.close(fig)
    print(f"Saved plot: {out_plot}")

    return minute_rows


def main():
    parser = argparse.ArgumentParser(description="Classify croatia-2026 WAV files using a saved DRL checkpoint")
    parser.add_argument("--input-dir", type=str, default=DEFAULT_INPUT_DIR, help="Directory containing .wav files")
    parser.add_argument("--out-dir", type=str, default=DEFAULT_OUT_DIR, help="Output directory for plots and CSV")
    parser.add_argument("--agent", type=str, default="cpo", choices=["cpo", "ppo"], help="Which saved agent to use")
    parser.add_argument("--checkpoint", type=str, default=None, help="Optional explicit path to .pt checkpoint")
    parser.add_argument("--f-low", type=float, default=20.0, help="Low frequency bound (Hz) for feature extraction")
    parser.add_argument("--f-high", type=float, default=1600.0, help="High frequency bound (Hz) for feature extraction")
    args = parser.parse_args()

    os.makedirs(args.out_dir, exist_ok=True)
    ckpt_path = args.checkpoint or (CPO_MODEL_PATH if args.agent == "cpo" else PPO_MODEL_PATH)

    model, state_indices = load_trained_model(ckpt_path)
    print(f"Loaded DRL model from: {ckpt_path} (state_indices={state_indices})")

    wav_files = sorted(glob.glob(os.path.join(args.input_dir, "*.wav")))
    if not wav_files:
        raise FileNotFoundError(f"No .wav files found in: {args.input_dir}")

    dsp_cfg = DSPConfig()
    extractor = OfflineFeatureExtractor(dsp_cfg)

    all_rows = []
    for wav_path in wav_files:
        rows = classify_file_with_drl(
            wav_path,
            model=model,
            state_indices=state_indices,
            extractor=extractor,
            dsp_cfg=dsp_cfg,
            f_low=args.f_low,
            f_high=args.f_high,
            out_dir=args.out_dir,
        )
        all_rows.extend(rows)

    csv_path = os.path.join(args.out_dir, "croatia_2026_drl_predictions.csv")
    if all_rows:
        with open(csv_path, "w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=list(all_rows[0].keys()))
            writer.writeheader()
            writer.writerows(all_rows)
        print(f"\nSaved per-minute predictions CSV: {csv_path}")


if __name__ == "__main__":
    main()
