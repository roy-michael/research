# Digital Phase-Locked Loop (PLL) & Instantaneous Frequency Verification Report

## 1. Executive Summary

This report documents the design, mathematical formulation, implementation, and real-dataset statistical evaluation of the **Digital Phase-Locked Loop (PLL) Phase Lock & Instantaneous Frequency Verification** pipeline in `d:\dev\research\research-clean`.

To accurately track maneuvering acoustic sources without conflating 30-second macro-Doppler drift with local phase instability, the pipeline locks a **2nd-order quadrature Digital PLL** onto the **dominant frequency of each individual 0.5-second segment** (`slice_bw.slice_outputs{m}.main_f`) across the three real acoustic datasets in `D:\RoyStudies\Recordings`:
1. **`HaifaBay`** (Surface vessels — $480.35\text{ min}$, $480$ windows of $60\text{ s}$, $57{,}600$ segments of $0.5\text{ s}$)
2. **`Croatia`** (Underwater Diver Propulsion Vehicles / DPVs — $327.00\text{ min}$, $327$ windows of $60\text{ s}$, $39{,}240$ segments of $0.5\text{ s}$)
3. **`AUV`** (Autonomous Underwater Vehicle — $305.18\text{ min}$, $305$ windows of $60\text{ s}$, $36{,}600$ segments of $0.5\text{ s}$)

---

## 2. Pipeline Architecture & Code Integration

The PLL phase-lock and instantaneous frequency verification pipeline is integrated across the codebase as follows:

- **`+scooter_analysis/+config/AnalysisConfig.m`**:
  - Configures PLL parameters and passes them through `toBandwidthConfig()`:
    - `pll_bandpass_margin_hz = 80.0` (maximum half-width around the dominant frequency, Hz)
    - `pll_loop_bw_hz = 18.0` (natural loop bandwidth $B_L$, Hz)
    - `pll_damping_zeta = 0.707` (critically damped 2nd-order loop factor $\zeta = 1/\sqrt{2}$)
    - `pll_max_freq_dev_hz = 60.0` (maximum NCO frequency pull-in range, Hz)
    - `pll_freq_lock_tol_hz = 5.0` (instantaneous frequency lock tolerance, Hz)
- **`BandwidthTracker.m`**:
  - `compute_pll_phase_lock`: Performs per-0.5s-segment dominant-frequency bandpass filtering, Hilbert analytic signal conversion, AGC envelope normalization, 2nd-order Digital PLL tracking, and instantaneous frequency verification against the 0.5s FFT peak.
  - `compute_phase_stability_vs_window`: Applies a 5-second median pre-filter (`medfilt1`) and evaluates multiscale phase coherence $R(W)$, normalized phase Shannon entropy $H_{\phi,\text{norm}}(W)$, and instantaneous frequency lock fairness across window sizes $W \in [2, 60]\text{ s}$.
  - `compute_rolling_phase_stability`: Computes 60-second rolling trajectories of $R(t)$, $H_\phi(t)$, $1 - H_{\phi,\text{norm}}(t)$, and frequency lock fairness.
  - `compute_binned_phase_lock`: Aggregates 0.5-second slice metrics into 60-second statistical bins (means, SDs, SEMs).
- **Results & Pipeline Classes**:
  - `SegmentResult.m`, `SegmentAnalyzer.m`, `FileResult.m`, and `BatchAnalyzer.m` (`getPhaseLockResult`, `getRollingPhaseLockResult`, `getBinnedPhaseLockResult`).
- **Visualization & Reporting**:
  - `PlotGenerator.m`, `Visualizer.m`, `ReportGenerator.m`, and `run_analysis.m`.

---

## 3. Methodology: Per-0.5-Second Segment Dominant-Frequency Phase Tracking

### 3.1 Why Per-0.5-Second Dominant Frequency Tracking Is Essential

Previously, filtering an entire 30-second window around a single 30-second Welch PSD peak (`dom_lobe.peak_freq`) caused two physical artifacts:
1. **Inter-slice Dominant Frequency Drift**: Over a 30-second window (60 slices of $0.5\text{ s}$), a maneuvering vehicle's dominant frequency `slice_bw.slice_outputs{m}.main_f` shifts from slice to slice. Locking the PLL to the 30-second average peak meant that whenever a 0.5-second slice had a different dominant frequency, the PLL tracked the wrong spectral peak, inflating $|f_{\text{PLL}} - f_{\text{FFT}}|$ to $14.9\text{–}30.9\text{ Hz}$.
2. **Real-Mixer $2f_0$ Double-Frequency Ripple**: Multiplying a real signal by $-\sin(\hat{\phi})$ generates a sum-frequency term at $2f_0$ that leaks through the proportional loop filter and creates an artificial frequency-spread floor.

### 3.2 Step-by-Step 0.5-Second Segment Algorithm

For each 0.5-second segment $m \in \{1, \dots, M\}$ ($L = \lfloor f_s \cdot 0.5\text{ s} \rfloor$ samples):

1. **Dominant Frequency & Bandwidth Identification**:
   - Retrieves the 0.5-second segment's watershed peak frequency $f_{\text{dom},m} = \text{slice\_bw.slice\_outputs}\{m\}.\text{main\_f}$ and lobe width $\text{BW}_m = \text{main\_bw}$ (or computes a Hann-windowed 0.5s FFT with parabolic peak interpolation if `slice_bw` is not supplied).
2. **Guard-Padded Lobe-Matched Bandpass Filtering**:
   - Extracts the 0.5-second slice with a $50\text{ ms}$ guard pad on both ends from the continuous signal to prevent `filtfilt` and `hilbert` edge transients.
   - Applies a zero-phase 2nd-order Butterworth bandpass filter centered symmetrically at $f_{\text{dom},m}$ with half-width:
     $$\Delta f_{\text{margin},m} = \min\!\left(\Delta f_{\text{max}},\, \max(16.0\text{ Hz},\, 0.70 \cdot \text{BW}_m)\right)$$
3. **Quadrature Analytic Signal & AGC Normalization**:
   - Computes the analytic signal $z(t) = \mathcal{H}\{x_{\text{filt}}(t)\}$, normalizes by the local envelope $\text{movmean}(|z(t)|, 80\text{ ms})$ above an RMS noise floor, and trims the guard pad back to the exact $L$ samples of the 0.5-second slice.
4. **2nd-Order Quadrature Digital PLL**:
   - Initializes the Numerically Controlled Oscillator (NCO) at the 0.5-second dominant frequency $\omega_{\text{center},m} = 2\pi f_{\text{dom},m} / f_s$ and initial phase $\hat{\phi}(1) = \text{atan2}(\text{Im}\{z(1)\}, \text{Re}\{z(1)\})$.
   - Updates sample-by-sample ($i = 1, \dots, L$) using a quadrature phase detector free of $2f_0$ double-frequency ripple:
     $$e_{\sin}(i) = \text{Im}\{z_{\text{norm}}(i)\}\cos\hat{\phi}(i) - \text{Re}\{z_{\text{norm}}(i)\}\sin\hat{\phi}(i)$$
     $$e_{\cos}(i) = \text{Re}\{z_{\text{norm}}(i)\}\cos\hat{\phi}(i) + \text{Im}\{z_{\text{norm}}(i)\}\sin\hat{\phi}(i)$$
     $$\Delta\phi_{\text{det}}(i) = \text{atan2}(e_{\sin}(i), e_{\cos}(i))$$
   - Updates the proportional-integral loop filter ($k_p = 2\zeta\omega_n / f_s$, $k_i = \omega_n^2 / f_s^2$) and records the instantaneous PLL frequency:
     $$f_{\text{PLL}}(i) = \frac{f_s}{2\pi}\left(\omega_{\text{center},m} + \Delta\omega_{\text{ctrl}}(i)\right)$$

---

## 4. Meaning of the Phase Locking Value ($R$) and Stability Metrics

### 4.1 Mathematical & Geometric Definition of $R$

Within each 0.5-second segment, let $\Delta\phi_m(t_i) \in [-\pi, \pi]$ be the wrapped phase residual between the tracked acoustic wave and the segment's reference carrier. The **Phase Locking Value ($R$)**—or **Circular Mean Resultant Length**—is the magnitude of the mean complex unit phasor across the $L$ samples of the 0.5-second slice:

$$R_m = \left| \frac{1}{L} \sum_{i=1}^{L} e^{j \Delta\phi_m(t_i)} \right| = \sqrt{ \left( \frac{1}{L} \sum_{i=1}^{L} \cos\Delta\phi_m(t_i) \right)^2 + \left( \frac{1}{L} \sum_{i=1}^{L} \sin\Delta\phi_m(t_i) \right)^2 } \in [0, 1]$$

Geometrically, if each audio sample places a unit vector of length $1$ at angle $\Delta\phi_m(t_i)$ on the unit circle, **$R_m$ is the length of their vector average**:
- **$R \to 1.0$**: All unit vectors point in the same direction ($\Delta\phi_m(t_i) \approx 0$). The acoustic wave maintains a deterministic, cycle-to-cycle coherent phase.
- **$R \to 0.0$**: The unit vectors point in all directions around $[-\pi, \pi]$ and cancel out. The phase is random/unlocked.
- **Relationship to Circular Phase Jitter ($\sigma_\phi$)**:
  $$R \approx e^{-\sigma_\phi^2 / 2} \quad \Longleftrightarrow \quad \sigma_\phi \approx \sqrt{-2 \ln R}\text{ (rad)}$$

### 4.2 Meaning of $R$ in Relation to PLL Operation

| $R$ Value Range | PLL Lock Regime | Physical Behavior Inside the 0.5-Second Segment |
| :--- | :--- | :--- |
| **$R \in [0.70, 1.00]$** | **Tightly Phase-Locked** | Clean narrowband tone (e.g., active underwater electric propulsion). The PLL NCO locks immediately and holds $\Delta\phi(t) \approx 0^\circ$ across the entire 0.5s window with zero cycle slips. |
| **$R \in [0.40, 0.70]$** | **Locked with Phase Jitter** | The PLL remains locked to the dominant carrier frequency without losing synchronization, but multipath interference, moderate ambient noise, or smooth Doppler acceleration causes $\Delta\phi(t)$ to oscillate around $0^\circ$ ($\pm 45^\circ\text{ to }\pm 70^\circ$). |
| **$R \in [0.20, 0.40]$** | **Weak Lock / Cycle Slipping** | Broadband cavitation or competing spectral lines within the lobe cause amplitude dropouts and rapid phase jumps faster than the $18\text{ Hz}$ loop bandwidth can track. The PLL repeatedly **slips cycles** ($\Delta\phi$ wraps across $\pm 180^\circ$) and re-locks. |
| **$R < 0.20$** | **Out of Lock (Unlocked)** | Incoherent noise; the NCO cannot find a persistent sinusoidal carrier, and $\Delta\phi(t)$ rotates uniformly across $[-\pi, \pi]$. |

**Why $R$ Captures Physics That FFT Bandwidth Cannot**:
An FFT magnitude spectrum is phase-blind—it cannot distinguish between a continuous phase-coherent oscillation and a train of short, phase-incoherent impulses occurring at the same frequency. By testing cycle-by-cycle phase continuity via the PLL, $R$ directly separates coherent mechanical/electromagnetic rotation from stochastic cavitation impulses.

### 4.3 Multiscale & Windowed Stability Metrics

Across windows of $N$ consecutive 0.5-second slices (after a 5-second `medfilt1` pre-filter to remove single-slice impulse noise, matching `compute_stability_vs_window`):

1. **Multiscale Phase Coherence $R(W)$**:
   $$R(W) = \left| \frac{1}{N} \sum_{m=1}^{N} R_m \, e^{j \bar{\phi}_m} \right|$$
   Measures how well both within-slice lock ($R_m$) and inter-slice phase alignment ($\bar{\phi}_m$) hold together as the observation window $W$ expands from $2\text{ s}$ to $60\text{ s}$.
2. **Normalized Phase Shannon Entropy ($H_{\phi,\text{norm}}$) & Phase Stability ($1 - H_{\phi,\text{norm}}$)**:
   $$H_{\phi,\text{norm}} = -\frac{1}{\log_2 K} \sum_{k=1}^{K} p_k \log_2 p_k, \qquad \text{Phase Stability} = 1 - H_{\phi,\text{norm}} \in [0, 1]$$
   where $p_k$ is the empirical probability of $\bar{\phi}_m$ across $K = \min(20, N, \max(2, \text{round}(1.8\sqrt{N})))$ adaptive bins over $[-\pi, \pi]$.
3. **Instantaneous Frequency Lock Fairness Index ($\mathcal{J}(\sigma_f)$)**:
   $$\mathcal{J}(\sigma_f) = \frac{\left(\sum_{m=1}^{N} \sigma_{f,m}\right)^2}{N \sum_{m=1}^{N} \sigma_{f,m}^2} \in [0, 1]$$
   Jain's Fairness Index applied to the 0.5-second PLL instantaneous frequency spread $\sigma_{f,m}$, quantifying how stationary the FM spread remains across the window ($\mathcal{J} \to 1$ indicates uniform, steady frequency spread; lower $\mathcal{J}$ indicates intermittent bursts/transients).

---

## 5. Real Dataset Statistical Comparison (`HaifaBay`, `Croatia`, `AUV`)

All numbers below come directly from the real recordings processed by `run_analysis.m` and saved in `phase_lock_verification_statistics.txt`:

| Metric (60s Windows of 0.5s Segments) | **HaifaBay** (Surface Vessels) | **Croatia** (Underwater DPVs) | **AUV** (Autonomous Underwater) |
| :--- | :---: | :---: | :---: |
| **Total Duration / 60s Windows / 0.5s Slices** | $480.35\text{ min}$ / $480$ / $57{,}600$ | $327.00\text{ min}$ / $327$ / $39{,}240$ | $305.18\text{ min}$ / $305$ / $36{,}600$ |
| **Dominant Frequency (Welch Peak)** | $169.89 \pm 232.91\text{ Hz}$ | $740.83 \pm 267.25\text{ Hz}$ | $713.09 \pm 292.33\text{ Hz}$ |
| **PLL Tracked Instantaneous Frequency** | $172.95 \pm 232.61\text{ Hz}$ | $743.00 \pm 258.89\text{ Hz}$ | $720.13 \pm 285.68\text{ Hz}$ |
| **Inst. Freq Verification $\|f_{\text{PLL}} - f_{\text{FFT}}\|$ (Mean ± SD)** | **$3.79 \pm 4.73\text{ Hz}$** | **$2.15 \pm 2.59\text{ Hz}$** | **$2.12 \pm 2.28\text{ Hz}$** |
| **Inst. Freq Verification $\|f_{\text{PLL}} - f_{\text{FFT}}\|$ (Median)** | **$2.30\text{ Hz}$** | **$1.38\text{ Hz}$** | **$1.43\text{ Hz}$** |
| **Watershed Bandwidth (60s Slice Mean ± Intra-SD)** | $95.60 \pm 42.02\text{ Hz}$ | $27.40 \pm 15.70\text{ Hz}$ | $25.90 \pm 11.25\text{ Hz}$ |
| **Watershed Bandwidth (Macro SD Across 60s Windows)** | $38.00\text{ Hz}$ | $18.96\text{ Hz}$ | $12.85\text{ Hz}$ |
| **Phase Locking Value $R$ (60s Mean ± Intra-SD)** | **$0.294 \pm 0.175$** | **$0.435 \pm 0.218$** | **$0.428 \pm 0.205$** |
| **Phase Locking Value $R$ (Median Across 60s Windows)** | **$0.238$** | **$0.345$** | **$0.346$** |
| **Phase Locking Value $R$ (Macro SD Across 60s Windows)** | $0.117$ | $0.181$ | $0.188$ |
| **Wrapped Phase Error SD $\sigma_\phi$ (Mean ± Intra-SD)** | **$1.434 \pm 0.324\text{ rad}$** | **$1.213 \pm 0.471\text{ rad}$** | **$1.230 \pm 0.447\text{ rad}$** |
| **PLL Inst. Freq Spread $\sigma_f$ (60s Mean ± Intra-SD)** | **$12.92 \pm 3.81\text{ Hz}$** | **$10.19 \pm 3.33\text{ Hz}$** | **$10.22 \pm 2.79\text{ Hz}$** |
| **PLL Inst. Freq Spread $\sigma_f$ (Macro SD Across 60s)** | $3.50\text{ Hz}$ | $3.10\text{ Hz}$ | $3.09\text{ Hz}$ |
| **Normalized Phase Entropy $H_\phi$ (60s Mean ± SD)** | $0.704 \pm 0.060$ | $0.689 \pm 0.067$ | $0.668 \pm 0.081$ |
| **Phase Concentration Stability $1 - H_{\phi,\text{norm}}$ (60s)** | $0.296 \pm 0.060$ | $0.311 \pm 0.067$ | $0.332 \pm 0.081$ |
| **Inst. Freq Stability Fairness $\mathcal{J}(\sigma_f)$ (60s)** | $0.973 \pm 0.041$ | $0.937 \pm 0.082$ | $0.960 \pm 0.061$ |

---

## 6. Key Physical Insights & Stability Analysis

### 6.1 Profound Distinction Between Underwater (`Croatia`, `AUV`) and Surface (`HaifaBay`) Sources

1. **Instantaneous Frequency Verification Accuracy (`|f_PLL - f_FFT|`)**:
   - In both underwater datasets, the PLL-tracked mean frequency of each 0.5-second segment matches the 0.5-second FFT peak to within **$2.12\text{–}2.15\text{ Hz}$** on average (median **$1.38\text{–}1.43\text{ Hz}$**), which is narrower than a single 0.5-second FFT bin ($\Delta f_{\text{bin}} = 1 / 0.5\text{ s} = 2.0\text{ Hz}$).
   - In `HaifaBay`, the verification error is nearly **twice as large** ($3.79 \pm 4.73\text{ Hz}$, median $2.30\text{ Hz}$) because surface-vessel cavitation lobes ($\text{BW} = 95.60\text{ Hz}$) are asymmetric and undergo rapid intra-slice spectral wandering inside a 0.5-second window.

2. **0.5-Second Phase Lock ($R$) & Wrapped Phase Error Density ($\Delta\phi$)**:
   - Underwater vehicles achieve a **46%–48% higher mean Phase Locking Value** (`Croatia`: $R = 0.435$, `AUV`: $R = 0.428$) than surface vessels (`HaifaBay`: $R = 0.294$), and a **45% higher median $R$** ($0.345\text{–}0.346$ vs. $0.238$).
   - Correspondingly, the wrapped phase error standard deviation $\sigma_\phi$ is significantly lower in `Croatia` ($1.213\text{ rad}$) and `AUV` ($1.230\text{ rad}$) than in `HaifaBay` ($1.434\text{ rad}$).
   - In the Wrapped Carrier Phase Error PDF (`comparison_phase_lock/Fig4P_Phase_Lock_Distribution.png`, Subplot 1), `Croatia` and `AUV` follow nearly identical distributions peaking at **$0.445\text{ rad}^{-1}$** at $\Delta\phi = 0$, whereas `HaifaBay` peaks at only **$0.298\text{ rad}^{-1}$** with heavy tails toward $\pm\pi$.

3. **Why Underwater Datasets Show Higher Macro-SD of $R$ Across 60s Windows (`0.181–0.188` vs. `0.117`)**:
   - As shown in `comparison_binned_phase_lock_60s_auv.png` (Top-Left histogram and Bottom-Left time series), **`HaifaBay` is persistently unlocked/weakly locked**: ~95% of its 480 one-minute windows cluster tightly between $R = 0.18$ and $R = 0.35$, with only a single brief rise above $0.5$ around minutes 445–460. Because it rarely leaves its low-lock floor, its macro-variance across windows is small ($\text{Macro SD} = 0.117$).
   - By contrast, **`Croatia` and `AUV` transition between distant/ambient intervals ($R \approx 0.28\text{–}0.35$) and active close-range propulsion passes where $R$ surges to $0.70\text{–}0.95$** (and $\sigma_f$ drops to $3\text{–}6\text{ Hz}$). This bimodal/right-skewed distribution between ambient periods and high-lock tonal passes produces a larger macro-SD ($0.181\text{–}0.188$).

4. **Stability Comparison Between Autonomous (`AUV`) and Human-Piloted (`Croatia`) Underwater Vehicles**:
   - While `Croatia` and `AUV` have nearly identical mean 0.5-second phase lock ($R = 0.435$ vs. $0.428$) and mean frequency spread ($\sigma_f = 10.19\text{ Hz}$ vs. $10.22\text{ Hz}$), **`AUV` is measurably more stable across time within 60-second windows**:
     - **Lower within-window variability of $\sigma_f$**: $\text{Avg SD} = 2.79\text{ Hz}$ for `AUV` vs. $3.33\text{ Hz}$ for `Croatia` (and $3.81\text{ Hz}$ for `HaifaBay`), visible in `comparison_binned_inst_freq_spread_60s_auv.png`.
     - **Higher Phase Concentration Stability ($1 - H_{\phi,\text{norm}}$)**: $0.332$ for `AUV` vs. $0.311$ for `Croatia` and $0.296$ for `HaifaBay`.
     - **Higher Instantaneous Frequency Fairness ($\mathcal{J}(\sigma_f)$)**: $0.960$ for `AUV` vs. $0.937$ for `Croatia`, reflecting steady autonomous RPM control compared to human diver throttle adjustments on DPVs.

---

## 7. Generated Output Files & Figures

- **Statistical Text Report**: `scooter_analysis/output/phase_lock_verification_statistics.txt`
- **4-Panel Phase Lock PDF & Multiscale Stability**: `scooter_analysis/output/comparison_phase_lock/Fig4P_Phase_Lock_Distribution.png`
- **60s Binned Phase Lock ($R$) & PLL Frequency Spread ($\sigma_f$)**: `scooter_analysis/output/comparison_binned_phase_lock_60s_auv.png`
- **60s Binned PLL Frequency Spread & Within-Window SD**: `scooter_analysis/output/comparison_binned_inst_freq_spread_60s_auv.png`
- **60s Rolling Phase Lock Trajectories & Derivatives**:
  - `scooter_analysis/output/comparison_rolling_phase_lock_60s.png`
  - `scooter_analysis/output/comparison_rolling_phase_lock_derivative_60s.png`

