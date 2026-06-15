import os
import glob
import numpy as np
import matplotlib.pyplot as plt
from scipy.io import wavfile
from scipy import signal
from sklearn.decomposition import NMF
import traceback

def load_and_concatenate(file_dir):
    """
    Reads all .wav files in the directory, sorts them alphabetically (which 
    maintains chronological order for timestamped filenames), and concatenates 
    them into a single continuous signal.
    """
    search_pattern = os.path.join(file_dir, '*.wav')
    files = sorted(glob.glob(search_pattern))
    
    if not files:
        raise FileNotFoundError(f"No .wav files found in directory: {file_dir}")
    
    all_data = []
    base_samplerate = None
    
    print(f"Found {len(files)} .wav files. Concatenating into a continuous timeline...")
    for f in files:
        sr, data = wavfile.read(f)
        
        # Check if data is empty or too small
        if data.size == 0:
            print(f"Warning: Empty data in {f}. Skipping.")
            continue
            
        if base_samplerate is None:
            base_samplerate = sr
        elif base_samplerate != sr:
            print(f"Warning: Sample rate mismatch in {f}. Expected {base_samplerate}, got {sr}")
            
        # Convert to mono if stereo
        if len(data.shape) > 1:
            data = data.mean(axis=1)
            
        all_data.append(data)
        
    if not all_data:
        raise ValueError("All files were empty or could not be read.")
        
    return base_samplerate, np.concatenate(all_data)

def plot_histogram(data):
    """Plots a single amplitude histogram of the given data."""
    plt.figure(figsize=(10, 6))
    
    # Remove NaNs and Infs if any exist
    clean_data = data[np.isfinite(data)]
    
    # Check if the array size is too large for a standard histogram,
    # large arrays might cause internal matplotlib/numpy issues with bin index calculation
    # Subsample if necessary
    max_elements = 10000000 # Use 10M samples max for visualization
    if len(clean_data) > max_elements:
        print(f"Downsampling for histogram from {len(clean_data)} to {max_elements} samples to avoid memory/index issues.")
        # Subsample evenly
        step = len(clean_data) // max_elements
        clean_data = clean_data[::step]
    
    # compute the histogram values directly to avoid negative index issues
    counts, bins = np.histogram(clean_data, bins=100)
    
    plt.stairs(counts, bins, fill=True, alpha=0.75, color='blue')
    plt.title("Amplitude Histogram of Continuous Timeline Signal")
    plt.xlabel("Amplitude")
    plt.ylabel("Frequency (Count)")
    plt.grid(True)
    plt.tight_layout()
    plt.show()

def plot_welch(samplerate, data):
    """Plots the power spectral density using Welch's method."""
    # Remove NaNs and Infs if any exist
    clean_data = data[np.isfinite(data)]
    
    # ensure nperseg isn't greater than data size
    nperseg = min(1024, len(clean_data))
    
    if nperseg < 2:
         print("Not enough data points for Welch's method.")
         return
         
    f, pxx = signal.welch(clean_data, fs=samplerate, nperseg=nperseg)
    plt.figure(figsize=(10, 6))
    plt.semilogy(f, pxx)
    plt.title("Welch's Power Spectral Density")
    plt.xlabel("Frequency [Hz]")
    plt.ylabel("PSD [V**2/Hz]")
    plt.grid(True)
    plt.tight_layout()
    plt.show()

def plot_audio_signal(samplerate, data):
    # Calculate the time array for the x-axis
    length = data.shape[0] / samplerate
    time = np.linspace(0., length, data.shape[0])

    # Plot the signal
    plt.figure(figsize=(10, 6))
    plt.plot(time, data, label="Mono channel")
    plt.xlabel("Time [s]")
    plt.ylabel("Amplitude")
    plt.title("Audio Signal (Continuous Timeline)")
    plt.grid(True)
    plt.legend()
    plt.tight_layout()
    plt.show()

def compute_and_plot_nmf(samplerate, data, n_components=2):
    # ensure nperseg isn't greater than data size
    nperseg = min(1024, len(data))
    
    # Compute STFT
    f, t, zxx = signal.stft(data, fs=samplerate, nperseg=nperseg)
    magnitude_spectrogram = np.abs(zxx)

    # Apply NMF
    model = NMF(n_components=n_components, init='random', random_state=0, max_iter=500)
    w_matrix = model.fit_transform(magnitude_spectrogram)
    h_matrix = model.components_

    # Plotting
    plt.figure(figsize=(12, 8))

    # Plot Spectrogram
    plt.subplot(2, 2, 1)
    plt.pcolormesh(t, f, magnitude_spectrogram, shading='gouraud')
    plt.title('Magnitude Spectrogram')
    plt.ylabel('Frequency [Hz]')
    plt.xlabel('Time [sec]')

    # Plot w_matrix (Basis Functions)
    plt.subplot(2, 2, 2)
    plt.plot(f, w_matrix)
    plt.title('Basis Functions (W)')
    plt.xlabel('Frequency [Hz]')
    plt.ylabel('Amplitude')
    plt.legend([f'Component {i+1}' for i in range(n_components)])

    # Plot h_matrix (Activations)
    plt.subplot(2, 1, 2)
    for i in range(n_components):
        plt.plot(t, h_matrix[i], label=f'Component {i+1}')
    plt.title('Temporal Activations (H)')
    plt.xlabel('Time [sec]')
    plt.ylabel('Amplitude')
    plt.legend()

    plt.tight_layout()
    plt.show()

if __name__ == '__main__':
    DIR_PATH = "C:\\Users\\Roy\\Downloads\\recordings\\scooter"
    
    try:
        # Load and concatenate all .wav files to form a continuous timeline
        sample_rate, continuous_data = load_and_concatenate(DIR_PATH)

        print(f"Successfully loaded data. Shape: {continuous_data.shape}, Type: {continuous_data.dtype}")
        
        # Plot a single histogram of the concatenated signal
        plot_histogram(continuous_data)
        
        # Plot Welch's power spectral density as requested previously
        plot_welch(sample_rate, continuous_data)
        
    except FileNotFoundError as err:
        print(err)
    except Exception as err:
        print(f"An error occurred: {err}")
        traceback.print_exc()