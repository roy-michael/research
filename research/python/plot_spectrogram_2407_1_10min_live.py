import os
import glob
import numpy as np
from scipy.io import wavfile
import matplotlib.pyplot as plt
from plot_spectrogram_2407_1 import plot_spectrogram

def load_segment(file_dir, start_file_idx=20, end_file_idx=30):
    """
    Reads a specific segment of .wav files in the directory.
    Assumes each file is 1-minute long (based on 2407_1 dataset).
    """
    search_pattern = os.path.join(file_dir, '*.wav')
    files = sorted(glob.glob(search_pattern))
    
    if len(files) < end_file_idx:
        raise ValueError(f"Not enough files. Found {len(files)}, need at least {end_file_idx}.")
        
    selected_files = files[start_file_idx:end_file_idx]
    
    all_data = []
    base_samplerate = None
    
    print(f"Loading {len(selected_files)} files (from {start_file_idx} to {end_file_idx-1})...")
    
    for f in selected_files:
        print(f"Reading {os.path.basename(f)}...")
        sr, data = wavfile.read(f)
        
        if base_samplerate is None:
            base_samplerate = sr
            
        # Convert to mono if stereo
        if len(data.shape) > 1:
            data = data.mean(axis=1)
            
        all_data.append(data)
        
    return base_samplerate, np.concatenate(all_data)

if __name__ == '__main__':
    DIR_PATH = r"C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_1_600m"
    try:
        sample_rate, continuous_data = load_segment(DIR_PATH, 20, 30)
        print(f"Successfully loaded 10-minute segment. Shape: {continuous_data.shape}, Sample Rate: {sample_rate} Hz")
        
        # Remove NaNs and Infs if any exist
        clean_data = continuous_data[np.isfinite(continuous_data)]
        
        print("Launching interactive spectrogram...")
        # Re-using the plot_spectrogram from your existing script which has the DynamicSpectrogram class
        # This will pop up a matplotlib window that allows zooming and dynamically re-renders high-res details
        plot_spectrogram(sample_rate, clean_data)
        
    except Exception as e:
        print(f"An error occurred: {e}")
        import traceback
        traceback.print_exc()
