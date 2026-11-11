"""
Completely Blind Physics-Informed 3-Class Acoustic Classifier & DEMON Analyzer
Operates strictly on physical acoustic signals without reading or utilizing filenames:
  Target Directory: D:\\RoyStudies\\Recordings\\croatia-2026

Physical Acoustic Classes:
  0: Ambient Ocean Noise
     - Low acoustic power (RMS < 120), diffuse background noise floor.
     - Absence of stable mechanical motor carrier lines or ultrasonic pinger.
  1: Underwater Vehicle / Scooter
     - Phase-locked electric motor harmonics (350, 450, 630, 850, 1050 Hz).
     - Submerged acoustic navigation pinger (31.8 - 32.4 kHz > 20 dB SNR).
     - Propeller blade-pass envelope modulation (17 - 28 Hz).
     - Low-frequency diesel rumble is strictly absent (< 40 power).
  2: Surface Vessel
     - Massive low-frequency diesel rumble, propeller shaft rate, and cavitation (20 - 150 Hz > 50 power).
     - High acoustic broadband power (RMS > 350 to 15,000).

Outputs:
  - Generates 3-panel synchronized publication plot for each file in output/croatia_2026_blind_detection/
  - Prints per-minute classification breakdown.
"""

import os
import glob
import numpy as np
import scipy.signal as signal
from scipy.io import wavfile
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

INPUT_DIR = r"D:\RoyStudies\Recordings\croatia-2026"
OUTPUT_DIR = r"d:\dev\research\drl\output\croatia_2026_blind_detection"
os.makedirs(OUTPUT_DIR, exist_ok=True)

TARGET_FS = 6000
SCOOTER_HARMONICS = [350.0, 450.0, 631.0, 850.0, 1050.0]


def classify_recording_blindly(filepath: str):
    filename = os.path.basename(filepath)
    stem = os.path.splitext(filename)[0]
    print(f"\n=======================================================")
    print(f"Blind Classification of: {filename}")
    print(f"=======================================================")

    fs_raw, data_mmap = wavfile.read(filepath, mmap=True)
    total_samples = len(data_mmap)
    total_sec = total_samples / float(fs_raw)
    total_mins = int(np.floor(total_sec / 60.0))
    down = max(1, int(round(fs_raw / float(TARGET_FS))))
    effective_fs = fs_raw / float(down)

    time_mins = np.arange(0, total_mins, 1.0)
    carrier_freqs = np.linspace(250.0, 1250.0, 160)
    dem_freqs = np.linspace(0.5, 55.0, 110)

    carrier_gram = np.zeros((len(carrier_freqs), len(time_mins)), dtype=np.float32)
    demon_gram = np.zeros((len(dem_freqs), len(time_mins)), dtype=np.float32)

    class_labels = np.zeros(len(time_mins), dtype=np.int32)
    class_names = []
    reasons = []

    nyq = effective_fs / 2.0
    b_bp, a_bp = signal.butter(4, [1000.0 / nyq, min(2600.0, nyq - 50.0) / nyq], btype="bandpass")

    for idx, m in enumerate(time_mins):
        start_s = int(m * 60 * fs_raw)
        dur_s = int(12 * fs_raw) # 12 sec slice
        raw = data_mmap[start_s:start_s + dur_s]
        if raw.ndim > 1:
            raw = raw[:, 0]  # Hydrophone channel 0
        raw = raw.astype(np.float32)

        # 1. Ultrasonic Navigation Pinger (31.5 - 32.5 kHz)
        f_raw, p_raw = signal.welch(raw, fs=fs_raw, nperseg=int(fs_raw * 0.5))
        mask_pinger = (f_raw >= 31500) & (f_raw <= 32500)
        p_pinger_max = np.max(p_raw[mask_pinger])
        p_flr = np.median(p_raw[(f_raw >= 10000) & (f_raw <= 28000)])
        pinger_snr_db = float(10.0 * np.log10(p_pinger_max / (p_flr + 1e-12)))

        # 2. Low-Frequency Diesel Cavitation & Engine Rumble (20 - 150 Hz)
        low_f_pwr = float(np.mean(p_raw[(f_raw >= 20) & (f_raw <= 150)]))
        rms_val = float(np.std(raw))

        # 3. Downsample for Audio Carrier and DEMON analysis
        sig = signal.resample_poly(raw, up=1, down=down)

        # Carrier Spectrum (250 - 1250 Hz)
        f_aud, p_aud = signal.welch(sig, fs=effective_fs, nperseg=int(effective_fs * 1.5), noverlap=int(effective_fs * 0.75))
        p_aud_db = 10.0 * np.log10(p_aud + 1e-12)
        carrier_gram[:, idx] = np.interp(carrier_freqs, f_aud, p_aud_db)

        # Motor Stator Harmonic Detection
        stator_snrs = []
        for h in SCOOTER_HARMONICS:
            mask_h = abs(f_aud - h) <= 12.0
            mask_bg = (abs(f_aud - h) <= 45.0) & (~mask_h)
            if np.any(mask_h) and np.any(mask_bg):
                snr_h = 10.0 * np.log10(np.max(p_aud[mask_h]) / (np.median(p_aud[mask_bg]) + 1e-12))
                stator_snrs.append(snr_h)
            else:
                stator_snrs.append(0.0)
        max_stator_snr = float(max(stator_snrs))
        has_stator_harmonics = max_stator_snr >= 9.0

        # DEMON Envelope Demodulation (0.5 - 55 Hz)
        try:
            sig_bp = signal.filtfilt(b_bp, a_bp, sig)
            env = np.abs(signal.hilbert(sig_bp))
            env = env - np.mean(env)
            f_env, p_env = signal.welch(env, fs=effective_fs, nperseg=int(effective_fs * 3.0), noverlap=int(effective_fs * 1.5))
            p_env_db = 10.0 * np.log10(p_env + 1e-12)
            demon_gram[:, idx] = np.interp(dem_freqs, f_env, p_env_db)

            mask_blade = (f_env >= 16.0) & (f_env <= 30.0)
            demon_snr = 10.0 * np.log10(np.max(p_env[mask_blade]) / (np.median(p_env[(f_env >= 5.0) & (f_env <= 50.0)]) + 1e-12))
            has_blade_rate = demon_snr >= 5.5
        except Exception:
            has_blade_rate = False
            demon_snr = 0.0

        # Blind Classification Decision:
        # Priority 1: Surface Vessel (Massive low-frequency diesel power or high RMS cavitation)
        if low_f_pwr >= 45.0 or (rms_val >= 380.0 and low_f_pwr >= 30.0):
            pred_class = 2  # Surface Vessel
            reason = f"Surface Vessel (Low-f Diesel Pwr: {low_f_pwr:.1f}, RMS: {rms_val:.0f})"
        # Priority 2: Underwater Vehicle / Scooter (Pinger, Electric motor stator lines, or blade modulation)
        elif (pinger_snr_db >= 20.0) or (has_stator_harmonics and rms_val >= 150.0) or has_blade_rate:
            pred_class = 1  # Underwater Scooter
            reason = f"Underwater Scooter (Pinger: {pinger_snr_db:.1f} dB, Stator SNR: {max_stator_snr:.1f} dB)"
        # Priority 3: Ambient Ocean Noise Floor
        else:
            pred_class = 0  # Ambient Noise
            reason = f"Ambient Ocean Noise (Calm Floor, RMS: {rms_val:.1f})"

        class_labels[idx] = pred_class
        reasons.append(reason)

    n_ambient = int(np.sum(class_labels == 0))
    n_scooter = int(np.sum(class_labels == 1))
    n_vessel = int(np.sum(class_labels == 2))

    print(f"Blind Classification Breakdown for {filename} ({total_mins} mins):")
    print(f"  • Ambient Noise      : {n_ambient:2d} mins ({n_ambient / total_mins * 100:5.1f}%)")
    print(f"  • Underwater Scooter : {n_scooter:2d} mins ({n_scooter / total_mins * 100:5.1f}%)")
    print(f"  • Surface Vessel     : {n_vessel:2d} mins ({n_vessel / total_mins * 100:5.1f}%)")

    # Generate 3-panel figure
    fig, (ax1, ax2, ax3) = plt.subplots(3, 1, figsize=(15, 11), sharex=True, gridspec_kw={"height_ratios": [1.2, 1.2, 0.85]})
    fig.patch.set_facecolor("#0d1117")

    for ax in (ax1, ax2, ax3):
        ax.set_facecolor("#161b22")
        ax.tick_params(colors="#c9d1d9", labelsize=10)
        for spine in ax.spines.values():
            spine.set_color("#30363d")

    # Panel 1: Carrier Spectrogram
    im1 = ax1.pcolormesh(time_mins, carrier_freqs, carrier_gram, cmap="magma", shading="gouraud")
    ax1.set_ylabel("Carrier (Hz)", color="#f0f6fc", fontsize=11, fontweight="bold")
    ax1.set_title(f"BLIND ACOUSTIC CLASSIFICATION & DEMON SPECTRUM: {filename} ({total_mins} mins)",
                  color="#58a6ff", fontsize=13, fontweight="bold", pad=12)

    for h in SCOOTER_HARMONICS:
        ax1.axhline(h, color="#58a6ff", linestyle=":", alpha=0.35, linewidth=1.0)
        ax1.text(0.2, h + 5, f"{int(h)} Hz", color="#58a6ff", fontsize=8, alpha=0.7)

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

    # Panel 3: Classified 3-Class Timeline
    ax3.set_ylim(-0.3, 2.5)
    ax3.set_yticks([0, 1, 2])
    ax3.set_yticklabels(["Ambient Noise", "Underwater Scooter", "Surface Vessel"], color="#c9d1d9", fontsize=10, fontweight="bold")
    ax3.set_xlabel("Elapsed Time in Recording (Minutes)", color="#f0f6fc", fontsize=11, fontweight="bold")

    for idx, m in enumerate(time_mins):
        c = class_labels[idx]
        if c == 1:
            ax3.bar(m, 1.0, width=1.0, color="#238636", alpha=0.85, edgecolor="#3fb950")
            ax1.axvline(m, color="#3fb950", alpha=0.35, linewidth=1.0)
            ax2.axvline(m, color="#3fb950", alpha=0.35, linewidth=1.0)
        elif c == 2:
            ax3.bar(m, 2.0, width=1.0, color="#da3633", alpha=0.85, edgecolor="#f85149")
            ax1.axvline(m, color="#f85149", alpha=0.35, linewidth=1.0)
            ax2.axvline(m, color="#f85149", alpha=0.35, linewidth=1.0)
        else:
            ax3.bar(m, 0.25, width=1.0, color="#30363d", alpha=0.55, edgecolor="#484f58")

    from matplotlib.patches import Patch
    legend_elements = [
        Patch(facecolor="#238636", edgecolor="#3fb950", label=f"Underwater Scooter ({n_scooter} mins)"),
        Patch(facecolor="#da3633", edgecolor="#f85149", label=f"Surface Vessel ({n_vessel} mins)"),
        Patch(facecolor="#30363d", edgecolor="#484f58", label=f"Ambient Ocean Noise ({n_ambient} mins)"),
    ]
    ax3.legend(handles=legend_elements, loc="upper right", facecolor="#161b22", edgecolor="#30363d", labelcolor="#c9d1d9", fontsize=9)

    plt.tight_layout()
    out_plot = os.path.join(OUTPUT_DIR, f"{stem}_blind_detection.png")
    plt.savefig(out_plot, dpi=180, facecolor=fig.get_facecolor())
    plt.close()
    print(f"Saved plot: {out_plot}")

    return {
        "filename": filename,
        "total_mins": total_mins,
        "n_ambient": n_ambient,
        "n_scooter": n_scooter,
        "n_vessel": n_vessel,
        "plot_path": out_plot,
    }


def main():
    wav_files = sorted(glob.glob(os.path.join(INPUT_DIR, "*.wav")))
    print(f"Found {len(wav_files)} files in croatia-2026. Running blind physical acoustic detection...")
    summaries = []
    for wf in wav_files:
        summary = classify_recording_blindly(wf)
        summaries.append(summary)

    print("\n" + "=" * 90)
    print("BLIND PHYSICAL ACOUSTIC CLASSIFICATION RESULTS (CROATIA-2026)")
    print("=" * 90)
    print(f"{'Filename':<30} | {'Duration':<9} | {'Ambient Noise':<16} | {'Underwater Scooter':<20} | {'Surface Vessel'}")
    print("-" * 90)
    for s in summaries:
        print(f"{s['filename']:<30} | {s['total_mins']:2d} mins  | "
              f"{s['n_ambient']:2d}m ({s['n_ambient']/s['total_mins']*100:4.1f}%) | "
              f"{s['n_scooter']:2d}m ({s['n_scooter']/s['total_mins']*100:4.1f}%)       | "
              f"{s['n_vessel']:2d}m ({s['n_vessel']/s['total_mins']*100:4.1f}%)")
    print("=" * 90)


if __name__ == "__main__":
    main()

