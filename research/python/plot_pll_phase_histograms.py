import os
import glob
import numpy as np
import matplotlib.pyplot as plt
from scipy.io import wavfile
import pickle
import hashlib
from analyze_fairness import (
    compute_fairness, 
    calc_kld_matrix
)
from analyze_pll import extract_pll_phases
from utils_plotting import plot_divergence_heatmap, plot_single_histogram


def extract_pll_phases_for_dir(directory, limit=None, target_freq=2485.0, segment_length_seconds=2):
    wav_files = glob.glob(os.path.join(directory, "*.wav"))
    if not wav_files:
        print(f"No .wav files found in {directory}.")
        return []
    if limit is not None:
        wav_files = wav_files[:limit]
    print(f"Found .wav files, processing {len(wav_files)} file(s) in {directory}.")
    return extract_pll_phases(wav_files, os.path.basename(directory), target_freq, segment_length_seconds=segment_length_seconds, bandpass_margin=100.0)


def main():
    base_dir = r"C:\Users\Roy\Recordings\Croatia"
    
    wav_dirs = []
    for root, dirs, files in os.walk(base_dir):
        if any(f.endswith('.wav') for f in files):
            lower_root = root.lower()
            if "out" not in lower_root and "copy" not in lower_root:
                wav_dirs.append(root)
            
    if not wav_dirs:
        print(f"No valid directories with .wav files found in {base_dir}")
        return
        
    labels = [os.path.basename(d) for d in wav_dirs]
    print(f"Found datasets: {labels}")
    
    SEGMENT_SEC = 2
    BUFFER_SEC = 15
    TARGET_FREQ = 2485.0
    
    all_phases = []
    for d in wav_dirs:
        p = extract_pll_phases_for_dir(d, limit=20, target_freq=TARGET_FREQ, segment_length_seconds=SEGMENT_SEC)
        all_phases.append(p)
        
    all_fairness_p = []
    all_phases_flat = []
    
    for p in all_phases:
        if p:
            fairness_p, phases_flat = compute_fairness(p, SEGMENT_SEC, BUFFER_SEC, is_circular=True)
            all_fairness_p.append(fairness_p)
            all_phases_flat.append(phases_flat)
        else:
            all_fairness_p.append([])
            all_phases_flat.append([])
            
    N = len(wav_dirs)
    colors = plt.cm.tab10(np.linspace(0, 1, N))
    
    fig, axes = plt.subplots(N + 1, 2, figsize=(16, 3 * (N + 1)))
    
    counts_dict_phase = {}
    bins_phase = np.linspace(-np.pi, np.pi, 40)
    
    counts_dict_fair = {}
    bins_fair = np.linspace(0, 1.05, 43)
    
    for i in range(N):
        counts_p = plot_single_histogram(axes[i, 0], all_phases_flat[i], bins_phase, labels[i], colors[i], "Histogram of PLL Phase Angles", "Phase (Radians)")
        if len(all_phases_flat[i]) > 0:
            counts_dict_phase[labels[i]] = counts_p
            
        counts_f = plot_single_histogram(axes[i, 1], all_fairness_p[i], bins_fair, labels[i], colors[i], f"PLL Phase Sync (Buf={BUFFER_SEC}s, Seg={SEGMENT_SEC}s)", "Mean Resultant Length (R)")
        if len(all_fairness_p[i]) > 0:
            counts_dict_fair[labels[i]] = counts_f
            axes[i, 1].axvline(np.mean(all_fairness_p[i]), color='red', linestyle='dashed', linewidth=1.5, label=f'Mean: {np.mean(all_fairness_p[i]):.2f}')
            axes[i, 1].legend()

    if len(counts_dict_phase) > 1:
        keys_phase, _, jsd_mat_phase = calc_kld_matrix(counts_dict_phase, f'Phases (Seg={SEGMENT_SEC}s)')
        plot_divergence_heatmap(axes[N, 0], keys_phase, jsd_mat_phase, "JSD Heatmap: PLL Phase Angles")
    else:
        axes[N, 0].set_title("Not enough datasets for Phase Heatmap")
        
    if len(counts_dict_fair) > 1:
        keys_fair, _, jsd_mat_fair = calc_kld_matrix(counts_dict_fair, f'Phase Synchronization (Seg={SEGMENT_SEC}s, Buf={BUFFER_SEC}s)')
        plot_divergence_heatmap(axes[N, 1], keys_fair, jsd_mat_fair, "JSD Heatmap: PLL Phase Synchronization")
    else:
        axes[N, 1].set_title("Not enough datasets for Fairness Heatmap")

    fig.tight_layout()
    output_png = "pll_croatia_phase_histograms.png"
    plt.savefig(output_png)
    print(f"Saved plot to {output_png}")

if __name__ == '__main__':
    main()
