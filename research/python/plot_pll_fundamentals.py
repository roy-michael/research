import os
import glob
import numpy as np
import matplotlib.pyplot as plt
import pickle
import hashlib

from analyze_fairness import compute_fairness
from plot_pll_phase_histograms import read_and_process_wav, plot_single_histogram
from plot_pll_harmonics import extract_pll_phases_for_harmonic

def main():
    directory = r"C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_1_600m"
    wav_files = glob.glob(os.path.join(directory, "*.wav"))
    if not wav_files:
        print(f"No .wav files found in {directory}.")
        return
        
    # Take first 10 files to keep execution time reasonable
    wav_files = wav_files[:10]
    print(f"Processing {len(wav_files)} file(s) for Fundamental Fairness Analysis.")
    
    SEGMENT_SEC = 2
    BUFFER_SEC = 15
    
    # Top 5 detected fundamentals from the HSS script
    fundamentals = [383.0, 438.0, 467.0, 497.0, 582.0]
    
    all_fairness_p = []
    
    for f0 in fundamentals:
        print(f"Tracking Fundamental at {f0:.1f} Hz...")
        p = extract_pll_phases_for_harmonic(wav_files, f0, f"F_{f0}", segment_length_seconds=SEGMENT_SEC)
        
        if p:
            fairness_p, _ = compute_fairness(p, SEGMENT_SEC, BUFFER_SEC, is_circular=True)
            all_fairness_p.append(fairness_p)
        else:
            all_fairness_p.append([])
            
    # Plotting grid
    fig, axes = plt.subplots(5, 1, figsize=(10, 20))
    if len(fundamentals) == 1:
        axes = [axes]
    
    bins_fair = np.linspace(0, 1.05, 43)
    colors = plt.cm.tab10(np.linspace(0, 1, len(fundamentals)))
    
    for i, f0 in enumerate(fundamentals):
        counts_f = plot_single_histogram(
            axes[i], 
            all_fairness_p[i], 
            bins_fair, 
            f"Family {i+1} ({f0:.0f} Hz)", 
            colors[i], 
            f"Fairness of Fundamental {i+1}", 
            "Mean Resultant Length (R)"
        )
        
        if len(all_fairness_p[i]) > 0:
            mean_val = np.mean(all_fairness_p[i])
            axes[i].axvline(mean_val, color='red', linestyle='dashed', linewidth=1.5, label=f'Mean: {mean_val:.2f}')
            axes[i].legend()

    fig.tight_layout()
    output_png = "pll_fundamentals_fairness.png"
    plt.savefig(output_png)
    print(f"Saved plot to {output_png}")

if __name__ == '__main__':
    main()
