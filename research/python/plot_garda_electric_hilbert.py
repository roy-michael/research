import os
import glob
import re
import numpy as np
import librosa
import matplotlib.pyplot as plt
from scipy.signal import hilbert, welch

dataset_dir = r"C:\Users\Roy\Recordings\garda_trial_data"
subdirs = sorted([d for d in os.listdir(dataset_dir) if os.path.isdir(os.path.join(dataset_dir, d))])

def get_time_hhmm(filename):
    basename = os.path.basename(filename)
    m1 = re.match(r'^(\d{4})\.wav$', basename)
    if m1: return int(m1.group(1))
    m2 = re.search(r'_(\d{2})-(\d{2})-\d{2}\.wav$', basename)
    if m2: return int(m2.group(1) + m2.group(2))
    return -1

def is_electric_boat(hhmm):
    return (928 <= hhmm <= 1004) or (1150 <= hhmm <= 1247)

# Find first available electric boat file
target_file = None
for subdir in subdirs:
    dir_path = os.path.join(dataset_dir, subdir)
    wav_files = glob.glob(os.path.join(dir_path, "*.wav"))
    electric_files = [f for f in wav_files if is_electric_boat(get_time_hhmm(f))]
    if electric_files:
        target_file = electric_files[0]
        break

if not target_file:
    print("No valid electric boat files found.")
    exit(0)

print(f"Processing: {target_file}")

# Load 0.1 seconds of audio for clear time-domain visualization
duration = 0.1
y, sr = librosa.load(target_file, sr=None, duration=duration, offset=5.0)

# Calculate the analytic signal using Hilbert transform
analytic_signal = hilbert(y)
# The upper envelope is the magnitude of the analytic signal
upper_envelope = np.abs(analytic_signal)
# The lower envelope is the negative magnitude
lower_envelope = -upper_envelope

time_axis = np.linspace(0, duration, len(y))

# Plot the time-domain signal and envelopes
plt.figure(figsize=(12, 6))
plt.plot(time_axis, y, label='Raw Signal', color='gray', alpha=0.7)
plt.plot(time_axis, upper_envelope, label='Upper Envelope (Hilbert Magnitude)', color='red', linewidth=2)
plt.plot(time_axis, lower_envelope, label='Lower Envelope (- Magnitude)', color='blue', linewidth=2)

plt.title(f"Hilbert Transform Envelope - {os.path.basename(target_file)}")
plt.xlabel("Time (seconds)")
plt.ylabel("Amplitude")
plt.grid(True)
plt.legend(loc='upper right')

output_dir = r"c:\Users\Roy\dev\research\research\output"
os.makedirs(output_dir, exist_ok=True)
output_path = os.path.join(output_dir, "electric_boat_hilbert_envelope.png")
plt.tight_layout()
plt.savefig(output_path, dpi=150)
print(f"Saved time-domain plot to {output_path}")

# Additionally, compute and plot the DEMON spectrum (PSD of the envelope)
# for a 30-second segment
y_full, sr_full = librosa.load(target_file, sr=None, duration=30.0)
env_full = np.abs(hilbert(y_full))

# Compute Welch PSD of the envelope
nperseg = min(int(sr_full), len(env_full))
f_demon, psd_demon = welch(env_full - np.mean(env_full), sr_full, nperseg=nperseg)

plt.figure(figsize=(12, 6))
plt.plot(f_demon, 10 * np.log10(np.maximum(psd_demon, 1e-15)), color='purple')
plt.title(f"DEMON Spectrum (PSD of Hilbert Envelope) - {os.path.basename(target_file)}")
plt.xlabel("Frequency (Hz)")
plt.ylabel("PSD (dB/Hz)")
plt.xlim(0, 1000) # Typical DEMON frequency range of interest
plt.grid(True)

output_path_demon = os.path.join(output_dir, "electric_boat_hilbert_demon.png")
plt.tight_layout()
plt.savefig(output_path_demon, dpi=150)
print(f"Saved DEMON plot to {output_path_demon}")
