import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'analysis')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'plotting')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'simulation')))

import numpy as np
import matplotlib.pyplot as plt
from matplotlib.widgets import Slider
from matplotlib.collections import LineCollection
from matplotlib.colors import to_rgba

def run_advanced_multipath_sim():
    # --- 1. Helper Functions ---
    def welch_psd(x, fs, nperseg=16384, noverlap=8192):
        window = np.hanning(nperseg)
        u = np.sum(window**2) / nperseg
        step = nperseg - noverlap
        segments = []
        for i in range(0, len(x) - nperseg + 1, step):
            seg = x[i:i+nperseg] * window
            segments.append(np.abs(np.fft.rfft(seg))**2 / (fs * nperseg * u))
        psd = np.mean(segments, axis=0)
        freqs = np.fft.rfftfreq(nperseg, d=1/fs)
        psd[1:-1] *= 2
        return freqs, psd

    def calculate_decidecade_levels(freqs, psd):
        n_vals = np.arange(17, 47)
        center_freqs = 10.0**(n_vals / 10.0)
        levels = []
        valid_centers = []
        df = freqs[1] - freqs[0]
        for fc in center_freqs:
            f_low = fc * (10.0**-0.05)
            f_high = fc * (10.0**0.05)
            idx = (freqs >= f_low) & (freqs <= f_high)
            if np.any(idx):
                band_power = np.sum(psd[idx]) * df
                spl = 10 * np.log10(band_power) if band_power > 0 else -150.0
                levels.append(spl)
                valid_centers.append(fc)
        return np.array(valid_centers), np.array(levels)

    def calculate_absorption_coefficient(f_hz, T_c, S_ppt, depth_m):
        f = f_hz / 1000.0
        z = depth_m / 1000.0
        f1 = 0.78 * np.sqrt(S_ppt / 35.0) * np.exp(T_c / 26.0)
        f2 = 42.0 * np.exp(T_c / 17.0)
        part1 = 0.106 * (f1 * f**2) / (f**2 + f1**2) * np.exp((T_c - 20.0) / 17.0)
        part2 = 0.52 * (1.0 + T_c / 43.0) * (S_ppt / 35.0) * (f2 * f**2) / (f**2 + f2**2) * np.exp(T_c / 26.0) * np.exp(-z / 6.0)
        part3 = 0.00049 * f**2 * np.exp(-T_c / 27.0) * np.exp(-z / 17.0)
        alpha_db_km = part1 + part2 + part3
        return alpha_db_km / 1000.0

    def generate_waveguide_paths(z_s, z_r, r, D, R_coeff, max_bounces):
        paths = [{'depth': z_s, 'coeff': 1.0, 'n_s': 0, 'n_b': 0, 'label': 'Direct'}]
        for k in range(1, max_bounces + 1):
            for start_bounce in ['S', 'B']:
                sequence = []
                current = start_bounce
                for _ in range(k):
                    sequence.append(current)
                    current = 'B' if current == 'S' else 'S'
                z_val = z_s
                n_s = 0
                n_b = 0
                for bounce in sequence:
                    if bounce == 'S':
                        z_val = -z_val
                        n_s += 1
                    else:
                        z_val = 2 * D - z_val
                        n_b += 1
                coeff = ((-1.0) ** n_s) * (R_coeff ** n_b)
                paths.append({'depth': z_val, 'coeff': coeff, 'n_s': n_s, 'n_b': n_b, 'label': f"{k}-Bounce"})
        return paths

    def fold_depth(z, D):
        temp = z % (2 * D)
        return np.where(temp > D, 2 * D - temp, temp)

    def plot_faded_path(ax, x, y, color, base_alpha, max_x, lw=1.0):
        points = np.array([x, y]).T.reshape(-1, 1, 2)
        segments = np.concatenate([points[:-1], points[1:]], axis=1)
        dist_factor = np.clip(1.0 - x[:-1] / max_x, 0, 1)
        alphas = base_alpha * (dist_factor ** 1.8)
        colors = [to_rgba(color, alpha=a) for a in alphas]
        lc = LineCollection(segments, colors=colors, linewidths=lw)
        ax.add_collection(lc)

    # --- 2. Fixed Simulation Parameters ---
    fs = 96000
    R_coeff = 0.8
    T = 15.0
    max_bounces = 4
    duration_rx = 0.5
    t_rx = np.arange(0, duration_rx, 1/fs)
    t_src = np.arange(-0.5, 1.0, 1/fs)
    
    white_fft = np.fft.rfft(np.random.default_rng(42).normal(0, 1, size=len(t_src)))
    freqs_src = np.fft.rfftfreq(len(t_src), d=1/fs)
    envelope = 1.0 / (1.0 + (freqs_src / 80.0)**0.8)
    colored_noise = np.fft.irfft(white_fft * envelope, n=len(t_src))
    colored_noise = colored_noise / np.std(colored_noise) * 15.0

    tonals = [(60.0, 45.0), (120.0, 30.0), (180.0, 20.0), (240.0, 15.0), (300.0, 12.0), (600.0, 10.0), (1200.0, 15.0), (2500.0, 8.0), (5000.0, 6.0), (12000.0, 4.0), (24000.0, 2.5)]
    source_signal = colored_noise
    for f_t, amp in tonals:
        source_signal += amp * np.sin(2 * np.pi * f_t * t_src)

    source_window_len = len(t_rx)
    source_segment = source_signal[t_src >= 0][:source_window_len]
    freqs_src_psd, psd_src_ref = welch_psd(source_segment, fs)

    # --- 3. Figure and Axes Setup ---
    fig, (ax_env, ax_psd, ax_dec) = plt.subplots(3, 1, figsize=(14, 11))
    plt.subplots_adjust(bottom=0.45, hspace=0.35)

    ax_env.set_title('Environment & Ray Paths')
    ax_env.set_xlabel('Range (m)')
    ax_env.set_ylabel('Depth (m)')
    ax_env.invert_yaxis()
    ax_env.grid(True, linestyle=':', alpha=0.5)

    line_src_psd, = ax_psd.plot([], [], '--', color='grey', linewidth=1.2, alpha=0.5, label='Source PSD (Free Space)')
    line_psd, = ax_psd.plot([], [], color='#1f77b4', linewidth=1.5, label='Received PSD')
    v_line_psd = ax_psd.axvline(np.nan, color='red', linestyle='--', linewidth=1.5, alpha=0.8, label="Lloyd's Mirror Cutoff")
    v_line_fun_psd = ax_psd.axvline(60.0, color='green', linestyle=':', linewidth=1.5, alpha=0.8, label="Source Fundamental (60 Hz)")
    ax_psd.set_title('Narrowband Welch PSD')
    ax_psd.set_xlabel('Frequency [Hz] (Log Scale)')
    ax_psd.set_ylabel('PSD [dB re 1 $\mu$Pa$^2$/Hz]')
    ax_psd.set_xscale('log')
    ax_psd.set_xlim(50, 40000)
    ax_psd.set_ylim(-10, 70)
    ax_psd.grid(True, which='both', linestyle=':', alpha=0.7)
    ax_psd.legend(loc='upper right', fontsize='small')

    line_dec, = ax_dec.plot([], [], 'o-', color='#ff7f0e', linewidth=1.5, markersize=5, label='TOB Mean')
    v_line_dec = ax_dec.axvline(np.nan, color='red', linestyle='--', linewidth=1.5, alpha=0.8, label="Lloyd's Mirror Cutoff")
    v_line_fun_dec = ax_dec.axvline(60.0, color='green', linestyle=':', linewidth=1.5, alpha=0.8, label="Source Fundamental (60 Hz)")
    ax_dec.set_title('Decidecade Band Levels')
    ax_dec.set_xlabel('Band Center Frequency [Hz] (Log Scale)')
    ax_dec.set_ylabel('SPL [dB re 1 $\mu$Pa]')
    ax_dec.set_xscale('log')
    ax_dec.set_xlim(50, 40000)
    ax_dec.set_ylim(-200, 100)
    ax_dec.grid(True, which='both', linestyle=':', alpha=0.7)
    ax_dec.legend(loc='upper right', fontsize='small')

    ticks = [50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 40000]
    tick_labels = ['50 Hz', '100 Hz', '200 Hz', '500 Hz', '1 kHz', '2 kHz', '5 kHz', '10 kHz', '20 kHz', '40 kHz']
    for ax in [ax_psd, ax_dec]:
        ax.set_xticks(ticks)
        ax.set_xticklabels(tick_labels)

    # --- 4. Sliders Setup ---
    ax_sal = plt.axes([0.15, 0.33, 0.65, 0.02]); ax_depth = plt.axes([0.15, 0.28, 0.65, 0.02]); ax_src = plt.axes([0.15, 0.23, 0.65, 0.02]); ax_rx = plt.axes([0.15, 0.18, 0.65, 0.02]); ax_range = plt.axes([0.15, 0.13, 0.65, 0.02]); ax_vel = plt.axes([0.15, 0.08, 0.65, 0.02]); ax_dopwt = plt.axes([0.15, 0.03, 0.65, 0.02])

    s_sal = Slider(ax_sal, 'Salinity (ppt)', 0.0, 40.0, valinit=35.0)
    s_depth = Slider(ax_depth, 'Water Depth (m)', 10.0, 100.0, valinit=50.0)
    s_src = Slider(ax_src, 'Source Depth (m)', 0.1, 99.0, valinit=10.0)
    s_rx = Slider(ax_rx, 'Receiver Depth (m)', 0.1, 99.0, valinit=30.0)
    s_range = Slider(ax_range, 'Range (m)', 50.0, 500.0, valinit=200.0)
    s_vel = Slider(ax_vel, 'Source Vel (m/s)', -30.0, 30.0, valinit=5.0)
    s_dopwt = Slider(ax_dopwt, 'Doppler Weight', 0.0, 10.0, valinit=1.0)

    # --- 5. Update Logic ---
    def update(val):
        S, D, r, v_s, w_dop = s_sal.val, s_depth.val, s_range.val, s_vel.val, s_dopwt.val
        z_s, z_r = min(s_src.val, D - 0.1), min(s_rx.val, D - 0.1)
        c = 1449.2 + 4.6*T - 0.055*(T**2) + (1.34 - 0.01*T)*(S - 35) + 0.016*(D/2.0)
        R_dir = np.sqrt(r**2 + (z_s - z_r)**2)
        R_sur = np.sqrt(r**2 + (z_s + z_r)**2)
        f_lm = c / (2.0 * max(1e-5, R_sur - R_dir))
        paths = generate_waveguide_paths(z_s, z_r, r, D, R_coeff, max_bounces)

        ax_env.clear()
        ax_env.set_title(f"Environment (c: {c:.1f} m/s | Lloyd's Cutoff: {f_lm:.1f} Hz)")
        ax_env.set_xlabel('Range (m)'); ax_env.set_ylabel('Depth (m)'); ax_env.invert_yaxis()
        ax_env.set_xlim(-10, r + 50); ax_env.set_ylim(D + 5, -5)
        ax_env.axhline(0, color='blue', lw=2, label='Surface'); ax_env.axhline(D, color='saddlebrown', lw=3, label='Seabed')
        ax_env.plot(0, z_s, 'ko', markersize=8, label='Source'); ax_env.plot(r, z_r, 'r^', markersize=8, label='Receiver')
        
        x_grid_bg = np.linspace(0, r + 30, 400)
        angles = np.linspace(-np.radians(82), np.radians(82), 32)
        for theta in angles:
            z_line_bg = z_s + x_grid_bg * np.tan(theta)
            z_folded_bg = fold_depth(z_line_bg, D)
            plot_faded_path(ax_env, x_grid_bg, z_folded_bg, color='lightblue', base_alpha=0.15, max_x=r+50, lw=0.7)

        y_total = np.zeros_like(t_rx)
        x_grid = np.linspace(0, r, 300)
        for p in paths:
            z_v = p['depth']
            coeff = p['coeff']
            total_bounces = p['n_s'] + p['n_b']
            R_path = np.sqrt(r**2 + (z_v - z_r)**2)
            tau = R_path / c
            z_line = z_v + (z_r - z_v) * (x_grid / r)
            z_folded = fold_depth(z_line, D)
            
            if total_bounces == 0:
                color = 'blue'; lw = 2.0; base_a = 0.8
            elif total_bounces == 1:
                color = 'red' if p['n_s'] > 0 else 'green'; lw = 1.5; base_a = 0.7
            elif total_bounces == 2:
                color = 'purple'; lw = 1.0; base_a = 0.5
            else:
                color = 'grey'; lw = 0.8; base_a = 0.3
            plot_faded_path(ax_env, x_grid, z_folded, color=color, base_alpha=base_a, max_x=r+50, lw=lw)

            alpha = calculate_absorption_coefficient(1000.0, T, S, D/2.0)
            atten = 10**(-alpha * R_path / 20.0)
            v_proj = v_s * (r / R_path)
            doppler_scale = (c - v_proj * w_dop) / c
            y_total += (coeff * atten / R_path) * np.interp((t_rx - tau) * doppler_scale, t_src, source_signal, left=0, right=0)
        
        y_total += np.random.default_rng(42).normal(0, 0.05, size=len(y_total))
        freqs, psd = welch_psd(y_total, fs)
        line_src_psd.set_data(freqs_src_psd, 10 * np.log10(psd_src_ref + 1e-15) - 20 * np.log10(R_dir))
        line_psd.set_data(freqs, 10 * np.log10(psd + 1e-15))
        centers, levels = calculate_decidecade_levels(freqs, psd)
        line_dec.set_data(centers, levels)

        v_line_psd.set_xdata([f_lm, f_lm])
        v_line_dec.set_xdata([f_lm, f_lm])

        ax_env.legend(loc='upper right', fontsize='small')
        fig.canvas.draw_idle()

    # --- 6. Bind Events and Initialize ---
    s_sal.on_changed(update)
    s_depth.on_changed(update)
    s_src.on_changed(update)
    s_rx.on_changed(update)
    s_range.on_changed(update)
    s_vel.on_changed(update)
    s_dopwt.on_changed(update)

    update(None)
    plt.show()

if __name__ == "__main__":
    run_advanced_multipath_sim()