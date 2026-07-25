import os
import glob
import re
import numpy as np
import librosa
import matplotlib.pyplot as plt
from scipy.signal import hilbert, butter, filtfilt, find_peaks

dataset_dir = r"C:\Users\Roy\Recordings\Garda_2_26\2_Deep Water\Electric"

def get_time_hhmm(filename):
    basename = os.path.basename(filename)
    m1 = re.match(r'^(\d{4})\.wav$', basename)
    if m1: return int(m1.group(1))
    m2 = re.search(r'_(\d{2})-(\d{2})-\d{2}\.wav$', basename)
    if m2: return int(m2.group(1) + m2.group(2))
    return -1

def is_electric_boat(hhmm):
    return True 

wav_files = glob.glob(os.path.join(dataset_dir, "*.wav"))
# Ensure files are sorted by time so they plot continuously correctly
electric_files = sorted([f for f in wav_files if is_electric_boat(get_time_hhmm(f))], key=get_time_hhmm)

if not electric_files:
    print("No valid files found.")
    exit(0)

fig, (ax_upper, ax_lower, ax_both) = plt.subplots(3, 1, figsize=(18, 14), sharex=True)

cumulative_time = 0.0
# block size for downsampling (e.g. 1000 samples)
downsample_factor = 1000 

print(f"Processing {len(electric_files)} files sequentially...")

for f in electric_files:
    print(f"Loading {os.path.basename(f)}...")
    try:
        # Load entire file
        y, sr = librosa.load(f, sr=None)
        if len(y) == 0:
            continue
            
        # Calculate Hilbert envelope
        v_tilde = np.abs(hilbert(y))
        
        # --- Target Size Estimation (Adapted for raw acoustic data) ---
        # Smooth the envelope using a low-pass filter to trace the energy burst
        b, a = butter(2, 1.0 / (sr / 2), btype='low')
        v_smooth = filtfilt(b, a, v_tilde)
        
        # Find all prominent peaks in the file
        mean_v = np.mean(v_smooth)
        std_v = np.std(v_smooth)
        peaks, _ = find_peaks(v_smooth, height=mean_v + 3.0*std_v, distance=10*sr, prominence=mean_v)
        
        # To avoid plotting millions of points, we downsample by taking the max/min over blocks
        # We need to make sure the array length is a multiple of downsample_factor
        pad_len = downsample_factor - (len(y) % downsample_factor)
        if pad_len != downsample_factor:
            y_padded = np.pad(y, (0, pad_len))
            v_tilde_padded = np.pad(v_tilde, (0, pad_len))
        else:
            y_padded = y
            v_tilde_padded = v_tilde
            
        # Reshape and take max/min for plotting
        y_max = np.max(y_padded.reshape(-1, downsample_factor), axis=1)
        y_min = np.min(y_padded.reshape(-1, downsample_factor), axis=1)
        v_tilde_ds = np.max(v_tilde_padded.reshape(-1, downsample_factor), axis=1)
        
        # Calculate time axis for this chunk
        chunk_duration = len(y) / sr
        time_axis = np.linspace(cumulative_time, cumulative_time + chunk_duration, len(y_max))
        
        # Plot upper
        ax_upper.fill_between(time_axis, y_min, y_max, color='gray', alpha=0.5, step='mid')
        ax_upper.plot(time_axis, v_tilde_ds, color='red', alpha=0.8, linewidth=1)
        
        # Plot lower
        ax_lower.fill_between(time_axis, y_min, y_max, color='gray', alpha=0.5, step='mid')
        ax_lower.plot(time_axis, -v_tilde_ds, color='blue', alpha=0.8, linewidth=1)
        
        # Plot both
        ax_both.fill_between(time_axis, y_min, y_max, color='gray', alpha=0.5, step='mid')
        ax_both.plot(time_axis, v_tilde_ds, color='red', alpha=0.8, linewidth=1)
        ax_both.plot(time_axis, -v_tilde_ds, color='blue', alpha=0.8, linewidth=1)
        
        for t_hat in peaks:
            # Find points where the smoothed envelope drops below the mean background noise level
            after_peak = np.where(v_smooth[t_hat:] < mean_v)[0]
            if len(after_peak) > 0:
                l1 = t_hat + after_peak[0]
            else:
                l1 = len(y) - 1
                
            before_peak = np.where(v_smooth[:t_hat] < mean_v)[0]
            if len(before_peak) > 0:
                l2 = before_peak[-1]
            else:
                l2 = 0
                
            t_peak_global = cumulative_time + t_hat / sr
            t_l1_global = cumulative_time + l1 / sr
            t_l2_global = cumulative_time + l2 / sr
            start_t = min(t_l1_global, t_l2_global)
            end_t = max(t_l1_global, t_l2_global)
            
            # Plot bounds and markers
            ax_upper.scatter(t_l1_global, y[l1], color='black', marker='x', zorder=10)
            ax_upper.scatter(t_l2_global, y[l2], color='black', marker='x', zorder=10)
            ax_upper.scatter(t_peak_global, y[t_hat], color='black', marker='o', zorder=10)
            ax_upper.axvspan(start_t, end_t, color='gold', alpha=0.3)
            ax_upper.axvline(start_t, color='black', linestyle='--', linewidth=1.5, alpha=0.8)
            ax_upper.axvline(end_t, color='black', linestyle='--', linewidth=1.5, alpha=0.8)
            
            ax_lower.scatter(t_l1_global, y[l1], color='black', marker='x', zorder=10)
            ax_lower.scatter(t_l2_global, y[l2], color='black', marker='x', zorder=10)
            ax_lower.scatter(t_peak_global, y[t_hat], color='black', marker='o', zorder=10)
            ax_lower.axvspan(start_t, end_t, color='gold', alpha=0.3)
            ax_lower.axvline(start_t, color='black', linestyle='--', linewidth=1.5, alpha=0.8)
            ax_lower.axvline(end_t, color='black', linestyle='--', linewidth=1.5, alpha=0.8)
            
            ax_both.scatter(t_l1_global, y[l1], color='black', marker='x', zorder=10)
            ax_both.scatter(t_l2_global, y[l2], color='black', marker='x', zorder=10)
            ax_both.scatter(t_peak_global, y[t_hat], color='black', marker='o', zorder=10)
            ax_both.axvspan(start_t, end_t, color='gold', alpha=0.3)
            ax_both.axvline(start_t, color='black', linestyle='--', linewidth=1.5, alpha=0.8)
            ax_both.axvline(end_t, color='black', linestyle='--', linewidth=1.5, alpha=0.8)
        
        # Add a vertical dashed line to mark the boundary between files
        ax_upper.axvline(x=cumulative_time + chunk_duration, color='black', linestyle='--', linewidth=0.5)
        ax_lower.axvline(x=cumulative_time + chunk_duration, color='black', linestyle='--', linewidth=0.5)
        ax_both.axvline(x=cumulative_time + chunk_duration, color='black', linestyle='--', linewidth=0.5)
        
        # Add text label for the file on top subplot
        ax_upper.text(cumulative_time, np.max(v_tilde_ds), f" {os.path.basename(f)}", rotation=90, fontsize=8, verticalalignment='top')
        
        cumulative_time += chunk_duration
        
    except Exception as e:
        print(f"Error processing {f}: {e}")

ax_upper.set_title(f"Continuous Upper Hilbert Envelope (Downsampled)")
ax_upper.set_ylabel("Amplitude")
ax_upper.grid(True)

ax_lower.set_title(f"Continuous Lower Hilbert Envelope (Downsampled)")
ax_lower.set_ylabel("Amplitude")
ax_lower.grid(True)

ax_both.set_title(f"Combined Upper and Lower Hilbert Envelopes")
ax_both.set_ylabel("Amplitude")
ax_both.grid(True)

from matplotlib.lines import Line2D
ax_upper.legend([Line2D([0], [0], color='red', lw=2), Line2D([0], [0], color='gray', lw=5, alpha=0.5)], ['Upper Envelope', 'Raw Signal'], loc='upper right')
ax_lower.legend([Line2D([0], [0], color='blue', lw=2), Line2D([0], [0], color='gray', lw=5, alpha=0.5)], ['Lower Envelope', 'Raw Signal'], loc='upper right')
ax_both.legend([Line2D([0], [0], color='red', lw=2), Line2D([0], [0], color='blue', lw=2), Line2D([0], [0], color='gray', lw=5, alpha=0.5)], ['Upper Envelope', 'Lower Envelope', 'Raw Signal'], loc='upper right')

ax_both.set_xlabel("Continuous Time (seconds)")
plt.tight_layout()

output_dir = r"c:\Users\Roy\dev\research\research\output"
os.makedirs(output_dir, exist_ok=True)
output_path = os.path.join(output_dir, "electric_boat_welch_signals.png")
plt.savefig(output_path, dpi=200)
print(f"Saved continuous plot to {output_path}")
