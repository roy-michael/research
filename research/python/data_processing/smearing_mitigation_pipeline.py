import os
import argparse
import numpy as np
from scipy.io import wavfile
from scipy.signal import welch

def load_and_segment_audio(filepath, window_len_sec=1.0):
    """
    1 & 2. AUDIO FILE INPUT & BUFFER/SEGMENT
    Loads the wav file and segments it into J buffers of specified length in seconds.
    """
    print(f"Loading audio file: {filepath}")
    fs, data = wavfile.read(filepath)
    
    # If stereo, convert to mono by averaging channels
    if data.ndim > 1:
        data = data.mean(axis=1)
        
    # Calculate samples per window
    samples_per_window = int(fs * window_len_sec)
    
    # Number of full buffers (J)
    J = len(data) // samples_per_window
    if J == 0:
        raise ValueError("Audio file is too short for the specified window length.")
        
    # Segment data
    buffers = np.array_split(data[:J * samples_per_window], J)
    print(f"Segmented audio into {J} buffers of {window_len_sec}s ({samples_per_window} samples each).")
    return fs, buffers, J

def calculate_bandwidth(buffer_data, fs, fc, search_width_hz=500):
    """
    2c. CALCULATE BANDWIDTH PARAMETERS
    Calculates the 3dB bandwidth around a center frequency fc.
    """
    # Calculate Power Spectral Density using Welch's method
    f, Pxx = welch(buffer_data, fs, nperseg=len(buffer_data))
    
    # Isolate the frequency band around fc
    idx_min = np.argmin(np.abs(f - (fc - search_width_hz/2)))
    idx_max = np.argmin(np.abs(f - (fc + search_width_hz/2)))
    
    band_f = f[idx_min:idx_max]
    band_Pxx = Pxx[idx_min:idx_max]
    
    if len(band_Pxx) == 0:
        return 0.0
        
    # Find the peak power in this band
    peak_idx = np.argmax(band_Pxx)
    peak_power = band_Pxx[peak_idx]
    
    # Find 3dB drop-off (half power)
    half_power = peak_power / 2.0
    
    # Find left and right bounds
    left_idx = np.where(band_Pxx[:peak_idx] <= half_power)[0]
    right_idx = np.where(band_Pxx[peak_idx:] <= half_power)[0]
    
    f_left = band_f[left_idx[-1]] if len(left_idx) > 0 else band_f[0]
    f_right = band_f[peak_idx + right_idx[0]] if len(right_idx) > 0 else band_f[-1]
    
    bw = f_right - f_left
    return bw

def process_pipeline(filepath, center_frequencies, window_len_sec=1.0):
    """
    Executes the full pipeline based on the Doubly Spread Channel diagram.
    """
    # 1 & 2: Load and segment
    fs, buffers, J = load_and_segment_audio(filepath, window_len_sec)
    I = len(center_frequencies)
    
    # MATRIX W_{i,j}
    W = np.zeros((I, J))
    
    print("\n--- 2a-2c: Calculating Bandwidth Parameters ---")
    for i, fc in enumerate(center_frequencies):
        for j, buf in enumerate(buffers):
            W[i, j] = calculate_bandwidth(buf, fs, fc)
            
    print("Bandwidth Parameter Matrix W computed.")
    
    # 3a. CHECK STABILITY (P_i)
    # We define stability as the inverse of the coefficient of variation (mean/std)
    # A higher P_i means higher stability (less variation across buffers)
    P = np.zeros(I)
    
    # 3b. COMBINE BANDWIDTH (Rw_i)
    # We use the mean bandwidth across the J buffers
    Rw = np.zeros(I)
    
    print("\n--- 3a-3b: Checking Stability and Combining Bandwidths ---")
    for i, fc in enumerate(center_frequencies):
        mean_bw = np.mean(W[i, :])
        std_bw = np.std(W[i, :])
        
        Rw[i] = mean_bw
        
        # Avoid division by zero
        if std_bw == 0:
            P[i] = float('inf') if mean_bw > 0 else 0
        else:
            P[i] = mean_bw / std_bw  # SNR-like stability metric
            
        print(f"Freq: {fc} Hz | Combined BW: {Rw[i]:.2f} Hz | Stability Indicator: {P[i]:.2f}")
        
    # 4. DECISION MAKING
    # We select the channel that has the highest stability (highest P_i) 
    # while maintaining a reasonable bandwidth.
    print("\n--- 4-5: Decision Making and Result ---")
    
    # Filter out channels with zero bandwidth
    valid_indices = np.where(Rw > 0)[0]
    
    if len(valid_indices) == 0:
        print("RESULT: No valid channels found.")
        return None
        
    # Best channel is the one with highest stability
    best_idx = valid_indices[np.argmax(P[valid_indices])]
    best_fc = center_frequencies[best_idx]
    
    print(f"RESULT: Optimal Channel Selected -> {best_fc} Hz")
    print(f"  - Stability Score: {P[best_idx]:.2f}")
    print(f"  - Average Smeared Bandwidth: {Rw[best_idx]:.2f} Hz")
    
    return best_fc, P, Rw, W

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Doubly Spread Channel Smearing Mitigation Pipeline")
    parser.add_argument("wav_file", help="Path to the input .wav file")
    parser.add_argument("--frequencies", nargs="+", type=float, default=[1000, 2000, 4000, 8000], help="List of center frequencies to analyze")
    parser.add_argument("--window", type=float, default=1.0, help="Buffer window length in seconds")
    
    args = parser.parse_args()
    
    if not os.path.exists(args.wav_file):
        print(f"Error: File {args.wav_file} does not exist.")
    else:
        process_pipeline(args.wav_file, args.frequencies, args.window)
