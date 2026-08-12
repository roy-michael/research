# Doubly Spread Channel Simulator

An interactive, web-based tool for simulating underwater acoustic multipath fading. This simulator calculates real-time signal propagation taking into account surface waves, source depth, and receiver positions, modeling the complex doubly-spread characteristics of the channel.

## Purpose

The primary goal of this tool is to visualize the shift between different acoustic scattering phenomena—specifically, the transition from **multiplicative fading** (envelope smearing) seen by sources at the ocean surface, to **additive interference** (macroscopic multipath) seen by sources located deeper underwater.

This simulator achieves this through an elegant **unified mathematical formulation**. Instead of using distinct algorithms for surface vs. deep sources, the model strictly uses a generalized additive reflection equation. As the source depth reaches `0`, the surface-reflected path length perfectly aligns with the direct path, and the mathematics naturally collapse to produce accurate multiplicative fading. Furthermore, exponential decay functions are applied to calculate the diminishing physical effects of surface wave heave based on source depth.

## Features

- **High-Performance Python Engine:** Core mathematical calculations utilizing `numpy` ensure high-fidelity signal simulation.
- **Interactive UI:** HTML/JS frontend using `Chart.js` for real-time, responsive visualization of transmitted and received waveforms.
- **Unified Physics Model:** Seamless transitions between acoustic phenomena by merely dragging the "Source Depth" slider.
- **Micro-Analysis:** Chart zooming and panning capabilities allowing deep inspection of signal distortion.
- **Dynamic Metrics:** Real-time calculation of Grazing Angle, Modulation Index, and Doppler Spread.

## Usage Instructions

### Prerequisites
- Python 3.x
- Required Python Packages: `numpy`

### Running the Simulator

1. **Start the API Server**
   Open your terminal, navigate to this directory (`web_simulator`), and run the Python backend using your virtual environment:
   ```bash
   python server.py
   ```

2. **Open the Interface**
   Launch your web browser and navigate to:
   ```text
   http://localhost:8000
   ```

3. **Interact**
   - Adjust the **Source Depth** ($H_{src}$) to observe the unified model gracefully switch between surface fading and deep-water echo separation.
   - Adjust the **Carrier Frequency** ($f_0$) up to 500 Hz to see higher frequency distortion.
   - Adjust **Heave Amplitude** ($A_w$) and **Wave Frequency** ($f_w$) to simulate different sea states.
   - Use your mouse wheel to **zoom** into the charts for closer inspection, and use the **Reset Zoom** button to return to the full view.

## Simulator Parameters & Mathematical Theory

The simulator provides several interactive controls that directly influence the underlying mathematical equations:

### Source Depth ($H_{src}$)
- **Purpose:** Controls the vertical position of the acoustic source in the water column.
- **Math:** This is the most critical parameter in the unified model. The surface wave's effect on the source's physical heave decays exponentially with depth, governed by the deep-water dispersion relation $k = (2\pi f_w)^2 / g$. Furthermore, the macroscopic time delay between the direct path and the surface echo is $\Delta\tau = (R_{surf} - R_{dir}) / c$. As $H_{src} \to 0$, $\Delta\tau \to 0$, and the unified additive model ($p_{rx} = p_{dir} + p_{surf}$) perfectly collapses into multiplicative fading.

### Carrier Frequency ($f_0$)
- **Purpose:** The base frequency of the transmitted acoustic signal.
- **Math:** Higher frequencies result in shorter wavelengths ($\lambda = c / f_0$). The time-varying phase shift induced by the surface motion is heavily dependent on the carrier frequency, meaning higher $f_0$ leads to significantly more severe Doppler spreading and signal distortion.

### Heave Amplitude ($A_w$) & Wave Frequency ($f_w$)
- **Purpose:** Dictates the severity and speed of the ocean surface waves (sea state).
- **Math:** These define the instantaneous vertical motion of the surface $h_s(t) = A_w \sin(2\pi f_w t)$. This kinematic boundary motion imparts a dynamic delay on the reflected acoustic path, which translates into a time-varying phase shift $\phi(t)$ that frequency-modulates the signal.

### Range ($R$) & Receiver Depth ($H_{rec}$)
- **Purpose:** Defines the geometry of the acoustic channel between the source and the receiver.
- **Math:** Together with $H_{src}$, these parameters are used to calculate the Grazing Angle ($\theta_g$) using geometry: $\theta_g = \arctan(\frac{H_{rec} - H_{src}}{R})$. A smaller grazing angle typically results in less severe scattering. They also define the absolute path lengths $R_{dir}$ and $R_{surf}$.

### Roughness ($R_0$)
- **Purpose:** Represents the base acoustic reflectivity of the ocean surface boundary.
- **Math:** Acts as a scalar multiplier for the amplitude of the surface-reflected signal path ($p_{surf}$), effectively determining how much energy is lost during the bounce.
