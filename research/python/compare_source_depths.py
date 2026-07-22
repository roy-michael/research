import os
import subprocess
import numpy as np
import matplotlib.pyplot as plt

def run_single_sim(sd_val, bin_path, script_dir):
    env_file = os.path.join(script_dir, f"temp_sd_{int(sd_val)}.env")
    ray_file = os.path.join(script_dir, f"temp_sd_{int(sd_val)}.ray")
    arr_file = os.path.join(script_dir, f"temp_sd_{int(sd_val)}.arr")
    file_root = os.path.splitext(env_file)[0]
    
    # 30m water column downward refracting profile
    z_min = 0.0
    z_max = 30.0
    z_axis = np.linspace(z_min, z_max, 31)
    ssp_c = np.linspace(1520.0, 1500.0, 31)
    
    # 1. Run Ray Tracing
    env_lines_ray = [
        f"'Ray Trace SD={sd_val}m'",
        "100.0",
        "1",
        "'SVF'",
        f"{len(z_axis)} {z_min:.1f} {z_max:.1f}"
    ]
    for z, c in zip(z_axis, ssp_c):
        env_lines_ray.append(f"{z:.2f} {c:.2f} /")
    env_lines_ray.extend([
        "'A' 0.0",
        f"{z_max:.1f} 1600.0 0.0 1.5 0.2 /",
        "1",
        f"{sd_val:.1f} /",
        "1",
        "15.0 /",
        "1",
        "0.5 /",
        "'R'",
        "401",
        "-45.0 45.0 /",
        "0.0 60.0 1.0"
    ])
    with open(env_file, "w") as f:
        f.write("\n".join(env_lines_ray) + "\n")
        
    subprocess.run([bin_path, file_root], capture_output=True, text=True)
    
    # Parse Ray File
    rays = []
    if os.path.exists(ray_file):
        with open(ray_file, "r") as f:
            f.readline() # Title
            f.readline() # Freq
            f.readline() # Skip
            nbeams, _ = map(int, f.readline().split())
            while True:
                line = f.readline().strip().strip("'")
                if line == 'rz':
                    break
            for _ in range(nbeams):
                angle = float(f.readline().strip())
                stats = f.readline()
                npts, b_bounces, s_bounces = map(int, stats.split())
                r_coords = []
                z_coords = []
                for _ in range(npts):
                    pt = f.readline()
                    r, z = map(float, pt.split())
                    r_coords.append(r)
                    z_coords.append(z)
                rays.append({
                    'angle': angle,
                    'r': np.array(r_coords) / 1000.0,
                    'z': np.array(z_coords),
                    'bottom_bounces': b_bounces,
                    'surface_bounces': s_bounces
                })
                
    # 2. Run Arrivals (for Doppler / Signal)
    env_lines_arr = env_lines_ray.copy()
    env_lines_arr[-4] = "'A'" # Change RunType to Arrivals
    env_lines_arr[-3] = "801" # 801 beams
    env_lines_arr[-2] = "-80.0 80.0 /"
    with open(env_file, "w") as f:
        f.write("\n".join(env_lines_arr) + "\n")
        
    subprocess.run([bin_path, file_root], capture_output=True, text=True)
    
    # Parse Arrivals
    arrivals = []
    if os.path.exists(arr_file):
        with open(arr_file, "r") as f:
            f.readline()
            f.readline()
            f.readline()
            f.readline()
            f.readline()
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
        if os.path.exists(ray_file): os.remove(ray_file)
        if os.path.exists(arr_file): os.remove(arr_file)
        for ext in ['.shd', '.prt']:
            path = file_root + ext
            if os.path.exists(path): os.remove(path)
    except OSError:
        pass
        
    return rays, arrivals

def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    workspace_dir = os.path.abspath(os.path.join(script_dir, "..", ".."))
    bin_path = os.path.join(workspace_dir, "bellhopcuda", "bellhopcxx.exe")
    output_dir = os.path.abspath(os.path.join(script_dir, "..", "output"))
    os.makedirs(output_dir, exist_ok=True)
    
    print("Running simulation for SD = 0.1m...")
    rays_1m, arr_1m = run_single_sim(0.1, bin_path, script_dir)
    
    print("Running simulation for SD = 10m...")
    rays_10m, arr_10m = run_single_sim(10.0, bin_path, script_dir)
    
    # Simulate Received Signals for both (incorporating Doppler)
    fs = 48000
    duration = 4.0
    t = np.arange(0, duration, 1/fs)
    
    # Source signal
    np.random.seed(42)
    white_noise = np.random.normal(0, 1.0, size=len(t))
    white_fft = np.fft.rfft(white_noise)
    freqs_src = np.fft.rfftfreq(len(t), d=1/fs)
    envelope = 1.0 / (1.0 + (freqs_src / 100.0)**0.8)
    colored_noise = np.fft.irfft(white_fft * envelope, n=len(t))
    colored_noise = colored_noise / np.std(colored_noise) * 2.0
    
    tonals = [(60.0, 5.0), (120.0, 3.5), (300.0, 2.0), (600.0, 1.5), (1200.0, 1.0)]
    source_signal = colored_noise.copy()
    for f_t, amp_t in tonals:
        source_signal += amp_t * np.sin(2 * np.pi * f_t * t)
        
    v_s = 5.0
    c_ref_1m = 1520.0
    c_ref_10m = 1513.3
    
    def synthesize_signal(arrs, c_ref, apply_waves=False):
        rx = np.zeros_like(t)
        np.random.seed(123)
        for arr in arrs:
            tau = arr['delay']
            amp = arr['amp']
            phase_deg = arr['phase']
            if apply_waves and arr['surface_bounces'] > 0:
                # Apply 90 deg phase perturbation due to wave scattering
                phase_deg += np.random.normal(0, 90.0)
            phase_rad = np.radians(phase_deg)
            src_angle_rad = np.radians(arr['src_angle'])
            v_proj = v_s * np.cos(src_angle_rad)
            doppler_scale = (c_ref - v_proj) / c_ref
            t_shifted = (t - tau) * doppler_scale
            rx += amp * np.interp(t_shifted, t, source_signal, left=0, right=0) * np.cos(phase_rad)
        rx += np.random.normal(0, 0.05, size=len(t))
        return rx
        
    rx_1m_flat = synthesize_signal(arr_1m, c_ref_1m, apply_waves=False)
    rx_1m_waves = synthesize_signal(arr_1m, c_ref_1m, apply_waves=True)
    rx_10m = synthesize_signal(arr_10m, c_ref_10m, apply_waves=False)
    
    # PSD analysis
    from scipy.signal import welch
    def get_psd(x):
        f_p, p_est = welch(x, fs, nperseg=8192, noverlap=4096)
        return f_p, 10 * np.log10(p_est + 1e-15)
        
    f_psd, psd_src = get_psd(source_signal)
    _, psd_rx_1m_flat = get_psd(rx_1m_flat)
    _, psd_rx_1m_waves = get_psd(rx_1m_waves)
    _, psd_rx_10m = get_psd(rx_10m)
    
    # 4-panel comparison plotting
    plt.style.use('dark_background')
    fig, axes = plt.subplots(2, 2, figsize=(18, 12))
    fig.suptitle("Source Depth Propagation & Receiver Multipath Comparison (Shallow Water: 30m)", fontsize=16, fontweight='bold', color='#E2E8F0')
    
    # Plot formatting helpers
    def format_ray_plot(ax, title_str, sd_val):
        ax.set_title(title_str, fontsize=12, fontweight='bold', color='#E2E8F0')
        ax.set_xlabel('Range (km)', color='#94A3B8')
        ax.set_ylabel('Depth (m)', color='#94A3B8')
        ax.axhline(0, color='#0284C7', linewidth=2, label='Ocean Surface')
        ax.axhline(30.0, color='#78350F', linewidth=2.5, label='Sea Floor')
        ax.plot(0, sd_val, 'go', markersize=10, markeredgecolor='white', label=f'Source ({sd_val}m)', zorder=5)
        ax.plot(0.5, 15.0, 'r^', markersize=10, markeredgecolor='white', label='Receiver (15m)', zorder=5)
        ax.invert_yaxis()
        ax.set_xlim(-0.02, 0.52)
        ax.set_ylim(35, -2)
        ax.grid(True, linestyle=':', alpha=0.3, color='#475569')
        
    def plot_rays(ax, rays):
        for r in rays:
            b = r['bottom_bounces'] + r['surface_bounces']
            if b == 0: color = '#10B981'; alpha = 0.8; lw = 1.2
            elif r['surface_bounces'] > 0 and r['bottom_bounces'] == 0: color = '#3B82F6'; alpha = 0.5; lw = 0.8
            elif r['bottom_bounces'] > 0 and r['surface_bounces'] == 0: color = '#F59E0B'; alpha = 0.5; lw = 0.8
            else: color = '#EC4899'; alpha = 0.4; lw = 0.6
            ax.plot(r['r'], r['z'], color=color, alpha=alpha, linewidth=lw)
            
    # Panel 1: Ray tracing SD = 0.1m
    format_ray_plot(axes[0, 0], "Ray Paths: Source at 0.1m (Right beneath Surface)", 0.1)
    plot_rays(axes[0, 0], rays_1m)
    axes[0, 0].legend(loc='lower left', frameon=True, facecolor='#1E293B', edgecolor='none')
    
    # Panel 2: Ray tracing SD = 10m
    format_ray_plot(axes[0, 1], "Ray Paths: Source at 10m (Deeper in Waveguide)", 10.0)
    plot_rays(axes[0, 1], rays_10m)
    axes[0, 1].legend(loc='lower left', frameon=True, facecolor='#1E293B', edgecolor='none')
    
    # Panel 3: Channel Impulse Response Comparison
    ax_ir = axes[1, 0]
    ax_ir.set_title("Channel Impulse Response Comparison", fontsize=12, fontweight='bold', color='#E2E8F0')
    
    # 0.1m arrivals (stems pointing up)
    d_1m = [a['delay'] for a in arr_1m]
    amp_1m = [a['amp'] for a in arr_1m]
    m1, s1, b1 = ax_ir.stem(d_1m, amp_1m, linefmt='#38BDF8', markerfmt='o', basefmt=" ")
    plt.setp(m1, 'color', '#38BDF8', 'label', f'SD=0.1m ({len(arr_1m)} arrivals)', 'markersize', 6)
    plt.setp(s1, 'color', '#38BDF8', 'alpha', 0.5)
    
    # 10m arrivals (stems pointing down/up but different color)
    d_10m = [a['delay'] for a in arr_10m]
    amp_10m = [a['amp'] for a in arr_10m]
    m2, s2, b2 = ax_ir.stem(d_10m, amp_10m, linefmt='#F43F5E', markerfmt='s', basefmt=" ")
    plt.setp(m2, 'color', '#F43F5E', 'label', f'SD=10m ({len(arr_10m)} arrivals)', 'markersize', 5)
    plt.setp(s2, 'color', '#F43F5E', 'alpha', 0.5)
    
    ax_ir.set_xlabel('Delay (s)', color='#94A3B8')
    ax_ir.set_ylabel('Arrival Amplitude', color='#94A3B8')
    ax_ir.grid(True, linestyle=':', alpha=0.3, color='#475569')
    ax_ir.legend(loc='upper right', frameon=True, facecolor='#1E293B', edgecolor='none')
    
    # Panel 4: Power Spectral Density comparison
    ax_psd = axes[1, 1]
    ax_psd.plot(f_psd, psd_rx_1m_flat, color='#F43F5E', linewidth=1.5, label='SD=0.1m (Flat Sea - Cancelled)')
    ax_psd.plot(f_psd, psd_rx_1m_waves, color='#10B981', linewidth=1.5, label="SD=0.1m (Rough Sea/Waves - Sound Arrives)")
    ax_psd.plot(f_psd, psd_rx_10m, color='#38BDF8', linewidth=1.5, label='Received PSD (SD=10m)')
    ax_psd.plot(f_psd, psd_src - 20, color='#94A3B8', alpha=0.5, linestyle='--', linewidth=1.0, label='Source PSD (Scaled)')
    
    ax_psd.set_xscale('log')
    ax_psd.set_xlim(20, 20000)
    ax_psd.set_ylim(-80, 20)
    ax_psd.set_title('Narrowband Received Spectrum Comparison', fontsize=12, fontweight='bold', color='#E2E8F0')
    ax_psd.set_xlabel('Frequency (Hz)', color='#94A3B8')
    ax_psd.set_ylabel('Power Spectral Density (dB)', color='#94A3B8')
    ticks = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]
    tick_labels = ['20 Hz', '50 Hz', '100 Hz', '200 Hz', '500 Hz', '1 kHz', '2 kHz', '5 kHz', '10 kHz', '20 kHz']
    ax_psd.set_xticks(ticks)
    ax_psd.set_xticklabels(tick_labels)
    ax_psd.grid(True, which='both', linestyle=':', alpha=0.3, color='#475569')
    ax_psd.legend(loc='upper right', frameon=True, facecolor='#1E293B', edgecolor='none')
    
    plt.tight_layout()
    output_image = os.path.join(output_dir, "bellhop_depth_comparison.png")
    plt.savefig(output_image, dpi=300, facecolor='#0F172A')
    plt.close()
    print(f"Comparison plot saved to: {output_image}")

if __name__ == "__main__":
    main()
