import os
import http.server
import socketserver
import json
import urllib.parse
import numpy as np

PORT = 8000
c = 1500 # Speed of sound (m/s)

# --- Atomic Mathematical Components ---
g = 9.81 # Gravity (m/s^2)

def calc_grazing_angle(Hrec, Hsrc, R):
    """Calculates the reflection angle (theta_g) using the image source geometry."""
    return np.arctan((Hrec + Hsrc) / R)

def calc_heave_attenuation(Aw, fw, Hsrc):
    """Calculates the physical heave of the source (Asrc) at depth Hsrc based on deep-water wave dispersion."""
    # Wave number k = (2 * pi * f_w)^2 / g
    k = (2 * np.pi * fw)**2 / g
    return Aw * np.exp(-k * Hsrc)

def calc_modulation_index(f0, Asrc, theta_g, c):
    """Calculates the FM modulation index (beta) caused by the vertical heave of the source."""
    return (2 * np.pi * f0 / c) * Asrc * np.cos(theta_g)

def calc_doppler_spread(beta, fw):
    """Calculates the instantaneous frequency spread (delta F)."""
    return beta * fw

def calc_surface_wave_height(Aw, fw, t):
    """Calculates the time-varying height of the moving sea surface (hs(t))."""
    return Aw * np.sin(2 * np.pi * fw * t)

def calc_scattering_phase_multiplier(f0, theta_g, c):
    """Calculates the multiplier (alpha) for the Doppler phase shift caused by the dynamic boundary."""
    return (4 * np.pi * f0 / c) * np.sin(theta_g)

def calc_macroscopic_delay(Hsrc, Hrec, R, c):
    """Calculates the macroscopic time delay (dTau) between the direct path and the surface echo."""
    Rdir = np.sqrt(R**2 + (Hrec - Hsrc)**2)
    Rsurf = np.sqrt(R**2 + (Hrec + Hsrc)**2)
    return (Rsurf - Rdir) / c

def simulate_channel(f0, Hsrc, Aw, fw, R, Hrec, R0, t):
    """
    Unified generalized additive model for the Doubly Spread Channel.
    Includes:
    1. Direct & surface-reflected coherent multipath with (1 + R0) normalization
       ensuring the maximum possible constructive peak does not exceed the transmitted amplitude.
    2. Physical diffuse surface roughness ambient noise: as surface roughness increases
       (lower specular reflection R0 or higher Aw), standard ocean wind/wave acoustic noise
       is injected proportional to (1 - R0) and sea state.
    """
    # 1. Geometry and Attenuation
    theta_g = calc_grazing_angle(Hrec, Hsrc, R)
    Asrc = calc_heave_attenuation(Aw, fw, Hsrc)
    beta = calc_modulation_index(f0, Asrc, theta_g, c)
    deltaF = calc_doppler_spread(beta, fw)
    
    # 2. Surface Properties
    hs_t = calc_surface_wave_height(Aw, fw, t)
    alpha = calc_scattering_phase_multiplier(f0, theta_g, c)
    dTau = calc_macroscopic_delay(Hsrc, Hrec, R, c)
    
    # 3. Transmitted Signal (Heave Modulated, normalized to peak 1.0)
    p_tx = np.cos(2 * np.pi * f0 * t + beta * np.sin(2 * np.pi * fw * t))
    
    # 4. Generalized Received Signal (Normalized Additive Model)
    # Direct Path
    dirPath = np.cos(2 * np.pi * f0 * t + beta * np.sin(2 * np.pi * fw * t))
    
    # Surface Specular Path (delayed by dTau, and phase-shifted by dynamic boundary)
    surfacePhase = 2 * np.pi * f0 * (t - dTau) + beta * np.sin(2 * np.pi * fw * (t - dTau)) + alpha * hs_t
    surfPath = -R0 * np.cos(surfacePhase)
    
    # Normalized Coherent Sum: divides by (1 + R0) so max constructive sum is 1.0 (matching p_tx scale)
    coherent_rx = (dirPath + surfPath) / (1.0 + R0) if (1.0 + R0) > 0 else dirPath
    
    # 5. Added Ambient & Diffuse Scattering Noise (Wenz / Rayleigh standard)
    # Surface roughness (1 - R0): lower R0 means high surface roughness, scattering energy into diffuse noise
    # Aw and fw scale the sea-state agitation level
    noise_amplitude = 0.25 * (1.0 - R0) + 0.05 * (Aw / 5.0)
    
    # Dynamic seed including R0 so moving the roughness slider produces distinct noise realization
    seed_val = int(abs(f0 * 100 + Hsrc * 10 + Hrec + round(R0, 2) * 1000 + Aw * 50)) % 100000
    rng = np.random.RandomState(seed_val)
    noise = rng.normal(0, noise_amplitude, len(t))
    
    p_rx = coherent_rx + noise
    
    return theta_g, beta, deltaF, p_tx, p_rx

class SimulationHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        # Always serve files from the directory containing this script
        directory = os.path.dirname(os.path.abspath(__file__))
        super().__init__(*args, directory=directory, **kwargs)

    def do_GET(self):
        parsed_path = urllib.parse.urlparse(self.path)
        if parsed_path.path == '/api/simulate':
            self.handle_simulate(parsed_path.query)
        else:
            # Serve static files from the script directory
            super().do_GET()

    def handle_simulate(self, query_string):
        params = urllib.parse.parse_qs(query_string)
        
        try:
            # 1. Parse Input Parameters
            f0 = float(params.get('f0', [1000])[0])
            Aw = float(params.get('Aw', [2])[0])
            fw = float(params.get('fw', [0.2])[0])
            R = float(params.get('R', [2000])[0])
            Hrec = float(params.get('Hrec', [100])[0])
            R0 = float(params.get('R0', [0.8])[0])
            depthSrc = float(params.get('depthSrc', [50])[0])
            
            # 2. Setup High-Performance Time Vector (1.0 second duration, 2,000 points)
            numPoints = 2000
            duration = 1.0
            t = np.linspace(0, duration, numPoints)
            
            # 3. Route to Unified Math Model
            theta_g, beta, deltaF, p_tx, p_rx = simulate_channel(f0, depthSrc, Aw, fw, R, Hrec, R0, t)
            
            # 4. Format and Return Compact Response (returns in <15ms)
            response = {
                'theta_g': float(theta_g),
                'beta': float(beta),
                'deltaF': float(deltaF),
                't': [round(val, 5) for val in t.tolist()],
                'tx': [round(val, 4) for val in p_tx.tolist()],
                'rx': [round(val, 4) for val in p_rx.tolist()]
            }
            
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(response).encode())
            
        except Exception as e:
            self.send_response(400)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps({'error': str(e)}).encode())

if __name__ == "__main__":
    with socketserver.TCPServer(("", PORT), SimulationHandler) as httpd:
        print(f"Serving at port {PORT}")
        httpd.serve_forever()
