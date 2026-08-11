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
    
    # Get all .wav files sorted alphabetically (chronological order)
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
                # Normalize based on integer range
                if data.dtype == np.int32:
                    data = data.astype(np.float32) / 2147483648.0
                elif data.dtype == np.int16:
                    data = data.astype(np.float32) / 32768.0
                else:
                    data = data.astype(np.float32)
            
            if len(data.shape) > 1:
                data = data.mean(axis=1)
                
            # Apply bandpass filter
            filtered = butter_bandpass_filter(data, 400.0, 1200.0, fs, order=5)
            
            # Downsample by 32 (slicing since the signal is filtered below Nyquist for new fs = fs/32 = 4000 Hz)
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
    
    # Compute spectrogram
    nfft = 2048
    noverlap = int(nfft * 0.75)
    
    plt.figure(figsize=(12, 6))
    # We use specgram directly which handles plotting and returns values
    # viridis or inferno colormap looks premium
    pxx, freqs, bins, im = plt.specgram(
        concatenated_data,
        NFFT=nfft,
        Fs=new_fs,
        noverlap=noverlap,
        cmap='inferno',
        mode='psd'
    )
    
    plt.title(f"Spectrogram of Croatia {dataset_name}\nBandpass Filtered: 400 - 1000 Hz", fontsize=14, fontweight='bold', pad=15)
    plt.xlabel("Time [seconds]", fontsize=12)
    plt.ylabel("Frequency [Hz]", fontsize=12)
    plt.ylim(400, 1500)  # Focus only on the bandpassed region
    
    # Add a nice colorbar with label
    cbar = plt.colorbar(im, label="Power Spectral Density (dB/Hz)")
    
    plt.grid(True, linestyle='--', alpha=0.5)
    plt.tight_layout()
    
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, f"croatia_spectrogram_{dataset_name}.png")
    plt.savefig(output_path, dpi=300)
    plt.close()
    
    print(f"Successfully saved plot to: {output_path}")

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
