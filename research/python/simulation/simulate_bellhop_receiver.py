import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'analysis')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'plotting')))
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..', 'simulation')))

import os
import subprocess
import numpy as np
import matplotlib.pyplot as plt

def run_bellhop_receiver_simulation():
    # 1. Define Paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    workspace_dir = os.path.abspath(os.path.join(script_dir, "..", "..", ".."))
    bin_path = os.path.join(workspace_dir, "bellhopcuda", "bellhopcxx.exe")
    
    # Output directory for images
    output_dir = os.path.abspath(os.path.join(script_dir, "..", "..", "output"))
    os.makedirs(output_dir, exist_ok=True)
    
    # Temporary files
    env_file = os.path.join(script_dir, "munk_receiver.env")
    arr_file = os.path.join(script_dir, "munk_receiver.arr")
    
    # 2. Define Sound Speed Profile for Shallow Water (50m)
    z_min = 0.0
    z_max = 30.0
    z_axis = np.linspace(z_min, z_max, 31)
    ssp_c = np.linspace(1520.0, 1500.0, 31) # Downward refracting profile
    
    # 3. Create .env File Content (Arrivals Mode)
    env_lines = [
        "'Shallow water receiver simulation (30m)'",  # Title
        "100.0",                               # Frequency (Hz)
        "1",                                   # Number of media layers
        "'SVF'",                               # SSPOPT: Spline, Vacuum, Flat bottom
        f"{len(z_axis)} {z_min:.1f} {z_max:.1f}"
    ]
    
    # Add SSP
    for z, c in zip(z_axis, ssp_c):
        env_lines.append(f"{z:.2f} {c:.2f} /")
        
    # Add bottom properties
    env_lines.extend([
        "'A' 0.0",
        f"{z_max:.1f} 1600.0 0.0 1.5 0.2 /",
        "1",                    # NSD
        "10.0 /",               # SD (m)
        "1",                    # NRD
        "15.0 /",               # RD (m)
        "1",                    # NR
        "0.5 /",                # R (km) - BELLHOP expects km here
        "'A'",                  # RunType: 'A' for Arrivals
        "801",                  # Number of beams (increased)
        "-80.0 80.0 /",         # Launch angles (deg)
        "0.0 60.0 1.0"          # STEP, ZBOX, RBOX
    ])
    
    # Write to env file
    with open(env_file, "w") as f:
        f.write("\n".join(env_lines) + "\n")
        
    print(f"Environment file written to {env_file}")
    
    # 4. Run BELLHOP
    file_root = os.path.splitext(env_file)[0]
    print(f"Running BELLHOP on {file_root} in arrivals mode...")
    res = subprocess.run([bin_path, file_root], capture_output=True, text=True)
    if res.returncode != 0:
        print("Error running BELLHOP:")
        print(res.stdout)
        print(res.stderr)
        return
        
    print("BELLHOP run finished successfully.")
    
    # 5. Parse the .arr output file
    if not os.path.exists(arr_file):
        print(f"Error: Arrivals file {arr_file} was not generated.")
        return
        
    print(f"Parsing arrivals from {arr_file}...")
    with open(arr_file, "r") as f:
        type_str = f.readline().strip().strip("'")
        freq = float(f.readline().strip().strip("'"))
        # Skip NSD, NRD, NR lines
        f.readline()
        f.readline()
        f.readline()
        
        # Read number of arrivals
        narr = int(f.readline().strip())
        f.readline() # Read max arrivals line
        
        arrivals = []
        for _ in range(narr):
            line = f.readline()
            if not line:
                break
            tokens = line.split()
            amp = float(tokens[0])
            phase = float(tokens[1])
            delay = float(tokens[2])
            src_angle = float(tokens[4])
            rcvr_angle = float(tokens[5])
            b_bounces = int(tokens[6])
            s_bounces = int(tokens[7])
            
            arrivals.append({
                'amp': amp,
                'phase': phase,
                'delay': delay,
                'src_angle': src_angle,
                'rcvr_angle': rcvr_angle,
                'bottom_bounces': b_bounces,
                'surface_bounces': s_bounces
            })
            
    print(f"Successfully parsed {len(arrivals)} arrivals.")
    
    # 6. Signal Simulation at the Receiver
    fs = 48000 # Sample rate
    duration = 4.0 # 4 seconds duration
    t = np.arange(0, duration, 1/fs)
    
    # Source signal: Colored Noise + Tonals
    np.random.seed(42)
    white_noise = np.random.normal(0, 1.0, size=len(t))
    # Apply low-pass filter to simulate colored noise (approx. -8dB/dec slope)
    white_fft = np.fft.rfft(white_noise)
    freqs_src = np.fft.rfftfreq(len(t), d=1/fs)
    envelope = 1.0 / (1.0 + (freqs_src / 100.0)**0.8)
    colored_noise = np.fft.irfft(white_fft * envelope, n=len(t))
    colored_noise = colored_noise / np.std(colored_noise) * 2.0
    
    # Add Tonal components
    # 60 Hz, 120 Hz, 300 Hz, 600 Hz, 1200 Hz
    tonals = [(60.0, 5.0), (120.0, 3.5), (300.0, 2.0), (600.0, 1.5), (1200.0, 1.0)]
    source_signal = colored_noise.copy()
    for f_t, amp_t in tonals:
        source_signal += amp_t * np.sin(2 * np.pi * f_t * t)
        
    # Received signal synthesis using multi-path arrivals
    # y_rx(t) = sum_i A_i * x_src((t - tau_i) * doppler_scale_i)
    received_signal = np.zeros_like(t)
    v_s = 5.0  # Source velocity of 5.0 m/s moving horizontally toward the receiver
    c_ref = 1513.3 # Approximate sound speed at 10m source depth in 30m water column
    
    for arr in arrivals:
        tau = arr['delay']
        amp = arr['amp']
        phase_rad = np.radians(arr['phase'])
        src_angle_rad = np.radians(arr['src_angle'])
        
        # Calculate projection of velocity onto the launch ray path
        # src_angle of 0 is horizontal. cos(src_angle) gives the horizontal projection
        v_proj = v_s * np.cos(src_angle_rad)
        doppler_scale = (c_ref - v_proj) / c_ref
        
        # Interpolate the Doppler-scaled and delayed signal
        t_shifted = (t - tau) * doppler_scale
        shifted_src = np.interp(t_shifted, t, source_signal, left=0, right=0)
        
        # Apply amplitude and phase scaling
        received_signal += amp * shifted_src * np.cos(phase_rad)
            
    # Add some local receiver ambient noise
    received_signal += np.random.normal(0, 0.05, size=len(t))
    
    # 7. Welch PSD analysis
    def compute_psd(x, fs):
        from scipy.signal import welch
        f_p, p_est = welch(x, fs, nperseg=8192, noverlap=4096)
        return f_p, 10 * np.log10(p_est + 1e-15)
        
    f_psd, psd_src = compute_psd(source_signal, fs)
    _, psd_rx = compute_psd(received_signal, fs)
    
    # 8. Plotting (Dark Theme)
    plt.style.use('dark_background')
    fig, axes = plt.subplots(3, 1, figsize=(14, 12))
    
    # Panel 1: Channel Impulse Response
    ax_ir = axes[0]
    delays = [arr['delay'] for arr in arrivals]
    amps = [arr['amp'] for arr in arrivals]
    # Classify by bounces for coloring
    colors = []
    for arr in arrivals:
        if arr['bottom_bounces'] + arr['surface_bounces'] == 0:
            colors.append('#10B981') # Green (Direct)
        elif arr['surface_bounces'] > 0 and arr['bottom_bounces'] == 0:
            colors.append('#3B82F6') # Blue (Surface)
        elif arr['bottom_bounces'] > 0 and arr['surface_bounces'] == 0:
            colors.append('#F59E0B') # Amber (Bottom)
        else:
            colors.append('#EC4899') # Pink (Multi-bounce)
            
    markerline, stemlines, baseline = ax_ir.stem(delays, amps, basefmt=" ")
    plt.setp(stemlines, 'color', '#475569', 'linewidth', 1.5)
    plt.setp(markerline, 'markersize', 8, 'markeredgecolor', 'white')
    # Set individual colors for markers
    for idx, (d, a) in enumerate(zip(delays, amps)):
        ax_ir.plot(d, a, 'o', color=colors[idx], markersize=8, markeredgecolor='white')
        
    ax_ir.set_title('Channel Impulse Response (Arrivals at Receiver)', fontsize=12, fontweight='bold', color='#E2E8F0')
    ax_ir.set_xlabel('Delay (s)', color='#94A3B8')
    ax_ir.set_ylabel('Amplitude', color='#94A3B8')
    ax_ir.grid(True, linestyle=':', alpha=0.3, color='#475569')
    
    # Custom legend for Impulse Response
    from matplotlib.lines import Line2D
    custom_legend = [
        Line2D([0], [0], marker='o', color='none', markerfacecolor='#10B981', markeredgecolor='white', markersize=8, label='Direct Path'),
        Line2D([0], [0], marker='o', color='none', markerfacecolor='#3B82F6', markeredgecolor='white', markersize=8, label='Surface Reflected'),
        Line2D([0], [0], marker='o', color='none', markerfacecolor='#F59E0B', markeredgecolor='white', markersize=8, label='Bottom Reflected'),
        Line2D([0], [0], marker='o', color='none', markerfacecolor='#EC4899', markeredgecolor='white', markersize=8, label='Multi-bounce')
    ]
    ax_ir.legend(handles=custom_legend, loc='upper right', frameon=True, facecolor='#1E293B', edgecolor='none')
    
    # Panel 2: Time Domain Signals (Zoomed)
    ax_time = axes[1]
    # Zoom in to a window where the signals are active
    # Find the first arrival delay to start zoom window
    first_delay = min(delays) if delays else 0.0
    t_start = first_delay - 0.05
    t_end = t_start + 0.15
    idx_zoom = (t >= t_start) & (t <= t_end)
    
    ax_time.plot(t[idx_zoom], source_signal[idx_zoom], color='#94A3B8', alpha=0.5, linewidth=1.2, label='Source Signal')
    ax_time.plot(t[idx_zoom], received_signal[idx_zoom], color='#38BDF8', linewidth=1.5, label='Received Signal (Multi-path)')
    ax_time.set_title(f'Waveforms in Time Domain (Zoomed Window: {t_start:.3f}s to {t_end:.3f}s)', fontsize=12, fontweight='bold', color='#E2E8F0')
    ax_time.set_xlabel('Time (s)', color='#94A3B8')
    ax_time.set_ylabel('Amplitude', color='#94A3B8')
    ax_time.grid(True, linestyle=':', alpha=0.3, color='#475569')
    ax_time.legend(loc='upper right', frameon=True, facecolor='#1E293B', edgecolor='none')
    
    # Panel 3: Welch PSD Comparison
    ax_psd = axes[2]
    ax_psd.plot(f_psd, psd_src, color='#94A3B8', alpha=0.5, linewidth=1.2, label='Source PSD')
    ax_psd.plot(f_psd, psd_rx, color='#38BDF8', linewidth=1.5, label='Received PSD')
    ax_psd.set_xscale('log')
    ax_psd.set_xlim(20, 20000)
    ax_psd.set_ylim(-80, 20)
    ax_psd.set_title('Narrowband Welch PSD (Source vs Received)', fontsize=12, fontweight='bold', color='#E2E8F0')
    ax_psd.set_xlabel('Frequency (Hz)', color='#94A3B8')
    ax_psd.set_ylabel('Power Spectral Density (dB)', color='#94A3B8')
    
    # Set frequency ticks nicely
    ticks = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000]
    tick_labels = ['20 Hz', '50 Hz', '100 Hz', '200 Hz', '500 Hz', '1 kHz', '2 kHz', '5 kHz', '10 kHz', '20 kHz']
    ax_psd.set_xticks(ticks)
    ax_psd.set_xticklabels(tick_labels)
    ax_psd.grid(True, which='both', linestyle=':', alpha=0.3, color='#475569')
    ax_psd.legend(loc='upper right', frameon=True, facecolor='#1E293B', edgecolor='none')
    
    plt.tight_layout()
    output_image = os.path.join(output_dir, "bellhop_receiver_simulation.png")
    plt.savefig(output_image, dpi=300, facecolor='#0F172A')
    plt.close()
    
    print(f"Receiver simulation visualization saved to: {output_image}")
    
    # 7.5 Save signals as WAV files for the user
    import scipy.io.wavfile as wav
    def save_normalized_wav(path, data, rate):
        max_val = np.max(np.abs(data))
        norm_data = (data / max_val * 0.9) if max_val > 0 else data
        wav.write(path, rate, norm_data.astype(np.float32))
        
    src_wav_path = os.path.join(output_dir, "simulated_source.wav")
    rx_wav_path = os.path.join(output_dir, "simulated_received.wav")
    
    save_normalized_wav(src_wav_path, source_signal, fs)
    save_normalized_wav(rx_wav_path, received_signal, fs)
    print(f"Saved source audio signal to: {src_wav_path}")
    print(f"Saved received audio signal to: {rx_wav_path}")
    
    # Cleanup env and arr files
    try:
        os.remove(env_file)
        os.remove(arr_file)
        for ext in ['.shd', '.ray', '.prt']:
            path = file_root + ext
            if os.path.exists(path):
                os.remove(path)
    except OSError as e:
        print(f"Error cleaning up temp files: {e}")

if __name__ == "__main__":
    run_bellhop_receiver_simulation()
