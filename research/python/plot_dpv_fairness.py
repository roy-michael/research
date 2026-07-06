import os
import glob
import numpy as np
import matplotlib.pyplot as plt
import pickle
import hashlib

from analyze_fairness import compute_fairness, extract_frequencies_for_files
from analyze_pll import butter_bandpass_filter, digital_pll, extract_pll_phases

def extract_freq_amp_dpv(file_paths, name, target_freq=497.0, segment_length_seconds=2):
    min_freq = max(50.0, target_freq - 100.0)
    max_freq = target_freq + 100.0
    f, a, _ = extract_frequencies_for_files(file_paths, name, min_freq, max_freq, segment_length_seconds)
    return f, a

def main():
    directory = r"C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2307"
    wav_files = glob.glob(os.path.join(directory, "*.wav"))
    if not wav_files:
        print("No wav files found.")
        return
        
    # Process only 10 files to keep execution time reasonable
    wav_files = wav_files[:10]
        
    SEGMENT_SEC = 2
    BUFFER_SEC = 15
    f0 = 497.0
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
        p_phases = extract_pll_phases(wav_files, f"dpv_H{h}", target_f, SEGMENT_SEC, bandpass_margin=100.0)
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
        freqs, amps = extract_freq_amp_dpv(wav_files, f"DPV_H{h}_FA", target_f, SEGMENT_SEC)
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

    fig_p.tight_layout()
    fig_p.savefig('dpv_pll_harmonic_fairness.png')
    
    fig_f.tight_layout()
    fig_f.savefig('dpv_jains_freq_harmonics.png')
    
    fig_a.tight_layout()
    fig_a.savefig('dpv_jains_amp_harmonics.png')
    
    print("Saved all DPV fairness plots!")

if __name__ == '__main__':
    main()
