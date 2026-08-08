import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'analysis')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'plotting')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'simulation')))

import os
import glob
import numpy as np
import matplotlib.pyplot as plt

from analyze_fairness import compute_fairness, extract_frequencies_for_files

def extract_freq_amp_for_dir(directory, limit=10, target_freq=497.0, segment_length_seconds=2):
    wav_files = glob.glob(os.path.join(directory, "*.wav"))
    if not wav_files:
        return [], []
    if limit is not None:
        wav_files = wav_files[:limit]
        
    min_freq = max(50.0, target_freq - 100.0)
    max_freq = target_freq + 100.0
    
    f, a, _ = extract_frequencies_for_files(wav_files, os.path.basename(directory), min_freq, max_freq, segment_length_seconds)
    return f, a

def main():
    base_dir = r"C:\Users\Roy\Recordings\Croatia\Ocean Sonics"
    wav_dirs = []
    for d in os.listdir(base_dir):
        full_path = os.path.join(base_dir, d)
        if os.path.isdir(full_path):
            wav_dirs.append(full_path)
            
    if not wav_dirs:
        print(f"No directories found in {base_dir}")
        return
        
    labels = [os.path.basename(d) for d in wav_dirs]
    print(f"Found datasets: {labels}")
    
    SEGMENT_SEC = 2
    BUFFER_SEC = 15
    f0 = 497.0
    harmonics = list(range(1, 11))
    
    fig_f, axes_f = plt.subplots(5, 2, figsize=(15, 20))
    axes_f = axes_f.flatten()
    
    fig_a, axes_a = plt.subplots(5, 2, figsize=(15, 20))
    axes_a = axes_a.flatten()
    
    bins_fair = np.linspace(0, 1.05, 43)
    colors = plt.cm.tab10(np.linspace(0, 1, len(wav_dirs)))
    
    for i, h in enumerate(harmonics):
        target_f = f0 * h
        print(f"\n--- Processing Harmonic {h} ({target_f} Hz) ---")
        
        ax_f = axes_f[i]
        ax_f.set_title(f"H{h} ({target_f:.0f} Hz) Freq Jain's Fairness")
        ax_f.set_xlabel("Jain's Fairness Index (Frequency)")
        ax_f.set_ylabel("Probability")
        ax_f.grid(True, alpha=0.5)
        
        ax_a = axes_a[i]
        ax_a.set_title(f"H{h} ({target_f:.0f} Hz) Amp Jain's Fairness")
        ax_a.set_xlabel("Jain's Fairness Index (Amplitude)")
        ax_a.set_ylabel("Probability")
        ax_a.grid(True, alpha=0.5)
        
        for d_idx, d in enumerate(wav_dirs):
            freqs, amps = extract_freq_amp_for_dir(d, limit=10, target_freq=target_f, segment_length_seconds=SEGMENT_SEC)
            
            if freqs:
                fairness_f, _ = compute_fairness(freqs, SEGMENT_SEC, BUFFER_SEC, is_circular=False)
                if len(fairness_f) > 0:
                    weights = np.ones_like(fairness_f) / len(fairness_f)
                    ax_f.hist(fairness_f, bins=bins_fair, alpha=0.5, label=f"{labels[d_idx]} (\u03bc={np.mean(fairness_f):.2f})", color=colors[d_idx], weights=weights)
            
            if amps:
                fairness_a, _ = compute_fairness(amps, SEGMENT_SEC, BUFFER_SEC, is_circular=False)
                if len(fairness_a) > 0:
                    weights = np.ones_like(fairness_a) / len(fairness_a)
                    ax_a.hist(fairness_a, bins=bins_fair, alpha=0.5, label=f"{labels[d_idx]} (\u03bc={np.mean(fairness_a):.2f})", color=colors[d_idx], weights=weights)
        
        ax_f.legend(fontsize=8)
        ax_a.legend(fontsize=8)

    fig_f.tight_layout()
    output_png_f = "jains_freq_harmonics_cross_dataset.png"
    fig_f.savefig(output_png_f)
    print(f"Saved frequency fairness plot to {output_png_f}")
    
    fig_a.tight_layout()
    output_png_a = "jains_amp_harmonics_cross_dataset.png"
    fig_a.savefig(output_png_a)
    print(f"Saved amplitude fairness plot to {output_png_a}")

if __name__ == '__main__':
    main()
