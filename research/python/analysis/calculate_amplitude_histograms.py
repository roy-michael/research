import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'analysis')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'plotting')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'simulation')))

import glob
import numpy as np
import matplotlib.pyplot as plt
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

def process_dataset(dataset_dir, dataset_name, output_dir):
    print(f"\nProcessing dataset: {dataset_name} in {dataset_dir}...")
    
    # Get all .wav files sorted alphabetically
    search_pattern = os.path.join(dataset_dir, '*.wav')
    files = sorted(glob.glob(search_pattern))
    
    if not files:
        print(f"No .wav files found for {dataset_name}. Skipping.")
        return
        
    print(f"Found {len(files)} files. Loading, filtering, and downsampling...")
    
    fs = None
    all_filtered_data = []
    
    for f in files:
        try:
            sr, data = wavfile.read(f)
            if data.size == 0:
                continue
                
            if fs is None:
                fs = sr
            elif fs != sr:
                print(f"Warning: sample rate mismatch in {f}. Expected {fs}, got {sr}")
                
            # Convert to float and mono
            if data.dtype != np.float32 and data.dtype != np.float64:
                if data.dtype == np.int32:
                    data = data.astype(np.float32) / 2147483648.0
                elif data.dtype == np.int16:
                    data = data.astype(np.float32) / 32768.0
                else:
                    data = data.astype(np.float32)
            
            if len(data.shape) > 1:
                data = data.mean(axis=1)
                
            # Apply bandpass filter (matching the spectrogram script)
            filtered = butter_bandpass_filter(data, 400.0, 1200.0, fs, order=5)
            
            # Downsample by 32
            downsampled = filtered[::32]
            all_filtered_data.append(downsampled)
            
        except Exception as e:
            print(f"Error reading or processing {f}: {e}")
            
    if not all_filtered_data:
        print(f"No valid data loaded for {dataset_name}.")
        return
        
    concatenated_data = np.concatenate(all_filtered_data)
    new_fs = fs / 32.0
    print(f"Concatenated data shape: {concatenated_data.shape}, New Sample Rate: {new_fs} Hz")
    
    # Compute spectrogram using mlab.specgram (matches plt.specgram but non-visual)
    nfft = 2048
    noverlap = int(nfft * 0.75)
    
    # Specgram returns PSD (pxx), frequencies (freqs), and time bins
    pxx, freqs, bins = mlab.specgram(
        concatenated_data,
        NFFT=nfft,
        Fs=new_fs,
        noverlap=noverlap,
        mode='psd'
    )
    
    # Define target frequencies (harmonics of 497 Hz)
    target_freqs = [497.0, 994.0, 1491.0]
    
    # Find the indices of the closest frequency bins to target_freqs
    freq_indices = [np.argmin(np.abs(freqs - tf)) for tf in target_freqs]
    pxx = pxx[freq_indices, :]
    freqs = freqs[freq_indices]
    
    # Calculate amplitude (linear and dB)
    amp_linear = np.sqrt(pxx)
    amp_dB = 10 * np.log10(pxx + 1e-12)
    
    # We will compute a 2D histogram grid (probability distribution) for the amplitude
    # 1. dB amplitude histogram
    db_bins = np.linspace(-120, -10, 11) # 10 bins
    db_hist_2d = np.zeros((len(freqs), len(db_bins) - 1))
    
    # 2. Linear amplitude histogram
    lin_max = np.percentile(amp_linear, 99.9) # Robust max to ignore outliers
    lin_bins = np.linspace(0, lin_max, 11) # 10 bins
    lin_hist_2d = np.zeros((len(freqs), len(lin_bins) - 1))
    
    print("Calculating histograms for each frequency bin...")
    for i in range(len(freqs)):
        # dB histogram
        hist_db, _ = np.histogram(amp_dB[i, :], bins=db_bins, density=True)
        db_hist_2d[i, :] = hist_db
        
        # Linear histogram
        hist_lin, _ = np.histogram(amp_linear[i, :], bins=lin_bins, density=True)
        lin_hist_2d[i, :] = hist_lin
        
    os.makedirs(output_dir, exist_ok=True)
    
    # Save the raw histogram data to .npz
    npz_path = os.path.join(output_dir, f"amplitude_histograms_{dataset_name}.npz")
    np.savez(
        npz_path,
        frequencies=target_freqs,
        db_bins=db_bins,
        db_hist_2d=db_hist_2d,
        lin_bins=lin_bins,
        lin_hist_2d=lin_hist_2d
    )
    print(f"Saved histogram data to: {npz_path}")
    
    # Plotting 2D heatmaps of the distributions
    # 1. dB Heatmap
    plt.figure(figsize=(10, 7))
    db_bin_centers = 0.5 * (db_bins[:-1] + db_bins[1:])
    # Swapped X and Y: X=target frequencies, Y=amplitude (dB)
    plt.pcolormesh(np.arange(len(target_freqs)), db_bin_centers, db_hist_2d.T, cmap='inferno', shading='nearest')
    plt.colorbar(label='Probability Density')
    plt.title(f"Amplitude (dB) Distribution per Harmonic Bin\nDataset: {dataset_name}", fontsize=14, fontweight='bold')
    plt.xticks(np.arange(len(target_freqs)), [f"{tf} Hz" for tf in target_freqs])
    plt.xlabel("Frequency Harmonic (Hz)", fontsize=12)
    plt.ylabel("Amplitude (dB)", fontsize=12)
    plt.grid(True, linestyle='--', alpha=0.3)
    plt.tight_layout()
    plot_path_db = os.path.join(output_dir, f"amplitude_db_hist_2d_{dataset_name}.png")
    plt.savefig(plot_path_db, dpi=300)
    plt.close()
    
    # 2. Linear Heatmap
    plt.figure(figsize=(10, 7))
    lin_bin_centers = 0.5 * (lin_bins[:-1] + lin_bins[1:])
    # Swapped X and Y: X=target frequencies, Y=amplitude (linear)
    plt.pcolormesh(np.arange(len(target_freqs)), lin_bin_centers, lin_hist_2d.T, cmap='inferno', shading='nearest')
    plt.colorbar(label='Probability Density')
    plt.title(f"Amplitude (Linear) Distribution per Harmonic Bin\nDataset: {dataset_name}", fontsize=14, fontweight='bold')
    plt.xticks(np.arange(len(target_freqs)), [f"{tf} Hz" for tf in target_freqs])
    plt.xlabel("Frequency Harmonic (Hz)", fontsize=12)
    plt.ylabel("Amplitude (Linear)", fontsize=12)
    plt.grid(True, linestyle='--', alpha=0.3)
    plt.tight_layout()
    plot_path_lin = os.path.join(output_dir, f"amplitude_linear_hist_2d_{dataset_name}.png")
    plt.savefig(plot_path_lin, dpi=300)
    plt.close()
    
    print(f"Saved plots to:\n  - {plot_path_db}\n  - {plot_path_lin}")

def main():
    base_dir = r"D:\RoyStudies\Recordings\Croatia\Ocean Sonics"
    script_dir = os.path.dirname(os.path.abspath(__file__))
    output_dir = os.path.abspath(os.path.join(script_dir, "..", "..", "output", "croatia"))
    
    datasets = ['2307_free', '2407_1_600m', '2407_2_snake', '2507_1_1k', '2507_2_joint']
    
    for ds in datasets:
        dataset_dir = os.path.join(base_dir, ds)
        if os.path.exists(dataset_dir):
            process_dataset(dataset_dir, ds, output_dir)
        else:
            print(f"Dataset directory not found: {dataset_dir}")

if __name__ == "__main__":
    main()
