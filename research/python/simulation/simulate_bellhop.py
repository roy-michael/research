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
from matplotlib.colors import LinearSegmentedColormap

def run_bellhop_simulation():
    # 1. Define Paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    workspace_dir = os.path.abspath(os.path.join(script_dir, "..", "..", ".."))
    bin_path = os.path.join(workspace_dir, "bellhopcuda", "bellhopcxx.exe") # Use CPU version for stability/compatibility
    
    # Output directory for images
    output_dir = os.path.abspath(os.path.join(script_dir, "..", "..", "output", "bellhop"))
    os.makedirs(output_dir, exist_ok=True)
    
    # Temporary files in current directory
    env_file = os.path.join(script_dir, "munk_simulation.env")
    ray_file = os.path.join(script_dir, "munk_simulation.ray")
    
    # 2. Define Sound Speed Profile for Shallow Water (50m)
    z_min = 0.0
    z_max = 30.0
    z_axis = np.linspace(z_min, z_max, 31)
    ssp_c = np.linspace(1520.0, 1500.0, 31) # Downward refracting profile
    
    # 3. Create .env File Content
    env_lines = [
        "'Shallow water simulation (30m)'",  # Title
        "100.0",                     # Frequency (Hz)
        "1",                         # Number of media layers
        "'SVF'",                     # SSPOPT: Spline interpolation, Vacuum above, Flat bottom
        f"{len(z_axis)} {z_min:.1f} {z_max:.1f}"  # SSP points, min depth, max depth
    ]
    
    # Add SSP points
    for z, c in zip(z_axis, ssp_c):
        env_lines.append(f"{z:.2f} {c:.2f} /")
        
    # Add bottom properties
    env_lines.extend([
        "'A' 0.0",                   # Acoustic bottom halfspace, zero roughness
        f"{z_max:.1f} 1600.0 0.0 1.5 0.2 /", # Bottom depth, Cp, Cs, density, Ap
        "1",                         # Number of source depths (NSD)
        "10.0 /",                    # Source depth (SD)
        "1",                         # Number of receiver depths (NRD)
        "15.0 /",                    # Receiver depths
        "1",                         # Number of receiver ranges (NR)
        "0.5 /",                     # Receiver ranges (in km)
        "'R'",                       # RunType: 'R' for Ray trace
        "401",                       # Number of beams (increased)
        "-45.0 45.0 /",              # Launch angles (deg)
        "0.0 60.0 1.0"               # STEP, ZBOX, RBOX (RBOX in km)
    ])
    
    # Write to env file
    with open(env_file, "w") as f:
        f.write("\n".join(env_lines) + "\n")
        
    print(f"Environment file written to {env_file}")
    
    # 4. Run Bellhop Execution
    file_root = os.path.splitext(env_file)[0]
    print(f"Running BELLHOP on {file_root}...")
    res = subprocess.run([bin_path, file_root], capture_output=True, text=True)
    if res.returncode != 0:
        print("Error running BELLHOP:")
        print(res.stdout)
        print(res.stderr)
        return
        
    print("BELLHOP run finished successfully.")
    
    # 5. Parse the .ray output file
    if not os.path.exists(ray_file):
        print(f"Error: Ray file {ray_file} was not generated.")
        return
        
    print(f"Parsing ray paths from {ray_file}...")
    
    with open(ray_file, "r") as f:
        title = f.readline().strip().strip("'")
        freq = float(f.readline().strip().strip("'"))
        # Skip NMedia, NSD, NRD
        f.readline()
        # Read NBeams
        nbeams, _ = map(int, f.readline().split())
        # Skip until 'rz' header
        while True:
            line = f.readline().strip().strip("'")
            if line == 'rz':
                break
                
        rays = []
        for _ in range(nbeams):
            angle_line = f.readline()
            if not angle_line:
                break
            angle = float(angle_line.strip())
            stats_line = f.readline()
            npts, b_bounces, s_bounces = map(int, stats_line.split())
            
            r_coords = []
            z_coords = []
            for _ in range(npts):
                pt_line = f.readline()
                r, z = map(float, pt_line.split())
                r_coords.append(r)
                z_coords.append(z)
                
            rays.append({
                'angle': angle,
                'npts': npts,
                'bottom_bounces': b_bounces,
                'surface_bounces': s_bounces,
                'r': np.array(r_coords) / 1000.0, # Convert range to km
                'z': np.array(z_coords)
            })
            
    print(f"Successfully parsed {len(rays)} ray paths.")
    
    # 6. Plotting with Premium Aesthetics (Dark Theme / Sleek Design)
    plt.style.use('dark_background')
    fig, (ax_ssp, ax_rays) = plt.subplots(1, 2, figsize=(15, 8), gridspec_kw={'width_ratios': [1, 4]})
    fig.suptitle(f"BELLHOP Propagation Simulation (Freq: {freq:.1f} Hz)\nTitle: {title}", fontsize=14, fontweight='bold', color='#E2E8F0')
    
    # SSP Plot
    ax_ssp.plot(ssp_c, z_axis, color='#38BDF8', linewidth=2.5, label='Munk SSP')
    ax_ssp.set_title('Sound Speed Profile', fontsize=11, fontweight='bold', color='#94A3B8')
    ax_ssp.set_xlabel('Sound Speed (m/s)', color='#94A3B8')
    ax_ssp.set_ylabel('Depth (m)', color='#94A3B8')
    ax_ssp.invert_yaxis()
    ax_ssp.grid(True, linestyle=':', alpha=0.3, color='#475569')
    ax_ssp.legend(loc='lower left', frameon=True, facecolor='#1E293B', edgecolor='none')
    
    # Rays Plot
    # Customize colors based on ray interaction (direct vs bounced)
    ax_rays.set_title('Ray Path Simulation (Range-Depth)', fontsize=11, fontweight='bold', color='#94A3B8')
    ax_rays.set_xlabel('Range (km)', color='#94A3B8')
    ax_rays.set_ylabel('Depth (m)', color='#94A3B8')
    
    # Draw surface and bottom boundaries
    ax_rays.axhline(z_min, color='#0284C7', linewidth=2, label='Ocean Surface')
    ax_rays.axhline(z_max, color='#78350F', linewidth=2.5, label='Sea Floor')
    
    # Plot source location
    ax_rays.plot(0, 10.0, 'go', markersize=10, markeredgecolor='white', label='Source (10m)', zorder=5)
    
    # Color map for rays based on launch angle
    angles = [r['angle'] for r in rays]
    min_ang, max_ang = min(angles), max(angles)
    
    for r in rays:
        # Style based on bounces
        bounces = r['bottom_bounces'] + r['surface_bounces']
        if bounces == 0:
            color = '#10B981' # Green for direct path
            alpha = 0.8
            lw = 1.5
        elif r['surface_bounces'] > 0 and r['bottom_bounces'] == 0:
            color = '#3B82F6' # Blue for surface-only bounces
            alpha = 0.5
            lw = 1.0
        elif r['bottom_bounces'] > 0 and r['surface_bounces'] == 0:
            color = '#F59E0B' # Amber for bottom-only bounces
            alpha = 0.5
            lw = 1.0
        else:
            color = '#EC4899' # Pink/magenta for multiple bounces
            alpha = 0.4
            lw = 0.8
            
        ax_rays.plot(r['r'], r['z'], color=color, alpha=alpha, linewidth=lw)

    # Add custom handles to legend
    from matplotlib.lines import Line2D
    custom_legend = [
        Line2D([0], [0], color='#10B981', lw=2, label='Direct Rays'),
        Line2D([0], [0], color='#3B82F6', lw=1.5, label='Surface Reflected'),
        Line2D([0], [0], color='#F59E0B', lw=1.5, label='Bottom Reflected'),
        Line2D([0], [0], color='#EC4899', lw=1, label='Multi-bounce Rays'),
        Line2D([0], [0], marker='o', color='none', markerfacecolor='g', markeredgecolor='white', markersize=10, label='Source (10m)'),
        Line2D([0], [0], marker='^', color='none', markerfacecolor='r', markeredgecolor='white', markersize=10, label='Receiver (15m)')
    ]
    
    # Plot receiver location
    ax_rays.plot(0.5, 15.0, 'r^', markersize=10, markeredgecolor='white', zorder=5)
    
    ax_rays.invert_yaxis()
    ax_rays.set_xlim(-0.05, 0.55)
    ax_rays.set_ylim(z_max + 5, -5)
    ax_rays.grid(True, linestyle=':', alpha=0.3, color='#475569')
    ax_rays.legend(handles=custom_legend, loc='upper right', frameon=True, facecolor='#1E293B', edgecolor='none')
    
    # Save the output image
    output_image = os.path.join(output_dir, "bellhop_munk_simulation.png")
    plt.tight_layout()
    plt.savefig(output_image, dpi=300, facecolor='#0F172A')
    plt.close()
    
    print(f"Simulation visualization saved to: {output_image}")
    
    # 7. Clean up env and ray files
    try:
        os.remove(env_file)
        os.remove(ray_file)
        # Clean up other possible files generated by bellhop
        for ext in ['.shd', '.arr', '.prt']:
            path = file_root + ext
            if os.path.exists(path):
                os.remove(path)
    except OSError as e:
        print(f"Error cleaning up temp files: {e}")

if __name__ == "__main__":
    run_bellhop_simulation()
