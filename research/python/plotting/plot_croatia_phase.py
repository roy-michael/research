import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'analysis')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'plotting')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'simulation')))

import os
import numpy as np
import matplotlib.pyplot as plt
from analyze_fairness import (
    extract_frequencies_for_dir, 
    compute_fairness, 
    calc_kld_matrix
)
from utils_plotting import plot_divergence_heatmap, plot_single_histogram

def main():
    base_dir = r"C:\Users\Roy\Recordings\Croatia"
    
    # Find all subdirectories containing .wav files, ignoring 'out' and 'Copy'
    wav_dirs = []
    for root, dirs, files in os.walk(base_dir):
        if any(f.endswith('.wav') for f in files):
            lower_root = root.lower()
            if "out" not in lower_root and "copy" not in lower_root:
                wav_dirs.append(root)
            
    if not wav_dirs:
        print(f"No valid directories with .wav files found in {base_dir} (excluding 'out' and 'Copy')")
        return
        
    labels = [os.path.basename(d) for d in wav_dirs]
    print(f"Found datasets: {labels}")
    
    SEGMENT_SEC = 2
    BUFFER_SEC = 15
    
    all_phases = []
    for d in wav_dirs:
        _, _, p = extract_frequencies_for_dir(d, limit=None, min_freq=300, max_freq=1500, segment_length_seconds=SEGMENT_SEC)
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
    
    # Create a grid: N rows for histograms, plus 1 row at the bottom for heatmaps
    fig, axes = plt.subplots(N + 1, 2, figsize=(16, 3 * (N + 1)))
    
    # If N is 0, this will crash earlier. If it's valid, axes is a 2D array.
    
    counts_dict_phase = {}
    bins_phase = np.linspace(-np.pi, np.pi, 40)
    
    counts_dict_fair = {}
    bins_fair = np.linspace(0, 1.05, 43)
    
    for i in range(N):
        # Phase Angles Histogram (Left column)
        counts_p = plot_single_histogram(axes[i, 0], all_phases_flat[i], bins_phase, labels[i], colors[i], "Histogram of Phase Angles", "Phase (Radians)")
        if len(all_phases_flat[i]) > 0:
            counts_dict_phase[labels[i]] = counts_p
            
        # Phase Synchronization Histogram (Right column)
        counts_f = plot_single_histogram(axes[i, 1], all_fairness_p[i], bins_fair, labels[i], colors[i], f"Phase Sync (Buf={BUFFER_SEC}s, Seg={SEGMENT_SEC}s)", "Mean Resultant Length (R)")
        if len(all_fairness_p[i]) > 0:
            counts_dict_fair[labels[i]] = counts_f
            axes[i, 1].axvline(np.mean(all_fairness_p[i]), color='red', linestyle='dashed', linewidth=1.5, label=f'Mean: {np.mean(all_fairness_p[i]):.2f}')
            axes[i, 1].legend()

    # Heatmaps at the bottom (Row N)
    if len(counts_dict_phase) > 1:
        keys_phase, _, jsd_mat_phase = calc_kld_matrix(counts_dict_phase, f'Phases (Seg={SEGMENT_SEC}s)')
        plot_divergence_heatmap(axes[N, 0], keys_phase, jsd_mat_phase, "JSD Heatmap: Phase Angles")
    else:
        axes[N, 0].set_title("Not enough datasets for Phase Heatmap")
        
    if len(counts_dict_fair) > 1:
        keys_fair, _, jsd_mat_fair = calc_kld_matrix(counts_dict_fair, f'Phase Synchronization (Seg={SEGMENT_SEC}s, Buf={BUFFER_SEC}s)')
        plot_divergence_heatmap(axes[N, 1], keys_fair, jsd_mat_fair, "JSD Heatmap: Phase Synchronization")
    else:
        axes[N, 1].set_title("Not enough datasets for Fairness Heatmap")

    fig.tight_layout()
    plt.show()

if __name__ == '__main__':
    main()
