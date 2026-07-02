import os
import glob
import numpy as np
import matplotlib.pyplot as plt
import pickle
import hashlib
from scipy.io import wavfile

from analyze_fairness import compute_fairness
from analyze_pll import butter_bandpass_filter, digital_pll, extract_pll_phases
from utils_plotting import plot_single_histogram

def main():
    directory = r"C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_1_600m"
    wav_files = glob.glob(os.path.join(directory, "*.wav"))
    if not wav_files:
        print(f"No .wav files found in {directory}.")
        return
        
    # Take first 10 files to keep execution time reasonable
    wav_files = wav_files[:10]
    print(f"Processing {len(wav_files)} file(s) for Harmonic Fairness Analysis.")
    
    SEGMENT_SEC = 2
    BUFFER_SEC = 15
    f0 = 497.0 # the newly discovered dominant fundamental
    
    harmonics = list(range(1, 11)) # H1 to H10
    
    all_fairness_p = []
    
    for h in harmonics:
        target_f = f0 * h
        print(f"Tracking Harmonic {h} at {target_f:.1f} Hz...")
        p = extract_pll_phases(wav_files, f"H{h}", target_f, segment_length_seconds=SEGMENT_SEC, bandpass_margin=100.0)
        
        if p:
            fairness_p, _ = compute_fairness(p, SEGMENT_SEC, BUFFER_SEC, is_circular=True)
            all_fairness_p.append(fairness_p)
        else:
            all_fairness_p.append([])
            
    # Plotting grid
    fig, axes = plt.subplots(5, 2, figsize=(15, 20))
    axes = axes.flatten()
    
    bins_fair = np.linspace(0, 1.05, 43)
    colors = plt.cm.tab10(np.linspace(0, 1, 10))
    
    for i, h in enumerate(harmonics):
        target_f = f0 * h
        counts_f = plot_single_histogram(
            axes[i], 
            all_fairness_p[i], 
            bins_fair, 
            f"H{h} ({target_f:.0f} Hz)", 
            colors[i], 
            f"Fairness of Harmonic {h}", 
            "Mean Resultant Length (R)"
        )
        
        if len(all_fairness_p[i]) > 0:
            mean_val = np.mean(all_fairness_p[i])
            axes[i].axvline(mean_val, color='red', linestyle='dashed', linewidth=1.5, label=f'Mean: {mean_val:.2f}')
            axes[i].legend()

    fig.tight_layout()
    output_png = "pll_harmonic_fairness.png"
    plt.savefig(output_png)
    print(f"Saved plot to {output_png}")

if __name__ == '__main__':
    main()
