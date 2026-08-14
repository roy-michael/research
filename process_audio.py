import os
import numpy as np
import matplotlib.pyplot as plt
from scipy.io import wavfile
from scipy.signal import welch

# Paths
WAV_PATH = r"D:\RoyStudies\Recordings\hear-my-ship\V1\Aux Vessels\Kapetan MRS_09.08.23_160955_20secCPA.wav"
OUTPUT_DIR = r"C:\Users\gorke\.gemini\antigravity-ide\brain\47110015-490b-4b68-8ced-2b0f920ed130"
OUTPUT_IMAGE = os.path.join(OUTPUT_DIR, "welch_diagram.png")

def main():
    if not os.path.exists(WAV_PATH):
        print(f"Error: WAV file not found at {WAV_PATH}")
        return

    # Read WAV file
    print(f"Reading: {WAV_PATH}")
    fs, data = wavfile.read(WAV_PATH)
    
    # Handle stereo if needed
    if len(data.shape) > 1:
        data = data[:, 0]
        print("Stereo detected, using first channel.")

    # Calculate segment parameters
    segment_length_samples = fs  # 1 second
    total_samples = len(data)
    num_segments = total_samples // segment_length_samples

    print(f"Sample Rate: {fs} Hz")
    print(f"Total Duration: {total_samples / fs:.2f} seconds")
    print(f"Split into {num_segments} segments of 1 second each.")

    # Extract and process each segment
    all_psds = []
    frequencies = None
    for segment_idx in range(num_segments):
        start_sample = segment_idx * segment_length_samples
        end_sample = start_sample + segment_length_samples
        segment_data = data[start_sample:end_sample]

        # Normalize segment data to range [-1.0, 1.0] if it's integer type
        if np.issubdtype(segment_data.dtype, np.integer):
            max_val = np.iinfo(segment_data.dtype).max
            segment_data = segment_data.astype(np.float32) / max_val

        # Compute Welch PSD
        nperseg = min(2048, len(segment_data))
        freqs, psd = welch(segment_data, fs=fs, nperseg=nperseg)
        frequencies = freqs
        all_psds.append(psd)

        # Convert PSD to dB
        psd_db = 10 * np.log10(psd + 1e-12)

        # Get min/max within the 0-4kHz range for proper plot limits
        mask = (frequencies >= 0) & (frequencies <= 4000)
        psd_db_zoom = psd_db[mask]

        # Create a clean, modern plot
        plt.figure(figsize=(10, 5), dpi=150)
        plt.plot(frequencies, psd_db, color="#1A5276", linewidth=1.5, label=f"Segment {segment_idx} PSD")
        
        # Styling
        plt.title(f"Welch PSD of 1-Second Segment (Segment {segment_idx})\nFile: {os.path.basename(WAV_PATH)}", fontsize=12, fontweight="bold", pad=15)
        plt.xlabel("Frequency (Hz)", fontsize=10, labelpad=8)
        plt.ylabel("Power Spectral Density (dB/Hz)", fontsize=10, labelpad=8)
        plt.grid(True, linestyle="--", alpha=0.6)
        plt.xlim(0, 4000)  # Focus on 0-4 kHz
        plt.ylim(np.min(psd_db_zoom) - 5, np.max(psd_db_zoom) + 5)
        plt.legend()
        plt.tight_layout()

        # Save output image
        segment_image_path = os.path.join(OUTPUT_DIR, f"welch_segment_{segment_idx}.png")
        os.makedirs(OUTPUT_DIR, exist_ok=True)
        plt.savefig(segment_image_path, bbox_inches="tight")
        plt.close()
        
        print(f"[{segment_idx + 1}/{num_segments}] Welch diagram saved to {segment_image_path}")

    # Compute and plot average of all segments
    if all_psds and frequencies is not None:
        avg_psd = np.mean(all_psds, axis=0)
        avg_psd_db = 10 * np.log10(avg_psd + 1e-12)

        # Get min/max within the 0-4kHz range for proper plot limits
        mask = (frequencies >= 0) & (frequencies <= 4000)
        avg_psd_db_zoom = avg_psd_db[mask]

        plt.figure(figsize=(10, 5), dpi=150)
        plt.plot(frequencies, avg_psd_db, color="#E74C3C", linewidth=2.0, label="Average PSD")
        
        plt.title(f"Average Welch PSD (Average of {num_segments} Segments)\nFile: {os.path.basename(WAV_PATH)}", fontsize=12, fontweight="bold", pad=15)
        plt.xlabel("Frequency (Hz)", fontsize=10, labelpad=8)
        plt.ylabel("Power Spectral Density (dB/Hz)", fontsize=10, labelpad=8)
        plt.grid(True, linestyle="--", alpha=0.6)
        plt.xlim(0, 4000)  # Focus on 0-4 kHz
        plt.ylim(np.min(avg_psd_db_zoom) - 5, np.max(avg_psd_db_zoom) + 5)
        plt.legend()
        plt.tight_layout()

        avg_image_path = os.path.join(OUTPUT_DIR, "welch_segment_average.png")
        plt.savefig(avg_image_path, bbox_inches="tight")
        plt.close()
        print(f"Average Welch diagram saved to {avg_image_path}")

        # Find dominant frequencies in the 0-4 kHz range
        from scipy.signal import find_peaks
        mask_peaks = (frequencies >= 0) & (frequencies <= 4000)
        freqs_zoom = frequencies[mask_peaks]
        psd_zoom = avg_psd_db[mask_peaks]

        # Use find_peaks with minimum distance and prominence
        peaks, _ = find_peaks(psd_zoom, distance=15, prominence=1.0)
        if len(peaks) == 0:
            # Fallback if no peaks match prominence criteria
            peaks, _ = find_peaks(psd_zoom, distance=5)

        # Sort peaks by amplitude descending
        sorted_peak_indices = peaks[np.argsort(psd_zoom[peaks])][::-1]
        
        dominant_freqs = []
        print("\n--- Top Dominant Frequencies (0-4 kHz) ---")
        for idx, p_idx in enumerate(sorted_peak_indices[:5]):
            f_val = freqs_zoom[p_idx]
            db_val = psd_zoom[p_idx]
            dominant_freqs.append((f_val, db_val))
            print(f"Rank {idx+1}: {f_val:.2f} Hz ({db_val:.2f} dB/Hz)")

        # Create Markdown Report
        report_path = r"d:\dev\research\research\reports\welch_analysis_report.md"
        report_dir = os.path.dirname(report_path)
        os.makedirs(report_dir, exist_ok=True)

        report_content = f"""# Welch PSD Analysis Report

**File Analyzed:** `{os.path.basename(WAV_PATH)}`  
**Full Path:** `{WAV_PATH}`  
**Sample Rate:** {fs} Hz  
**Total Duration:** {total_samples / fs:.2f} seconds  
**Number of Segments:** {num_segments} (1 second each)  

---

## Dominant Frequencies (0-4 kHz Range)
Below are the top dominant spectral peaks identified in the average Power Spectral Density (PSD) estimate:

| Rank | Frequency (Hz) | PSD (dB/Hz) |
| :--- | :--- | :--- |
"""
        for idx, (f_val, db_val) in enumerate(dominant_freqs):
            report_content += f"| {idx+1} | {f_val:.2f} Hz | {db_val:.2f} dB/Hz |\n"

        report_content += f"""
---

## Visualizations

### Average Spectral Density
![Average Welch PSD](file:///{avg_image_path.replace('\\', '/')})

### Segmented Spectral Densities
Here is the spectral breakdown for each 1-second segment showing time-varying frequency evolution:

"""
        # Add links/images for individual segments
        for s_idx in range(num_segments):
            seg_img = os.path.join(OUTPUT_DIR, f"welch_segment_{s_idx}.png").replace('\\', '/')
            report_content += f"* **Segment {s_idx}**: [View Diagram](file:///{seg_img})\n"

        with open(report_path, "w", encoding="utf-8") as f:
            f.write(report_content)
        print(f"\nSaved analysis report to {report_path}")


if __name__ == "__main__":
    main()
