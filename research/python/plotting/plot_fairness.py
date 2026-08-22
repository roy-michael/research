import sys
import os
import argparse
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'analysis')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'plotting')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'simulation')))

import glob
import numpy as np
import matplotlib.pyplot as plt

from analyze_fairness import compute_fairness, extract_frequencies_for_files
from analyze_pll import extract_pll_phases
from config import get_output_dir

def extract_freq_amp(file_paths, name, target_freq, bandpass_margin, segment_length_seconds=2):
    min_freq = max(10.0, target_freq - bandpass_margin)
    max_freq = target_freq + bandpass_margin
    f, a, _ = extract_frequencies_for_files(file_paths, name, min_freq, max_freq, segment_length_seconds)
    return f, a

def plot_dataset_fairness(directory, dataset_name, f0, bandpass_margin):
    wav_files = glob.glob(os.path.join(directory, "*.wav"))
    if not wav_files:
        print(f"No wav files found in {directory}")
        return
        
    SEGMENT_SEC = 2
    BUFFER_SEC = 15
    harmonics = list(range(1, 11))
    
    fig_p, axes_p = plt.subplots(5, 2, figsize=(15, 20))
    axes_p = axes_p.flatten()
    
    fig_f, axes_f = plt.subplots(5, 2, figsize=(15, 20))
    axes_f = axes_f.flatten()
    
    fig_a, axes_a = plt.subplots(5, 2, figsize=(15, 20))
    axes_a = axes_a.flatten()
    
    bins_fair = np.linspace(0, 1.05, 43)
    
    for i, h in enumerate(harmonics):
        target_f = f0 * h
        print(f"Processing Harmonic {h} ({target_f} Hz)...")
        
        # 1. Phase Fairness
        p_phases = extract_pll_phases(wav_files, f"{dataset_name}_H{h}", target_f, SEGMENT_SEC, bandpass_margin=bandpass_margin)
        fairness_p, _ = compute_fairness(p_phases, SEGMENT_SEC, BUFFER_SEC, is_circular=True)
        
        ax = axes_p[i]
        ax.set_title(f"H{h} ({target_f:.0f} Hz) Phase Fairness")
        ax.set_xlabel("Mean Resultant Length (R)")
        ax.grid(True, alpha=0.5)
        if fairness_p:
            weights = np.ones_like(fairness_p) / len(fairness_p)
            ax.hist(fairness_p, bins=bins_fair, alpha=0.7, color='indigo', weights=weights, label=f"\u03bc={np.mean(fairness_p):.2f}")
            ax.axvline(np.mean(fairness_p), color='black', linestyle='dashed')
            ax.legend()
            
        # 2. Freq/Amp Fairness
        freqs, amps = extract_freq_amp(wav_files, f"{dataset_name}_H{h}_FA", target_f, bandpass_margin, SEGMENT_SEC)
        fairness_f, _ = compute_fairness(freqs, SEGMENT_SEC, BUFFER_SEC, is_circular=False)
        fairness_a, _ = compute_fairness(amps, SEGMENT_SEC, BUFFER_SEC, is_circular=False)
        
        ax = axes_f[i]
        ax.set_title(f"H{h} ({target_f:.0f} Hz) Freq Jain's Fairness")
        ax.set_xlabel("Jain's Fairness Index")
        ax.grid(True, alpha=0.5)
        if fairness_f:
            weights = np.ones_like(fairness_f) / len(fairness_f)
            ax.hist(fairness_f, bins=bins_fair, alpha=0.7, color='darkred', weights=weights, label=f"\u03bc={np.mean(fairness_f):.2f}")
            ax.axvline(np.mean(fairness_f), color='black', linestyle='dashed')
            ax.legend()
            
        ax = axes_a[i]
        ax.set_title(f"H{h} ({target_f:.0f} Hz) Amp Jain's Fairness")
        ax.set_xlabel("Jain's Fairness Index")
        ax.grid(True, alpha=0.5)
        if fairness_a:
            weights = np.ones_like(fairness_a) / len(fairness_a)
            ax.hist(fairness_a, bins=bins_fair, alpha=0.7, color='darkgreen', weights=weights, label=f"\u03bc={np.mean(fairness_a):.2f}")
            ax.axvline(np.mean(fairness_a), color='black', linestyle='dashed')
            ax.legend()

    out_dir = get_output_dir(dataset_name)
    
    fig_p.tight_layout()
    fig_p.savefig(out_dir / f'{dataset_name}_pll_harmonic_fairness.png')
    
    fig_f.tight_layout()
    fig_f.savefig(out_dir / f'{dataset_name}_jains_freq_harmonics.png')
    
    fig_a.tight_layout()
    fig_a.savefig(out_dir / f'{dataset_name}_jains_amp_harmonics.png')
    
    print(f"Saved all {dataset_name} fairness plots to {out_dir}!")

def main():
    parser = argparse.ArgumentParser(description="Plot fairness metrics for a dataset.")
    parser.add_argument("--dir", required=True, help="Directory containing the .wav files")
    parser.add_argument("--dataset-name", required=True, help="Name of the dataset (for output folder and files)")
    parser.add_argument("--f0", type=float, required=True, help="Fundamental frequency (Hz)")
    parser.add_argument("--margin", type=float, default=20.0, help="Bandpass margin (Hz)")
    
    args = parser.parse_args()
    plot_dataset_fairness(args.dir, args.dataset_name, args.f0, args.margin)

if __name__ == '__main__':
    main()
