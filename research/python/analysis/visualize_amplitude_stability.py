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
import pandas as pd
import seaborn as sns
from scipy.io import wavfile
from scipy.signal import butter, sosfiltfilt, find_peaks
import matplotlib.mlab as mlab
from config import get_output_dir

def butter_bandpass(lowcut, highcut, fs, order=5):
    nyq = 0.5 * fs
    low = lowcut / nyq
    high = highcut / nyq
    sos = butter(order, [low, high], btype='band', output='sos')
    return sos

def butter_bandpass_filter(data, lowcut, highcut, fs, order=9):
    sos = butter_bandpass(lowcut, highcut, fs, order=order)
    y = sosfiltfilt(sos, data)
    return y

def load_and_process_dataset(dataset_dir, dataset_name, target_duration_sec=30.0):
    print(f"Loading {dataset_name} in {dataset_dir}...")
    search_pattern = os.path.join(dataset_dir, '*.wav')
    files = sorted(glob.glob(search_pattern))
    if not files:
        print(f"No files found for {dataset_name}.")
        return None, None
    
    fs = None
    all_filtered = []
    for f in files[:20]: # Limit to first 20 files for performance
        try:
            sr, data = wavfile.read(f)
            if data.size == 0:
                continue
            if fs is None:
                fs = sr
            if len(data.shape) > 1:
                data = data.mean(axis=1)
            filtered = butter_bandpass_filter(data, 100.0, 2000.0, fs, order=5)
            all_filtered.append(filtered[::10])
        except Exception as e:
            print(f"Error reading {f}: {e}")
            
    if not all_filtered:
        return None, None
        
    concatenated = np.concatenate(all_filtered)
    new_fs = fs / 10.0

    target_samples = int(target_duration_sec * new_fs)
    if len(concatenated) < target_samples:
        print(f"[{dataset_name}] Shorter than {target_duration_sec}s. Skipping.")
        return None, None

    return concatenated[:target_samples], new_fs

def main():
    base_dirs = [
        r"C:\Users\Roy\Recordings\hear_my_ship\V1\Motor Boats",
        r"C:\Users\Roy\Recordings\Croatia\Ocean Sonics"
    ]
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = os.path.abspath(os.path.join(script_dir, "..", "..", "output", "combined_analysis"))
    os.makedirs(output_dir, exist_ok=True)
    
    all_datasets = []
    for bdir in base_dirs:
        if os.path.exists(bdir):
            for d in os.listdir(bdir):
                if os.path.isdir(os.path.join(bdir, d)):
                    all_datasets.append((d, os.path.join(bdir, d)))
    
    cv_data = [] # to store CV values for Bar Chart
    fairness_data = [] # to store Jain's Fairness values
    
    for ds, dataset_dir in all_datasets:
        if not os.path.exists(dataset_dir):
            continue
            
        data_signal, fs = load_and_process_dataset(ds_dir, ds_name)
        if data_signal is None:
            continue
            
        # Compute spectrogram
        nfft = 2048
        noverlap = int(nfft * 0.75)
        pxx, freqs, bins = mlab.specgram(data_signal, NFFT=nfft, Fs=fs, noverlap=noverlap, mode='psd')
        
        # --- Dynamic Peak Finding ---
        mean_pxx = np.mean(pxx, axis=1)
        # Find peaks in the mean power spectrum
        peaks, properties = find_peaks(mean_pxx, height=np.max(mean_pxx) * 0.01, distance=10)

        # Get the top 3 highest peaks
        if len(peaks) == 0:
            print(f"No peaks found for {ds}, skipping.")
            continue

        peak_heights = properties['peak_heights']
        # Sort by height descending and take top 3
        top_peaks_idx = peaks[np.argsort(peak_heights)[-3:][::-1]]
        target_freqs = sorted([freqs[p] for p in top_peaks_idx])
        print(f"[{ds}] Detected Target Frequencies: {[f'{f:.1f} Hz' for f in target_freqs]}")

        # Get amplitudes for targets
        harmonics_amp_db = {}
        harmonics_amp_lin = {}
        
        for i, tf in enumerate(target_freqs):
            idx = np.argmin(np.abs(freqs - tf))
            amp_lin = np.sqrt(pxx[idx, :])
            amp_db = 10 * np.log10(pxx[idx, :] + 1e-12)
            
            harmonics_amp_lin[tf] = amp_lin
            harmonics_amp_db[tf] = amp_db

            mean_lin = np.mean(amp_lin)
            std_lin = np.std(amp_lin)
            cv = std_lin / mean_lin if mean_lin > 0 else 0

            # --- Calculate Fairness ---
            # 1. Amplitude Fairness
            amp_fairness = (np.sum(amp_lin))**2 / (len(amp_lin) * np.sum(amp_lin**2)) if np.sum(amp_lin**2) > 0 else 0

            # 2. Frequency and Bandwidth Fairness
            search_bins = 5
            freq_track = []
            bw_track = []
            for t_idx in range(pxx.shape[1]):
                local_slice = pxx[max(0, idx-search_bins):min(len(freqs), idx+search_bins+1), t_idx]
                peak_idx_local = np.argmax(local_slice)
                true_idx = max(0, idx-search_bins) + peak_idx_local
                freq_track.append(freqs[true_idx])
                
                # Calculate 3dB Bandwidth (half power)
                half_power = pxx[true_idx, t_idx] / 2.0
                l_idx = true_idx
                while l_idx > 0 and pxx[l_idx, t_idx] > half_power:
                    l_idx -= 1
                r_idx = true_idx
                while r_idx < len(freqs)-1 and pxx[r_idx, t_idx] > half_power:
                    r_idx += 1
                bw_track.append(freqs[r_idx] - freqs[l_idx])
                
            freq_track = np.array(freq_track)
            bw_track = np.array(bw_track)
            freq_fairness = (np.sum(freq_track))**2 / (len(freq_track) * np.sum(freq_track**2)) if np.sum(freq_track**2) > 0 else 0
            bw_fairness = (np.sum(bw_track))**2 / (len(bw_track) * np.sum(bw_track**2)) if np.sum(bw_track**2) > 0 else 0

            fairness_data.append({
                'Dataset': ds,
                'Harmonic': f"Peak {i+1}",
                'Amplitude Fairness': amp_fairness,
                'Frequency Fairness': freq_fairness,
                'Bandwidth Fairness': bw_fairness
            })

            cv_data.append({
                'Dataset': ds_name,
                'Harmonic': f"Peak {i+1}",
                'CV': cv,
                'Mean_dB': np.mean(amp_db),
                'Std_dB': np.std(amp_db)
            })
            
        # --- Option 1: Violin Plot ---
        plt.figure(figsize=(10, 6))
        df_violin = pd.DataFrame({f"{tf} Hz": harmonics_amp_db[tf] for tf in target_freqs})
        sns.violinplot(data=df_violin, palette="muted", inner="quartile")
        plt.title(f"Amplitude Spread (dB) Violin Plot\nDataset: {ds_name}", fontsize=14, fontweight='bold')
        plt.xlabel("Harmonic Frequency", fontsize=12)
        plt.ylabel("Amplitude (dB)", fontsize=12)
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        violin_path = output_dir / f"{args.dataset_name}_stability_violin_{ds_name}.png"
        plt.savefig(violin_path, dpi=300)
        plt.close()
        
        # --- Option 2: Time-Series with rolling std ---
        plt.figure(figsize=(12, 6))
        time_seconds = bins
        window = 100
        
        for tf in target_freqs:
            y = harmonics_amp_db[tf]
            s = pd.Series(y)
            roll_mean = s.rolling(window, center=True).mean()
            roll_std = s.rolling(window, center=True).std()
            
            p = plt.plot(time_seconds, roll_mean, label=f"{tf} Hz (mean)")
            color = p[0].get_color()
            plt.fill_between(time_seconds, roll_mean - roll_std, roll_mean + roll_std, color=color, alpha=0.2, label=f"{tf} Hz ±1 std")
            
        plt.title(f"Amplitude Time-Series with Rolling Std Envelope\nDataset: {ds_name} (Window={window})", fontsize=14, fontweight='bold')
        plt.xlabel("Time (seconds)", fontsize=12)
        plt.ylabel("Amplitude (dB)", fontsize=12)
        plt.legend(loc='upper right')
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        ts_path = output_dir / f"{args.dataset_name}_stability_timeseries_{ds_name}.png"
        plt.savefig(ts_path, dpi=300)
        plt.close()
        
        print(f"Generated Violin & Time-Series plots for {ds_name}.")
        
    # --- Option 3: CV Bar Chart ---
    if cv_data:
        df_cv = pd.DataFrame(cv_data)
        plt.figure(figsize=(12, 7))
        sns.barplot(data=df_cv, x='Dataset', y='CV', hue='Harmonic', palette='viridis')
        plt.title(f"{args.dataset_name.capitalize()} Amplitude Coefficient of Variation (CV)\nLower CV = Higher Stability", fontsize=14, fontweight='bold')
        plt.xlabel("Dataset", fontsize=12)
        plt.ylabel("Coefficient of Variation (std / mean)", fontsize=12)
        plt.grid(True, axis='y', alpha=0.3)
        plt.tight_layout()
        cv_path = output_dir / f"{args.dataset_name}_stability_cv_comparison.png"
        plt.savefig(cv_path, dpi=300)
        plt.close()
        print(f"Generated CV plot to: {cv_path}")

    # --- Option 4: Fairness Histograms ---
    if fairness_data:
        df_fair = pd.DataFrame(fairness_data)

        plt.figure(figsize=(18, 6))

        # Subplot 1: Amplitude Fairness
        plt.subplot(1, 3, 1)
        sns.histplot(data=df_fair, x='Amplitude Fairness', hue='Harmonic', multiple='stack', bins=20, palette='viridis')
        plt.title("Amplitude Fairness Histogram (Jain's Index)", fontsize=12, fontweight='bold')
        plt.xlabel("Fairness Index (1.0 = Perfectly Stable)", fontsize=10)
        plt.ylabel("Count", fontsize=10)

        # Subplot 2: Frequency Fairness
        plt.subplot(1, 3, 2)
        sns.histplot(data=df_fair, x='Frequency Fairness', hue='Harmonic', multiple='stack', bins=20, palette='viridis')
        plt.title("Frequency Fairness Histogram (Jain's Index)", fontsize=12, fontweight='bold')
        plt.xlabel("Fairness Index (1.0 = Perfectly Stable)", fontsize=10)
        plt.ylabel("Count", fontsize=10)

        # Subplot 3: Bandwidth Fairness
        plt.subplot(1, 3, 3)
        sns.histplot(data=df_fair, x='Bandwidth Fairness', hue='Harmonic', multiple='stack', bins=20, palette='viridis')
        plt.title("Bandwidth Fairness Histogram (Jain's Index)", fontsize=12, fontweight='bold')
        plt.xlabel("Fairness Index (1.0 = Perfectly Stable)", fontsize=10)
        plt.ylabel("Count", fontsize=10)

        plt.tight_layout()
        fair_path = os.path.join(output_dir, "stability_option4_fairness_histograms.png")
        plt.savefig(fair_path, dpi=300)
        plt.close()
        print(f"Generated Option 4 plot to: {fair_path}")

if __name__ == '__main__':
    main()
