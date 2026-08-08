import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'analysis')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'plotting')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'simulation')))

import os
import glob
import numpy as np
import pickle
import hashlib
import matplotlib.pyplot as plt
from scipy.io import wavfile
from scipy import signal
from scipy.special import rel_entr
from scipy.spatial.distance import jensenshannon
from functools import lru_cache
from utils_plotting import plot_divergence_heatmap, plot_histogram

@lru_cache(maxsize=None)
def read_and_process_wav(filepath):
    try:
        samplerate, data = wavfile.read(filepath)
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return None, None
        
    # Convert to mono if stereo
    if len(data.shape) > 1:
        data = data.mean(axis=1)
        
    return samplerate, data

def calculate_kld(counts_p, counts_q):
    """Calculate the Kullback-Leibler Divergence between two histograms."""
    epsilon = 1e-10
    p = np.array(counts_p) + epsilon
    q = np.array(counts_q) + epsilon
    p = p / np.sum(p)
    q = q / np.sum(q)
    return np.sum(rel_entr(p, q))

def calculate_jsd(counts_p, counts_q):
    """Calculate the Jensen-Shannon Divergence between two histograms."""
    epsilon = 1e-10
    p = np.array(counts_p) + epsilon
    q = np.array(counts_q) + epsilon
    p = p / np.sum(p)
    q = q / np.sum(q)
    return jensenshannon(p, q) ** 2

def calc_kld_matrix(dict_counts, name):
    keys = list(dict_counts.keys())
    keys.sort()
    n = len(keys)
    kld_matrix = np.zeros((n, n))
    jsd_matrix = np.zeros((n, n))
    print(f"\n--- Divergence for {name} ---")
    for i in range(n):
        for j in range(n):
            if i != j:
                kld = calculate_kld(dict_counts[keys[i]], dict_counts[keys[j]])
                jsd = calculate_jsd(dict_counts[keys[i]], dict_counts[keys[j]])
                kld_matrix[i, j] = kld
                jsd_matrix[i, j] = jsd
                print(f"{keys[i]} || {keys[j]}: KLD={kld:.4f}, JSD={jsd:.4f}")
    return keys, kld_matrix, jsd_matrix



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

def circular_fairness_index(x):
    """Calculate Circular Fairness (Mean Resultant Length) for a given array of phase angles x."""
    x = np.asarray(x, dtype=np.float64)
    if x.size == 0:
        return 0.0
    # Mean Resultant Length R
    mean_vector = np.sum(np.exp(1j * x)) / x.size
    return np.abs(mean_vector)

def extract_frequencies_for_files(file_paths, name, min_freq=150, max_freq=2500, segment_length_seconds=2):
    os.makedirs("cache", exist_ok=True)
    
    # Create a unique cache key based on the parameters
    key_string = f"{name}_{min_freq}_{max_freq}_{segment_length_seconds}"
    key_hash = hashlib.md5(key_string.encode('utf-8')).hexdigest()
    cache_file = os.path.join("cache", f"processed_{key_hash}.pkl")
    
    if os.path.exists(cache_file):
        print(f"[{name}] Loading cached processed data from {cache_file}...")
        with open(cache_file, "rb") as f:
            return pickle.load(f)

    all_files_freqs = []
    all_files_amps = []
    all_files_phases = []
    
    for idx, filepath in enumerate(file_paths):
        print(f"[{name}] Processing file {idx+1}/{len(file_paths)}: {os.path.basename(filepath)}")
        samplerate, data = read_and_process_wav(filepath)
        if data is None:
            continue
            
        segment_samples = int(segment_length_seconds * samplerate)
        num_segments = len(data) // segment_samples
        
        freqs, amps, phases = [], [], []
        for i in range(num_segments):
            start = i * segment_samples
            end = start + segment_samples
            segment = data[start:end]
            
            # Use rfft for frequency, amplitude and phase
            fft_vals = np.fft.rfft(segment)
            f = np.fft.rfftfreq(segment_samples, d=1.0/samplerate)
            
            # Focus only on frequencies between min_freq and max_freq
            valid_idx = np.where((f >= min_freq) & (f <= max_freq))[0]
            if len(valid_idx) == 0:
                continue
                
            # Find peak inside the valid range
            fft_valid = fft_vals[valid_idx]
            peak_idx_valid = np.argmax(np.abs(fft_valid))
            peak_idx = valid_idx[peak_idx_valid]
            
            dominant_freq = f[peak_idx]
            peak_amp = np.abs(fft_vals[peak_idx])
            peak_phase = np.angle(fft_vals[peak_idx])
            
            freqs.append(dominant_freq)
            amps.append(peak_amp)
            phases.append(peak_phase)
            
        all_files_freqs.append(freqs)
        all_files_amps.append(amps)
        all_files_phases.append(phases)
        
    result = (all_files_freqs, all_files_amps, all_files_phases)
    with open(cache_file, "wb") as f:
        pickle.dump(result, f)
        
    return all_files_freqs, all_files_amps, all_files_phases

def compute_fairness(all_files_freqs, segment_length_seconds, buffer_length_seconds, is_circular=False):
    segments_per_buffer = buffer_length_seconds // segment_length_seconds
    all_fairness_values = []
    all_dominant_freqs = []
    
    for freqs in all_files_freqs:
        all_dominant_freqs.extend(freqs)
        if segments_per_buffer > 0:
            for i in range(0, len(freqs) - segments_per_buffer + 1, segments_per_buffer):
                buffer_freqs = freqs[i:i+segments_per_buffer]
                if is_circular:
                    fairness = circular_fairness_index(buffer_freqs)
                else:
                    fairness = jains_fairness_index(buffer_freqs)
                all_fairness_values.append(fairness)
                
    return all_fairness_values, all_dominant_freqs

def extract_frequencies_for_dir(directory, limit=None, min_freq=150, max_freq=2500, segment_length_seconds=2):
    wav_files = glob.glob(os.path.join(directory, "*.wav"))
    
    if not wav_files:
        print(f"No .wav files found in {directory}.")
        return [], [], []
        
    if limit is not None:
        wav_files = wav_files[:limit]
        
    print(f"Found .wav files, processing {len(wav_files)} file(s) in {directory}.")
    
    return extract_frequencies_for_files(wav_files, os.path.basename(directory), min_freq, max_freq, segment_length_seconds)



def main():
    dir1 = r"C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_2"
    dir2 = r"C:\Users\Roy\Recordings\Garda_2_26\2_Deep Water\Petrol"
    dir3 = r"C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2307"
    dir4 = r"C:\Users\Roy\Recordings\Garda_2_26\1_Shallow Water\Petrol"

    segment_sizes = [2]
    buffer_sizes = [15]
    
    labels = ['2407_2', 'Garda Petrol', '2307', 'Garda Shallow Petrol']
    colors = ['dodgerblue', 'crimson', 'mediumseagreen', 'darkviolet']

    for SEGMENT_SEC in segment_sizes:
        print(f"\n=======================================================")
        print(f"Extracting Data for Segment Size: {SEGMENT_SEC} seconds")
        print(f"=======================================================\n")
        
        f1, a1, p1 = extract_frequencies_for_dir(dir1, limit=None, min_freq=300, max_freq=1500, segment_length_seconds=SEGMENT_SEC)
        f3, a3, p3 = extract_frequencies_for_dir(dir3, limit=None, min_freq=300, max_freq=1500, segment_length_seconds=SEGMENT_SEC)
        
        lme_files = glob.glob(os.path.join(dir2, "*.wav"))
        if lme_files:
            f2, a2, p2 = extract_frequencies_for_files(lme_files, "Garda Petrol Deep", min_freq=150, max_freq=2000, segment_length_seconds=SEGMENT_SEC)
        else:
            f2, a2, p2 = [], [], []
            
        f4, a4, p4 = [], [], []

        for BUFFER_SEC in buffer_sizes:
            if BUFFER_SEC // SEGMENT_SEC < 3:
                print(f"Skipping Buffer={BUFFER_SEC}s for Segment={SEGMENT_SEC}s (Need at least 3 segments per buffer)")
                continue
                
            print(f"\n---> Generating Plot for Segment={SEGMENT_SEC}s, Buffer={BUFFER_SEC}s")
            
            # --- Frequencies ---
            fairness_f1, freqs1 = compute_fairness(f1, SEGMENT_SEC, BUFFER_SEC)
            fairness_f2, freqs2 = compute_fairness(f2, SEGMENT_SEC, BUFFER_SEC)
            fairness_f3, freqs3 = compute_fairness(f3, SEGMENT_SEC, BUFFER_SEC)
            fairness_f4, freqs4 = compute_fairness(f4, SEGMENT_SEC, BUFFER_SEC)
            
            # --- Amplitudes ---
            fairness_a1, amps1 = compute_fairness(a1, SEGMENT_SEC, BUFFER_SEC)
            fairness_a2, amps2 = compute_fairness(a2, SEGMENT_SEC, BUFFER_SEC)
            fairness_a3, amps3 = compute_fairness(a3, SEGMENT_SEC, BUFFER_SEC)
            fairness_a4, amps4 = compute_fairness(a4, SEGMENT_SEC, BUFFER_SEC)
            
            # --- Phases ---
            fairness_p1, phases1 = compute_fairness(p1, SEGMENT_SEC, BUFFER_SEC, is_circular=True)
            fairness_p2, phases2 = compute_fairness(p2, SEGMENT_SEC, BUFFER_SEC, is_circular=True)
            fairness_p3, phases3 = compute_fairness(p3, SEGMENT_SEC, BUFFER_SEC, is_circular=True)
            fairness_p4, phases4 = compute_fairness(p4, SEGMENT_SEC, BUFFER_SEC, is_circular=True)
            
            fig, axes = plt.subplots(6, 2, figsize=(16, 42))
            ax_freq, ax_freq_heat = axes[0, 0], axes[0, 1]
            ax_amp, ax_amp_heat = axes[1, 0], axes[1, 1]
            ax_phase, ax_phase_heat = axes[2, 0], axes[2, 1]
            ax_fair_f, ax_fair_f_heat = axes[3, 0], axes[3, 1]
            ax_fair_a, ax_fair_a_heat = axes[4, 0], axes[4, 1]
            ax_fair_p, ax_fair_p_heat = axes[5, 0], axes[5, 1]
            
            # --- Frequencies ---
            c1, c2, c3, c4 = plot_histogram(ax_freq, freqs1, freqs2, freqs3, freqs4, np.linspace(150, 2500, 40), labels, colors, f"Histogram of Dominant Frequencies (Hz)", "Frequency (Hz)")
            counts_dict = {'2407_2': c1, 'Garda Petrol': c2}
            if len(c3): counts_dict['2307'] = c3
            if len(c4): counts_dict['Garda Shallow Petrol'] = c4
            keys, _, jsd_mat = calc_kld_matrix(counts_dict, f'Frequencies (Seg={SEGMENT_SEC}s)')
            plot_divergence_heatmap(ax_freq_heat, keys, jsd_mat, "JSD Heatmap: Dominant Frequencies")
            
            # --- Amplitude ---
            max_amp = max([max(amps1) if amps1 else 0, max(amps2) if amps2 else 0, max(amps3) if amps3 else 0, max(amps4) if amps4 else 0])
            c1, c2, c3, c4 = plot_histogram(ax_amp, amps1, amps2, amps3, amps4, np.linspace(0, max_amp, 40), labels, colors, f"Histogram of Peak Amplitudes", "Amplitude")
            counts_dict = {'2407_2': c1, 'Garda Petrol': c2}
            if len(c3): counts_dict['2307'] = c3
            if len(c4): counts_dict['Garda Shallow Petrol'] = c4
            keys, _, jsd_mat = calc_kld_matrix(counts_dict, f'Amplitudes (Seg={SEGMENT_SEC}s)')
            plot_divergence_heatmap(ax_amp_heat, keys, jsd_mat, "JSD Heatmap: Peak Amplitudes")
            
            # --- Phase ---
            c1, c2, c3, c4 = plot_histogram(ax_phase, phases1, phases2, phases3, phases4, np.linspace(-np.pi, np.pi, 40), labels, colors, f"Histogram of Phase Angles", "Phase (Radians)")
            counts_dict = {'2407_2': c1, 'Garda Petrol': c2}
            if len(c3): counts_dict['2307'] = c3
            if len(c4): counts_dict['Garda Shallow Petrol'] = c4
            keys, _, jsd_mat = calc_kld_matrix(counts_dict, f'Phases (Seg={SEGMENT_SEC}s)')
            plot_divergence_heatmap(ax_phase_heat, keys, jsd_mat, "JSD Heatmap: Phase Angles")
            
            # --- Fairness (Frequency) ---
            c1, c2, c3, c4 = plot_histogram(ax_fair_f, fairness_f1, fairness_f2, fairness_f3, fairness_f4, np.linspace(0, 1.05, 43), labels, colors, f"Histogram of Freq Fairness\n(Buf={BUFFER_SEC}s, Seg={SEGMENT_SEC}s)", "Jain's Fairness Index")
            counts_dict = {'2407_2': c1, 'Garda Petrol': c2}
            if len(c3): counts_dict['2307'] = c3
            if len(c4): counts_dict['Garda Shallow Petrol'] = c4
            keys, _, jsd_mat = calc_kld_matrix(counts_dict, f'Freq Fairness (Seg={SEGMENT_SEC}s, Buf={BUFFER_SEC}s)')
            plot_divergence_heatmap(ax_fair_f_heat, keys, jsd_mat, "JSD Heatmap: Freq Fairness")
            if fairness_f1: ax_fair_f.axvline(np.mean(fairness_f1), color='navy', linestyle='dashed', linewidth=1.5, label=f'2407_2 Mean: {np.mean(fairness_f1):.2f}')
            if fairness_f2: ax_fair_f.axvline(np.mean(fairness_f2), color='darkred', linestyle='dashed', linewidth=1.5, label=f'Petrol Mean: {np.mean(fairness_f2):.2f}')
            if fairness_f3: ax_fair_f.axvline(np.mean(fairness_f3), color='darkgreen', linestyle='dashed', linewidth=1.5, label=f'2307 Mean: {np.mean(fairness_f3):.2f}')
            if fairness_f4: ax_fair_f.axvline(np.mean(fairness_f4), color='indigo', linestyle='dashed', linewidth=1.5, label=f'Shallow Petrol Mean: {np.mean(fairness_f4):.2f}')
            ax_fair_f.legend()
            
            # --- Fairness (Amplitude) ---
            c1, c2, c3, c4 = plot_histogram(ax_fair_a, fairness_a1, fairness_a2, fairness_a3, fairness_a4, np.linspace(0, 1.05, 43), labels, colors, f"Histogram of Amp Fairness\n(Buf={BUFFER_SEC}s, Seg={SEGMENT_SEC}s)", "Jain's Fairness Index")
            counts_dict = {'2407_2': c1, 'Garda Petrol': c2}
            if len(c3): counts_dict['2307'] = c3
            if len(c4): counts_dict['Garda Shallow Petrol'] = c4
            keys, _, jsd_mat = calc_kld_matrix(counts_dict, f'Amp Fairness (Seg={SEGMENT_SEC}s, Buf={BUFFER_SEC}s)')
            plot_divergence_heatmap(ax_fair_a_heat, keys, jsd_mat, "JSD Heatmap: Amp Fairness")
            if fairness_a1: ax_fair_a.axvline(np.mean(fairness_a1), color='navy', linestyle='dashed', linewidth=1.5, label=f'2407_2 Mean: {np.mean(fairness_a1):.2f}')
            if fairness_a2: ax_fair_a.axvline(np.mean(fairness_a2), color='darkred', linestyle='dashed', linewidth=1.5, label=f'Petrol Mean: {np.mean(fairness_a2):.2f}')
            if fairness_a3: ax_fair_a.axvline(np.mean(fairness_a3), color='darkgreen', linestyle='dashed', linewidth=1.5, label=f'2307 Mean: {np.mean(fairness_a3):.2f}')
            if fairness_a4: ax_fair_a.axvline(np.mean(fairness_a4), color='indigo', linestyle='dashed', linewidth=1.5, label=f'Shallow Petrol Mean: {np.mean(fairness_a4):.2f}')
            ax_fair_a.legend()
            
            # --- Fairness (Phase) ---
            c1, c2, c3, c4 = plot_histogram(ax_fair_p, fairness_p1, fairness_p2, fairness_p3, fairness_p4, np.linspace(0, 1.05, 43), labels, colors, f"Histogram of Phase Synchronization (R)\n(Buf={BUFFER_SEC}s, Seg={SEGMENT_SEC}s)", "Mean Resultant Length (R)")
            counts_dict = {'2407_2': c1, 'Garda Petrol': c2}
            if len(c3): counts_dict['2307'] = c3
            if len(c4): counts_dict['Garda Shallow Petrol'] = c4
            keys, _, jsd_mat = calc_kld_matrix(counts_dict, f'Phase Synchronization (Seg={SEGMENT_SEC}s, Buf={BUFFER_SEC}s)')
            plot_divergence_heatmap(ax_fair_p_heat, keys, jsd_mat, "JSD Heatmap: Phase Synchronization")
            if fairness_p1: ax_fair_p.axvline(np.mean(fairness_p1), color='navy', linestyle='dashed', linewidth=1.5, label=f'2407_2 Mean: {np.mean(fairness_p1):.2f}')
            if fairness_p2: ax_fair_p.axvline(np.mean(fairness_p2), color='darkred', linestyle='dashed', linewidth=1.5, label=f'Petrol Mean: {np.mean(fairness_p2):.2f}')
            if fairness_p3: ax_fair_p.axvline(np.mean(fairness_p3), color='darkgreen', linestyle='dashed', linewidth=1.5, label=f'2307 Mean: {np.mean(fairness_p3):.2f}')
            if fairness_p4: ax_fair_p.axvline(np.mean(fairness_p4), color='indigo', linestyle='dashed', linewidth=1.5, label=f'Shallow Petrol Mean: {np.mean(fairness_p4):.2f}')
            ax_fair_p.legend()

            plt.tight_layout()
            
            output_filename = f"fairness_plot_seg_{SEGMENT_SEC}s_buf_{BUFFER_SEC}s.png"
            plt.savefig(output_filename, dpi=150, bbox_inches='tight')
            print(f"Saved: {output_filename}")
            plt.close(fig)

if __name__ == '__main__':
    main()
