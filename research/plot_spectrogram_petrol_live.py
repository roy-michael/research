import os
import glob
import numpy as np
from scipy.io import wavfile
import matplotlib.pyplot as plt
from plot_spectrogram_2407_1 import plot_spectrogram

def load_petrol_dataset(file_dir):
    """
    Reads all .wav files in the directory.
    """
    search_pattern = os.path.join(file_dir, '*.wav')
    files = sorted(glob.glob(search_pattern))
    
    if len(files) == 0:
        raise ValueError(f"No .wav files found in {file_dir}.")
        
    all_data = []
    base_samplerate = None
    
    print(f"Loading all {len(files)} files from {file_dir}...")
    
    for f in files:
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
    # Change to "1_Shallow Water\Petrol" for the shallow dataset
    DIR_PATH = r"C:\Users\Roy\Recordings\Garda_2_26\2_Deep Water\Petrol"
    try:
        sample_rate, continuous_data = load_petrol_dataset(DIR_PATH)
        print(f"Successfully loaded Petrol dataset. Shape: {continuous_data.shape}, Sample Rate: {sample_rate} Hz")
        
        # Remove NaNs and Infs if any exist
        clean_data = continuous_data[np.isfinite(continuous_data)]
        
        print("Launching interactive spectrogram...")
        # Re-using the plot_spectrogram from your existing script which has the DynamicSpectrogram class.
        # This is mathematically designed to handle massive (e.g. 6.5 GB+) datasets by only
        # calculating and rendering the exact portion of the matrix you are zoomed in on!
        plot_spectrogram(sample_rate, clean_data)
        
    except Exception as e:
        print(f"An error occurred: {e}")
        import traceback
        traceback.print_exc()
