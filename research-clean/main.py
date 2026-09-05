# from scipy.io import wavfile
# from wave import wavfile
import matplotlib.pyplot as plt
import numpy as np
from scipy.signal import welch
import soundfile as sf

def main():
    # filepath = "C:/Users/Roy/Recordings/hear_my_ship/V1/Yachts/Yacht_02.08.23_120420/Yacht_02.08.23_120420_20secCPA.wav"
    filepath = "C:\\Users\\Roy\\Recordings\\Croatia\\Ocean Sonics\\2407_1_600m\\merged_output.wav"
    # filepath = "C:\\Users\\Roy\\Recordings\\hear_my_ship\\V1\\Motor Boats\\Motorboat_08.08.23_142223_20secCPA.wav"

    files = [
        "C:\\Users\\Roy\\Recordings\\Croatia\\Ocean Sonics\\2407_2_snake\\merged_output.wav",
        # "C:\\Users\\Roy\\Recordings\\Croatia\\Ocean Sonics\\2407_1_600m\\merged_output.wav",
        # "C:\\Users\\Roy\\Recordings\\hear_my_ship\\V1\\Motor Boats\\Motorboat_08.08.23_142223_20secCPA.wav"
    ]

    for filepath in files:
        read_and_process(filepath)

    plt.show()

        
def read_and_process(filepath):

    data, sr = sf.read(filepath)
    
    if len(data.shape) > 1:
        data = data.mean(axis=1)

    # nperseg = min(4096, len(data))
    nperseg = 1024 * 8
    freqs, psd = welch(data, fs=sr, nperseg=nperseg)
    # psd_db = 10 * np.log10(psd + 1e-12)


    # 3. Plot the data
    plt.figure(figsize=(10, 6))

    # We use semilogy because audio power can vary across huge magnitudes
    plt.semilogy(freqs, psd, color='blue', linewidth=1.5)

    plt.title("Power Spectral Density (Welch's Method)")
    plt.xlabel("Frequency (Hz)")
    plt.ylabel("Power/Frequency (Density)")
    plt.grid(True, which="both", linestyle='--', alpha=0.6)
    plt.xlim([0, sr / 2])  # Limit X-axis to the Nyquist frequency
    plt.tight_layout()
    # plt.show()

if __name__ == "__main__":
    main()