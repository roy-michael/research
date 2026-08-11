import sys
import os
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
    print(f"Loading {dataset_name}...")
    search_pattern = os.path.join(dataset_dir, '*.wav')
    files = sorted(glob.glob(search_pattern))
    if not files:
        return None, None
    
    fs = None
    all_filtered = []
    for f in files[:20]: # limit to first 20 files for performance
        try:
            sr, data = wavfile.read(f)
            if data.size == 0:
                continue
            if fs is None:
                fs = sr
            if len(data.shape) > 1:
                data = data.mean(axis=1)
            filtered = butter_bandpass_filter(data, 400.0, 1200.0, fs, order=5)
            all_filtered.append(filtered[::32])
        except Exception as e:
            print(f"Error reading {f}: {e}")
            
    if not all_filtered:
        return None, None
        
    concatenated = np.concatenate(all_filtered)
    new_fs = fs / 32.0
    return concatenated, new_fs

def main():
    base_dir = r"D:\RoyStudies\Recordings\Croatia\Ocean Sonics"
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = os.path.abspath(os.path.join(script_dir, "..", "..", "output", "croatia"))
    os.makedirs(output_dir, exist_ok=True)
    
    datasets = ['2307_free', '2407_1_600m', '2407_2_snake', '2507_1_1k', '2507_2_joint']
    target_freqs = [497.0, 994.0, 1491.0]
    
    cv_data = [] # to store CV values for Bar Chart
    
    for ds in datasets:
        dataset_dir = os.path.join(base_dir, ds)
        if not os.path.exists(dataset_dir):
            continue
            
        data_signal, fs = load_and_process_dataset(dataset_dir, ds)
        if data_signal is None:
            continue
            
        # Compute spectrogram
        nfft = 2048
        noverlap = int(nfft * 0.75)
        pxx, freqs, bins = mlab.specgram(data_signal, NFFT=nfft, Fs=fs, noverlap=noverlap, mode='psd')
        
        # Get amplitudes for targets
        harmonics_amp_db = {}
        harmonics_amp_lin = {}
        
        for tf in target_freqs:
            idx = np.argmin(np.abs(freqs - tf))
            actual_f = freqs[idx]
            amp_lin = np.sqrt(pxx[idx, :])
            amp_db = 10 * np.log10(pxx[idx, :] + 1e-12)
            
            harmonics_amp_lin[tf] = amp_lin
            harmonics_amp_db[tf] = amp_db
            
            # Calculate CV
            mean_lin = np.mean(amp_lin)
            std_lin = np.std(amp_lin)
            cv = std_lin / mean_lin if mean_lin > 0 else 0
            cv_data.append({
                'Dataset': ds,
                'Harmonic': f"{tf} Hz",
                'CV': cv,
                'Mean_dB': np.mean(amp_db),
                'Std_dB': np.std(amp_db)
            })
            
        # --- Option 1: Violin Plot (Amplitude Spread in dB) ---
        plt.figure(figsize=(10, 6))
        df_violin = pd.DataFrame({f"{tf} Hz": harmonics_amp_db[tf] for tf in target_freqs})
        sns.violinplot(data=df_violin, palette="muted", inner="quartile")
        plt.title(f"Option 1: Amplitude Spread (dB) Violin Plot\nDataset: {ds}", fontsize=14, fontweight='bold')
        plt.xlabel("Harmonic Frequency", fontsize=12)
        plt.ylabel("Amplitude (dB)", fontsize=12)
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        violin_path = os.path.join(output_dir, f"stability_option1_violin_{ds}.png")
        plt.savefig(violin_path, dpi=300)
        plt.close()
        
        # --- Option 2: Time-Series with rolling standard deviation envelope ---
        plt.figure(figsize=(12, 6))
        time_seconds = bins
        window = 100 # rolling window for smoothing
        
        for tf in target_freqs:
            y = harmonics_amp_db[tf]
            # Smooth using pandas rolling
            s = pd.Series(y)
            roll_mean = s.rolling(window, center=True).mean()
            roll_std = s.rolling(window, center=True).std()
            
            p = plt.plot(time_seconds, roll_mean, label=f"{tf} Hz (mean)")
            color = p[0].get_color()
            plt.fill_between(time_seconds, roll_mean - roll_std, roll_mean + roll_std, color=color, alpha=0.2, label=f"{tf} Hz ±1 std")
            
        plt.title(f"Option 2: Amplitude Time-Series with Rolling Std Envelope\nDataset: {ds} (Window={window})", fontsize=14, fontweight='bold')
        plt.xlabel("Time (seconds)", fontsize=12)
        plt.ylabel("Amplitude (dB)", fontsize=12)
        plt.legend(loc='upper right')
        plt.grid(True, alpha=0.3)
        plt.tight_layout()
        ts_path = os.path.join(output_dir, f"stability_option2_timeseries_{ds}.png")
        plt.savefig(ts_path, dpi=300)
        plt.close()
        
        print(f"Generated Option 1 and Option 2 plots for {ds}.")
        
    # --- Option 3: Coefficient of Variation (CV) Bar Chart ---
    if cv_data:
        df_cv = pd.DataFrame(cv_data)
        plt.figure(figsize=(12, 7))
        sns.barplot(data=df_cv, x='Dataset', y='CV', hue='Harmonic', palette='viridis')
        plt.title("Option 3: Amplitude Coefficient of Variation (CV) Comparison\nLower CV = Higher Stability", fontsize=14, fontweight='bold')
        plt.xlabel("Dataset", fontsize=12)
        plt.ylabel("Coefficient of Variation (std / mean)", fontsize=12)
        plt.grid(True, axis='y', alpha=0.3)
        plt.tight_layout()
        cv_path = os.path.join(output_dir, "stability_option3_cv_comparison.png")
        plt.savefig(cv_path, dpi=300)
        plt.close()
        print(f"Generated Option 3 plot to: {cv_path}")

if __name__ == '__main__':
    main()
