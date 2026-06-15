import os
import glob
import numpy as np
import matplotlib.pyplot as plt
from scipy.io import wavfile
from scipy import signal

def jains_fairness_index(x):
    """Calculate Jain's fairness index for a given array x."""
    x = np.asarray(x, dtype=np.float64)
    if x.size == 0:
        return 0.0
    num = np.sum(x)**2
    den = x.size * np.sum(x**2)
    if den == 0:
        return 0.0
    return num / den

def process_specific_files(file_paths, name, min_freq=150, max_freq=2500):
    segment_length_seconds = 5
    buffer_length_seconds = 30
    segments_per_buffer = buffer_length_seconds // segment_length_seconds
    
    all_fairness_values = []
    all_dominant_freqs = []
    
    for idx, filepath in enumerate(file_paths):
        print(f"[{name}] Processing file {idx+1}/{len(file_paths)}: {os.path.basename(filepath)}")
        try:
            samplerate, data = wavfile.read(filepath)
        except Exception as e:
            print(f"Error reading {filepath}: {e}")
            continue
            
        # Convert to mono if stereo
        if len(data.shape) > 1:
            data = data.mean(axis=1)
            
        segment_samples = int(segment_length_seconds * samplerate)
        num_segments = len(data) // segment_samples
        
        dominant_freqs = []
        for i in range(num_segments):
            start = i * segment_samples
            end = start + segment_samples
            segment = data[start:end]
            
            f, psd = signal.welch(segment, fs=samplerate, nperseg=1024)
            
            # Focus only on frequencies between min_freq and max_freq
            psd[(f < min_freq) | (f > max_freq)] = 0
            
            dominant_freq = f[np.argmax(psd)]
            dominant_freqs.append(dominant_freq)
            all_dominant_freqs.append(dominant_freq)
            
        # Calculate fairness over 30-second buffers (non-overlapping)
        for i in range(0, len(dominant_freqs) - segments_per_buffer + 1, segments_per_buffer):
            buffer_freqs = dominant_freqs[i:i+segments_per_buffer]
            fairness = jains_fairness_index(buffer_freqs)
            all_fairness_values.append(fairness)
            
    print(f"Computed {len(all_fairness_values)} fairness values for {name}.")
    return all_fairness_values, all_dominant_freqs

def process_directory(directory, limit=None, min_freq=150, max_freq=2500):
    wav_files = glob.glob(os.path.join(directory, "*.wav"))
    
    if not wav_files:
        print(f"No .wav files found in {directory}.")
        return [], []
        
    if limit is not None:
        wav_files = wav_files[:limit]
        
    print(f"Found .wav files, processing {len(wav_files)} file(s) in {directory}.")
    
    return process_specific_files(wav_files, os.path.basename(directory), min_freq, max_freq)

def main():
    dir1 = r"C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2307"
    dir2 = r"C:\Users\Roy\Recordings\20250805_Haifa_bay_LME"
    
    fairness1, freqs1 = process_directory(dir1, limit=None, min_freq=400)
    
    lme_files = glob.glob(os.path.join(dir2, "*.wav"))
    if len(lme_files) >= 2:
        fairness2, freqs2 = process_specific_files([lme_files[0]], "Haifa Bay LME (File 1)", min_freq=150)
        fairness3, freqs3 = process_specific_files([lme_files[1]], "Haifa Bay LME (File 2)", min_freq=150)
    elif len(lme_files) == 1:
        fairness2, freqs2 = process_specific_files([lme_files[0]], "Haifa Bay LME (File 1)", min_freq=150)
        fairness3, freqs3 = [], []
    else:
        fairness2, freqs2, fairness3, freqs3 = [], [], [], []
    
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(15, 6))
    
    # Plotting Dominant Frequencies Histogram
    bins = np.linspace(150, 2500, 20)
    counts1, bins1, patches1 = ax1.hist(freqs1, bins=bins, alpha=0.6, label='Croatia (Ocean Sonics)', color='skyblue', density=False)
    counts2, bins2, patches2 = ax1.hist(freqs2, bins=bins, alpha=0.6, label='Haifa Bay LME (File 1)', color='salmon', density=False)
    if freqs3:
        counts3, bins3, patches3 = ax1.hist(freqs3, bins=bins, alpha=0.6, label='Haifa Bay LME (File 2)', color='lightgreen', density=False)
    else:
        counts3, patches3 = [], []
    
    # Add frequency (count) labels to the bins
    for count, patch in zip(counts1, patches1):
        if count > 0:
            ax1.text(patch.get_x() + patch.get_width()/2, patch.get_height(), str(int(count)), ha='center', va='bottom', fontsize=8, color='darkblue')
    for count, patch in zip(counts2, patches2):
        if count > 0:
            ax1.text(patch.get_x() + patch.get_width()/2, patch.get_height(), str(int(count)), ha='center', va='bottom', fontsize=8, color='darkred')
    if freqs3:
        for count, patch in zip(counts3, patches3):
            if count > 0:
                ax1.text(patch.get_x() + patch.get_width()/2, patch.get_height(), str(int(count)), ha='center', va='bottom', fontsize=8, color='darkgreen')
            
    ax1.set_title("Histogram of Dominant Frequencies (Hz)\n(Evaluated every 5 seconds)")
    ax1.set_xlabel("Frequency (Hz)")
    ax1.set_ylabel("Count")
    ax1.set_xticks(np.arange(0, 2750, 250))
    ax1.legend()
    ax1.grid(True, alpha=0.5)
    
    # Plotting Fairness Histograms
    bins_fairness = np.linspace(0, 1.05, 22) # bins from 0 to 1
    counts1_f, bins1_f, patches1_f = ax2.hist(fairness1, bins=bins_fairness, alpha=0.6, label='Croatia (Ocean Sonics)', color='skyblue', density=False)
    counts2_f, bins2_f, patches2_f = ax2.hist(fairness2, bins=bins_fairness, alpha=0.6, label='Haifa Bay LME (File 1)', color='salmon', density=False)
    if fairness3:
        counts3_f, bins3_f, patches3_f = ax2.hist(fairness3, bins=bins_fairness, alpha=0.6, label='Haifa Bay LME (File 2)', color='lightgreen', density=False)
    else:
        counts3_f, patches3_f = [], []
    
    # Add count labels
    for count, patch in zip(counts1_f, patches1_f):
        if count > 0:
            ax2.text(patch.get_x() + patch.get_width()/2, patch.get_height(), str(int(count)), ha='center', va='bottom', fontsize=8, color='darkblue')
    for count, patch in zip(counts2_f, patches2_f):
        if count > 0:
            ax2.text(patch.get_x() + patch.get_width()/2, patch.get_height(), str(int(count)), ha='center', va='bottom', fontsize=8, color='darkred')
    if fairness3:
        for count, patch in zip(counts3_f, patches3_f):
            if count > 0:
                ax2.text(patch.get_x() + patch.get_width()/2, patch.get_height(), str(int(count)), ha='center', va='bottom', fontsize=8, color='darkgreen')
            
    # Add mean lines
    if fairness1:
        ax2.axvline(np.mean(fairness1), color='blue', linestyle='dashed', linewidth=1.5, label=f'Croatia Mean: {np.mean(fairness1):.2f}')
    if fairness2:
        ax2.axvline(np.mean(fairness2), color='red', linestyle='dashed', linewidth=1.5, label=f'Haifa 1 Mean: {np.mean(fairness2):.2f}')
    if fairness3:
        ax2.axvline(np.mean(fairness3), color='green', linestyle='dashed', linewidth=1.5, label=f'Haifa 2 Mean: {np.mean(fairness3):.2f}')
        
    ax2.set_title("Histogram of Fairness of Dominant Frequencies\n(Evaluated over 30-second buffers)")
    ax2.set_xlabel("Jain's Fairness Index")
    ax2.set_ylabel("Count")
    ax2.legend()
    ax2.grid(True, alpha=0.5)
    
    plt.tight_layout()
    plt.show()

if __name__ == '__main__':
    main()
