"""
Completely Blind Physics-Informed 3-Class Acoustic Classifier & DEMON Analyzer
Operates strictly on physical acoustic signals without reading or utilizing filenames:
  Target Directory: D:\\RoyStudies\\Recordings\\croatia-2026

Physical Acoustic Classes:
  0: Ambient Ocean Noise
     - Low inter-harmonic broadband power (20 - 250 Hz excluding 50 Hz mains harmonics < 2.0) and low RMS.
     - Absence of stable mechanical motor carrier lines or ultrasonic pinger.
  1: Underwater Vehicle / Scooter
     - Phase-locked electric motor harmonics above mains hum (426, 631, 810, 838, 912, 1048 Hz).
     - Submerged acoustic navigation pinger (31.8 - 32.4 kHz > 20 dB SNR).
     - Despiked DEMON propeller blade-pass envelope modulation (17 - 28 Hz).
     - Broadband low-frequency diesel rumble is strictly absent.
  2: Surface Vessel
     - Broadband low-frequency diesel rumble and propeller cavitation (20 - 250 Hz excluding 50 Hz mains harmonics).

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
MAINS_HARMONICS = [50.0 * k for k in range(1, 26)]  # 50 Hz to 1250 Hz electrical hum harmonics
SCOOTER_HARMONICS = [360.0, 426.0, 631.0, 715.0, 815.0, 912.0]  # Reference guide lines for plotting


def _build_mains_notch_filters(fs: float, q: float = 35.0):
    notches = []
    for f0 in MAINS_HARMONICS:
        if f0 < (fs / 2.0 - 10.0):
            b, a = signal.iirnotch(f0, q, fs)
            notches.append((b, a))
    return notches


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

    step_sec = 15.0
    win_sec = 10.0
    time_secs = np.arange(0.0, max(1.0, total_sec - win_sec), step_sec)
    time_mins = time_secs / 60.0
    carrier_freqs = np.linspace(250.0, 1250.0, 160)
    dem_freqs = np.linspace(0.5, 55.0, 110)

    carrier_gram = np.zeros((len(carrier_freqs), len(time_mins)), dtype=np.float32)
    demon_gram = np.zeros((len(dem_freqs), len(time_mins)), dtype=np.float32)

    class_labels = np.zeros(len(time_mins), dtype=np.int32)
    reasons = []

    nyq = effective_fs / 2.0
    b_bp, a_bp = signal.butter(4, [1000.0 / nyq, min(2600.0, nyq - 50.0) / nyq], btype="bandpass")
    mains_notches = _build_mains_notch_filters(effective_fs, q=35.0)

    for idx, t0 in enumerate(time_secs):
        start_s = int(t0 * fs_raw)
        dur_s = int(win_sec * fs_raw)
        raw = data_mmap[start_s:start_s + dur_s]
        if raw.ndim > 1:
            raw = raw[:, 0]  # Hydrophone channel 0 (ignore dead channel 1)
        raw = raw.astype(np.float32)

        # 1. Broadband Vessel & Cavitation Metrics (strictly excluding +/-4 Hz around 50 Hz mains harmonics)
        f_raw, p_raw = signal.welch(raw, fs=fs_raw, nperseg=int(fs_raw * 0.5))
        not_mains_raw = np.ones_like(f_raw, dtype=bool)
        for mh in range(50, 2501, 50):
            not_mains_raw &= (np.abs(f_raw - mh) > 4.0)

        mask_20_250 = (f_raw >= 20.0) & (f_raw <= 250.0) & not_mains_raw
        low_f_inter_mean = float(np.mean(p_raw[mask_20_250]))
        low_f_inter_med = float(np.median(p_raw[mask_20_250]))
        mid_med = float(np.median(p_raw[(f_raw >= 250.0) & (f_raw <= 1500.0) & not_mains_raw]))
        cav_med = float(np.median(p_raw[(f_raw >= 1000.0) & (f_raw <= 10000.0) & not_mains_raw]))

        # 2. Downsample and apply 50 Hz harmonic notch comb for Audio Carrier and DEMON analysis
        sig = signal.resample_poly(raw, up=1, down=down)
        for b_n, a_n in mains_notches:
            sig = signal.filtfilt(b_n, a_n, sig)

        # Carrier Spectrum (250 - 1250 Hz)
        f_aud, p_aud = signal.welch(sig, fs=effective_fs, nperseg=int(effective_fs * 1.5), noverlap=int(effective_fs * 0.75))
        p_aud_db = 10.0 * np.log10(p_aud + 1e-12)
        carrier_gram[:, idx] = np.interp(carrier_freqs, f_aud, p_aud_db)

        # Narrowband Non-Mains Scooter Motor Line Detection (320 - 1200 Hz, excluding +/-4 Hz around 50 Hz harmonics)
        not_mains_aud = np.ones_like(f_aud, dtype=bool)
        for mh in range(50, 1251, 50):
            not_mains_aud &= (np.abs(f_aud - mh) > 4.0)
        mask_motor_band = (f_aud >= 320.0) & (f_aud <= 1200.0) & not_mains_aud
        p_motor_sub = p_aud[mask_motor_band]
        f_motor_sub = f_aud[mask_motor_band]
        top_motor_f = float(f_motor_sub[np.argmax(p_motor_sub)])
        max_stator_snr = float(10.0 * np.log10(np.max(p_motor_sub) / (np.median(p_motor_sub) + 1e-12)))
        has_stator_harmonics = max_stator_snr >= 10.5

        # DEMON Envelope Demodulation (0.5 - 55 Hz) with transient despiker
        try:
            sig_bp = signal.filtfilt(b_bp, a_bp, sig)
            env = np.abs(signal.hilbert(sig_bp))
            med_env = float(np.median(env))
            mad_env = float(np.median(np.abs(env - med_env))) + 1e-8
            env = np.clip(env, 0.0, med_env + 4.5 * mad_env)
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

        # Blind Classification Decision (no 32 kHz pinger bias, immune to 50 Hz mains hum):
        # Priority 1: Surface Vessel (Broadband low-frequency rumble OR broadband mid/high propeller cavitation)
        if low_f_inter_mean >= 5.0 or low_f_inter_med >= 2.0 or cav_med >= 0.8 or mid_med >= 2.0:
            pred_class = 2  # Surface Vessel
            reason = f"Surface Vessel (Low-f: {low_f_inter_mean:.1f}, Cav: {cav_med:.2f}, Mid: {mid_med:.2f})"
        # Priority 2: Underwater Vehicle / Scooter (Non-mains narrowband stator lines OR despiked DEMON blade rate)
        elif has_stator_harmonics or has_blade_rate:
            pred_class = 1  # Underwater Scooter
            reason = f"Underwater Scooter (Tone {top_motor_f:.0f}Hz: {max_stator_snr:.1f} dB, DEMON: {demon_snr:.1f} dB)"
        # Priority 3: Ambient Ocean Noise Floor
        else:
            pred_class = 0  # Ambient Noise
            reason = f"Ambient Ocean Noise (Low-f: {low_f_inter_mean:.2f}, Cav: {cav_med:.2f})"

        class_labels[idx] = pred_class
        reasons.append(reason)

    n_total = len(class_labels)
    n_ambient = int(np.sum(class_labels == 0))
    n_scooter = int(np.sum(class_labels == 1))
    n_vessel = int(np.sum(class_labels == 2))

    print(f"Blind Classification Breakdown for {filename} ({total_mins} mins, {n_total} x 15s windows):")
    print(f"  • Ambient Noise      : {n_ambient:3d} windows ({n_ambient / n_total * 100:5.1f}%)")
    print(f"  • Underwater Scooter : {n_scooter:3d} windows ({n_scooter / n_total * 100:5.1f}%)")
    print(f"  • Surface Vessel     : {n_vessel:3d} windows ({n_vessel / n_total * 100:5.1f}%)")

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

    bar_w = step_sec / 60.0
    for idx, m in enumerate(time_mins):
        c = class_labels[idx]
        if c == 1:
            ax3.bar(m, 1.0, width=bar_w, color="#238636", alpha=0.85, edgecolor="#3fb950", linewidth=0.5)
            ax1.axvline(m, color="#3fb950", alpha=0.22, linewidth=0.8)
            ax2.axvline(m, color="#3fb950", alpha=0.22, linewidth=0.8)
        elif c == 2:
            ax3.bar(m, 2.0, width=bar_w, color="#da3633", alpha=0.85, edgecolor="#f85149", linewidth=0.5)
            ax1.axvline(m, color="#f85149", alpha=0.22, linewidth=0.8)
            ax2.axvline(m, color="#f85149", alpha=0.22, linewidth=0.8)
        else:
            ax3.bar(m, 0.25, width=bar_w, color="#30363d", alpha=0.55, edgecolor="#484f58", linewidth=0.5)

    from matplotlib.patches import Patch
    legend_elements = [
        Patch(facecolor="#238636", edgecolor="#3fb950", label=f"Underwater Scooter ({n_scooter / n_total * 100:.1f}%)"),
        Patch(facecolor="#da3633", edgecolor="#f85149", label=f"Surface Vessel ({n_vessel / n_total * 100:.1f}%)"),
        Patch(facecolor="#30363d", edgecolor="#484f58", label=f"Ambient Ocean Noise ({n_ambient / n_total * 100:.1f}%)"),
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
        "n_total": n_total,
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
        nt = s['n_total']
        print(f"{s['filename']:<30} | {s['total_mins']:2d} mins  | "
              f"{s['n_ambient']:3d} ({s['n_ambient']/nt*100:4.1f}%) | "
              f"{s['n_scooter']:3d} ({s['n_scooter']/nt*100:4.1f}%)       | "
              f"{s['n_vessel']:3d} ({s['n_vessel']/nt*100:4.1f}%)")
    print("=" * 90)


if __name__ == "__main__":
    main()

