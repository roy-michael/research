import numpy as np
import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec
from matplotlib.widgets import Slider, Button
from scipy.signal import spectrogram

from bandwidth_tracker import analyze_signal_bandwidth

# ==============================================================================
# Modern Dark Sonar / Acoustic Dashboard Theme
# ==============================================================================
THEME = {
    "bg_fig": "#0b0f17",
    "bg_panel": "#131b2e",
    "bg_control": "#162038",
    "border": "#263554",
    "text_primary": "#e2e8f0",
    "text_muted": "#94a3b8",
    "accent_cyan": "#38bdf8",
    "accent_teal": "#2dd4bf",
    "accent_coral": "#fb7185",
    "accent_amber": "#f59e0b",
    "accent_mint": "#38e08c",
    "slider_track": "#1e293b",
}

plt.rcParams.update({
    "figure.facecolor": THEME["bg_fig"],
    "axes.facecolor": THEME["bg_panel"],
    "axes.edgecolor": THEME["border"],
    "axes.labelcolor": THEME["text_primary"],
    "xtick.color": THEME["text_muted"],
    "ytick.color": THEME["text_muted"],
    "text.color": THEME["text_primary"],
    "font.family": "sans-serif",
    "font.size": 9.0,
    "grid.color": "#1e293b",
    "grid.linestyle": "--",
    "grid.alpha": 0.6,
})


# ==============================================================================
# Core Interactive Acoustic Simulation + Watershed Bandwidth Analysis
# ==============================================================================
def run_interactive_simulation(tx_depth, rx_depth, f0, wind_speed, rx_range):
    """
    Synthesizes the received hydrophone signal, computes geometric eigenray
    diagnostics, and runs the `research-clean` Watershed Bandwidth & Stability
    pipeline (`SpectralEngine` + `BandwidthTracker`).
    """
    fs = 2000.0      # Sampling frequency (Hz)
    duration = 20.0  # Signal duration (seconds)
    c = 1500.0       # Speed of sound in water (m/s)

    t = np.arange(0, duration, 1.0 / fs)
    k = 2 * np.pi * f0 / c

    # 1. Generate sea surface waves (Pierson-Moskowitz spectrum) from wind speed
    np.random.seed(42)  # Fixed seed for visual consistency while dragging sliders
    f_wave = np.linspace(0.1, 1.0, 30)
    S_wave = (
        0.0081 * (9.81**2) / ((2 * np.pi)**4 * f_wave**5)
        * np.exp(-1.25 * ((0.13 * 9.81 / wind_speed)**4 / f_wave**4))
    )
    wave_amps = np.sqrt(2 * S_wave * (f_wave[1] - f_wave[0]))
    wave_phases = np.random.uniform(0, 2 * np.pi, len(f_wave))

    h_t = sum(A * np.cos(2 * np.pi * f * t + ph) for A, f, ph in zip(wave_amps, f_wave, wave_phases))
    v_wave = sum(-A * (2 * np.pi * f) * np.sin(2 * np.pi * f * t + ph) for A, f, ph in zip(wave_amps, f_wave, wave_phases))
    wave_rms = float(np.std(h_t))

    # 2. Source kinematics by depth (Surface vessel vs. Submerged vehicle)
    is_surface = tx_depth < 2.0
    if is_surface:
        # Surface boat: horizontal/vertical surge & heave with wave orbital velocity + FM smearing
        inst_freq_dev = 3.0 * v_wave + 1.5 * np.random.randn(len(t))
        smooth_win = int(fs * 0.1)
        inst_freq_dev = np.convolve(inst_freq_dev, np.ones(smooth_win) / smooth_win, mode="same")
        source_phase_fm = 2 * np.pi * np.cumsum(inst_freq_dev) / fs
        fading_env = np.clip(1.0 + 0.6 * h_t + 0.3 * np.random.randn(len(t)), 0.1, 2.0)
    else:
        # Underwater scooter / AUV: stable propulsion below the wave base
        source_phase_fm = np.zeros_like(t)
        fading_env = np.ones_like(t)

    # 3. Geometric eigenrays (Direct path and Sea-Surface Reflected path)
    L_dir = np.sqrt(rx_range**2 + (rx_depth - tx_depth)**2)
    theta_dir = np.arctan2(abs(rx_depth - tx_depth), rx_range)

    L_surf = np.sqrt(rx_range**2 + (rx_depth + tx_depth)**2)
    theta_surf = np.arctan2(rx_depth + tx_depth, rx_range)

    # Rayleigh surface roughness parameter and coherent reflection loss
    rayleigh_g = float(2.0 * k * wave_rms * np.sin(theta_surf))
    coherent_loss = float(np.exp(-0.5 * rayleigh_g**2))
    surf_amp = (0.85 / L_surf) if is_surface else (0.25 * coherent_loss / L_surf)

    # 4. Multipath superposition
    p_dir = (1.0 / L_dir) * np.cos(2 * np.pi * f0 * (t - L_dir / c) + source_phase_fm)

    surface_mod = (4 * np.pi * f0 / c) * h_t * np.sin(theta_surf)
    p_surf = surf_amp * np.cos(2 * np.pi * f0 * (t - L_surf / c) + source_phase_fm + surface_mod + np.pi)

    sig = (p_dir + p_surf) * fading_env
    sig = sig / (np.std(sig) + 1e-6) + np.random.normal(0, 0.2, size=len(t))

    # 5. Watershed Bandwidth & Stability Analysis (ported from research-clean)
    f_low_bw = max(20.0, f0 - 300.0)
    f_high_bw = min(fs / 2.0 - 10.0, f0 + 300.0)
    bw_res = analyze_signal_bandwidth(sig, fs, f_low=f_low_bw, f_high=f_high_bw)

    diagnostics = {
        "is_surface": is_surface,
        "wave_rms": wave_rms,
        "theta_surf_deg": float(np.rad2deg(theta_surf)),
        "rayleigh_g": rayleigh_g,
        "coherent_loss": coherent_loss,
        "L_dir": float(L_dir),
        "L_surf": float(L_surf),
    }
    return t, sig, diagnostics, bw_res


# ==============================================================================
# Build Polished Interactive Dashboard UI
# ==============================================================================
def build_dashboard():
    defaults = {
        "tx_depth": 25.0,
        "rx_depth": 30.0,
        "freq": 400.0,
        "wind": 8.0,
        "range": 1000.0,
    }

    fig = plt.figure(figsize=(14.8, 9.0))
    fig.canvas.manager.set_window_title("Underwater Acoustic Multipath, Doppler & Watershed Bandwidth Simulator")

    # Dashboard title & live telemetry banner
    fig.text(
        0.04, 0.958,
        "UNDERWATER ACOUSTIC PROPAGATION, DOPPLER & WATERSHED BANDWIDTH SIMULATOR",
        fontsize=12.5, fontweight="bold", color=THEME["text_primary"]
    )
    status_badge = fig.text(
        0.04, 0.924, "",
        fontsize=9.0, fontweight="bold", color=THEME["accent_teal"],
        bbox=dict(boxstyle="round,pad=0.35", facecolor=THEME["bg_control"], edgecolor=THEME["border"], lw=1.0)
    )
    telemetry_text = fig.text(
        0.37, 0.924, "",
        fontsize=8.6, color=THEME["text_muted"],
        bbox=dict(boxstyle="round,pad=0.35", facecolor=THEME["bg_panel"], edgecolor=THEME["border"], lw=1.0)
    )

    # Main plot grid:
    # Row 0: [Time-Domain Waveform | Watershed Bandwidth Slice | 2D Eigenray Geometry]
    # Row 1: [Narrowband Spectrogram with Watershed BW Bounds (spans all 3 cols) + Colorbar]
    gs = GridSpec(
        2, 4, figure=fig,
        height_ratios=[1.0, 1.32],
        width_ratios=[1.0, 1.15, 1.0, 0.035],
        left=0.05, right=0.95, top=0.87, bottom=0.29,
        hspace=0.38, wspace=0.24
    )

    ax_sig = fig.add_subplot(gs[0, 0])
    ax_bw = fig.add_subplot(gs[0, 1])
    ax_geo = fig.add_subplot(gs[0, 2])
    ax_spec = fig.add_subplot(gs[1, 0:3])
    ax_cbar = fig.add_subplot(gs[1, 3])

    # Initial simulation run
    t, sig, diag, bw_res = run_interactive_simulation(
        defaults["tx_depth"], defaults["rx_depth"],
        defaults["freq"], defaults["wind"], defaults["range"]
    )
    f_spec, t_spec, Sxx = spectrogram(sig, fs=2000.0, nperseg=512, noverlap=384)
    Sxx_dB = 10 * np.log10(Sxx + 1e-12)

    # --- Panel 1: Time-Domain Signal Envelope (First 0.20 sec) ---
    n_samples_view = 400
    (line_sig,) = ax_sig.plot(t[:n_samples_view], sig[:n_samples_view], color=THEME["accent_cyan"], lw=1.15)
    ax_sig.set_title("Time-Domain Waveform (First 0.20 s)", fontsize=10.0, fontweight="bold", pad=7)
    ax_sig.set_xlabel("Time [s]")
    ax_sig.set_ylabel("Normalized Amplitude")
    ax_sig.set_xlim(0, t[n_samples_view - 1])
    ax_sig.set_ylim(-3.2, 3.2)
    ax_sig.grid(True)

    # --- Panel 2: Watershed Peak & Base Bandwidth Detection (Midpoint 500 ms Slice) ---
    (line_bw_fft,) = ax_bw.plot([], [], color="#d1d9e6", lw=1.3, label="FFT Slice (Hann @ Midpoint)")
    line_bw_floor = ax_bw.axhline(0.0, color=THEME["accent_amber"], lw=1.2, ls=":", label="Local Noise Floor")
    line_bw_l = ax_bw.axvline(defaults["freq"], color=THEME["accent_coral"], lw=1.1, ls="--", alpha=0.8)
    line_bw_r = ax_bw.axvline(defaults["freq"], color=THEME["accent_coral"], lw=1.1, ls="--", alpha=0.8)
    (pt_bw_bounds,) = ax_bw.plot(
        [], [], "d", markersize=7,
        markerfacecolor=THEME["accent_coral"], markeredgecolor=THEME["accent_coral"],
        label="Watershed Base Bounds"
    )
    (pt_bw_peak,) = ax_bw.plot(
        [], [], "v", markersize=8,
        markerfacecolor=THEME["accent_mint"], markeredgecolor="none",
        label="Dominant Peak"
    )
    ax_bw.set_title("Watershed Bandwidth Detection", fontsize=10.0, fontweight="bold", pad=7)
    ax_bw.set_xlabel("Frequency [Hz]")
    ax_bw.set_ylabel("Magnitude [dB]")
    ax_bw.grid(True)
    ax_bw.legend(loc="upper right", frameon=True, facecolor=THEME["bg_fig"], edgecolor=THEME["border"], fontsize=7.5)

    # --- Panel 3: Live 2D Acoustic Ray Geometry Cross-Section ---
    max_bathy = 105.0
    (line_wave_surf,) = ax_geo.plot([], [], color=THEME["accent_cyan"], lw=1.4, label="Rough Sea Surface")
    (line_ray_dir,) = ax_geo.plot([], [], color=THEME["accent_teal"], lw=1.8, ls="-", label="Direct Ray")
    (line_ray_surf,) = ax_geo.plot([], [], color=THEME["accent_amber"], lw=1.5, ls="--", label="Surface-Reflected Ray")
    (pt_tx,) = ax_geo.plot([], [], marker="o", markersize=8, color=THEME["accent_coral"], label="Source (Tx)")
    (pt_rx,) = ax_geo.plot([], [], marker="s", markersize=7, color=THEME["accent_cyan"], label="Hydrophone (Rx)")

    ax_geo.axhspan(100.0, max_bathy, color="#27201c", alpha=0.8)
    ax_geo.axhline(100.0, color="#a16207", lw=1.2, ls=":")
    ax_geo.set_title("2D Eigenray Propagation Geometry", fontsize=10.0, fontweight="bold", pad=7)
    ax_geo.set_xlabel("Horizontal Range [m]")
    ax_geo.set_ylabel("Depth [m]")
    ax_geo.set_ylim(max_bathy, -6.0)
    ax_geo.grid(True)
    ax_geo.legend(loc="lower right", frameon=True, facecolor=THEME["bg_fig"], edgecolor=THEME["border"], fontsize=7.5)

    # --- Panel 4: Narrowband Spectrogram with Watershed Bandwidth Bounds ---
    spec_mesh = ax_spec.pcolormesh(
        t_spec, f_spec, Sxx_dB,
        shading="gouraud", cmap="magma", vmin=-22, vmax=6
    )
    f0_ref_line = ax_spec.axhline(defaults["freq"], color=THEME["accent_cyan"], lw=0.9, ls="--", alpha=0.65, label="Center Freq $f_0$")
    spec_bw_low_line = ax_spec.axhline(defaults["freq"] - 10, color=THEME["accent_mint"], lw=1.1, ls=":", alpha=0.85, label="Watershed BW Bounds")
    spec_bw_high_line = ax_spec.axhline(defaults["freq"] + 10, color=THEME["accent_mint"], lw=1.1, ls=":", alpha=0.85)
    ax_spec.set_ylim(defaults["freq"] - 40, defaults["freq"] + 40)
    ax_spec.set_title("Narrowband Spectrogram (Frequency Smearing & Multipath Fading)", fontsize=10.5, fontweight="bold", pad=7)
    ax_spec.set_xlabel("Time [s]")
    ax_spec.set_ylabel("Frequency [Hz]")
    ax_spec.grid(True, alpha=0.25)
    ax_spec.legend(loc="upper right", frameon=True, facecolor=THEME["bg_fig"], edgecolor=THEME["border"], fontsize=8.0)

    cbar = fig.colorbar(spec_mesh, cax=ax_cbar)
    cbar.set_label("Power Spectral Density [dB]", fontsize=8.5, color=THEME["text_muted"])
    cbar.ax.tick_params(labelsize=8, colors=THEME["text_muted"])

    # ==============================================================================
    # Bottom Control Deck: 2-Column Sliders + Quick Scenario Presets
    # ==============================================================================
    def make_styled_slider(rect, label, valmin, valmax, valinit, valstep, color=THEME["accent_cyan"]):
        ax_s = fig.add_axes(rect, facecolor=THEME["slider_track"])
        for spine in ax_s.spines.values():
            spine.set_edgecolor(THEME["border"])
        slider = Slider(
            ax=ax_s, label=label, valmin=valmin, valmax=valmax,
            valinit=valinit, valstep=valstep,
            color=color, track_color=THEME["slider_track"],
            handle_style={"facecolor": THEME["text_primary"], "edgecolor": color, "size": 9}
        )
        slider.label.set_color(THEME["text_primary"])
        slider.label.set_fontsize(9.0)
        slider.valtext.set_color(color)
        slider.valtext.set_fontweight("bold")
        slider.valtext.set_fontsize(9.0)
        return slider

    # Left column sliders
    s_depth = make_styled_slider([0.13, 0.185, 0.30, 0.024], "Source Depth [m]  ", 0.5, 50.0, defaults["tx_depth"], 0.5, THEME["accent_coral"])
    s_rx_depth = make_styled_slider([0.13, 0.135, 0.30, 0.024], "Receiver Depth [m]  ", 5.0, 100.0, defaults["rx_depth"], 1.0, THEME["accent_cyan"])
    s_freq = make_styled_slider([0.13, 0.085, 0.30, 0.024], "Center Freq [Hz]  ", 100.0, 800.0, defaults["freq"], 10.0, THEME["accent_teal"])

    # Right column sliders
    s_wind = make_styled_slider([0.60, 0.185, 0.30, 0.024], "Wind Speed [m/s]  ", 2.0, 20.0, defaults["wind"], 0.5, THEME["accent_amber"])
    s_range = make_styled_slider([0.60, 0.135, 0.30, 0.024], "Horiz. Range [m]  ", 200.0, 3000.0, defaults["range"], 50.0, THEME["accent_cyan"])

    # Preset Buttons Row
    def make_preset_button(rect, text, accent):
        ax_b = fig.add_axes(rect)
        btn = Button(ax_b, text, color=THEME["bg_control"], hovercolor="#233252")
        for spine in ax_b.spines.values():
            spine.set_edgecolor(accent)
            spine.set_linewidth(1.0)
        btn.label.set_color(THEME["text_primary"])
        btn.label.set_fontsize(8.5)
        btn.label.set_fontweight("bold")
        return btn

    btn_boat = make_preset_button([0.52, 0.075, 0.13, 0.036], "Surface Boat (0.5m)", THEME["accent_coral"])
    btn_diver = make_preset_button([0.665, 0.075, 0.13, 0.036], "Shallow AUV (8m)", THEME["accent_amber"])
    btn_scooter = make_preset_button([0.81, 0.075, 0.13, 0.036], "Deep Scooter (25m)", THEME["accent_teal"])
    btn_reset = make_preset_button([0.13, 0.025, 0.10, 0.032], "Reset Defaults", THEME["border"])

    fig.text(
        0.25, 0.035,
        "Tip: Drag sliders or click a preset on the right to inspect real-time Watershed Bandwidth & Jain's Fairness metrics.",
        fontsize=8.5, color=THEME["text_muted"]
    )

    # ==============================================================================
    # Real-Time Update Callback
    # ==============================================================================
    updating_preset = False

    def refresh_views(d, rx_d, f, w, r):
        _, sig_new, diag_new, bw_new = run_interactive_simulation(d, rx_d, f, w, r)
        f_s, t_s, S_new = spectrogram(sig_new, fs=2000.0, nperseg=512, noverlap=384)
        S_new_dB = 10 * np.log10(S_new + 1e-12)

        is_surf = diag_new["is_surface"]
        accent = THEME["accent_coral"] if is_surf else THEME["accent_teal"]
        eps = np.finfo(float).eps

        # 1. Update Time-Domain plot
        line_sig.set_ydata(sig_new[:n_samples_view])
        line_sig.set_color(accent)

        # 2. Update Watershed Bandwidth Slice plot (matching research-clean Visualizer Figure 2)
        if bw_new["found"] and len(bw_new["f_segment"]) > 0:
            f_seg = bw_new["f_segment"]
            mag_seg_db = 20.0 * np.log10(bw_new["mag_segment"] + eps)
            nf_db = 20.0 * np.log10(bw_new["noise_floor"] + eps)

            line_bw_fft.set_data(f_seg, mag_seg_db)
            line_bw_floor.set_ydata([nf_db, nf_db])

            l_idx = int(np.argmin(np.abs(f_seg - bw_new["l_freq"])))
            r_idx = int(np.argmin(np.abs(f_seg - bw_new["r_freq"])))
            l_db = float(mag_seg_db[l_idx])
            r_db = float(mag_seg_db[r_idx])
            pk_db = float(20.0 * np.log10(bw_new["main_mag"] + eps))

            pt_bw_bounds.set_data([bw_new["l_freq"], bw_new["r_freq"]], [l_db, r_db])
            pt_bw_peak.set_data([bw_new["main_f"]], [pk_db])
            line_bw_l.set_xdata([bw_new["l_freq"], bw_new["l_freq"]])
            line_bw_r.set_xdata([bw_new["r_freq"], bw_new["r_freq"]])

            ax_bw.set_xlim(f_seg[0], f_seg[-1])
            ax_bw.set_ylim(min(np.min(mag_seg_db), nf_db) - 5.0, pk_db + 6.0)
            stab = bw_new["stability"]
            ax_bw.set_title(
                f"Watershed BW: {bw_new['main_bw']:.1f} Hz  (Mean: {stab['mean_bw']:.1f}±{stab['std_bw']:.1f} Hz)",
                fontsize=9.8, fontweight="bold", pad=7
            )

        # 3. Update 2D Ray Geometry plot
        x_r = np.linspace(0, r, 150)
        visual_wave = -2.2 * diag_new["wave_rms"] * np.sin(2 * np.pi * x_r / max(r / 8.0, 30.0))
        line_wave_surf.set_data(x_r, visual_wave)

        x_bounce = r * (d / (d + rx_d))
        line_ray_dir.set_data([0, r], [d, rx_d])
        line_ray_surf.set_data([0, x_bounce, r], [d, 0.0, rx_d])
        pt_tx.set_data([0], [d])
        pt_rx.set_data([r], [rx_d])
        ax_geo.set_xlim(-0.04 * r, 1.06 * r)

        # 4. Update Spectrogram mesh and Watershed BW lines
        spec_mesh.set_array(S_new_dB.ravel())
        f0_ref_line.set_ydata([f, f])
        if bw_new["found"]:
            spec_bw_low_line.set_ydata([bw_new["l_freq"], bw_new["l_freq"]])
            spec_bw_high_line.set_ydata([bw_new["r_freq"], bw_new["r_freq"]])
        ax_spec.set_ylim(f - 40, f + 40)

        # 5. Update Status Badge & Live Telemetry
        if is_surf:
            mode_str = f"SURFACE VESSEL (Depth {d:.1f} m)  •  Broadened FM Smearing"
            status_badge.set_color(THEME["accent_coral"])
        else:
            mode_str = f"SUBMERGED VEHICLE (Depth {d:.1f} m)  •  Coherent Narrowband Tonal"
            status_badge.set_color(THEME["accent_teal"])
        status_badge.set_text(mode_str)

        stab = bw_new["stability"]
        telemetry_text.set_text(
            f"Watershed BW: {bw_new['main_bw']:.1f} Hz (Mean {stab['mean_bw']:.1f}±{stab['std_bw']:.1f} Hz)  |  "
            f"Macro-Lobe: {bw_new['dom_lobe']['bandwidth']:.1f} Hz  |  "
            f"Fairness: {stab['fairness']:.3f}  |  TiB: {stab['tib']*100:.0f}%  |  "
            f"Rayleigh g: {diag_new['rayleigh_g']:.2f}"
        )

        ax_spec.set_title(
            f"Narrowband Spectrogram  —  Center Freq: {f:.0f} Hz  |  Watershed Bounds: [{bw_new['l_freq']:.1f}, {bw_new['r_freq']:.1f}] Hz  |  Range: {r:.0f} m",
            fontsize=10.2, fontweight="bold", color=THEME["text_primary"], pad=7
        )

        fig.canvas.draw_idle()

    def on_slider_change(_):
        if updating_preset:
            return
        refresh_views(s_depth.val, s_rx_depth.val, s_freq.val, s_wind.val, s_range.val)

    def apply_preset(depth_val, wind_val=None):
        nonlocal updating_preset
        updating_preset = True
        s_depth.set_val(depth_val)
        if wind_val is not None:
            s_wind.set_val(wind_val)
        updating_preset = False
        refresh_views(s_depth.val, s_rx_depth.val, s_freq.val, s_wind.val, s_range.val)

    def on_reset(_):
        nonlocal updating_preset
        updating_preset = True
        s_depth.set_val(defaults["tx_depth"])
        s_rx_depth.set_val(defaults["rx_depth"])
        s_freq.set_val(defaults["freq"])
        s_wind.set_val(defaults["wind"])
        s_range.set_val(defaults["range"])
        updating_preset = False
        refresh_views(s_depth.val, s_rx_depth.val, s_freq.val, s_wind.val, s_range.val)

    s_depth.on_changed(on_slider_change)
    s_rx_depth.on_changed(on_slider_change)
    s_freq.on_changed(on_slider_change)
    s_wind.on_changed(on_slider_change)
    s_range.on_changed(on_slider_change)

    btn_boat.on_clicked(lambda _: apply_preset(0.5))
    btn_diver.on_clicked(lambda _: apply_preset(8.0))
    btn_scooter.on_clicked(lambda _: apply_preset(25.0))
    btn_reset.on_clicked(on_reset)

    # Populate initial state
    refresh_views(defaults["tx_depth"], defaults["rx_depth"], defaults["freq"], defaults["wind"], defaults["range"])
    plt.show()


if __name__ == "__main__":
    build_dashboard()
