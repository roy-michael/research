"""
Croatia Acoustic Dataset Classifier & DEMON Analysis Generator
Analyzes all 6 merged recordings in D:\\RoyStudies\\Recordings\\Croatia\\wav\\merged:
  - merged_2207_colmar.wav   (41.0 mins, 300m route)
  - merged_2307_free.wav     (64.0 mins, freediving + ferry)
  - merged_2407_1_600m.wav   (60.0 mins, 600m route)
  - merged_2407_2_snake.wav  (22.0 mins, snake route)
  - merged_2507_1_1k.wav     (90.0 mins, 1000m route)
  - merged_2507_2_joint.wav  (50.0 mins, joint exercise)

For each file:
  1. Computes carrier narrowband spectrogram (350 - 1150 Hz).
  2. Computes DEMON envelope demodulation spectrum (0.5 - 55 Hz).
  3. Classifies every minute into 3 acoustic categories:
       - 'Underwater Scooter' (phase-locked stator harmonics + 18-28 Hz DEMON modulation)
       - 'Surface Vessel / Boat' (low-frequency diesel rumble, broad cavitation, high SNR)
       - 'Ambient Ocean Noise' (calm diffuse sea noise floor)
  4. Generates a publication-quality 3-panel figure and writes a summary report.
"""

import os
import glob
import numpy as np
import scipy.signal as signal
from scipy.io import wavfile
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

INPUT_DIR = r"D:\RoyStudies\Recordings\Croatia\wav\merged"
OUTPUT_DIR = r"d:\dev\research\drl\output\croatia_analysis"
os.makedirs(OUTPUT_DIR, exist_ok=True)

TARGET_FS = 6000
SCOOTER_HARMONICS = [426.0, 631.0, 838.0, 912.0, 1048.0]

def analyze_file(filepath: str):
    filename = os.path.basename(filepath)
    stem = os.path.splitext(filename)[0]
    print(f"\n=======================================================")
    print(f"Processing: {filename}")
    print(f"=======================================================")

    fs_raw, data_mmap = wavfile.read(filepath, mmap=True)
    total_samples = len(data_mmap)
    total_sec = total_samples / float(fs_raw)
    total_mins = int(np.floor(total_sec / 60.0))
    down = max(1, int(round(fs_raw / float(TARGET_FS))))
    effective_fs = fs_raw / float(down)

    time_mins = np.arange(0, total_mins, 1.0)
    carrier_freqs = np.linspace(350.0, 1150.0, 150)
    dem_freqs = np.linspace(0.5, 55.0, 110)

    carrier_gram = np.zeros((len(carrier_freqs), len(time_mins)), dtype=np.float32)
    demon_gram = np.zeros((len(dem_freqs), len(time_mins)), dtype=np.float32)

    # Classification outcomes per minute: 0=Ambient, 1=Scooter, 2=Surface Vessel
    class_labels = np.zeros(len(time_mins), dtype=np.int32)
    class_reasons = []

    # Bandpass filter for DEMON envelope extraction (1000 - 2600 Hz)
    nyq = effective_fs / 2.0
    b_bp, a_bp = signal.butter(4, [1000.0 / nyq, min(2600.0, nyq - 50.0) / nyq], btype="bandpass")

    # Low-frequency vessel detector filter (20 - 250 Hz)
    b_vessel, a_vessel = signal.butter(4, [25.0 / nyq, 250.0 / nyq], btype="bandpass")

    for idx, m in enumerate(time_mins):
        start_s = int(m * 60 * fs_raw)
        dur_s = int(12 * fs_raw) # 12 sec segment
        raw = data_mmap[start_s:start_s + dur_s].astype(np.float32)
        if raw.ndim > 1:
            raw = raw[:, 0]
        sig = signal.resample_poly(raw, up=1, down=down)

        # 1. Carrier Spectrum (350 - 1150 Hz)
        f_aud, p_aud = signal.welch(sig, fs=effective_fs, nperseg=int(effective_fs * 1.5), noverlap=int(effective_fs * 0.75))
        p_aud_db = 10.0 * np.log10(p_aud + 1e-12)
        carrier_gram[:, idx] = np.interp(carrier_freqs, f_aud, p_aud_db)

        # Scooter harmonic detection
        mask_scoot_band = (f_aud >= 380.0) & (f_aud <= 1120.0)
        p_sub = p_aud[mask_scoot_band]
        f_sub = f_aud[mask_scoot_band]
        top_f_aud = f_sub[np.argmax(p_sub)]
        noise_floor_aud = np.median(p_sub)
        aud_snr = 10.0 * np.log10(np.max(p_sub) / (noise_floor_aud + 1e-12))

        # Check if peak aligns with any known scooter harmonic within 18 Hz tolerance
        harmonic_match = any(abs(top_f_aud - h) <= 18.0 for h in SCOOTER_HARMONICS) and (aud_snr >= 8.5)

        # 2. DEMON Envelope Demodulation Spectrum (0.5 - 55 Hz)
        try:
            sig_bp = signal.filtfilt(b_bp, a_bp, sig)
            env = np.abs(signal.hilbert(sig_bp))
            env = env - np.mean(env)
            f_env, p_env = signal.welch(env, fs=effective_fs, nperseg=int(effective_fs * 3.0), noverlap=int(effective_fs * 1.5))
            p_env_db = 10.0 * np.log10(p_env + 1e-12)
            demon_gram[:, idx] = np.interp(dem_freqs, f_env, p_env_db)

            # DEMON blade-pass rate check (18 - 30 Hz)
            mask_blade = (f_env >= 16.0) & (f_env <= 30.0)
            top_f_dem = f_env[mask_blade][np.argmax(p_env[mask_blade])]
            demon_snr = 10.0 * np.log10(np.max(p_env[mask_blade]) / (np.median(p_env[(f_env >= 5.0) & (f_env <= 50.0)]) + 1e-12))
            demon_blade_match = (18.0 <= top_f_dem <= 28.0) and (demon_snr >= 5.5)
        except Exception:
            demon_blade_match = False
            demon_snr = 0.0
            top_f_dem = 0.0

        # 3. Surface Vessel Cavitation & Diesel Rumble Check (25 - 250 Hz)
        mask_vessel = (f_aud >= 25.0) & (f_aud <= 250.0)
        p_vessel = np.mean(p_aud[mask_vessel])
        p_total = np.mean(p_aud)
        low_freq_ratio = p_vessel / (p_total + 1e-12)
        vessel_snr = 10.0 * np.log10(np.max(p_aud[mask_vessel]) / (np.median(p_aud) + 1e-12))

        # Low frequency diesel cavitation check: strong low-band energy and high broadband level
        is_surface_vessel = (vessel_snr >= 17.0 and low_freq_ratio >= 0.40) or (vessel_snr >= 22.0)

        # Classification decision hierarchy:
        if is_surface_vessel and not harmonic_match:
            class_labels[idx] = 2  # Surface Vessel
            class_reasons.append(f"Vessel Cavitation (SNR: {vessel_snr:.1f} dB, Low-f Ratio: {low_freq_ratio:.2f})")
        elif harmonic_match or demon_blade_match:
            class_labels[idx] = 1  # Scooter
            reason = f"Carrier {top_f_aud:.0f} Hz ({aud_snr:.1f} dB)" if harmonic_match else f"DEMON {top_f_dem:.1f} Hz ({demon_snr:.1f} dB)"
            class_reasons.append(reason)
        else:
            class_labels[idx] = 0  # Ambient
            class_reasons.append("Ambient Ocean Noise")

    n_scooter = int(np.sum(class_labels == 1))
    n_vessel = int(np.sum(class_labels == 2))
    n_ambient = int(np.sum(class_labels == 0))
    print(f"Classification Summary for {filename} ({total_mins} mins):")
    print(f"  -> Underwater Scooter : {n_scooter:2d} mins ({n_scooter / total_mins * 100:.1f}%)")
    print(f"  -> Surface Vessel     : {n_vessel:2d} mins ({n_vessel / total_mins * 100:.1f}%)")
    print(f"  -> Ambient Noise      : {n_ambient:2d} mins ({n_ambient / total_mins * 100:.1f}%)")

    # Plot 3-panel figure
    fig, (ax1, ax2, ax3) = plt.subplots(3, 1, figsize=(15, 11), sharex=True, gridspec_kw={"height_ratios": [1.2, 1.2, 0.8]})
    fig.patch.set_facecolor("#0d1117")

    for ax in (ax1, ax2, ax3):
        ax.set_facecolor("#161b22")
        ax.tick_params(colors="#c9d1d9", labelsize=10)
        for spine in ax.spines.values():
            spine.set_color("#30363d")

    # Panel 1: Carrier Spectrogram
    im1 = ax1.pcolormesh(time_mins, carrier_freqs, carrier_gram, cmap="magma", shading="gouraud")
    ax1.set_ylabel("Carrier (Hz)", color="#f0f6fc", fontsize=11, fontweight="bold")
    ax1.set_title(f"CROATIA ACOUSTIC CLASSIFICATION & DEMON SPECTRUM: {filename} ({total_mins} mins)",
                  color="#58a6ff", fontsize=13, fontweight="bold", pad=12)

    for h in SCOOTER_HARMONICS:
        ax1.axhline(h, color="#58a6ff", linestyle=":", alpha=0.35, linewidth=1.0)
        ax1.text(0.5, h + 4, f"{int(h)} Hz", color="#58a6ff", fontsize=8, alpha=0.7)

    cbar1 = plt.colorbar(im1, ax=ax1, pad=0.015, aspect=18)
    cbar1.ax.tick_params(colors="#c9d1d9", labelsize=9)
    cbar1.set_label("Carrier PSD (dB)", color="#c9d1d9", fontsize=9)

    # Panel 2: DEMON Demodulation Spectrum
    im2 = ax2.pcolormesh(time_mins, dem_freqs, demon_gram, cmap="viridis", shading="gouraud")
    ax2.set_ylabel("DEMON (Hz)", color="#f0f6fc", fontsize=11, fontweight="bold")
    ax2.axhspan(18.0, 28.0, color="#3fb950", alpha=0.15, label="Scooter Blade-Pass Zone (18-28 Hz)")
    ax2.axhline(22.0, color="#3fb950", linestyle="--", linewidth=1.2, alpha=0.7, label="Nominal Blade Rate (~22 Hz)")

    cbar2 = plt.colorbar(im2, ax=ax2, pad=0.015, aspect=18)
    cbar2.ax.tick_params(colors="#c9d1d9", labelsize=9)
    cbar2.set_label("DEMON PSD (dB)", color="#c9d1d9", fontsize=9)
    ax2.legend(loc="upper right", facecolor="#161b22", edgecolor="#30363d", labelcolor="#c9d1d9", fontsize=9)

    # Panel 3: 3-Class Classified Timeline
    ax3.set_ylim(-0.3, 2.5)
    ax3.set_yticks([0, 1, 2])
    ax3.set_yticklabels(["Ambient", "Scooter", "Vessel / Boat"], color="#c9d1d9", fontsize=10, fontweight="bold")
    ax3.set_xlabel("Elapsed Time in Recording (Minutes)", color="#f0f6fc", fontsize=11, fontweight="bold")

    # Color segments based on detected class
    for idx, m in enumerate(time_mins):
        c = class_labels[idx]
        if c == 1:
            ax3.bar(m, 1.0, width=1.0, color="#238636", alpha=0.75, edgecolor="#3fb950")
            ax1.axvline(m, color="#3fb950", alpha=0.35, linewidth=1.0)
            ax2.axvline(m, color="#3fb950", alpha=0.35, linewidth=1.0)
        elif c == 2:
            ax3.bar(m, 2.0, width=1.0, color="#da3633", alpha=0.75, edgecolor="#f85149")
            ax1.axvline(m, color="#f85149", alpha=0.35, linewidth=1.0)
            ax2.axvline(m, color="#f85149", alpha=0.35, linewidth=1.0)
        else:
            ax3.bar(m, 0.2, width=1.0, color="#30363d", alpha=0.45, edgecolor="#484f58")

    # Add legend to ax3
    from matplotlib.patches import Patch
    legend_elements = [
        Patch(facecolor="#238636", edgecolor="#3fb950", label=f"Underwater Scooter ({n_scooter} mins)"),
        Patch(facecolor="#da3633", edgecolor="#f85149", label=f"Surface Vessel / Boat ({n_vessel} mins)"),
        Patch(facecolor="#30363d", edgecolor="#484f58", label=f"Ambient Ocean Noise ({n_ambient} mins)"),
    ]
    ax3.legend(handles=legend_elements, loc="upper right", facecolor="#161b22", edgecolor="#30363d", labelcolor="#c9d1d9", fontsize=9)

    plt.tight_layout()
    out_plot = os.path.join(OUTPUT_DIR, f"{stem}_demon_classification.png")
    plt.savefig(out_plot, dpi=180, facecolor=fig.get_facecolor())
    plt.close()
    print(f"Saved plot: {out_plot}")

    return {
        "filename": filename,
        "total_mins": total_mins,
        "n_scooter": n_scooter,
        "n_vessel": n_vessel,
        "n_ambient": n_ambient,
        "plot_path": out_plot,
    }


def main():
    wav_files = sorted(glob.glob(os.path.join(INPUT_DIR, "*.wav")))
    print(f"Found {len(wav_files)} merged Croatia recordings.")
    summaries = []
    for wf in wav_files:
        summary = analyze_file(wf)
        summaries.append(summary)

    print("\n" + "=" * 80)
    print("ALL CROATIA FILES ACOUSTIC CLASSIFICATION SUMMARY")
    print("=" * 80)
    print(f"{'Filename':<25} | {'Duration':<9} | {'Scooter':<10} | {'Surface Vessel':<16} | {'Ambient Noise'}")
    print("-" * 80)
    for s in summaries:
        print(f"{s['filename']:<25} | {s['total_mins']:2d} mins  | "
              f"{s['n_scooter']:2d}m ({s['n_scooter']/s['total_mins']*100:4.1f}%) | "
              f"{s['n_vessel']:2d}m ({s['n_vessel']/s['total_mins']*100:4.1f}%) | "
              f"{s['n_ambient']:2d}m ({s['n_ambient']/s['total_mins']*100:4.1f}%)")
    print("=" * 80)


if __name__ == "__main__":
    main()

