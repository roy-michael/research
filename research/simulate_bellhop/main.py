import os
import sys
from pathlib import Path
import numpy as np
import matplotlib.pyplot as plt
from scipy.signal import spectrogram
import arlpy.uwapm as pm

from bandwidth_tracker import analyze_signal_bandwidth

# Ensure UTF-8 output on Windows consoles
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

# Add local bellhopcuda directory to PATH so arlpy can locate bellhop.exe
_bellhop_dir = Path(__file__).resolve().parents[2] / 'bellhopcuda'
if _bellhop_dir.is_dir():
    os.environ['PATH'] = str(_bellhop_dir) + os.pathsep + os.environ.get('PATH', '')

# ==============================================================================
# Step 1: Build BELLHOP Environment from Scratch (No External .env File)
# ==============================================================================
def build_environment_and_get_arrivals(tx_depth, rx_depth=30.0, rx_range=1000.0, freq=400.0):
    """
    Builds an environment dictionary from scratch, runs BELLHOP (or computes
    geometrically if BELLHOP is not installed), and returns the list of arrivals.
    """
    c_water = 1500.0
    max_depth = 100.0

    # Create environment settings from scratch (replaces the .env file)
    env = pm.create_env2d(
        name='Underwater_Sim',
        depth=max_depth,                 # Bottom depth (meters)
        soundspeed=c_water,              # Speed of sound in water (can also be a depth profile)
        tx_depth=tx_depth,               # Source depth (surface boat or underwater scooter)
        rx_depth=rx_depth,               # Hydrophone depth
        rx_range=rx_range,               # Horizontal range (meters)
        bottom_soundspeed=1600.0,        # Speed of sound in bottom sediment (sand/mud)
        bottom_density=1800.0,           # Bottom density (kg/m^3)
        bottom_absorption=0.5,           # Bottom attenuation (dB/wavelength)
        nbeams=1000,                     # Number of beams launched from the source
        min_angle=-80.0,                 # Minimum launch angle (degrees)
        max_angle=80.0,                  # Maximum launch angle (degrees)
        frequency=freq                   # Center frequency of the motor
    )

    # Optional: inspect the environment parameters generated behind the scenes:
    # pm.print_env(env)

    try:
        # Run BELLHOP to obtain the ray arrivals table
        arrivals_df = pm.compute_arrivals(env)
        if arrivals_df is None or arrivals_df.empty:
            raise RuntimeError("BELLHOP returned no arrivals")

        # Convert the arlpy DataFrame into a uniform list of dicts for synthesis
        arrivals = []
        for _, row in arrivals_df.iterrows():
            rx_angle = row['angle_of_arrival'] if 'angle_of_arrival' in row else row['rx_angle']
            arrivals.append({
                'time_of_arrival': float(np.real(row['time_of_arrival'])),
                'amplitude': complex(row['arrival_amplitude']),
                'surface_bounces': int(np.real(row['surface_bounces'])),
                'bottom_bounces': int(np.real(row['bottom_bounces'])),
                # Sea-surface grazing angle (approx. departure/arrival angle for constant SSP)
                'grazing_angle_rad': np.deg2rad(abs(float(np.real(rx_angle))))
            })
        print(f"[BELLHOP] Found {len(arrivals)} arrivals for source depth {tx_depth}m.")
        return arrivals

    except Exception as e:
        print(f"[NOTE] BELLHOP engine not found in PATH ({e}). Falling back to built-in analytical eigenrays...")
        return fallback_analytical_eigenrays(tx_depth, rx_depth, rx_range, max_depth, c_water)


def fallback_analytical_eigenrays(z_tx, z_rx, R, H, c):
    """
    Exact mathematical fallback (method of images) in case the BELLHOP executable
    is not installed on the machine. Computes the main rays: direct path,
    surface reflection, and bottom reflection.
    """
    rays = []
    # 1. Direct Path
    L_dir = np.sqrt(R**2 + (z_rx - z_tx)**2)
    rays.append({
        'time_of_arrival': L_dir / c,
        'amplitude': (1.0 / L_dir) + 0j,
        'surface_bounces': 0,
        'bottom_bounces': 0,
        'grazing_angle_rad': np.arctan2(abs(z_rx - z_tx), R)
    })

    # 2. Surface Reflected Path - phase inversion (-1)
    L_surf = np.sqrt(R**2 + (z_rx + z_tx)**2)
    rays.append({
        'time_of_arrival': L_surf / c,
        'amplitude': (-0.95 / L_surf) + 0j,
        'surface_bounces': 1,
        'bottom_bounces': 0,
        'grazing_angle_rad': np.arctan2(z_rx + z_tx, R)
    })

    # 3. Bottom Reflected Path
    L_bot = np.sqrt(R**2 + ((2*H - z_tx) - z_rx)**2)
    rays.append({
        'time_of_arrival': L_bot / c,
        'amplitude': (0.5 / L_bot) + 0j,
        'surface_bounces': 0,
        'bottom_bounces': 1,
        'grazing_angle_rad': np.arctan2((2*H - z_tx) - z_rx, R)
    })
    return rays


# ==============================================================================
# Step 2: Physical Sea Wave Generator (Pierson-Moskowitz Spectrum)
# ==============================================================================
def generate_sea_surface(wind_speed=8.5, duration=30.0, fs_env=50.0):
    """
    Generates a time series of sea surface elevation h(t) and orbital wave
    velocity v_orbital(t) according to the Pierson-Moskowitz spectrum.
    """
    g = 9.81
    alpha = 0.0081
    beta_pm = 0.74

    f = np.linspace(0.08, 1.2, 250)
    df = f[1] - f[0]
    omega = 2 * np.pi * f
    omega_0 = g / wind_speed

    # Wave spectrum S(omega)
    S_omega = (alpha * g**2 / omega**5) * np.exp(-beta_pm * (omega_0 / omega)**4)
    S_f = S_omega * (2 * np.pi)

    amps = np.sqrt(2 * S_f * df)
    phases = np.random.uniform(0, 2 * np.pi, size=len(f))

    t_env = np.arange(0, duration, 1.0 / fs_env)
    # Sum wave components to produce time-varying sea surface height and velocity
    h_t = np.sum(amps[:, None] * np.cos(omega[:, None] * t_env[None, :] + phases[:, None]), axis=0)
    v_orbital = np.sum((amps * omega)[:, None] * np.sin(omega[:, None] * t_env[None, :] + phases[:, None]), axis=0)

    return t_env, h_t, v_orbital


# ==============================================================================
# Step 3: Acoustic Signal Synthesis (Combining Rays with Sea & Vessel Dynamics)
# ==============================================================================
def synthesize_acoustic_signal(arrivals, f0=400.0, duration=30.0, fs_audio=2000.0, is_surface_boat=True):
    c = 1500.0
    k = 2 * np.pi * f0 / c  # Acoustic wavenumber
    t = np.arange(0, duration, 1.0 / fs_audio)

    # 1. Generate sea waves and interpolate to the acoustic sampling rate
    t_env, h_env, v_env = generate_sea_surface(wind_speed=8.5, duration=duration)
    h_t = np.interp(t, t_env, h_env)
    v_wave = np.interp(t, t_env, v_env)
    wave_rms = np.std(h_t)

    # 2. Source kinematics & low-grazing-angle shadowing envelope
    if is_surface_boat:
        # Surface vessel experiences surge/heave along the wave orbital velocity
        # and propeller load variations near the air-water interface (FM smearing)
        inst_freq_dev = 3.5 * v_wave + 2.0 * np.random.randn(len(t))
        smooth_win = int(fs_audio * 0.15)
        inst_freq_dev = np.convolve(inst_freq_dev, np.ones(smooth_win) / smooth_win, mode='same')
        source_phase_fm = 2 * np.pi * np.cumsum(inst_freq_dev) / fs_audio

        # Acoustic lensing and wave-crest shadowing at shallow grazing angles (~1.7 deg)
        fading_envelope = np.clip(1.0 + 0.7 * h_t + 0.4 * np.random.randn(len(t)), 0.05, 2.5)
        env_win = int(fs_audio * 0.08)
        fading_envelope = np.convolve(fading_envelope, np.ones(env_win) / env_win, mode='same')
    else:
        # Underwater scooter (DPV / AUV) operates below the wave base:
        # stable electric propulsion and no surface heave (beta ~ 0)
        inst_freq_dev = 0.15 * np.sin(2 * np.pi * 0.05 * t)
        source_phase_fm = 2 * np.pi * np.cumsum(inst_freq_dev) / fs_audio
        fading_envelope = np.ones_like(t)

    p_rx = np.zeros_like(t)

    # 3. Multipath Superposition across all BELLHOP rays
    for ray in arrivals:
        tau_i = ray['time_of_arrival']
        amp_i = np.abs(ray['amplitude'])
        phase_i = np.angle(ray['amplitude'])
        n_surf = ray['surface_bounces']
        theta_g = ray['grazing_angle_rad']

        t_delayed = t - tau_i

        # Phase modulation (Doppler smearing) & coherent scattering loss at the rough surface
        if n_surf > 0:
            # Rayleigh roughness parameter: steeper surface bounces scatter energy incoherently
            rayleigh_g = 2.0 * k * wave_rms * np.sin(theta_g)
            coherent_loss = np.exp(-0.5 * (n_surf * rayleigh_g)**2)

            if not is_surface_boat:
                # For a deep source, the steeper surface-reflected path is strongly scattered
                amp_i *= 0.25 * coherent_loss

            micro_scattering = np.cumsum(np.random.normal(0, 0.08, size=len(t)))
            surface_mod = n_surf * (4 * np.pi * f0 / c) * h_t * np.sin(theta_g) + micro_scattering
        else:
            surface_mod = 0.0

        total_phase = 2 * np.pi * f0 * t_delayed + source_phase_fm + surface_mod + phase_i
        p_rx += amp_i * np.cos(total_phase)

    # Apply multiplicative fading envelope and normalize signal power for fair SNR comparison
    p_rx = p_rx * fading_envelope
    p_rx = p_rx / np.std(p_rx)

    noise = np.random.normal(0, 0.35, size=len(t))
    return t, p_rx + noise


# ==============================================================================
# Step 4: Run Demo and Plot Side-by-Side Spectrograms
# ==============================================================================
if __name__ == '__main__':
    f_motor = 400.0  # Example motor frequency (400 Hz)
    fs = 2000.0      # Sampling frequency (Hz)
    T_dur = 30.0     # Recording duration (30 seconds)

    # 1. Compute rays, synthesize signal, and run Watershed Bandwidth analysis for a surface boat (depth 0.5 m)
    arr_boat = build_environment_and_get_arrivals(tx_depth=0.5, freq=f_motor)
    t, sig_boat = synthesize_acoustic_signal(arr_boat, f0=f_motor, duration=T_dur, fs_audio=fs, is_surface_boat=True)
    bw_boat = analyze_signal_bandwidth(sig_boat, fs, f_low=100.0, f_high=900.0)

    # 2. Compute rays, synthesize signal, and run Watershed Bandwidth analysis for an underwater scooter (depth 25 m)
    arr_scooter = build_environment_and_get_arrivals(tx_depth=25.0, freq=f_motor)
    _, sig_scooter = synthesize_acoustic_signal(arr_scooter, f0=f_motor, duration=T_dur, fs_audio=fs, is_surface_boat=False)
    bw_scooter = analyze_signal_bandwidth(sig_scooter, fs, f_low=100.0, f_high=900.0)

    for label, bw in [("Underwater Scooter (25m)", bw_scooter), ("Surface Motorboat (0.5m)", bw_boat)]:
        stab = bw["stability"]
        print(
            f"[WATERSHED BW] {label}: Peak={bw['main_f']:.1f} Hz | "
            f"Midpoint BW={bw['main_bw']:.1f} Hz [{bw['l_freq']:.1f}-{bw['r_freq']:.1f} Hz] | "
            f"Mean Slice BW={stab['mean_bw']:.1f}±{stab['std_bw']:.1f} Hz | "
            f"Fairness={stab['fairness']:.3f} | TiB={stab['tib']*100:.0f}% | Entropy={stab['entropy']:.2f}"
        )

    # 3. Plot 2x2 Dashboard: Spectrograms (top) + Watershed Bandwidth Detection (bottom)
    plt.rcParams.update({
        "figure.facecolor": "#0b0f17",
        "axes.facecolor": "#131b2e",
        "axes.edgecolor": "#263554",
        "axes.labelcolor": "#e2e8f0",
        "xtick.color": "#94a3b8",
        "ytick.color": "#94a3b8",
        "text.color": "#e2e8f0",
    })
    fig, axes = plt.subplots(2, 2, figsize=(14.5, 8.5), gridspec_kw={"height_ratios": [1.25, 1.0]})
    fig.canvas.manager.set_window_title("BELLHOP Acoustic Multipath & Watershed Bandwidth Comparison")

    mesh = None
    eps = np.finfo(float).eps
    scenarios = [
        (0, sig_scooter, bw_scooter, "Underwater Scooter / AUV (Depth = 25m)", "#2dd4bf"),
        (1, sig_boat, bw_boat, "Surface Motorboat (Depth = 0.5m)", "#fb7185"),
    ]

    for col, sig, bw, title, accent in scenarios:
        # Top row: Narrowband Spectrogram with Watershed BW boundaries
        ax_spec = axes[0, col]
        f_spec, t_spec, Sxx = spectrogram(sig, fs=fs, nperseg=1024, noverlap=896)
        mesh = ax_spec.pcolormesh(
            t_spec, f_spec, 10 * np.log10(Sxx + 1e-12),
            shading="gouraud", cmap="magma", vmin=-25, vmax=5
        )
        ax_spec.axhline(f_motor, color=accent, lw=0.9, ls="--", alpha=0.7, label="Center Freq $f_0$")
        if bw["found"]:
            ax_spec.axhline(bw["l_freq"], color="#38e08c", lw=1.1, ls=":", alpha=0.85, label="Watershed BW Bounds")
            ax_spec.axhline(bw["r_freq"], color="#38e08c", lw=1.1, ls=":", alpha=0.85)
        ax_spec.set_title(title, fontsize=12.0, fontweight="bold", color=accent, pad=8)
        ax_spec.set_xlabel("Time [sec]")
        ax_spec.set_ylim(f_motor - 40, f_motor + 40)
        ax_spec.grid(color="#1e293b", linestyle="--", alpha=0.45)
        ax_spec.legend(loc="upper right", frameon=True, facecolor="#0b0f17", edgecolor="#263554", fontsize=8)

        # Bottom row: Watershed Peak & Base Bandwidth Detection (Midpoint FFT Slice)
        ax_bw = axes[1, col]
        if bw["found"]:
            f_seg = bw["f_segment"]
            mag_db = 20.0 * np.log10(bw["mag_segment"] + eps)
            nf_db = 20.0 * np.log10(bw["noise_floor"] + eps)
            pk_db = 20.0 * np.log10(bw["main_mag"] + eps)
            l_idx = int(np.argmin(np.abs(f_seg - bw["l_freq"])))
            r_idx = int(np.argmin(np.abs(f_seg - bw["r_freq"])))

            ax_bw.plot(f_seg, mag_db, color="#d1d9e6", lw=1.3, label="Signal FFT Slice (Hann @ Midpoint)")
            ax_bw.axhline(nf_db, color="#f59e0b", lw=1.2, ls=":", label="Local Noise Floor")
            ax_bw.axvline(bw["l_freq"], color="#fb7185", lw=1.0, ls="--", alpha=0.75)
            ax_bw.axvline(bw["r_freq"], color="#fb7185", lw=1.0, ls="--", alpha=0.75)
            ax_bw.plot(
                [bw["l_freq"], bw["r_freq"]], [mag_db[l_idx], mag_db[r_idx]], "d",
                markersize=7.5, markerfacecolor="#fb7185", markeredgecolor="#fb7185",
                label=f"Base BW: {bw['main_bw']:.1f} Hz"
            )
            ax_bw.plot(
                bw["main_f"], pk_db, "v",
                markersize=8, markerfacecolor="#38e08c", markeredgecolor="none"
            )
            stab = bw["stability"]
            ax_bw.set_title(
                f"Watershed Detection  |  Slice BW: {bw['main_bw']:.1f} Hz  |  Mean BW: {stab['mean_bw']:.1f}±{stab['std_bw']:.1f} Hz  |  Fairness: {stab['fairness']:.3f}",
                fontsize=10.0, fontweight="bold", color="#e2e8f0", pad=7
            )
            ax_bw.set_xlim(f_seg[0], f_seg[-1])
            ax_bw.set_ylim(min(np.min(mag_db), nf_db) - 5.0, pk_db + 6.0)
        ax_bw.set_xlabel("Frequency [Hz]")
        ax_bw.grid(color="#1e293b", linestyle="--", alpha=0.45)
        ax_bw.legend(loc="upper right", frameon=True, facecolor="#0b0f17", edgecolor="#263554", fontsize=8)

    axes[0, 0].set_ylabel("Frequency [Hz]")
    axes[1, 0].set_ylabel("Magnitude [dB]")
    plt.tight_layout(rect=[0.0, 0.0, 0.92, 1.0])
    cbar_ax = fig.add_axes([0.935, 0.56, 0.015, 0.38])
    cbar = fig.colorbar(mesh, cax=cbar_ax)
    cbar.set_label("Power Spectral Density [dB]", color="#94a3b8")
    cbar.ax.tick_params(colors="#94a3b8")
    plt.show()