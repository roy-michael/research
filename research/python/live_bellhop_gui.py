"""
live_bellhop_gui.py
Interactive Live BELLHOP Acoustic Ray-Tracing & Multipath Simulator.
Allows dragging the Source (Red Star) and Receiver (Green Circle) anywhere in the water column
and immediately recalculates & renders BELLHOP ray paths, multipath arrivals, and received audio in real time.
"""

import os
import subprocess
import numpy as np
import matplotlib.pyplot as plt

class LiveBellhopSimulator:
    def __init__(self):
        self.script_dir = os.path.dirname(os.path.abspath(__file__))
        self.workspace_dir = os.path.abspath(os.path.join(self.script_dir, "..", ".."))
        self.bin_path = os.path.join(self.workspace_dir, "bellhopcuda", "bellhopcxx.exe")
        
        if not os.path.exists(self.bin_path):
            self.bin_path = "bellhop.exe"
            
        self.output_dir = os.path.abspath(os.path.join(self.script_dir, "..", "output"))
        os.makedirs(self.output_dir, exist_ok=True)
        
        self.env_file = os.path.join(self.script_dir, "live_sim.env")
        self.file_root = os.path.join(self.script_dir, "live_sim")
        self.ray_file = os.path.join(self.script_dir, "live_sim.ray")
        self.arr_file = os.path.join(self.script_dir, "live_sim.arr")
        
        # Default Ocean Parameters
        self.water_depth = 50.0 # meters
        self.max_range_km = 1.0  # kilometers
        self.freq_hz = 500.0
        
        # Initial Source & Receiver Coordinates
        self.src_range_km = 0.0
        self.src_depth_m = 10.0
        self.rcv_range_km = 0.6
        self.rcv_depth_m = 25.0
        
        # Dragging & Busy State
        self.active_drag = None # 'source' or 'receiver'
        self.is_busy = False
        
        # Setup Figure Layout
        self.setup_ui()
        self.update_simulation()

    def setup_ui(self):
        plt.ion()
        self.fig = plt.figure(figsize=(14, 9), num="Live Interactive BELLHOP Acoustic Simulator")
        
        # Grid Spec: Top = Ray Trace (60% height), Bottom = Arrivals (40% height)
        self.ax_rays = plt.subplot2grid((3, 2), (0, 0), colspan=2, rowspan=2)
        self.ax_arr = plt.subplot2grid((3, 2), (2, 0), colspan=2)
        
        plt.subplots_adjust(left=0.08, right=0.95, top=0.92, bottom=0.12, hspace=0.35)
        
        # Connect Mouse Events for Drag and Drop
        self.fig.canvas.mpl_connect('button_press_event', self.on_press)
        self.fig.canvas.mpl_connect('motion_notify_event', self.on_motion)
        self.fig.canvas.mpl_connect('button_release_event', self.on_release)

    def write_env_file(self, run_type='R'):
        """Writes BELLHOP .env file for Ray Tracing ('R') or Arrivals ('A')"""
        z_ssp = np.array([0.0, 10.0, 25.0, self.water_depth])
        c_ssp = np.array([1520.0, 1515.0, 1505.0, 1495.0])
        
        env_lines = [
            f"'Live BELLHOP Simulation ({run_type})'",
            f"{self.freq_hz:.1f}",
            "1",
            "'SVF'",
            f"{len(z_ssp)} {z_ssp[0]:.1f} {z_ssp[-1]:.1f}"
        ]
        
        for z, c in zip(z_ssp, c_ssp):
            env_lines.append(f"{z:.2f} {c:.2f} /")
            
        env_lines.extend([
            "'A' 0.0",
            f"{self.water_depth:.1f} 1600.0 0.0 1.5 0.2 /",
            "1",
            f"{self.src_depth_m:.2f} /",
            "1",
            f"{self.rcv_depth_m:.2f} /",
            "1",
            f"{self.rcv_range_km:.3f} /",
            f"'{run_type}'",
            "201",  # Number of beams
            "-45.0 45.0 /",
            "0.0 60.0 1.2"
        ])
        
        with open(self.env_file, "w") as f:
            f.write("\n".join(env_lines) + "\n")

    def run_bellhop(self, run_type='R'):
        self.write_env_file(run_type)
        try:
            subprocess.run([self.bin_path, self.file_root], capture_output=True, text=True, check=True)
        except Exception as e:
            pass

    def read_ray_file(self):
        """Parses BELLHOP .ray output file"""
        rays = []
        if not os.path.exists(self.ray_file):
            return rays
            
        try:
            with open(self.ray_file, 'r') as f:
                lines = f.readlines()
                
            if len(lines) < 7:
                return rays
                
            idx = 7
            while idx < len(lines):
                line = lines[idx].strip()
                if not line:
                    idx += 1; continue
                tokens = line.split()
                if len(tokens) >= 2 and tokens[0].replace('.', '', 1).replace('-', '', 1).isdigit():
                    try:
                        nsteps = int(tokens[0])
                    except ValueError:
                        idx += 1; continue
                    idx += 1
                    r_coords = []
                    z_coords = []
                    for _ in range(nsteps):
                        if idx >= len(lines): break
                        step_tokens = lines[idx].strip().split()
                        if len(step_tokens) >= 2:
                            r_coords.append(float(step_tokens[0]))
                            z_coords.append(float(step_tokens[1]))
                        idx += 1
                    if r_coords:
                        rays.append((np.array(r_coords), np.array(z_coords)))
                else:
                    idx += 1
        except Exception:
            pass
        return rays

    def read_arr_file(self):
        """Parses BELLHOP .arr output file"""
        arrivals = []
        if not os.path.exists(self.arr_file):
            return arrivals
            
        try:
            with open(self.arr_file, "r") as f:
                lines = f.readlines()
                
            if len(lines) < 6:
                return arrivals
                
            narr = int(lines[5].strip())
            for i in range(7, 7 + narr):
                if i >= len(lines): break
                tokens = lines[i].strip().split()
                if len(tokens) >= 8:
                    arrivals.append({
                        'amp': float(tokens[0]),
                        'phase': float(tokens[1]),
                        'delay': float(tokens[2]),
                        'bottom_bounces': int(tokens[6]),
                        'surface_bounces': int(tokens[7])
                    })
        except Exception:
            pass
        return arrivals

    def update_simulation(self):
        if self.is_busy:
            return
        self.is_busy = True
        
        try:
            # Delete stale files to ensure clean updates
            if os.path.exists(self.ray_file):
                try: os.remove(self.ray_file)
                except Exception: pass
            if os.path.exists(self.arr_file):
                try: os.remove(self.arr_file)
                except Exception: pass
                
            # 1. Run Ray Tracing
            self.run_bellhop('R')
            rays = self.read_ray_file()
            
            # 2. Run Arrivals Calculation
            self.run_bellhop('A')
            arrivals = self.read_arr_file()
            
            # 3. Draw Ray Trace Axes
            self.ax_rays.clear()
            self.ax_rays.set_facecolor('#0f172a') # Deep dark ocean background
            
            # Plot ocean boundaries
            self.ax_rays.axhline(0, color='#38bdf8', linewidth=2, label='Sea Surface')
            self.ax_rays.axhline(self.water_depth, color='#b45309', linewidth=3, label='Seabed (1600 m/s)')
            
            # Plot Rays
            for r_coords, z_coords in rays:
                r_km = r_coords / 1000.0 if np.max(r_coords) > 10.0 else r_coords
                self.ax_rays.plot(r_km, z_coords, color='#38bdf8', alpha=0.35, linewidth=0.8)
                
            # Draw Source Handle (Red Star)
            self.ax_rays.plot(self.src_range_km, self.src_depth_m, 'r*', markersize=16, 
                              markeredgecolor='white', markeredgewidth=1.5, label=f'Source ({self.src_depth_m:.1f}m)')
            
            # Draw Receiver Handle (Green Circle)
            self.ax_rays.plot(self.rcv_range_km, self.rcv_depth_m, 'go', markersize=14, 
                              markeredgecolor='white', markeredgewidth=1.5, label=f'Receiver ({self.rcv_range_km*1000:.0f}m, {self.rcv_depth_m:.1f}m)')
            
            # Direct line from Source to Receiver
            self.ax_rays.plot([self.src_range_km, self.rcv_range_km], [self.src_depth_m, self.rcv_depth_m], 
                              'w--', alpha=0.4, linewidth=1.0)
            
            self.ax_rays.set_xlim([0, self.max_range_km])
            self.ax_rays.set_ylim([self.water_depth + 2, -2]) # Inverted depth axis
            self.ax_rays.set_xlabel('Range [km]', fontsize=11, fontweight='bold')
            self.ax_rays.set_ylabel('Depth [m]', fontsize=11, fontweight='bold')
            self.ax_rays.set_title(f'Live Acoustic Ray Tracing (Drag Source/Receiver handles!) | Freq: {self.freq_hz:.0f} Hz', 
                                   fontsize=12, fontweight='bold', pad=10)
            self.ax_rays.grid(True, linestyle=':', alpha=0.4, color='#94a3b8')
            self.ax_rays.legend(loc='lower right', facecolor='#1e293b', edgecolor='white', labelcolor='white')
            
            # 4. Draw Arrivals Axes (Impulse Response showing attenuation)
            self.ax_arr.clear()
            self.ax_arr.set_facecolor('#0f172a')
            
            if arrivals:
                delays = np.array([a['delay'] * 1000.0 for a in arrivals]) # Convert to ms
                amps = np.array([a['amp'] for a in arrivals])
                surf_b = np.array([a['surface_bounces'] for a in arrivals])
                bot_b = np.array([a['bottom_bounces'] for a in arrivals])
                
                # Plot absolute amplitudes directly to show distance attenuation
                markerline, stemlines, baseline = self.ax_arr.stem(delays, amps, linefmt='c-', markerfmt='co', basefmt='r-')
                plt.setp(markerline, 'markersize', 7, 'color', '#38bdf8')
                plt.setp(stemlines, 'linewidth', 1.5, 'color', '#38bdf8')
                
                for d, a, sb, bb in zip(delays, amps, surf_b, bot_b):
                    color = '#22c55e' if (sb == 0 and bb == 0) else ('#f59e0b' if sb > 0 else '#ef4444')
                    self.ax_arr.plot(d, a, 'o', color=color, markersize=8)
                    self.ax_arr.text(d, a + np.max(amps)*0.05, f"S{sb}/B{bb}", color='white', fontsize=8, ha='center')
                    
                self.ax_arr.set_title(f'Live Channel Impulse Response (Total Multipath Rays Reaching Receiver: {len(arrivals)})', 
                                      fontsize=11, fontweight='bold', color='black')
                self.ax_arr.set_ylim([0, max(0.15, np.max(amps)*1.2)])
            else:
                self.ax_arr.text(0.5, 0.5, 'No rays reach receiver at this position', color='white', 
                                 fontsize=12, ha='center', va='center')
                self.ax_arr.set_title('Live Channel Impulse Response', fontsize=11, fontweight='bold')
                self.ax_arr.set_ylim([0, 0.15])
                
            self.ax_arr.set_xlabel('Travel Time Delay [ms]', fontsize=11, fontweight='bold')
            self.ax_arr.set_ylabel('Absolute Amplitude |P/P0|', fontsize=11, fontweight='bold')
            self.ax_arr.grid(True, linestyle=':', alpha=0.4, color='#94a3b8')
            
            self.fig.canvas.draw_idle()
        finally:
            self.is_busy = False

    # --- Mouse Event Handlers for Drag and Drop ---
    def on_press(self, event):
        if event.inaxes != self.ax_rays:
            return
        if event.xdata is None or event.ydata is None:
            return
            
        click_r = event.xdata
        click_z = event.ydata
        
        # Distance to Source
        d_src = np.hypot(click_r - self.src_range_km, (click_z - self.src_depth_m) / 100.0)
        # Distance to Receiver
        d_rcv = np.hypot(click_r - self.rcv_range_km, (click_z - self.rcv_depth_m) / 100.0)
        
        threshold = 0.1
        if d_src < threshold and d_src <= d_rcv:
            self.active_drag = 'source'
        elif d_rcv < threshold:
            self.active_drag = 'receiver'
        else:
            self.active_drag = None

    def on_motion(self, event):
        if self.active_drag is None or event.inaxes != self.ax_rays:
            return
        if event.xdata is None or event.ydata is None:
            return
            
        new_r = np.clip(event.xdata, 0.0, self.max_range_km)
        new_z = np.clip(event.ydata, 1.0, self.water_depth - 1.0)
        
        if self.active_drag == 'source':
            self.src_range_km = new_r
            self.src_depth_m = new_z
        elif self.active_drag == 'receiver':
            self.rcv_range_km = new_r
            self.rcv_depth_m = new_z
            
        self.update_simulation()

    def on_release(self, event):
        self.active_drag = None

if __name__ == "__main__":
    print("Starting Live Interactive BELLHOP Simulator...")
    sim = LiveBellhopSimulator()
    plt.show(block=True)
