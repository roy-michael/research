import os
import numpy as np
import matplotlib.pyplot as plt
from scipy.io import wavfile
from scipy.signal import welch

def get_dominant_freq(wav_path):
    try:
        fs, data = wavfile.read(wav_path)
        if len(data.shape) > 1:
            data = data[:, 0]
        
        # Skip very short files
        if len(data) < fs:
            return None
            
        freqs, psd = welch(data, fs=fs, nperseg=min(2048, len(data)))
        
        # Convert PSD to dB
        psd_db = 10 * np.log10(psd + 1e-12)
        
        # Only consider 0-4000 Hz
        mask = (freqs >= 0) & (freqs <= 4000)
        freqs_zoom = freqs[mask]
        psd_zoom = psd_db[mask]
        
        dominant_idx = np.argmax(psd_zoom)
        return freqs_zoom[dominant_idx]
    except Exception as e:
        print(f"Error processing {wav_path}: {e}")
        return None

def main():
    motorboat_dir = r"D:\RoyStudies\Recordings\hear-my-ship\V1\Motor Boats"
    output_img = r"d:\dev\research\scratch\motorboat_histogram.png"
    
    if not os.path.exists(motorboat_dir):
        print(f"Directory not found: {motorboat_dir}")
        return
        
    dominant_freqs = []
    
    wav_files = [f for f in os.listdir(motorboat_dir) if f.lower().endswith('.wav')]
    print(f"Found {len(wav_files)} wav files.")
    
    for i, wav_file in enumerate(wav_files):
        wav_path = os.path.join(motorboat_dir, wav_file)
        freq = get_dominant_freq(wav_path)
        if freq is not None:
            dominant_freqs.append(freq)
            
        if (i + 1) % 50 == 0:
            print(f"Processed {i + 1}/{len(wav_files)}")
            
    # Plot histogram
    plt.figure(figsize=(10, 6), dpi=150)
    plt.hist(dominant_freqs, bins=50, color='skyblue', edgecolor='black')
    plt.title('Histogram of Dominant Frequencies for Motor Boats (Hear My Ship)')
    plt.xlabel('Frequency (Hz)')
    plt.ylabel('Count')
    plt.grid(axis='y', alpha=0.75)
    plt.xlim(0, 4000)
    
    plt.savefig(output_img, bbox_inches='tight')
    plt.close()
    print(f"Histogram saved to {output_img}")

if __name__ == "__main__":
    main()
