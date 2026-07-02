import numpy as np
import matplotlib.pyplot as plt
from scipy.io import wavfile
from scipy.signal import butter, lfilter
import numba
import os
import glob
import pickle
import hashlib

def read_and_process_wav(filepath):
    if not os.path.exists(filepath):
        print(f"File not found: {filepath}")
        return None, None
    fs, data = wavfile.read(filepath)
    if len(data.shape) > 1:
        data = data.mean(axis=1) # Convert to mono
    return fs, data

def butter_bandpass(lowcut, highcut, fs, order=5):
    nyq = 0.5 * fs
    low = lowcut / nyq
    high = highcut / nyq
    b, a = butter(order, [low, high], btype='band')
    return b, a

def butter_bandpass_filter(data, lowcut, highcut, fs, order=5):
    b, a = butter_bandpass(lowcut, highcut, fs, order=order)
    y = lfilter(b, a, data)
    return y

@numba.jit(nopython=True)
def digital_pll(signal_in, fs, f_center, kp, ki):
    """
    A simple digital Phase-Locked Loop (PLL).
    
    :param signal_in: Input signal array
    :param fs: Sampling frequency
    :param f_center: Center frequency of the NCO
    :param kp: Proportional gain
    :param ki: Integral gain
    :return: phase_out (instantaneous phase), freq_out (instantaneous frequency in Hz)
    """
    N = len(signal_in)
    
    phase_out = np.zeros(N)
    freq_out = np.zeros(N)
    
    phase = 0.0
    freq_integrator = 0.0
    
    # Base angular velocity per sample
    w_center = 2 * np.pi * f_center / fs
    
    for i in range(N):
        # 1. Phase Detector
        nco_out_sin = np.sin(phase)
        
        # Multiply input by NCO to get phase error
        # A true Costas loop would use both sin and cos, but a simple multiplier works 
        # if the input has a strong carrier at the target frequency.
        phase_error = -signal_in[i] * nco_out_sin
        
        # 2. Loop Filter (PI Controller)
        freq_integrator += ki * phase_error
        
        # Clamp integrator to prevent windup (e.g. max +/- 100 Hz deviation)
        max_dev = 2 * np.pi * 100 / fs
        if freq_integrator > max_dev:
            freq_integrator = max_dev
        elif freq_integrator < -max_dev:
            freq_integrator = -max_dev
        
        freq_control = kp * phase_error + freq_integrator
        if freq_control > max_dev:
            freq_control = max_dev
        elif freq_control < -max_dev:
            freq_control = -max_dev
        
        # 3. NCO update
        phase += w_center + freq_control
        
        # Keep phase within [-pi, pi] for numerical stability
        phase = (phase + np.pi) % (2 * np.pi) - np.pi
        
        phase_out[i] = phase
        freq_out[i] = (w_center + freq_control) * fs / (2 * np.pi)
        
    return phase_out, freq_out

def extract_pll_phases(file_paths, name, target_freq, segment_length_seconds=2, bandpass_margin=100.0):
    os.makedirs("cache", exist_ok=True)
    key_string = f"pll_{name}_{target_freq}_{segment_length_seconds}_{bandpass_margin}"
    key_hash = hashlib.md5(key_string.encode('utf-8')).hexdigest()
    cache_file = os.path.join("cache", f"processed_{key_hash}.pkl")
    
    if os.path.exists(cache_file):
        with open(cache_file, "rb") as f:
            return pickle.load(f)

    all_files_phases = []
    for filepath in file_paths:
        fs, data = read_and_process_wav(filepath)
        if data is None:
            continue
            
        data = data / np.max(np.abs(data))
        if fs > 12000:
            factor = fs // 12000
            if factor > 1:
                from scipy.signal import decimate
                data = decimate(data, factor, ftype='fir', zero_phase=True)
                fs = fs // factor
        
        band_low = max(10.0, target_freq - bandpass_margin)
        nyq = 0.5 * fs
        band_high = min(nyq - 5.0, target_freq + bandpass_margin)
        
        filtered_data = butter_bandpass_filter(data, band_low, band_high, fs, order=4)
        if np.max(np.abs(filtered_data)) > 1e-6:
            filtered_data = filtered_data / np.max(np.abs(filtered_data))
        else:
            filtered_data = np.zeros_like(filtered_data)
        
        zeta = 0.707
        Bn = 20.0
        wn = 2 * np.pi * Bn / (zeta + 1.0 / (4 * zeta))
        kp = (2 * zeta * wn) / fs
        ki = (wn * wn) / (fs * fs)
        
        phase_out, _ = digital_pll(filtered_data, fs, target_freq, kp, ki)
        
        segment_samples = int(segment_length_seconds * fs)
        num_segments = len(data) // segment_samples
        
        phases = []
        for i in range(num_segments):
            start = i * segment_samples
            end = start + segment_samples
            segment_phase = phase_out[start:end]
            mean_vector = np.sum(np.exp(1j * segment_phase)) / len(segment_phase)
            phases.append(np.angle(mean_vector))
            
        all_files_phases.append(phases)
        
    with open(cache_file, "wb") as f:
        pickle.dump(all_files_phases, f)
        
    return all_files_phases

def main():
    # Use the file path found in main.py for testing
    file_dir = r"C:\Users\Roy\Downloads\recordings\scooter"
    file_name = "RBW6922_20250612_063000.wav"
    file_path = os.path.join(file_dir, file_name)
    
    if os.path.exists(file_path):
        print(f"Reading {file_path}")
        fs, data = wavfile.read(file_path)
        if len(data.shape) > 1:
            data = data.mean(axis=1) # Convert to mono
            
        # Use first 5 seconds for quick testing
        data = data[:fs*5] 
    else:
        print("File not found, generating synthetic signal.")
        fs = 44100
        t = np.arange(0, 5, 1/fs)
        # Target freq = 500 Hz, with some frequency modulation
        f_target = 500 + 10 * np.sin(2 * np.pi * 1 * t)
        phase_target = np.cumsum(2 * np.pi * f_target / fs)
        data = np.cos(phase_target) + 0.5 * np.random.randn(len(t))

    # Normalize data
    data = data / np.max(np.abs(data))
    
    # We need a target center frequency. If we don't know it, we can estimate it via FFT
    # For now, let's estimate the peak frequency using FFT
    fft_vals = np.fft.rfft(data)
    f_axis = np.fft.rfftfreq(len(data), d=1.0/fs)
    # Consider only frequencies between 100 Hz and 2000 Hz
    valid_idx = np.where((f_axis >= 100) & (f_axis <= 2000))[0]
    peak_idx = valid_idx[np.argmax(np.abs(fft_vals[valid_idx]))]
    target_freq = f_axis[peak_idx]
    
    print(f"Estimated target frequency via FFT: {target_freq:.2f} Hz")
    
    # Pre-filter around the target frequency
    band_low = max(50, target_freq - 100)
    band_high = target_freq + 100
    print(f"Bandpass filtering between {band_low:.2f} Hz and {band_high:.2f} Hz")
    filtered_data = butter_bandpass_filter(data, band_low, band_high, fs, order=4)
    
    # PLL parameters
    zeta = 0.707 # Damping factor
    Bn = 20.0    # Loop bandwidth (Hz)
    
    # Approximate PI gains for digital PLL
    K = 1.0 # Assuming input is normalized
    wn = 2 * np.pi * Bn / (zeta + 1.0 / (4 * zeta))
    
    kp = (2 * zeta * wn) / (K * fs)
    ki = (wn * wn) / (K * fs * fs)
    
    print(f"Running PLL with: kp={kp:.5f}, ki={ki:.5f}")
    
    phase_out, freq_out = digital_pll(filtered_data, fs, target_freq, kp, ki)
    
    # Plotting
    t_axis = np.arange(len(filtered_data)) / fs
    
    plt.figure(figsize=(12, 8))
    
    plt.subplot(3, 1, 1)
    plt.plot(t_axis, filtered_data)
    plt.title(f"Filtered Input Signal (Center: {target_freq:.2f} Hz)")
    plt.ylabel("Amplitude")
    
    plt.subplot(3, 1, 2)
    plt.plot(t_axis, freq_out, label='Tracked Freq')
    plt.axhline(target_freq, color='r', linestyle='--', label='Center Freq')
    plt.title("PLL Tracked Frequency")
    plt.ylabel("Frequency (Hz)")
    plt.legend()
    
    plt.subplot(3, 1, 3)
    plt.plot(t_axis, phase_out, label='Phase (Wrapped)')
    plt.title("PLL Tracked Phase")
    plt.xlabel("Time (s)")
    plt.ylabel("Phase (Radians)")
    
    plt.tight_layout()
    output_png = "pll_tracking_result.png"
    plt.savefig(output_png)
    print(f"Saved plot to {output_png}")
    # plt.show() # Disabled for headless run

if __name__ == '__main__':
    main()
