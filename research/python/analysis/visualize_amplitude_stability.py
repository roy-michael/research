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
from scipy.signal import butter, sosfiltfilt
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

def load_and_process_dataset(dataset_dir, dataset_name):
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
            # Filter from 20 to 1500 Hz
            filtered = butter_bandpass_filter(data, 20.0, 1500.0, fs, order=5)
            all_filtered.append(filtered[::32]) # Downsample by 32
        except Exception as e:
            print(f"Error reading {f}: {e}")
            
    if not all_filtered:
        return None, None
        
    concatenated = np.concatenate(all_filtered)
    new_fs = fs / 32.0
    return concatenated, new_fs

def main():
    parser = argparse.ArgumentParser(description="Visualize amplitude stability.")
    parser.add_argument("--dataset-name", required=True, help="Global name for output folder (e.g. 'garda')")
    parser.add_argument("--subsets", nargs='+', required=True, help="List of subset name and path pairs (e.g. Shallow_Petrol C:/path/...)")
    parser.add_argument("--freqs", nargs='+', type=float, required=True, help="Target frequencies to analyze")
    
    args = parser.parse_args()
    
    # Parse subsets
    if len(args.subsets) % 2 != 0:
        print("Error: --subsets must be provided as name path pairs.")
        sys.exit(1)
        
    datasets = {}
    for i in range(0, len(args.subsets), 2):
        datasets[args.subsets[i]] = args.subsets[i+1]
        
    target_freqs = args.freqs
    output_dir = get_output_dir(args.dataset_name)
    
    cv_data = [] # Store CV values for Grouped Bar Chart
    
    for ds_name, ds_dir in datasets.items():
        if not os.path.exists(ds_dir):
            print(f"Directory not found: {ds_dir}")
            continue
            
        data_signal, fs = load_and_process_dataset(ds_dir, ds_name)
        if data_signal is None:
            continue
            
        # Compute spectrogram
        nfft = 2048
        noverlap = int(nfft * 0.75)
        pxx, freqs, bins = mlab.specgram(data_signal, NFFT=nfft, Fs=fs, noverlap=noverlap, mode='psd')
        
        harmonics_amp_db = {}
        harmonics_amp_lin = {}
        
        for tf in target_freqs:
            idx = np.argmin(np.abs(freqs - tf))
            amp_lin = np.sqrt(pxx[idx, :])
            amp_db = 10 * np.log10(pxx[idx, :] + 1e-12)
            
            harmonics_amp_lin[tf] = amp_lin
            harmonics_amp_db[tf] = amp_db
            
            mean_lin = np.mean(amp_lin)
            std_lin = np.std(amp_lin)
            cv = std_lin / mean_lin if mean_lin > 0 else 0
            cv_data.append({
                'Dataset': ds_name,
                'Harmonic': f"{tf} Hz",
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

if __name__ == '__main__':
    main()
