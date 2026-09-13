% =========================================================================
% UNDERWATER ACOUSTIC LOBE & NOISE FLOOR ANALYZER
% High-Performance Modular Pipeline for Passive Acoustic Signal Analysis
% =========================================================================
% Modules:
%   1. Central Configuration & Target Parameter Setup
%   2. Pipeline Orchestrator (Main Execution Loop)
%   3. Audio Ingestion, Resampling, and Signal Conditioning
%   4. Welch Power Spectral Density Estimation
%   5. Order-Statistic Noise Baseline Estimation (Moving Median & TPSW)
%   6. Prominence-Based Macro-Lobe Watershed Segmentation
%   7. Direct Time-Domain FFT & Hilbert Lower-Envelope Bandwidth (Exact Sub-Bin)
%   8. Time-Frequency Spectrogram Computation
%   9. Multi-Figure Interactive Visualizations (Figures 1, 2, and 3)
%  10. Diagnostic Reporting & Spectral Metrics Summary
% =========================================================================

clear; close all; clc;

% STREAMING_CHUNK:Configuring system paths and acoustic processing constants...
% =========================================================================
% MODULE 1: CENTRAL CONFIGURATION & TARGET PARAMETERS
% =========================================================================
function cfg = get_analysis_config()
% Defines all filepaths, frequency bounds, and algorithmic constants.
cfg = struct();

% Directory hierarchy
base_dir = 'D:\RoyStudies\Recordings';
dir_hear_my_ship = fullfile(base_dir, 'hear_my_ship', 'V1', 'Motor Boats');
dir_croatia      = fullfile(base_dir, 'Croatia', 'Ocean Sonics', '2407_1_600m');

% Dataset definitions with passband boundaries
cfg.datasets = struct(...
'name',   {'Dataset 1: Motorboat (Hear My Ship)', ...
'Dataset 2: Ocean Sonics (Croatia 600m)'}, ...
'folder', {dir_hear_my_ship, dir_croatia}, ...
'path',   {fullfile(dir_hear_my_ship, 'Motorboat (06.09.23_083534).wav'), ...
fullfile(dir_croatia, 'RBW6737_20250724_093000.wav')}, ...
'f_low',  {50,   400}, ...
'f_high', {2000, 2000} ...
);

% Standardized digital signal processing parameters
cfg.fs_common      = 48000;   % Standardized sampling rate (Hz)
cfg.dur_common     = 20.0;    % Analysis window duration (seconds)
cfg.df_eval        = 0.5;     % Uniform spectral evaluation grid step (Hz)

% Spectral estimation window durations
cfg.twin_welch     = 0.050;   % Welch window length (50 ms -> ~20 Hz resolution)
cfg.slice_dur_sec  = 0.250;   % Time-domain FFT slice duration for Hilbert analysis (250 ms)

% Two-Pass Split-Window (TPSW) CFAR parameters
cfg.tpsw_guard_hz  = 2.5;     % Guard band half-width (Hz)
cfg.tpsw_ref_hz    = 30.0;    % Reference noise band half-width (Hz)
cfg.tpsw_gate_db   = 3.0;     % Pass 1 peak censoring threshold (dB)
cfg.tpsw_thresh_db = 3.8;     % Pass 2 CFAR tonal detection threshold (dB)

% Watershed & Macro-Lobe segmentation parameters
cfg.prom_split_db  = 5.0;     % Inter-peak prominence drop for independent lobes (dB)
end

% STREAMING_CHUNK:Orchestrating end-to-end dataset analysis loop...
% =========================================================================
% MODULE 2: PIPELINE ORCHESTRATOR
% =========================================================================
cfg = get_analysis_config();
num_datasets = length(cfg.datasets);
analysis_results = cell(num_datasets, 1);

for k = 1:num_datasets
d_meta = cfg.datasets(k);
fprintf('\n============================================================\n');
fprintf('PROCESSING: %s\n', d_meta.name);
fprintf('============================================================\n');

% 1. Audio Ingestion & Preconditioning
[audio_sig, fs_actual] = ingest_and_condition_audio(d_meta, cfg);

% 2. High-Resolution Welch PSD Estimation
[psd_db, f_grid, df, k_welch] = compute_welch_psd(audio_sig, fs_actual, ...
    d_meta.f_low, d_meta.f_high, cfg.twin_welch, cfg.df_eval);

% 3. Order-Statistic Noise Baselines (Moving Median & TPSW)
[b_tpsw_db, b_med_db, idx_tonals, delta_tpsw, delta_med] = ...
    compute_noise_baselines(psd_db, f_grid, df, k_welch, cfg);

% 4. Prominence-Based Macro-Lobe Watershed Segmentation
% (Retains dominant frequency selection based on highest integrated energy)
[macro_lobes, dom_lobe, ocean_floor_smooth, ocean_ambient_db] = ...
    segment_macro_lobes(psd_db, f_grid, df, cfg.prom_split_db, idx_tonals);

% 5. Time-Domain Signal FFT & Hilbert Lower-Envelope Bandwidth
% (Centered on signal midpoint with sub-bin linear interpolation)
hilbert_bw = compute_signal_hilbert_bandwidth(audio_sig, fs_actual, ...
    dom_lobe.peak_freq, cfg.slice_dur_sec);

% 6. Time-Frequency 2D Spectrogram Computation
[t_spec, f_spec, p_spec_db] = compute_spectrogram_matrix(audio_sig, fs_actual, ...
    d_meta.f_low, d_meta.f_high);

% Assemble structured container
res = struct();
res.meta               = d_meta;
res.audio_sig          = audio_sig;
res.fs                 = fs_actual;
res.f_grid             = f_grid;
res.psd_db             = psd_db;
res.b_tpsw_db          = b_tpsw_db;
res.b_med_db           = b_med_db;
res.delta_tpsw         = delta_tpsw;
res.delta_med          = delta_med;
res.idx_tonals         = idx_tonals;
res.macro_lobes        = macro_lobes;
res.dom_lobe           = dom_lobe;
res.ocean_floor_smooth = ocean_floor_smooth;
res.ocean_ambient_db   = ocean_ambient_db;
res.hilbert_bw         = hilbert_bw;
res.t_spec             = t_spec;
res.f_spec             = f_spec;
res.p_spec_db          = p_spec_db;

analysis_results{k} = res;


end

% STREAMING_CHUNK:Rendering full graphical diagnostic figures...
render_spectral_and_cfar_figures(analysis_results, cfg);
render_dominant_hilbert_figures(analysis_results, cfg);
render_spectrogram_figures(analysis_results, cfg);
print_diagnostic_summary(analysis_results);

% STREAMING_CHUNK:Conditioning audio and generating synthetic fallbacks...
% =========================================================================
% MODULE 3: AUDIO INGESTION & CONDITIONING
% =========================================================================
function [conditioned_sig, fs_target] = ingest_and_condition_audio(d_meta, cfg)
% Reads the center segment of the audio file or generates a synthetic benchmark.
fs_target = cfg.fs_common;
dur = cfg.dur_common;
target_samples = round(dur * fs_target);

resolved_path = '';
if exist(d_meta.path, 'file') == 2
resolved_path = d_meta.path;
elseif exist(d_meta.folder, 'dir') == 7
wavs = dir(fullfile(d_meta.folder, '*.wav'));
if ~isempty(wavs)
resolved_path = fullfile(wavs(1).folder, wavs(1).name);
end
end

if ~isempty(resolved_path) && exist(resolved_path, 'file') == 2
fprintf('  Loading raw file: %s\n', resolved_path);
info = audioinfo(resolved_path);
fs_file = info.SampleRate;
total_sec = info.Duration;

if total_sec > dur
    t_start = max(0, (total_sec - dur) / 2);
    sample_bounds = round([t_start * fs_file + 1, (t_start + dur) * fs_file]);
    sample_bounds(2) = min(sample_bounds(2), info.TotalSamples);
    [raw_data, ~] = audioread(resolved_path, sample_bounds);
else
    [raw_data, ~] = audioread(resolved_path);
end


else
fprintf('  File not located. Generating synthetic benchmark signal...\n');
t = (0 : 1 / fs_target : dur)';
if contains(d_meta.name, 'Motorboat')
% STREAMING_CHUNK:Synthesizing motorboat benchmark signal with explicit multiplication...
% Motorboat: compound machinery (58 Hz, 140 Hz, 220 Hz) + cavitation (500-1100 Hz)
sig = 0.09 * sin(2 * pi * 58.0 * t) + ...
0.07 * sin(2 * pi * 140.5 * t) + ...
0.04 * sin(2 * pi * 218.0 * t) + ...
0.02 * sin(2 * pi * 920.0 * t);
[b_cav, a_cav] = butter(3, [500 1100] / (fs_target / 2), 'bandpass');
sig = sig + 0.12 * filter(b_cav, a_cav, randn(size(t))) + 0.003 * randn(size(t));
else
% STREAMING_CHUNK:Synthesizing Croatia benchmark signal with explicit multiplication...
% Croatia: clean ambient ocean + two independent stationary CW tonals
sig = 0.04 * sin(2 * pi * 583.0 * t) + ...
0.08 * sin(2 * pi * 631.5 * t) + ...
0.01 * sin(2 * pi * 1263.0 * t) + ...
0.0015 * randn(size(t));
end
raw_data = sig;
fs_file = fs_target;
end

% STREAMING_CHUNK:Resampling and removing low-frequency DC bias...
% Convert to mono
if size(raw_data, 2) > 1
raw_data = mean(raw_data, 2);
end

% Resample if necessary
if fs_file ~= fs_target
conditioned_sig = resample(raw_data, fs_target, fs_file);
else
conditioned_sig = raw_data;
end

% Enforce uniform record length
if length(conditioned_sig) < target_samples
conditioned_sig = [conditioned_sig; zeros(target_samples - length(conditioned_sig), 1)];
else
conditioned_sig = conditioned_sig(1:target_samples);
end

% DC offset removal and 20 Hz high-pass conditioning
conditioned_sig = conditioned_sig - mean(conditioned_sig);
[b_hp, a_hp] = butter(4, 20.0 / (fs_target / 2), 'high');
conditioned_sig = filtfilt(b_hp, a_hp, conditioned_sig);
end

% STREAMING_CHUNK:Estimating power spectral density with Welch averaging...
% =========================================================================
% MODULE 4: WELCH POWER SPECTRAL DENSITY ESTIMATION
% =========================================================================
function [psd_db, f_grid, df, k_welch] = compute_welch_psd(signal, fs, f_min, f_max, twin_sec, df_target)
% Computes high-resolution Welch PSD and interpolates onto a uniform frequency grid.
nwin = 2^nextpow2(fs * twin_sec);
win  = hamming(nwin);
nov  = floor(nwin * 0.75);
nfft = max(nwin, 8192);

[psd_raw, f_raw] = pwelch(signal, win, nov, nfft, fs);
k_welch = floor((length(signal) - nov) / (nwin - nov));

df = df_target;
f_grid = (f_min : df : f_max)';
psd_interp = interp1(f_raw, psd_raw, f_grid, 'pchip');
psd_db = 10 * log10(max(psd_interp, eps));
end

% STREAMING_CHUNK:Computing order-statistic and TPSW adaptive baselines...
% =========================================================================
% MODULE 5: ORDER-STATISTIC & TPSW BASELINE ESTIMATION
% =========================================================================
function [b_tpsw_db, b_med_db, idx_tonals, delta_tpsw, delta_med] = ...
compute_noise_baselines(psd_db, f_grid, df, k_welch, cfg)
% Calculates the local noise floor using:
% 1. Moving Median with Gamma/Erlang distribution bias correction.
% 2. Two-Pass Split-Window (TPSW) filter with guard cells and peak censoring.

N = length(psd_db);
p_lin = 10.^(psd_db / 10);

% --- 1. Linear Moving Median Baseline ---
bw_peak_hz = 1.3 / cfg.twin_welch;
peak_bins  = ceil(bw_peak_hz / df);
win_med    = 2 * ceil(1.5 * peak_bins) + 1;
b_med_raw  = movmedian(p_lin, win_med);

% Erlang bias scale factor for K averaged Welch blocks
if k_welch > 1
scale_welch = 1 / (1 - 1 / (3 * k_welch))^3;
else
scale_welch = 1 / log(2);
end
b_med_lin = scale_welch * b_med_raw;
b_med_db  = 10 * log10(max(b_med_lin, eps));
delta_med = psd_db - b_med_db;

% --- 2. Two-Pass Split-Window (TPSW) Baseline ---
g_bins = max(1, round(cfg.tpsw_guard_hz / df));
r_bins = max(2, round(cfg.tpsw_ref_hz / df));

% Pass 1: Local window averaging
tpsw_p1 = zeros(N, 1);
for i = 1:N
idx_l = max(1, i - g_bins - r_bins) : max(1, i - g_bins);
idx_r = min(N, i + g_bins) : min(N, i + g_bins + r_bins);
idx_l = idx_l(idx_l < i);
idx_r = idx_r(idx_r > i);
ref_vals = [psd_db(idx_l); psd_db(idx_r)];
if ~isempty(ref_vals)
tpsw_p1(i) = mean(ref_vals);
else
tpsw_p1(i) = psd_db(i);
end
end

% STREAMING_CHUNK:Applying CFAR thresholding and peak censoring...
% Pass 1 Censoring: Clip narrow peaks exceeding threshold
excess_p1 = psd_db - tpsw_p1;
psd_censored = psd_db;
mask_censor = excess_p1 > cfg.tpsw_gate_db;
psd_censored(mask_censor) = tpsw_p1(mask_censor);

% Pass 2: Re-estimate baseline from censored spectrum
b_tpsw_db = zeros(N, 1);
for i = 1:N
idx_l = max(1, i - g_bins - r_bins) : max(1, i - g_bins);
idx_r = min(N, i + g_bins) : min(N, i + g_bins + r_bins);
idx_l = idx_l(idx_l < i);
idx_r = idx_r(idx_r > i);
ref_vals = [psd_censored(idx_l); psd_censored(idx_r)];
if ~isempty(ref_vals)
b_tpsw_db(i) = mean(ref_vals);
else
b_tpsw_db(i) = psd_censored(i);
end
end

delta_tpsw = psd_db - b_tpsw_db;

% CFAR Detection of Discrete Spectral Lines
is_loc_pk = [false; (delta_tpsw(2:end-1) > delta_tpsw(1:end-2)) & ...
(delta_tpsw(2:end-1) >= delta_tpsw(3:end)); false];
idx_tonals = find(is_loc_pk & (delta_tpsw >= cfg.tpsw_thresh_db));
end

% STREAMING_CHUNK:Segmenting macro-lobes with ambient baseline valley tracking...
% =========================================================================
% MODULE 6: PROMINENCE-BASED MACRO-LOBE WATERSHED SEGMENTATION
% =========================================================================
function [macro_lobes, dom_lobe, ocean_floor_smooth, ocean_ambient_db] = ...
segment_macro_lobes(psd_db, f_grid, df, prom_split_db, idx_tonal_pks)
% Extracts broadband acoustic structures relative to ambient ocean baseline,
% resolving independent lobes via topographic saddle-point prominence splitting.
% Keeps dominant lobe selection strictly anchored to highest integrated linear energy.

N = length(psd_db);

% Smooth ambient ocean baseline via sliding minimum and percentile tracking
win_bg_bins = 2 * ceil(100.0 / df) + 1;
ocean_floor_raw = movmin(psd_db, win_bg_bins);
ocean_floor_smooth = smoothdata(ocean_floor_raw, 'gaussian', round(40.0 / df));
ocean_ambient_db = prctile(ocean_floor_smooth, 15);

% Net power elevation above ambient floor
delta_ambient_db = psd_db - ocean_floor_smooth;
p_lin_net = max(0, 10.^(psd_db / 10) - 10.^(ocean_floor_smooth / 10));
total_net_energy = trapz(f_grid, p_lin_net);

% Topographic saddle-point valley extraction on smoothed spectral envelope
psd_env = smoothdata(psd_db, 'gaussian', max(3, round(6.0 / df)));
is_local_min = [false; (psd_env(2:end-1) < psd_env(1:end-2)) & ...
(psd_env(2:end-1) <= psd_env(3:end)); false];
valleys = find(is_local_min);

% Peak summits
is_pk = [false; (psd_env(2:end-1) > psd_env(1:end-2)) & ...
(psd_env(2:end-1) >= psd_env(3:end)); false];
peaks = find(is_pk);

% STREAMING_CHUNK:Filtering acoustic boundaries and inter-harmonic saddles...
valid_valleys = [];
for v = 1:length(valleys)
idx_v = valleys(v);
left_pks  = peaks(peaks < idx_v);
right_pks = peaks(peaks > idx_v);
if ~isempty(left_pks) && ~isempty(right_pks)
pk_l = left_pks(end);
pk_r = right_pks(1);
drop_l = psd_env(pk_l) - psd_env(idx_v);
drop_r = psd_env(pk_r) - psd_env(idx_v);
min_drop = min(drop_l, drop_r);

    is_ambient_floor_return = (delta_ambient_db(idx_v) <= 3.0);
    is_isolated_carrier_split = (min_drop >= 7.0) && (delta_ambient_db(idx_v) <= 5.0);

    if is_ambient_floor_return || is_isolated_carrier_split
        valid_valleys = [valid_valleys; idx_v];
    end
end


end

% Partition regions
boundaries = unique([1; valid_valleys; N]);
cand_lobes = [];

for b = 1:length(boundaries) - 1
i_start = boundaries(b);
i_end   = boundaries(b + 1);
f_sub   = f_grid(i_start:i_end);
p_sub   = psd_db(i_start:i_end);
p_net_sub = p_lin_net(i_start:i_end);

[pk_val, pk_local] = max(p_sub);
pk_freq = f_sub(pk_local);
e_lobe  = trapz(f_sub, p_net_sub);
pct_e   = 100 * (e_lobe / max(total_net_energy, eps));

% Retain regions exhibiting measurable excess energy and elevation
if (pct_e >= 1.0) && ((pk_val - ocean_floor_smooth(i_start + pk_local - 1)) >= 2.5)
    i_core_start = i_start;
    while (i_core_start < i_start + pk_local - 1) && (delta_ambient_db(i_core_start) <= 1.0)
        i_core_start = i_core_start + 1;
    end
    i_core_end = i_end;
    while (i_core_end > i_start + pk_local - 1) && (delta_ambient_db(i_core_end) <= 1.0)
        i_core_end = i_core_end - 1;
    end

    lobe = struct();
    lobe.f_start      = f_grid(i_core_start);
    lobe.f_end        = f_grid(i_core_end);
    lobe.bandwidth    = lobe.f_end - lobe.f_start;
    lobe.peak_freq    = pk_freq;
    lobe.peak_psd     = pk_val;
    lobe.energy_lin   = e_lobe;
    lobe.pct_energy   = pct_e;
    
    cand_tonals = f_grid(idx_tonal_pks);
    lobe.internal_tonals = cand_tonals(cand_tonals >= lobe.f_start & cand_tonals <= lobe.f_end);
    
    cand_lobes = [cand_lobes; lobe];
end


end

if isempty(cand_lobes)
[max_val, max_idx] = max(psd_db);
dom_lobe = struct('f_start', f_grid(1), 'f_end', f_grid(end), ...
'bandwidth', f_grid(end) - f_grid(1), ...
'peak_freq', f_grid(max_idx), 'peak_psd', max_val, ...
'energy_lin', total_net_energy, 'pct_energy', 100, ...
'internal_tonals', []);
macro_lobes = dom_lobe;
else
% Dominant lobe selection strictly maintained as maximum integrated linear energy
[~, max_e_idx] = max([cand_lobes.energy_lin]);
dom_lobe = cand_lobes(max_e_idx);
macro_lobes = cand_lobes;
end
end

% STREAMING_CHUNK:Deriving dominant peak bandwidth on centered time-domain slice...
% =========================================================================
% MODULE 7: DIRECT TIME-DOMAIN FFT & HILBERT LOWER-ENVELOPE BANDWIDTH
% =========================================================================
function out = compute_signal_hilbert_bandwidth(signal, fs, dom_freq, slice_dur_sec)
% Derives the bandwidth of the dominant frequency using the original time-domain
% audio signal directly (not the Welch PSD).
% IMPROVEMENT 1: Aligns analysis slice to the signal's energetic midpoint.
% IMPROVEMENT 2: Implements exact sub-bin linear interpolation for intersection points.

out = struct('found', false, 'dom_freq', dom_freq, 'bandwidth', NaN, ...
'peak_amp', NaN, 'f_segment', [], 'fft_segment', [], ...
'trend', [], 'lower_env', [], 'l_freq', NaN, 'r_freq', NaN, ...
'l_amp', NaN, 'r_amp', NaN);

if isnan(dom_freq) || isempty(signal)
return;
end

% 1. Extract Time-Domain Slice Centered on Midpoint (Improvement 1: Timing Alignment)
slice_len = floor(fs * slice_dur_sec);
total_samples = length(signal);
center_idx = round(total_samples / 2);
start_idx  = max(1, center_idx - floor(slice_len / 2));
end_idx    = min(total_samples, start_idx + slice_len - 1);

sig_slice = signal(start_idx:end_idx);
if length(sig_slice) < slice_len
sig_slice = [sig_slice; zeros(slice_len - length(sig_slice), 1)];
end

% Apply Hann Window to eliminate boundary spectral leakage
win = hann(slice_len);
sig_win = sig_slice .* win;

% 2. Compute Direct FFT on Windowed Time Slice
sig_fft = fft(sig_win);
f_axis = (0 : slice_len - 1)' * (fs / slice_len);
pos_mask = (f_axis >= 0) & (f_axis <= fs / 2);
f_pos = f_axis(pos_mask);
spec_pos_db = 20 * log10(abs(sig_fft(pos_mask)) + 1e-12);

% STREAMING_CHUNK:Locking peak summit and detrending local spectral slice...
% 3. Extract Local Spectral Radius around the Dominant Frequency Peak Summit
[~, target_bin] = min(abs(f_pos - dom_freq));
search_half_bins = max(2, round(8.0 / (fs / slice_len)));
search_idx = max(1, target_bin - search_half_bins) : min(length(spec_pos_db), target_bin + search_half_bins);
[~, rel_pk] = max(spec_pos_db(search_idx));
peak_idx = search_idx(rel_pk);
dom_freq_actual = f_pos(peak_idx);

window_radius = 80;  % 80 bins flanking the dominant peak summit
seg_start = max(1, peak_idx - window_radius);
seg_end   = min(length(spec_pos_db), peak_idx + window_radius);

f_segment   = f_pos(seg_start:seg_end);
fft_segment = spec_pos_db(seg_start:seg_end);
dom_amp     = spec_pos_db(peak_idx);

% 4. Moving Median Detrending Baseline (41 bins)
trend = movmedian(fft_segment, 41);
ac_signal = fft_segment - trend;

% 5. Symmetric Mirror Padding to Eliminate Hilbert Gibbs Artifacts
pad_len = length(ac_signal);
ac_padded = [flipud(ac_signal); ac_signal; flipud(ac_signal)];
env_padded = abs(hilbert(ac_padded));
analytic_env = env_padded(pad_len + 1 : 2 * pad_len);

% Smooth analytic envelope to produce stable intersection contours
analytic_env = smoothdata(analytic_env, 'gaussian', 11);
lower_env = trend - analytic_env;

% STREAMING_CHUNK:Computing exact sub-bin linear intersection points...
% 6. True Sub-Bin Intersection Search (Improvement 2: Sub-Bin Zero Crossing)
peak_local_idx = peak_idx - seg_start + 1;
diff_curve = fft_segment - lower_env;  % Positive near peak, zero at intersection

% --- Exact Left Boundary Search ---
l_freq = NaN;
l_amp  = NaN;
found_left = false;
for i = peak_local_idx : -1 : 2
if (diff_curve(i) >= 0) && (diff_curve(i - 1) < 0)
% Exact linear interpolation between bin (i-1) and bin (i)
d0 = diff_curve(i - 1);
d1 = diff_curve(i);
alpha = -d0 / (d1 - d0);
l_freq = f_segment(i - 1) + alpha * (f_segment(i) - f_segment(i - 1));
l_amp  = lower_env(i - 1) + alpha * (lower_env(i) - lower_env(i - 1));
found_left = true;
break;
end
end
if ~found_left
% Fallback to closest approach
[~, best_l] = min(abs(diff_curve(1:peak_local_idx)));
l_freq = f_segment(best_l);
l_amp  = lower_env(best_l);
end

% --- Exact Right Boundary Search ---
r_freq = NaN;
r_amp  = NaN;
found_right = false;
for i = peak_local_idx : (length(diff_curve) - 1)
if (diff_curve(i) >= 0) && (diff_curve(i + 1) < 0)
% Exact linear interpolation between bin (i) and bin (i+1)
d0 = diff_curve(i);
d1 = diff_curve(i + 1);
alpha = -d0 / (d1 - d0);
r_freq = f_segment(i) + alpha * (f_segment(i + 1) - f_segment(i));
r_amp  = lower_env(i) + alpha * (lower_env(i + 1) - lower_env(i));
found_right = true;
break;
end
end
if ~found_right
% Fallback to closest approach
[~, best_r_rel] = min(abs(diff_curve(peak_local_idx:end)));
best_r = peak_local_idx + best_r_rel - 1;
r_freq = f_segment(best_r);
r_amp  = lower_env(best_r);
end

bandwidth = abs(r_freq - l_freq);

% Assemble structured output
out.found       = true;
out.dom_freq    = dom_freq_actual;
out.peak_amp    = dom_amp;
out.bandwidth   = bandwidth;
out.f_segment   = f_segment;
out.fft_segment = fft_segment;
out.trend       = trend;
out.lower_env   = lower_env;
out.l_freq      = l_freq;
out.r_freq      = r_freq;
out.l_amp       = l_amp;
out.r_amp       = r_amp;
end

% STREAMING_CHUNK:Computing 2D short-time Fourier spectrogram transform...
% =========================================================================
% MODULE 8: SPECTROGRAM MATRIX COMPUTATION
% =========================================================================
function [t_spec, f_spec_crop, p_spec_db] = compute_spectrogram_matrix(signal, fs, f_min, f_max)
% Generates 2D time-frequency spectrogram slice cropped to analysis passband.
nwin = 2^nextpow2(fs * 0.250);
nov  = floor(nwin * 0.90);
nfft = max(nwin, 4096);

[~, f_raw, t_spec, p_raw] = spectrogram(signal, hamming(nwin), nov, nfft, fs);
mask_f = (f_raw >= f_min) & (f_raw <= f_max);

f_spec_crop = f_raw(mask_f);
p_spec_db   = 10 * log10(max(p_raw(mask_f, :), eps));
end

% STREAMING_CHUNK:Styling Figure 1 with PSD, macro-lobes, and CFAR spectra...
% =========================================================================
% MODULE 9A: FIGURE 1 - SPECTRAL PSD, MACRO-LOBES & CFAR TONALS
% =========================================================================
function render_spectral_and_cfar_figures(results, cfg)
num_data = length(results);
c_bg   = [0.07 0.09 0.13];
c_ax   = [0.10 0.12 0.18];
c_text = [0.92 0.94 0.97];
c_grid = [0.20 0.24 0.32];
c_psd  = [0.20 0.82 1.00];  % Cyan
c_tpsw = [0.95 0.78 0.20];  % Gold
c_med  = [0.85 0.38 1.00];  % Magenta
c_amb  = [0.50 0.55 0.65];  % Steel Gray

figure('Name', 'Figure 1: Macro-Lobe Watershed & Order-Statistic Baselines', ...
'Color', c_bg, 'Position', [30, 40, 1600, 940]);

for k = 1:num_data
r = results{k};

% Top Row: PSD with Macro-Lobes and Baselines
ax_top = subplot(2, num_data, k);
set(ax_top, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, ...
            'GridColor', c_grid, 'GridAlpha', 0.5, 'LineWidth', 1.0);
hold(ax_top, 'on'); grid(ax_top, 'on');

% Fill dominant macro-lobe
dom = r.dom_lobe;
idx_dom = (r.f_grid >= dom.f_start) & (r.f_grid <= dom.f_end);
f_dom   = r.f_grid(idx_dom);
p_dom   = r.psd_db(idx_dom);
y_floor = min(r.psd_db) - 4;
fill(ax_top, [f_dom; flipud(f_dom)], [p_dom; y_floor * ones(size(p_dom))], ...
     [0.90 0.25 0.35], 'FaceAlpha', 0.35, 'EdgeColor', 'none', ...
     'DisplayName', sprintf('Dominant Lobe [%0.1f-%0.1f Hz | %0.1f%%]', ...
                            dom.f_start, dom.f_end, dom.pct_energy));

% Fill secondary candidate macro-lobes
for m = 1:length(r.macro_lobes)
    lob = r.macro_lobes(m);
    if lob.f_start ~= dom.f_start
        idx_m = (r.f_grid >= lob.f_start) & (r.f_grid <= lob.f_end);
        fill(ax_top, [r.f_grid(idx_m); flipud(r.f_grid(idx_m))], ...
             [r.psd_db(idx_m); y_floor * ones(sum(idx_m), 1)], ...
             [0.30 0.65 0.95], 'FaceAlpha', 0.18, 'EdgeColor', 'none', ...
             'DisplayName', sprintf('Lobe %d [%0.1f-%0.1f Hz | %0.1f%%]', ...
                                    m, lob.f_start, lob.f_end, lob.pct_energy));
    end
    xline(ax_top, lob.f_start, 'Color', [0.80 0.40 0.50], 'LineStyle', ':', 'LineWidth', 1.0, 'HandleVisibility', 'off');
    xline(ax_top, lob.f_end,   'Color', [0.80 0.40 0.50], 'LineStyle', ':', 'LineWidth', 1.0, 'HandleVisibility', 'off');
end

% Traces: PSD, Baselines, Ambient Floor
plot(ax_top, r.f_grid, r.psd_db, 'Color', c_psd, 'LineWidth', 1.2, 'DisplayName', 'Welch PSD (50 ms)');
plot(ax_top, r.f_grid, r.b_med_db, 'Color', c_med, 'LineWidth', 1.1, 'LineStyle', '--', 'DisplayName', 'Moving Median Baseline');
plot(ax_top, r.f_grid, r.b_tpsw_db, 'Color', c_tpsw, 'LineWidth', 1.2, 'LineStyle', '-.', 'DisplayName', 'TPSW CFAR Baseline');
plot(ax_top, r.f_grid, r.ocean_floor_smooth, 'Color', c_amb, 'LineWidth', 1.2, 'LineStyle', ':', ...
     'DisplayName', sprintf('Ambient Baseline (%0.1f dB)', r.ocean_ambient_db));

xlim(ax_top, [r.meta.f_low, r.meta.f_high]);
ylabel(ax_top, 'PSD (dB/Hz)', 'FontSize', 9, 'FontWeight', 'bold', 'Color', c_text);
title(ax_top, sprintf('%s\nMacro-Lobe Segmentation & Acoustic Baselines', r.meta.name), ...
      'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
legend(ax_top, 'Location', 'northeast', 'TextColor', c_text, 'Color', [0.08 0.10 0.15], ...
       'EdgeColor', c_grid, 'FontSize', 7.5);

% STREAMING_CHUNK:Rendering whitened spectral deflection and CFAR peaks...
% Bottom Row: Whitened CFAR Spectrum (TPSW Deflection)
ax_bot = subplot(2, num_data, k + num_data);
set(ax_bot, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, ...
            'GridColor', c_grid, 'GridAlpha', 0.5, 'LineWidth', 1.0);
hold(ax_bot, 'on'); grid(ax_bot, 'on');

pos_def = max(r.delta_tpsw, 0);
fill(ax_bot, [r.f_grid; flipud(r.f_grid)], [pos_def; zeros(size(pos_def))], ...
     c_tpsw, 'FaceAlpha', 0.25, 'EdgeColor', 'none', 'HandleVisibility', 'off');
plot(ax_bot, r.f_grid, r.delta_tpsw, 'Color', c_tpsw, 'LineWidth', 1.1, 'DisplayName', '\Delta_{TPSW} = PSD - B_{TPSW}');
yline(ax_bot, cfg.tpsw_thresh_db, 'Color', [1.0 0.35 0.40], 'LineStyle', ':', 'LineWidth', 1.2, ...
      'DisplayName', sprintf('CFAR Threshold (+%0.1f dB)', cfg.tpsw_thresh_db));

if ~isempty(r.idx_tonals)
    scatter(ax_bot, r.f_grid(r.idx_tonals), r.delta_tpsw(r.idx_tonals), 36, ...
            [0.25 0.92 0.60], 'filled', '^', 'DisplayName', sprintf('Tonal Lines (N = %d)', length(r.idx_tonals)));
end

xlim(ax_bot, [r.meta.f_low, r.meta.f_high]);
xlabel(ax_bot, 'Frequency (Hz)', 'FontSize', 9.5, 'FontWeight', 'bold', 'Color', c_text);
ylabel(ax_bot, 'Equalized Deflection (dB)', 'FontSize', 9, 'FontWeight', 'bold', 'Color', c_text);
title(ax_bot, 'Equalized / Whitened Spectrum (CFAR Line Extraction)', ...
      'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
legend(ax_bot, 'Location', 'northeast', 'TextColor', c_text, 'Color', [0.08 0.10 0.15], ...
       'EdgeColor', c_grid, 'FontSize', 8);


end
end

% STREAMING_CHUNK:Plotting Figure 2 with time-domain Hilbert lower envelopes...
% =========================================================================
% MODULE 9B: FIGURE 2 - TIME-DOMAIN FFT & HILBERT LOWER-ENVELOPE BANDWIDTH
% =========================================================================
function render_dominant_hilbert_figures(results, cfg)
num_data = length(results);
c_bg   = [0.07 0.09 0.13];
c_ax   = [0.10 0.12 0.18];
c_text = [0.92 0.94 0.97];
c_grid = [0.20 0.24 0.32];

figure('Name', 'Figure 2: Dominant Frequency Bandwidth via Time-Domain FFT & Hilbert Envelope', ...
'Color', c_bg, 'Position', [60, 80, 1500, 580]);

for k = 1:num_data
r = results{k};
h = r.hilbert_bw;

ax = subplot(1, num_data, k);
set(ax, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, ...
        'GridColor', c_grid, 'GridAlpha', 0.5, 'LineWidth', 1.0);
hold(ax, 'on'); grid(ax, 'on');

if h.found
    plot(ax, h.f_segment, h.fft_segment, 'Color', [0.75 0.80 0.88], 'LineWidth', 1.4, ...
         'DisplayName', 'Signal FFT Slice (0.25 s Hann @ Midpoint)');
    plot(ax, h.f_segment, h.trend, 'Color', [1.00 0.78 0.25], 'LineWidth', 1.4, 'LineStyle', ':', ...
         'DisplayName', 'Robust Trend (Moving Median)');
    plot(ax, h.f_segment, h.lower_env, 'Color', [0.25 0.75 1.00], 'LineWidth', 1.5, 'LineStyle', '--', ...
         'DisplayName', 'Lower Envelope (Padded Hilbert)');

    % Sub-Bin Interpolated Intersections (Plotted exactly on the intersection point)
    plot(ax, [h.l_freq, h.r_freq], [h.l_amp, h.r_amp], 'ro', ...
         'MarkerFaceColor', [1.00 0.30 0.40], 'MarkerSize', 8, 'LineWidth', 1.5, ...
         'DisplayName', sprintf('Exact Intersections (BW = %0.2f Hz)', h.bandwidth));
    xline(ax, h.dom_freq, 'Color', [0.20 0.90 0.55], 'LineWidth', 1.6, 'LineStyle', '-.', ...
          'DisplayName', sprintf('Dominant Peak: %0.1f Hz', h.dom_freq));

    title(ax, sprintf('%s: Dominant Peak Bandwidth\nPeak = %0.1f Hz | Sub-Bin Hilbert BW = %0.2f Hz', ...
                      r.meta.name, h.dom_freq, h.bandwidth), ...
          'FontSize', 10.5, 'FontWeight', 'bold', 'Color', c_text);
else
    title(ax, sprintf('%s: Dominant Frequency Not Found', r.meta.name), ...
          'FontSize', 10.5, 'FontWeight', 'bold', 'Color', c_text);
end

xlabel(ax, 'Frequency (Hz)', 'FontSize', 9.5, 'FontWeight', 'bold', 'Color', c_text);
ylabel(ax, 'Magnitude (dB)', 'FontSize', 9.5, 'FontWeight', 'bold', 'Color', c_text);
legend(ax, 'Location', 'best', 'TextColor', c_text, 'Color', [0.08 0.10 0.15], ...
       'EdgeColor', c_grid, 'FontSize', 8);


end
end

% STREAMING_CHUNK:Rendering Figure 3 with time-frequency 2D spectrograms...
% =========================================================================
% MODULE 9C: FIGURE 3 - HIGH-RESOLUTION 2D SPECTROGRAMS
% =========================================================================
function render_spectrogram_figures(results, cfg)
num_data = length(results);
c_bg   = [0.07 0.09 0.13];
c_ax   = [0.10 0.12 0.18];
c_text = [0.92 0.94 0.97];
c_grid = [0.20 0.24 0.32];

figure('Name', 'Figure 3: 2D Time-Frequency Spectrograms with Dominant Lobe Boundaries', ...
'Color', c_bg, 'Position', [90, 120, 1500, 600]);

for k = 1:num_data
r = results{k};
ax = subplot(1, num_data, k);
set(ax, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, ...
'GridColor', c_grid, 'LineWidth', 1.0);

% Render 2D Raster in kHz
f_khz = r.f_spec / 1000;
imagesc(ax, r.t_spec, f_khz, r.p_spec_db);
set(ax, 'YDir', 'normal');
colormap(ax, 'turbo');

% Contrast enhancement
c_lo = prctile(r.p_spec_db(:), 10);
c_hi = prctile(r.p_spec_db(:), 99.7);
if c_hi <= c_lo, c_hi = c_lo + 25; end
if exist('clim', 'builtin') || exist('clim', 'file')
    clim(ax, [c_lo, c_hi]);
else
    caxis(ax, [c_lo, c_hi]);
end

cb = colorbar(ax);
cb.Color = c_text;
ylabel(cb, 'PSD (dB/Hz)', 'Color', c_text, 'FontSize', 9);

% Overlay Dominant Macro-Lobe Boundaries
dom = r.dom_lobe;
yline(ax, dom.f_start / 1000, 'Color', [1.0 1.0 1.0], 'LineStyle', '--', 'LineWidth', 1.4);
yline(ax, dom.f_end   / 1000, 'Color', [1.0 1.0 1.0], 'LineStyle', '--', 'LineWidth', 1.4);

xlabel(ax, 'Time (s)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
ylabel(ax, 'Frequency (kHz)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
title(ax, sprintf('%s: Spectrogram [%d-%d Hz]\nDominant Lobe: [%0.1f - %0.1f Hz]', ...
                  r.meta.name, r.meta.f_low, r.meta.f_high, dom.f_start, dom.f_end), ...
      'FontSize', 10.5, 'FontWeight', 'bold', 'Color', c_text);


end
end

% STREAMING_CHUNK:Printing structured diagnostic summary to console...
% =========================================================================
% MODULE 10: DIAGNOSTIC REPORTING & CONSOLE OUTPUT
% =========================================================================
function print_diagnostic_summary(results)
fprintf('\n============================================================\n');
fprintf('ACOUSTIC LOBE & NOISE FLOOR ANALYSIS SUMMARY\n');
fprintf('============================================================\n');

for k = 1:length(results)
r = results{k};
fprintf('\n------------------------------------------------------------\n');
fprintf('  %s\n', r.meta.name);
fprintf('  Passband:                     %d - %d Hz\n', r.meta.f_low, r.meta.f_high);
fprintf('  Ambient Ocean Noise Floor:    %0.1f dB/Hz\n', r.ocean_ambient_db);
fprintf('  Detected Macro-Lobes:         %d partitioned regions\n', length(r.macro_lobes));
fprintf('  ----------------------------------------------------------\n');

for m = 1:length(r.macro_lobes)
    lob = r.macro_lobes(m);
    fprintf('    Lobe %d: [%5.1f - %5.1f Hz] (BW: %4.1f Hz) | Summit: %5.1f dB @ %5.1f Hz | Power: %4.1f%%\n', ...
            m, lob.f_start, lob.f_end, lob.bandwidth, lob.peak_psd, lob.peak_freq, lob.pct_energy);
    if ~isempty(lob.internal_tonals)
        fprintf('      -> Internal Tonals (CFAR): %s Hz\n', mat2str(lob.internal_tonals', 4));
    end
end

dom = r.dom_lobe;
fprintf('  ----------------------------------------------------------\n');
fprintf('  DOMINANT ENERGETIC LOBE:      [%0.1f - %0.1f Hz] (BW: %0.1f Hz)\n', ...
        dom.f_start, dom.f_end, dom.bandwidth);
fprintf('    Summit Peak:                %0.2f dB/Hz @ %0.1f Hz\n', dom.peak_psd, dom.peak_freq);
fprintf('    Acoustic Energy Fraction:   %0.2f%% OF TOTAL BAND POWER\n', dom.pct_energy);

h = r.hilbert_bw;
if h.found
    fprintf('  ----------------------------------------------------------\n');
    fprintf('  DOMINANT PEAK BANDWIDTH (Signal FFT + Hilbert @ Midpoint):\n');
    fprintf('    Peak Summit Frequency:      %0.2f Hz (Magnitude: %0.2f dB)\n', h.dom_freq, h.peak_amp);
    fprintf('    Exact Sub-Bin Hilbert BW:   %0.2f Hz (Bounds: %0.2f - %0.2f Hz)\n', ...
            h.bandwidth, h.l_freq, h.r_freq);
    fprintf('    Boundary Amplitudes:        Left = %0.2f dB | Right = %0.2f dB\n', ...
            h.l_amp, h.r_amp);
end


end
fprintf('\n============================================================\n\n');
end