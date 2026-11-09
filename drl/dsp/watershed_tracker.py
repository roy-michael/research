"""
Python port of the acoustic bandwidth & stability pipeline from `research-clean`
(`SpectralEngine.m` and `BandwidthTracker.m`).

Implements:
1. High-resolution Welch PSD estimation and PCHIP interpolation (`compute_welch_psd`)
2. Order-statistic ambient baseline & saddle-point macro-lobe segmentation (`segment_macro_lobes`)
3. Windowed-FFT topographic watershed slice bandwidth tracking (`compute_single_slice_watershed_bandwidth`,
   `compute_watershed_slice_bandwidth`)
4. Multiscale stability & fairness metrics: Time-in-Band (TiB), Normalized Shannon Entropy,
   and Jain's Fairness Index (`compute_stability_metrics`)
"""

import numpy as np
from scipy.interpolate import PchipInterpolator
from scipy.ndimage import gaussian_filter1d, median_filter, minimum_filter1d, uniform_filter1d
from scipy.signal import butter, filtfilt, welch
from scipy.signal.windows import hamming, hann


DEFAULT_BW_CONFIG = {
    "twin_welch": 0.050,                     # Welch window length (50 ms -> ~20 Hz resolution)
    "df_eval": 0.25,                         # Uniform spectral evaluation grid step (Hz)
    "slice_dur_sec": 0.500,                  # Time-domain FFT slice duration (500 ms)
    "prom_split_db": 5.0,                    # Inter-peak prominence drop for independent lobes (dB)
    "tib_tolerance_hz": 10.0,                # Tolerance for Time-in-Band stability metric (Hz)
    "entropy_max_bins": 20,                  # Maximum histogram bins for adaptive Shannon entropy
    "bw_smooth_method": "welch",             # Parabolic Welch smoothing window
    "bw_smooth_window": 5,                   # Base window size for smoothing segmented spectrum
    "watershed_prom_max_db": 8.0,            # Maximum prominence drop allowed before boundary (dB)
    "watershed_prom_min_db": 3.0,            # Minimum prominence drop allowed before boundary (dB)
    "watershed_prom_ratio": 0.40,            # Multiplier scaling prominence with peak elevation
    "watershed_noise_fallback_margin": 0.90, # Margin below noise floor for hybrid boundary
    "watershed_rebound_ratio": 0.50,         # Relative valley rebound ratio
    "watershed_min_dip_db": 1.50,            # Minimum valley dip (dB) for relative rebound
}


def _matlab_smoothdata_gaussian(x, window_len):
    """
    Matches MATLAB's `smoothdata(x, 'gaussian', W)` where the Gaussian standard
    deviation is sigma = W / 5 (corresponding to a 2.5-sigma half-width).
    """
    w = max(3, int(round(window_len)))
    sigma = max(0.5, w / 5.0)
    return gaussian_filter1d(np.asarray(x, dtype=float), sigma=sigma, mode="nearest")


def compute_welch_psd(signal, fs, f_min=0.0, f_max=None, twin_sec=0.050, df_target=0.25):
    """
    Port of `SpectralEngine.compute_welch_psd`:
    Computes high-resolution Welch PSD and interpolates onto a uniform frequency grid using PCHIP.
    """
    if f_max is None:
        f_max = fs / 2.0
    f_max = min(float(f_max), fs / 2.0)
    f_min = max(0.0, float(f_min))

    nwin = int(2 ** np.ceil(np.log2(max(4.0, fs * twin_sec))))
    nwin = min(nwin, len(signal))
    win = hamming(nwin, sym=True)
    nov = int(np.floor(nwin * 0.75))
    nfft = max(nwin, 8192)

    f_raw, psd_raw = welch(
        signal,
        fs=fs,
        window=win,
        nperseg=nwin,
        noverlap=nov,
        nfft=nfft,
        detrend=False,
        scaling="density",
    )

    df = float(df_target)
    f_grid = np.arange(f_min, f_max + 0.5 * df, df)
    pchip = PchipInterpolator(f_raw, np.maximum(psd_raw, np.finfo(float).eps), extrapolate=True)
    psd_interp = np.maximum(pchip(f_grid), np.finfo(float).eps)
    psd_db = 10.0 * np.log10(psd_interp)

    k_welch = int(np.floor((len(signal) - nov) / max(1, nwin - nov)))
    return psd_db, f_grid, df, k_welch


def segment_macro_lobes(psd_db, f_grid, df, prom_split_db=5.0):
    """
    Port of `SpectralEngine.segment_macro_lobes`:
    Extracts broadband acoustic structures relative to the ambient ocean baseline,
    resolving independent lobes via topographic saddle-point prominence splitting.
    Selects the dominant macro-lobe strictly by maximum integrated linear net energy.
    """
    psd_db = np.asarray(psd_db, dtype=float)
    f_grid = np.asarray(f_grid, dtype=float)
    n_pts = len(psd_db)
    eps = np.finfo(float).eps

    # 1. Smooth ambient ocean baseline via sliding minimum and Gaussian smoothing
    win_bg_bins = 2 * int(np.ceil(100.0 / df)) + 1
    ocean_floor_raw = minimum_filter1d(psd_db, size=win_bg_bins, mode="nearest")
    ocean_floor_smooth = _matlab_smoothdata_gaussian(ocean_floor_raw, round(40.0 / df))
    ocean_ambient_db = float(np.percentile(ocean_floor_smooth, 15))

    # 2. Net power elevation above ambient floor
    delta_ambient_db = psd_db - ocean_floor_smooth
    p_lin_net = np.maximum(0.0, 10.0 ** (psd_db / 10.0) - 10.0 ** (ocean_floor_smooth / 10.0))
    total_net_energy = float(np.trapezoid(p_lin_net, f_grid))

    # 3. Topographic saddle-point valley extraction on smoothed spectral envelope
    psd_env = _matlab_smoothdata_gaussian(psd_db, max(3, round(6.0 / df)))

    is_local_min = np.zeros(n_pts, dtype=bool)
    is_local_min[1:-1] = (psd_env[1:-1] < psd_env[:-2]) & (psd_env[1:-1] <= psd_env[2:])
    valleys = np.flatnonzero(is_local_min)

    is_pk = np.zeros(n_pts, dtype=bool)
    is_pk[1:-1] = (psd_env[1:-1] > psd_env[:-2]) & (psd_env[1:-1] >= psd_env[2:])
    peaks = np.flatnonzero(is_pk)

    valid_valleys = []
    for idx_v in valleys:
        left_pks = peaks[peaks < idx_v]
        right_pks = peaks[peaks > idx_v]
        if len(left_pks) > 0 and len(right_pks) > 0:
            pk_l = left_pks[-1]
            pk_r = right_pks[0]
            drop_l = psd_env[pk_l] - psd_env[idx_v]
            drop_r = psd_env[pk_r] - psd_env[idx_v]
            min_drop = min(drop_l, drop_r)

            is_ambient_floor_return = delta_ambient_db[idx_v] <= 3.0
            is_isolated_carrier_split = (min_drop >= 7.0) and (delta_ambient_db[idx_v] <= prom_split_db)
            if is_ambient_floor_return or is_isolated_carrier_split:
                valid_valleys.append(int(idx_v))

    boundaries = np.unique(np.concatenate(([0], valid_valleys, [n_pts - 1])).astype(int))
    cand_lobes = []

    for b in range(len(boundaries) - 1):
        i_start = int(boundaries[b])
        i_end = int(boundaries[b + 1])
        if i_end <= i_start:
            continue

        f_sub = f_grid[i_start : i_end + 1]
        p_sub = psd_db[i_start : i_end + 1]
        p_net_sub = p_lin_net[i_start : i_end + 1]

        pk_local = int(np.argmax(p_sub))
        pk_val = float(p_sub[pk_local])
        pk_freq = float(f_sub[pk_local])
        e_lobe = float(np.trapezoid(p_net_sub, f_sub))
        pct_e = 100.0 * (e_lobe / max(total_net_energy, eps))

        # Retain regions exhibiting measurable excess energy and elevation
        pk_global = i_start + pk_local
        if (pct_e >= 1.0) and ((pk_val - ocean_floor_smooth[pk_global]) >= 2.5):
            i_core_start = i_start
            while (i_core_start < pk_global) and (delta_ambient_db[i_core_start] <= 1.0):
                i_core_start += 1

            i_core_end = i_end
            while (i_core_end > pk_global) and (delta_ambient_db[i_core_end] <= 1.0):
                i_core_end -= 1

            cand_lobes.append({
                "f_start": float(f_grid[i_core_start]),
                "f_end": float(f_grid[i_core_end]),
                "bandwidth": float(f_grid[i_core_end] - f_grid[i_core_start]),
                "peak_freq": pk_freq,
                "peak_psd": pk_val,
                "energy_lin": e_lobe,
                "pct_energy": pct_e,
            })

    if not cand_lobes:
        max_idx = int(np.argmax(psd_db))
        dom_lobe = {
            "f_start": float(f_grid[0]),
            "f_end": float(f_grid[-1]),
            "bandwidth": float(f_grid[-1] - f_grid[0]),
            "peak_freq": float(f_grid[max_idx]),
            "peak_psd": float(psd_db[max_idx]),
            "energy_lin": total_net_energy,
            "pct_energy": 100.0,
        }
        macro_lobes = [dom_lobe]
    else:
        dom_lobe = max(cand_lobes, key=lambda lob: lob["energy_lin"])
        macro_lobes = cand_lobes

    return macro_lobes, dom_lobe, ocean_floor_smooth, ocean_ambient_db


def compute_single_slice_watershed_bandwidth(sig_slice, fs, dom_lobe, cfg=None):
    """
    Port of `BandwidthTracker.compute_single_slice_Watershed_bandwidth`:
    Implements windowed-FFT and topographic watershed flood-fill expansion around
    the dominant spectral peak within the macro-lobe ROI.
    """
    if cfg is None:
        cfg = DEFAULT_BW_CONFIG
    else:
        merged = dict(DEFAULT_BW_CONFIG)
        merged.update(cfg)
        cfg = merged

    eps = np.finfo(float).eps
    out = {
        "found": False,
        "main_bw": np.nan,
        "f_segment": np.array([]),
        "mag_segment": np.array([]),
        "noise_floor": np.nan,
        "target_mag": np.nan,
        "main_f": np.nan,
        "main_mag": np.nan,
        "l_freq": np.nan,
        "r_freq": np.nan,
    }

    sig_slice = np.asarray(sig_slice, dtype=float).ravel()
    slice_len = len(sig_slice)
    if slice_len < 16:
        return out

    # --- Phase 1: Windowed Fast Fourier Transform (FFT) ---
    win = hann(slice_len, sym=True)
    sig_win = sig_slice * win
    sig_fft = np.fft.fft(sig_win)
    f_axis = np.arange(slice_len, dtype=float) * (fs / slice_len)

    pos_mask = (f_axis >= 0.0) & (f_axis <= fs / 2.0)
    f_pos = f_axis[pos_mask]
    mag_pos = np.abs(sig_fft[pos_mask])

    # --- Phase 2: Region of Interest (ROI) & Adaptive Padding ---
    f_min_bound = float(cfg.get("f_low", 0.0))
    f_max_bound = min(fs / 2.0, float(cfg.get("f_high", fs / 2.0)))

    macro_bw = dom_lobe["f_end"] - dom_lobe["f_start"]
    rel_width = macro_bw / max(10.0, dom_lobe["peak_freq"])

    if dom_lobe["peak_freq"] <= 250.0:
        width_factor = min(1.0, max(0.0, (macro_bw - 30.0) / 70.0))
    else:
        width_factor = min(1.0, max(0.0, (rel_width - 0.35) / 0.40))

    pad_hz = min(50.0, max(20.0, macro_bw * 0.4))
    f_start = max(f_min_bound, dom_lobe["f_start"] - pad_hz)
    f_end = min(f_max_bound, dom_lobe["f_end"] + pad_hz)

    idx_mask = (f_pos >= f_start) & (f_pos <= f_end)
    f_segment = f_pos[idx_mask]
    mag_segment = mag_pos[idx_mask]

    if len(mag_segment) < 10:
        return out

    # --- Phase 3: Spectral Smoothing (Parabolic Welch Window) & Background Noise Floor ---
    n_smooth = int(round(cfg["bw_smooth_window"] + width_factor * 10.0))
    if n_smooth % 2 == 0:
        n_smooth += 1

    if str(cfg["bw_smooth_method"]).lower() == "welch" and n_smooth >= 3:
        half = (n_smooth - 1) / 2.0
        n_idx = np.arange(-half, half + 1.0)
        w = 1.0 - (n_idx / half) ** 2
        w_sum = np.sum(w)
        if w_sum > 0:
            w = w / w_sum
        mag_segment = np.convolve(mag_segment, w, mode="same")

    mag_smooth = mag_segment

    # Estimate ambient noise floor using the outer 15% edges of the segment
    n_seg = len(mag_smooth)
    edge_count = max(2, int(round(0.15 * n_seg)))
    edge_values = np.concatenate((mag_smooth[:edge_count], mag_smooth[-edge_count:]))
    noise_floor = float(np.median(edge_values))

    # --- Phase 4: Dominant Peak Localization ---
    pk_idx = int(np.argmax(mag_smooth))
    pk_mag_smooth = float(mag_smooth[pk_idx])
    pk_f = float(f_segment[pk_idx])
    pk_mag = float(mag_segment[pk_idx])

    excess_peak = pk_mag_smooth - noise_floor
    if excess_peak <= 0.0:
        return out

    out["found"] = True
    out["f_segment"] = f_segment
    out["mag_segment"] = mag_segment
    out["noise_floor"] = noise_floor
    out["main_f"] = pk_f
    out["main_mag"] = pk_mag

    # --- Phase 5: Topographic Watershed Expansion (Water Drop Algorithm) ---
    adaptive_max_prom_db = 2.5 + width_factor * (cfg["watershed_prom_max_db"] - 2.5)
    peak_elevation_db = 20.0 * np.log10(pk_mag_smooth + eps) - 20.0 * np.log10(noise_floor + eps)

    dynamic_prom_db = min(
        adaptive_max_prom_db,
        max(cfg["watershed_prom_min_db"], cfg["watershed_prom_ratio"] * peak_elevation_db),
    )
    prom_linear_ratio = 10.0 ** (dynamic_prom_db / 20.0)

    rebound_ratio = float(cfg["watershed_rebound_ratio"]) + width_factor * 0.25
    min_dip_db = float(cfg["watershed_min_dip_db"])

    # Right-side boundary expansion
    r_idx = pk_idx
    min_seen_right = mag_smooth[pk_idx]
    for i in range(pk_idx + 1, len(mag_smooth)):
        val = mag_smooth[i]
        if val < min_seen_right:
            min_seen_right = val
            r_idx = i
        elif val > min_seen_right:
            drop_db = 20.0 * np.log10(pk_mag_smooth + eps) - 20.0 * np.log10(min_seen_right + eps)
            rise_db = 20.0 * np.log10(val + eps) - 20.0 * np.log10(min_seen_right + eps)

            if (drop_db >= min_dip_db) and (rise_db >= rebound_ratio * drop_db):
                break
            if val > min_seen_right * prom_linear_ratio:
                break
            is_past_lobe = f_segment[i] >= dom_lobe["f_end"]
            if (is_past_lobe or width_factor == 0.0) and (
                min_seen_right <= noise_floor * cfg["watershed_noise_fallback_margin"]
            ):
                break

    # Left-side boundary expansion
    l_idx = pk_idx
    min_seen_left = mag_smooth[pk_idx]
    for i in range(pk_idx - 1, -1, -1):
        val = mag_smooth[i]
        if val < min_seen_left:
            min_seen_left = val
            l_idx = i
        elif val > min_seen_left:
            drop_db = 20.0 * np.log10(pk_mag_smooth + eps) - 20.0 * np.log10(min_seen_left + eps)
            rise_db = 20.0 * np.log10(val + eps) - 20.0 * np.log10(min_seen_left + eps)

            if (drop_db >= min_dip_db) and (rise_db >= rebound_ratio * drop_db):
                break
            if val > min_seen_left * prom_linear_ratio:
                break
            is_past_lobe = f_segment[i] <= dom_lobe["f_start"]
            if (is_past_lobe or width_factor == 0.0) and (
                min_seen_left <= noise_floor * cfg["watershed_noise_fallback_margin"]
            ):
                break

    out["l_freq"] = float(f_segment[l_idx])
    out["r_freq"] = float(f_segment[r_idx])
    out["main_bw"] = float(out["r_freq"] - out["l_freq"])
    out["target_mag"] = noise_floor
    return out


def compute_stability_metrics(bw_array, slice_dur_sec=0.500, tol_hz=10.0, max_bins=20):
    """
    Port of `BandwidthTracker` stability metrics:
    Computes median-filtered Time-in-Band (TiB), Normalized Shannon Entropy (H_norm)
    with adaptive binning, and Jain's Fairness Index across the bandwidth time series.
    """
    bw_clean = np.asarray(bw_array, dtype=float)
    bw_clean = bw_clean[np.isfinite(bw_clean) & (bw_clean > 0.0)]
    if len(bw_clean) == 0:
        return {
            "mean_bw": np.nan,
            "std_bw": np.nan,
            "median_bw": np.nan,
            "tib": np.nan,
            "entropy": np.nan,
            "fairness": np.nan,
        }

    # Raw statistics before median pre-filtering
    mean_bw = float(np.mean(bw_clean))
    std_bw = float(np.std(bw_clean, ddof=1)) if len(bw_clean) > 1 else 0.0
    median_bw = float(np.median(bw_clean))

    # 5-second median pre-filter as in BandwidthTracker.compute_stability_vs_window
    med_kernel = max(3, int(round(5.0 / slice_dur_sec)))
    if med_kernel % 2 == 0:
        med_kernel += 1
    bw_filt = median_filter(bw_clean, size=min(med_kernel, len(bw_clean)), mode="nearest")
    m_pts = len(bw_filt)

    # 1. Time-in-Band (TiB)
    med_val = float(np.median(bw_filt))
    tib = float(np.sum(np.abs(bw_filt - med_val) <= tol_hz) / m_pts)

    # 2. Normalized Shannon Entropy (H_norm) with adaptive binning
    if m_pts < 2:
        entropy = 0.0
    else:
        num_bins = min(max_bins, m_pts, max(2, int(round(np.sqrt(m_pts) * 1.8))))
        if np.ptp(bw_filt) < 1e-9:
            entropy = 0.0
        else:
            counts, _ = np.histogram(bw_filt, bins=num_bins)
            total = np.sum(counts)
            p = counts[counts > 0] / total
            if len(p) <= 1:
                entropy = 0.0
            else:
                h_val = -np.sum(p * np.log2(p))
                h_max = np.log2(len(counts))
                entropy = float(h_val / h_max)

    # 3. Jain's Fairness Index
    sum_val = float(np.sum(bw_filt))
    sum_sq_val = float(np.sum(bw_filt ** 2))
    fairness = float((sum_val ** 2) / (m_pts * sum_sq_val)) if sum_sq_val > 0 else np.nan

    return {
        "mean_bw": mean_bw,
        "std_bw": std_bw,
        "median_bw": median_bw,
        "tib": tib,
        "entropy": entropy,
        "fairness": fairness,
    }


def analyze_signal_bandwidth(signal, fs, f_low=0.0, f_high=None, cfg=None):
    """
    End-to-end execution of the `research-clean` bandwidth pipeline:
      1. High-resolution Welch PSD (`SpectralEngine.compute_welch_psd`)
      2. Prominence-based Macro-Lobe Watershed Segmentation (`SpectralEngine.segment_macro_lobes`)
      3. Direct Time-Domain Watershed Slice Bandwidth Tracking (`BandwidthTracker.compute_watershed_slice_bandwidth`)
      4. Stability & Fairness metrics (`TiB`, `Shannon Entropy`, `Jain's Fairness Index`)
    """
    if cfg is None:
        cfg = dict(DEFAULT_BW_CONFIG)
    else:
        merged = dict(DEFAULT_BW_CONFIG)
        merged.update(cfg)
        cfg = merged

    if f_high is None:
        f_high = fs / 2.0
    cfg["f_low"] = float(f_low)
    cfg["f_high"] = float(min(f_high, fs / 2.0))

    # Step 1: Welch PSD
    psd_db, f_grid, df, _ = compute_welch_psd(
        signal, fs, cfg["f_low"], cfg["f_high"], cfg["twin_welch"], cfg["df_eval"]
    )

    # Step 2: Macro-Lobe Segmentation
    macro_lobes, dom_lobe, ocean_floor_smooth, ocean_ambient_db = segment_macro_lobes(
        psd_db, f_grid, df, cfg["prom_split_db"]
    )

    # Step 3: Slice-by-Slice Watershed Bandwidth Tracking
    slice_dur_sec = float(cfg["slice_dur_sec"])
    slice_len = int(np.floor(fs * slice_dur_sec))
    total_samples = len(signal)
    num_slices = int(np.floor(total_samples / max(1, slice_len)))

    all_main_bws = []
    slice_times = []
    slice_l_freqs = []
    slice_r_freqs = []

    for i in range(num_slices):
        start = i * slice_len
        sig_slice = signal[start : start + slice_len]
        s_out = compute_single_slice_watershed_bandwidth(sig_slice, fs, dom_lobe, cfg)
        if s_out["found"] and np.isfinite(s_out["main_bw"]):
            all_main_bws.append(s_out["main_bw"])
            slice_times.append((i + 0.5) * slice_dur_sec)
            slice_l_freqs.append(s_out["l_freq"])
            slice_r_freqs.append(s_out["r_freq"])

    all_main_bws = np.asarray(all_main_bws, dtype=float)
    slice_times = np.asarray(slice_times, dtype=float)
    slice_l_freqs = np.asarray(slice_l_freqs, dtype=float)
    slice_r_freqs = np.asarray(slice_r_freqs, dtype=float)

    # Step 4: Midpoint representative slice for detailed diagnostics
    center_idx = int(round(total_samples / 2.0))
    start_idx = max(0, center_idx - slice_len // 2)
    end_idx = min(total_samples, start_idx + slice_len)
    sig_slice_center = signal[start_idx:end_idx]
    if len(sig_slice_center) < slice_len:
        sig_slice_center = np.pad(sig_slice_center, (0, slice_len - len(sig_slice_center)))

    center_out = compute_single_slice_watershed_bandwidth(sig_slice_center, fs, dom_lobe, cfg)

    # Step 5: Stability & Fairness Metrics
    stability = compute_stability_metrics(
        all_main_bws,
        slice_dur_sec=slice_dur_sec,
        tol_hz=cfg["tib_tolerance_hz"],
        max_bins=cfg["entropy_max_bins"],
    )

    center_out.update({
        "all_main_bws": all_main_bws,
        "slice_times": slice_times,
        "slice_l_freqs": slice_l_freqs,
        "slice_r_freqs": slice_r_freqs,
        "dom_lobe": dom_lobe,
        "macro_lobes": macro_lobes,
        "f_grid": f_grid,
        "psd_db": psd_db,
        "ocean_floor_smooth": ocean_floor_smooth,
        "ocean_ambient_db": ocean_ambient_db,
        "stability": stability,
    })
    return center_out


def compute_pll_phase_lock(signal, fs, f_center, bandpass_margin=80.0, loop_bw_hz=18.0, window_sec=1.5):
    """
    Port of the Digital Phase-Locked Loop (PLL) & Circular Fairness (Mean Resultant Length R)
    pipeline from `research/python/analysis/analyze_pll.py` and `analyze_fairness.py`.

    Tracks the carrier phase around `f_center` using a 2nd-order PI digital PLL
    (damping factor zeta = 0.707, noise bandwidth Bn = `loop_bw_hz`) and computes:
      - `phase_error`: Wrapped carrier phase deviation in [-pi, pi] relative to reference `f_center`
      - `freq_out`: Instantaneous PLL tracked frequency (Hz)
      - `plv_sliding`: Sliding-window Phase Locking Value / Mean Resultant Length R(t) in [0, 1]
      - `mean_plv`: Mean sliding PLV R across the signal
      - `global_r`: Global Circular Fairness Index |mean(exp(1j * phase_error))|
      - `phase_std_rad`: Circular standard deviation of the phase error (radians)
    """
    sig = np.asarray(signal, dtype=float).ravel()
    n_samples = len(sig)
    if n_samples < 32:
        return {
            "phase_error": np.zeros(n_samples),
            "freq_out": np.full(n_samples, f_center),
            "plv_sliding": np.zeros(n_samples),
            "mean_plv": 0.0,
            "global_r": 0.0,
            "phase_std_rad": np.nan,
        }

    # 1. Zero-phase 4th-order Butterworth bandpass filter around f_center
    nyq = 0.5 * fs
    low = max(10.0, f_center - bandpass_margin) / nyq
    high = min(nyq - 10.0, f_center + bandpass_margin) / nyq
    b, a = butter(4, [low, high], btype="band")
    filtered = filtfilt(b, a, sig)
    peak_abs = np.max(np.abs(filtered))
    if peak_abs > 1e-8:
        filtered = filtered / peak_abs

    # 2. Second-order Digital PLL loop filter gains (as in analyze_pll.py)
    zeta = 0.707
    wn = 2.0 * np.pi * loop_bw_hz / (zeta + 1.0 / (4.0 * zeta))
    kp = (2.0 * zeta * wn) / fs
    ki = (wn * wn) / (fs * fs)

    w_center = 2.0 * np.pi * f_center / fs
    max_dev = 2.0 * np.pi * 60.0 / fs

    phase_error = np.empty(n_samples, dtype=float)
    freq_out = np.empty(n_samples, dtype=float)

    phase = 0.0
    ref_phase = 0.0
    freq_integrator = 0.0
    sin_fn = np.sin
    two_pi = 2.0 * np.pi
    pi_val = np.pi

    for i in range(n_samples):
        pe = -filtered[i] * sin_fn(phase)
        freq_integrator += ki * pe
        if freq_integrator > max_dev:
            freq_integrator = max_dev
        elif freq_integrator < -max_dev:
            freq_integrator = -max_dev

        freq_ctrl = kp * pe + freq_integrator
        if freq_ctrl > max_dev:
            freq_ctrl = max_dev
        elif freq_ctrl < -max_dev:
            freq_ctrl = -max_dev

        phase += w_center + freq_ctrl
        ref_phase += w_center

        # Wrapped phase difference relative to the ideal unmodulated carrier
        phase_error[i] = (phase - ref_phase + pi_val) % two_pi - pi_val
        freq_out[i] = (w_center + freq_ctrl) * fs / two_pi

    # Remove mean constant phase offset so locked carrier centers around 0 rad
    unit_phasors = np.exp(1j * phase_error)
    mean_phasor = np.mean(unit_phasors)
    mean_angle = np.angle(mean_phasor)
    phase_error_centered = (phase_error - mean_angle + pi_val) % two_pi - pi_val

    # 3. Sliding-window Mean Resultant Length R(t) (Circular Fairness Index) without boundary roll-off
    win_samples = max(16, int(round(window_sec * fs)))
    cos_smooth = uniform_filter1d(np.cos(phase_error_centered), size=win_samples, mode="nearest")
    sin_smooth = uniform_filter1d(np.sin(phase_error_centered), size=win_samples, mode="nearest")
    plv_sliding = np.hypot(cos_smooth, sin_smooth)

    mean_plv = float(np.mean(plv_sliding))
    global_r = float(np.abs(mean_phasor))
    phase_std_rad = float(np.std(phase_error_centered))

    return {
        "phase_error": phase_error_centered,
        "freq_out": freq_out,
        "plv_sliding": plv_sliding,
        "mean_plv": mean_plv,
        "global_r": global_r,
        "phase_std_rad": phase_std_rad,
    }

