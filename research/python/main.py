import numpy as np
import matplotlib.pyplot as plt
from scipy.io import wavfile
from scipy import signal
from sklearn.decomposition import NMF

def plot_audio_signal(samplerate, data):
    # Read the audio file
    # samplerate is the number of samples per second (Hz)
    # data is the numpy array containing the audio signal
    # samplerate, data = wavfile.read(file_path)

    # Calculate the time array for the x-axis
    length = data.shape[0] / samplerate
    time = np.linspace(0., length, data.shape[0])

    # Plot the signal
    plt.figure(figsize=(10, 6))
    
    # Check if stereo or mono
    if len(data.shape) > 1:
        plt.plot(time, data[:, 0], label="Left channel")
        plt.plot(time, data[:, 1], label="Right channel")
        plt.legend()
    else:
        plt.plot(time, data, label="Mono channel")
        
    plt.xlabel("Time [s]")
    plt.ylabel("Amplitude")
    plt.title("Audio Signal")
    plt.grid(True)
    plt.show()

def compute_and_plot_nmf(samplerate, data, n_components=2):
    # samplerate, data = wavfile.read(file_path)

    # Convert to mono if stereo
    if len(data.shape) > 1:
        data = data.mean(axis=1)

    # Compute STFT
    f, t, Zxx = signal.stft(data, fs=samplerate, nperseg=1024)
    magnitude_spectrogram = np.abs(Zxx)

    # Apply NMF
    model = NMF(n_components=n_components, init='random', random_state=0, max_iter=500)
    W = model.fit_transform(magnitude_spectrogram)
    H = model.components_

    # Plotting
    plt.figure(figsize=(12, 8))

    # Plot Spectrogram
    plt.subplot(2, 2, 1)
    plt.pcolormesh(t, f, magnitude_spectrogram, shading='gouraud')
    plt.title('Magnitude Spectrogram')
    plt.ylabel('Frequency [Hz]')
    plt.xlabel('Time [sec]')

    # Plot W (Basis Functions)
    plt.subplot(2, 2, 2)
    plt.plot(f, W)
    plt.title('Basis Functions (W)')
    plt.xlabel('Frequency [Hz]')
    plt.ylabel('Amplitude')
    plt.legend([f'Component {i+1}' for i in range(n_components)])

    # Plot H (Activations)
    plt.subplot(2, 1, 2)
    for i in range(n_components):
        plt.plot(t, H[i], label=f'Component {i+1}')
    plt.title('Temporal Activations (H)')
    plt.xlabel('Time [sec]')
    plt.ylabel('Amplitude')
    plt.legend()

    plt.tight_layout()
    plt.show()

if __name__ == '__main__':
    file_dir = "C:\\Users\\Roy\\Downloads\\recordings\\scooter"
    file_name = "RBW6922_20250612_063000.wav"
    file_path = f"{file_dir}\\{file_name}"
    try:
        samplerate, data = wavfile.read(file_path)

        # plot_audio_signal(samplerate, data)
        compute_and_plot_nmf(samplerate, data, n_components=8)
    except FileNotFoundError:
        print("File not found. Please replace 'your_audio_file.wav' with your audio file path.")
    except Exception as e:
        print(f"An error occurred: {e}")
