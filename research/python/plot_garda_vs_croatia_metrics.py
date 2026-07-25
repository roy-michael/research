import os
import glob
import numpy as np
import matplotlib.pyplot as plt
import librosa
from scipy.signal import welch

def compute_metrics_for_dir(directory, label, max_files=None, duration=30):
    fwhm_vals = []
    wiener_vals = []
    tnr_vals = []
    
    wav_files = glob.glob(os.path.join(directory, "*.wav"))
    if not wav_files:
        print(f"No .wav files found in {directory}")
        return fwhm_vals, wiener_vals, tnr_vals
        
    if max_files:
        wav_files = wav_files[:max_files]
        
    print(f"Processing {len(wav_files)} files for {label}...")
    for wav_file in wav_files:
        try:
            # Use librosa for standard sampling rate reading
            y, sr = librosa.load(wav_file, sr=None, duration=duration, mono=True)
            if len(y) == 0:
                continue
                
            # Compute Welch PSD (1 Hz resolution if enough samples)
            nperseg = min(sr, len(y)) if len(y) > 0 else 4096
            f, psd = welch(y, sr, nperseg=nperseg)
            
            # Focus on relevant frequencies (e.g., 50 Hz to 2500 Hz for boats)
            valid_idx = np.where((f >= 50) & (f <= 2500))[0]
            if len(valid_idx) == 0:
                continue
                
            f_valid = f[valid_idx]
            psd_valid = psd[valid_idx]
            
            # Find dominant peak
            peak_idx = np.argmax(psd_valid)
            peak_freq = f_valid[peak_idx]
            peak_power = psd_valid[peak_idx]
            
            # 1. FWHM (Full Width at Half Maximum)
            half_max = peak_power / 2.0
            left_idx = peak_idx
            while left_idx > 0 and psd_valid[left_idx] > half_max:
                left_idx -= 1
                
            right_idx = peak_idx
            while right_idx < len(psd_valid) - 1 and psd_valid[right_idx] > half_max:
                right_idx += 1
                
            fwhm = f_valid[right_idx] - f_valid[left_idx]
            if fwhm > 0:
                fwhm_vals.append(fwhm)
                
            # 2. Wiener Entropy (Spectral Flatness) over the valid band
            eps = 1e-10
            arithmetic_mean = np.mean(psd_valid)
            geometric_mean = np.exp(np.mean(np.log(psd_valid + eps)))
            if arithmetic_mean > 0:
                wiener = geometric_mean / (arithmetic_mean + eps)
                # ensure it stays <= 1.0 due to floating point precision
                wiener = min(1.0, wiener)
                wiener_vals.append(wiener)
                
            # 3. Narrowband TNR (Tonal Noise Ratio)
            bandwidth = max(100.0, 0.2 * peak_freq) 
            band_min = peak_freq - bandwidth/2
            band_max = peak_freq + bandwidth/2
            
            cb_idx = np.where((f_valid >= band_min) & (f_valid <= band_max))[0]
            
            # Tone bins (e.g. +/- 10 Hz from peak)
            df = f[1] - f[0]
            tone_width_bins = max(1, int(10.0 / df))
            tone_idx = np.arange(max(0, peak_idx - tone_width_bins), min(len(psd_valid), peak_idx + tone_width_bins + 1))
            
            noise_idx = np.setdiff1d(cb_idx, tone_idx)
            
            if len(tone_idx) > 0 and len(noise_idx) > 0:
                tone_power = np.sum(psd_valid[tone_idx])
                mean_noise_psd = np.mean(psd_valid[noise_idx])
                total_noise_in_band = mean_noise_psd * len(cb_idx)
                
                if total_noise_in_band > 0:
                    tnr_linear = tone_power / total_noise_in_band
                    tnr_db = 10 * np.log10(tnr_linear + eps)
                    tnr_vals.append(tnr_db)
            
        except Exception as e:
            print(f"Error processing {wav_file}: {e}")
            
    return fwhm_vals, wiener_vals, tnr_vals


def main():
    datasets = {
        'Garda Electric Deep': r"C:\Users\Roy\Recordings\Garda_2_26\2_Deep Water\Electric",
        'Garda Electric Shallow': r"C:\Users\Roy\Recordings\Garda_2_26\1_Shallow Water\Electric",
        'Croatia 2307': r"C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2307_free",
        'Croatia 2407_2': r"C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_2_snake",
        'Croatia 2407_1': r"C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_1_600m",
        'AUV Straight Line': r"C:\Users\Roy\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692"
    }

    colors = {
        'Garda Electric Deep': 'crimson',
        'Garda Electric Shallow': 'darkviolet',
        'Croatia 2307': 'mediumseagreen',
        'Croatia 2407_2': 'dodgerblue',
        'Croatia 2407_1': 'navy',
        'AUV Straight Line': 'darkorange'
    }

    all_metrics = {}
    for label, path in datasets.items():
        fwhm, wiener, tnr = compute_metrics_for_dir(path, label, max_files=100) # limit files to keep runtime reasonable
        all_metrics[label] = {
            'FWHM': fwhm,
            'Wiener': wiener,
            'TNR': tnr
        }

    fig, axes = plt.subplots(3, 1, figsize=(12, 15))

    metrics_list = [
        ('FWHM', axes[0], 'Full Width at Half Maximum (Hz)', 'FWHM (Hz)'),
        ('Wiener', axes[1], 'Wiener Entropy (Spectral Flatness)', 'Wiener Entropy'),
        ('TNR', axes[2], 'Narrowband Tonal Noise Ratio (TNR)', 'TNR (dB)')
    ]

    for metric_key, ax, title, xlabel in metrics_list:
        all_vals = []
        for label, metrics in all_metrics.items():
            vals = metrics[metric_key]
            if vals:
                all_vals.extend(vals)
                
        if all_vals:
            # Set robust x-axis limits to ignore extreme outliers (1st to 99th percentile)
            p1 = np.percentile(all_vals, 1)
            p99 = np.percentile(all_vals, 99)
            # If p1 == p99, fallback to min/max
            if p1 == p99:
                p1, p99 = np.min(all_vals), np.max(all_vals)
            if p1 == p99:
                p1, p99 = p1 - 1, p99 + 1
                
            margin = (p99 - p1) * 0.05
            bin_edges = np.linspace(p1 - margin, p99 + margin, 40)
            
            for label, metrics in all_metrics.items():
                vals = metrics[metric_key]
                if vals:
                    # Only plot values within the robust range for better visualization
                    filtered_vals = [v for v in vals if (p1 - margin) <= v <= (p99 + margin)]
                    if filtered_vals:
                        ax.hist(filtered_vals, bins=bin_edges, alpha=0.5, label=f"{label} (μ={np.mean(vals):.2f})", density=True, color=colors[label])

            ax.set_xlim(p1 - margin, p99 + margin)

        ax.set_title(title)
        ax.set_xlabel(xlabel)
        ax.set_ylabel('Density')
        ax.legend()
        ax.grid(True, alpha=0.3)

    plt.tight_layout()
    output_path = 'garda_vs_croatia_advanced_metrics.png'
    plt.savefig(output_path, dpi=150)
    print(f"Saved advanced metrics plot to {output_path}")

if __name__ == "__main__":
    main()
