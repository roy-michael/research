import os
import subprocess
import numpy as np
import matplotlib.pyplot as plt

def run_arrivals_sim(sd_val, bin_path, script_dir):
    env_file = os.path.join(script_dir, "temp_waves.env")
    arr_file = os.path.join(script_dir, "temp_waves.arr")
    file_root = os.path.splitext(env_file)[0]
    
    # 30m water column downward refracting profile
    z_min = 0.0
    z_max = 30.0
    z_axis = np.linspace(z_min, z_max, 31)
    ssp_c = np.linspace(1520.0, 1500.0, 31)
    
    env_lines = [
        f"'Surface Waves Simulation SD={sd_val}m'",
        "100.0",
        "1",
        "'SVF'",
        f"{len(z_axis)} {z_min:.1f} {z_max:.1f}"
    ]
    for z, c in zip(z_axis, ssp_c):
        env_lines.append(f"{z:.2f} {c:.2f} /")
    env_lines.extend([
        "'A' 0.0",
        f"{z_max:.1f} 1600.0 0.0 1.5 0.2 /",
        "1",
        f"{sd_val:.1f} /",
        "1",
        "15.0 /",
        "1",
        "0.5 /",
        "'A'",                  # RunType: Arrivals
        "801",                  # 801 beams
        "-80.0 80.0 /",
        "0.0 60.0 1.0"
    ])
    with open(env_file, "w") as f:
        f.write("\n".join(env_lines) + "\n")
        
    subprocess.run([bin_path, file_root], capture_output=True, text=True)
    
    arrivals = []
    if os.path.exists(arr_file):
        with open(arr_file, "r") as f:
            f.readline(); f.readline(); f.readline(); f.readline(); f.readline()
            narr = int(f.readline().strip())
            f.readline()
            for _ in range(narr):
                tokens = f.readline().split()
                if not tokens:
                    break
                arrivals.append({
                    'amp': float(tokens[0]),
                    'phase': float(tokens[1]),
                    'delay': float(tokens[2]),
                    'src_angle': float(tokens[4]),
                    'rcvr_angle': float(tokens[5]),
                    'bottom_bounces': int(tokens[6]),
                    'surface_bounces': int(tokens[7])
                })
                
    # Clean up temp files
    try:
        os.remove(env_file)
        if os.path.exists(arr_file): os.remove(arr_file)
        for ext in ['.shd', '.prt', '.ray']:
            path = file_root + ext
            if os.path.exists(path): os.remove(path)
    except OSError:
        pass
        
    return arrivals

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    workspace_dir = os.path.abspath(os.path.join(script_dir, "..", ".."))
    bin_path = os.path.join(workspace_dir, "bellhopcuda", "bellhopcxx.exe")
    output_dir = os.path.abspath(os.path.join(script_dir, "..", "output"))
    os.makedirs(output_dir, exist_ok=True)
    
    # Run simulation for source right beneath the surface (SD = 0.5m)
    # We use 0.5m so the direct and reflected paths are resolved but extremely close
    sd_val = 0.5
    print(f"Running simulation for SD = {sd_val}m...")
    arrivals = run_arrivals_sim(sd_val, bin_path, script_dir)
    
    # 6. Signal Simulation at the Receiver
    fs = 48000
    duration = 4.0
    t = np.arange(0, duration, 1/fs)
    
    # Source signal: Vessel noise (colored noise + engine tonals)
    np.random.seed(42)
    white_noise = np.random.normal(0, 1.0, size=len(t))
    white_fft = np.fft.rfft(white_noise)
    freqs_src = np.fft.rfftfreq(len(t), d=1/fs)
    envelope = 1.0 / (1.0 + (freqs_src / 80.0)**0.8)
    colored_noise = np.fft.irfft(white_fft * envelope, n=len(t))
    colored_noise = colored_noise / np.std(colored_noise) * 2.0
    
    # Vessel engine cylinder tonals (60 Hz fundamental + harmonics)
    tonals = [(60.0, 5.0), (120.0, 3.5), (180.0, 2.5), (240.0, 1.8), (360.0, 1.2)]
    source_signal = colored_noise.copy()
    for f_t, amp_t in tonals:
        source_signal += amp_t * np.sin(2 * np.pi * f_t * t)
        
    v_s = 5.0 # Vessel speed
    c_ref = 1520.0
    
    # Condition 1: Flat Mirror Surface (No phase perturbation)
    rx_flat = np.zeros_like(t)
    for arr in arrivals:
        tau = arr['delay']
        amp = arr['amp']
        phase_rad = np.radians(arr['phase'])
        src_angle_rad = np.radians(arr['src_angle'])
        v_proj = v_s * np.cos(src_angle_rad)
        doppler_scale = (c_ref - v_proj) / c_ref
        t_shifted = (t - tau) * doppler_scale
        
        rx_flat += amp * np.interp(t_shifted, t, source_signal, left=0, right=0) * np.cos(phase_rad)
    rx_flat += np.random.normal(0, 0.05, size=len(t))
        
    # Condition 2: Rough Surface with Waves
    # Waves randomize/perturb the phase of any ray that bounces off the surface
    # We add a random phase shift (std dev of 90 degrees) to surface-reflected paths
    np.random.seed(123)
    rx_waves = np.zeros_like(t)
    for arr in arrivals:
        tau = arr['delay']
        amp = arr['amp']
        
        # Base phase
        phase_deg = arr['phase']
        if arr['surface_bounces'] > 0:
            # Apply phase perturbation due to waves scattering
            # std_dev = 90 degrees representing moderate ocean waves
            phase_deg += np.random.normal(0, 90.0)
            
        phase_rad = np.radians(phase_deg)
        src_angle_rad = np.radians(arr['src_angle'])
        v_proj = v_s * np.cos(src_angle_rad)
        doppler_scale = (c_ref - v_proj) / c_ref
        t_shifted = (t - tau) * doppler_scale
        
        rx_waves += amp * np.interp(t_shifted, t, source_signal, left=0, right=0) * np.cos(phase_rad)
    rx_waves += np.random.normal(0, 0.05, size=len(t))
    
    # PSD analysis
    from scipy.signal import welch
    def get_psd(x):
        f_p, p_est = welch(x, fs, nperseg=8192, noverlap=4096)
        return f_p, 10 * np.log10(p_est + 1e-15)
        
    f_psd, psd_src = get_psd(source_signal)
    _, psd_flat = get_psd(rx_flat)
    _, psd_waves = get_psd(rx_waves)
    
    # Plotting
    plt.style.use('dark_background')
    fig, axes = plt.subplots(2, 1, figsize=(14, 10))
    fig.suptitle(f"Ocean Surface Waves Impact on Lloyd's Mirror Cancellation (Source Depth: {sd_val}m)", fontsize=14, fontweight='bold', color='#E2E8F0')
    
    # Time Series Zoomed
    ax_time = axes[0]
    t_start = min([a['delay'] for a in arrivals]) - 0.02
    t_end = t_start + 0.15
    idx_zoom = (t >= t_start) & (t <= t_end)
    
    ax_time.plot(t[idx_zoom], rx_flat[idx_zoom], color='#F43F5E', alpha=0.8, linewidth=1.2, label="Flat Sea Surface (Coherent Cancellation)")
    ax_time.plot(t[idx_zoom], rx_waves[idx_zoom], color='#10B981', linewidth=1.5, label="Rough Surface / Waves (Broken Cancellation)")
    ax_time.set_title("Received Time-Domain Waveforms (Zoomed)", fontsize=11, fontweight='bold', color='#94A3B8')
    ax_time.set_xlabel("Time (s)", color='#94A3B8')
    ax_time.set_ylabel("Amplitude", color='#94A3B8')
    ax_time.grid(True, linestyle=':', alpha=0.3, color='#475569')
    ax_time.legend(loc='upper right', frameon=True, facecolor='#1E293B', edgecolor='none')
    
    # Spectrum comparison
    ax_psd = axes[1]
    ax_psd.plot(f_psd, psd_flat, color='#F43F5E', alpha=0.8, linewidth=1.5, label="Flat Sea (Lloyd's Mirror Cancellation)")
    ax_psd.plot(f_psd, psd_waves, color='#10B981', linewidth=1.8, label="Rough Sea / Waves (Sound Arrives)")
    ax_psd.plot(f_psd, psd_src - 20, color='#94A3B8', alpha=0.4, linestyle='--', label="Source Signal (Scaled)")
    
    ax_psd.set_xscale('log')
    ax_psd.set_xlim(20, 10000)
    ax_psd.set_ylim(-75, 15)
    ax_psd.set_title("Received Power Spectral Density (PSD) Comparison", fontsize=11, fontweight='bold', color='#94A3B8')
    ax_psd.set_xlabel("Frequency (Hz)", color='#94A3B8')
    ax_psd.set_ylabel("PSD (dB)", color='#94A3B8')
    ticks = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000]
    tick_labels = ['20 Hz', '50 Hz', '100 Hz', '200 Hz', '500 Hz', '1 kHz', '2 kHz', '5 kHz', '10 kHz']
    ax_psd.set_xticks(ticks)
    ax_psd.set_xticklabels(tick_labels)
    ax_psd.grid(True, which='both', linestyle=':', alpha=0.3, color='#475569')
    ax_psd.legend(loc='upper right', frameon=True, facecolor='#1E293B', edgecolor='none')
    
    plt.tight_layout()
    output_image = os.path.join(output_dir, "bellhop_surface_waves_comparison.png")
    plt.savefig(output_image, dpi=300, facecolor='#0F172A')
    plt.close()
    
    print(f"Waves simulation visualization saved to: {output_image}")

if __name__ == "__main__":
    main()
