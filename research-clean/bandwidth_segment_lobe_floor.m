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
base_dir = 'c:\Users\Roy\Recordings';
dir_hear_my_ship = fullfile(base_dir, 'hear_my_ship', 'V1', 'Motor Boats');
dir_croatia      = fullfile(base_dir, 'Croatia', 'Ocean Sonics', '2407_1_600m');

% Dataset definitions with passband boundaries
cfg.datasets = struct(...
    'name',   {'Dataset 1: Motorboat (Hear My Ship)', ...
    'Dataset 2: Ocean Sonics (Croatia 600m)'}, ...
    'folder', {dir_hear_my_ship, dir_croatia}, ...
    'path',   {fullfile(dir_hear_my_ship, 'Motorboat_08.08.23_105220_20secCPA.wav'), ...
    fullfile(dir_croatia, 'RBW6737_20250724_092500.wav')}, ...
    'f_low',  {50,   400}, ...
    'f_high', {2000, 1200} ...
    );

% Standardized digital signal processing parameters
cfg.fs_common      = 48000;   % Standardized sampling rate (Hz)
cfg.dur_common     = 20.0;    % Analysis window duration (seconds)
cfg.df_eval        = 0.25;     % Uniform spectral evaluation grid step (Hz)

% Spectral estimation window durations
cfg.twin_welch     = 0.050;   % Welch window length (50 ms -> ~20 Hz resolution)
cfg.slice_dur_sec  = 0.250;   % Time-domain FFT slice duration for Hilbert analysis (250 ms)

% Watershed & Macro-Lobe segmentation parameters
cfg.prom_split_db  = 5.0;     % Inter-peak prominence drop for independent lobes (dB)
cfg.floor_return_db = 10.0;    % Max height above noise floor to be considered a 'return' (dB)
cfg.floor_dist_db  = 50.0;    % Max height above floor for prominence split (set high to always split)
cfg.fairness_window = 5;      % Window size for rolling Jain's fairness index
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

    % 3. Prominence-Based Macro-Lobe Watershed Segmentation
    % (Retains dominant frequency selection based on highest integrated energy)
    [macro_lobes, dom_lobe, ocean_floor_smooth, ocean_ambient_db] = ...
        segment_macro_lobes(psd_db, f_grid, df, cfg.prom_split_db, cfg.floor_return_db, cfg.floor_dist_db);

    % 4. Adaptive Peak Narrow-Band Tracking on Time-Domain Slices (Intersection Method)
    adaptive_peak_bw = compute_adaptive_peak_bandwidth(audio_sig, fs_actual, d_meta.f_low, d_meta.f_high, ...
        f_grid, ocean_floor_smooth, macro_lobes, ...
        cfg.slice_dur_sec, cfg.prom_split_db, cfg.fairness_window);

    % 4b. Direct Time-Domain Watershed Bandwidth on Slices
    watershed_bw = compute_watershed_bandwidth(audio_sig, fs_actual, ...
        d_meta.f_low, d_meta.f_high, psd_db, f_grid, macro_lobes, ocean_floor_smooth, ...
        cfg.slice_dur_sec, cfg.fairness_window);

    % 5. Time-Frequency 2D Spectrogram Computation
    [t_spec, f_spec, p_spec_db] = compute_spectrogram_matrix(audio_sig, fs_actual, ...
        d_meta.f_low, d_meta.f_high);

    % Assemble structured container
    res = struct();
    res.meta               = d_meta;
    res.audio_sig          = audio_sig;
    res.fs                 = fs_actual;
    res.f_grid             = f_grid;
    res.psd_db             = psd_db;
    res.macro_lobes        = macro_lobes;
    res.dom_lobe           = dom_lobe;
    res.ocean_floor_smooth = ocean_floor_smooth;
    res.ocean_ambient_db   = ocean_ambient_db;
    res.adaptive_peak_bw          = adaptive_peak_bw;
    res.watershed_bw       = watershed_bw;
    res.t_spec             = t_spec;
    res.f_spec             = f_spec;
    res.p_spec_db          = p_spec_db;

    analysis_results{k} = res;


end

% STREAMING_CHUNK:Rendering full graphical diagnostic figures...
render_spectral_and_cfar_figures(analysis_results, cfg);
render_slice_comparison_figures(analysis_results, cfg);
render_spectrogram_figures(analysis_results, cfg);
render_bandwidth_distribution(analysis_results, cfg);
render_outlier_figures(analysis_results, cfg);
print_diagnostic_summary(analysis_results);

% STREAMING_CHUNK:Conditioning audio and generating synthetic fallbacks...
% =========================================================================
% MODULE 3: AUDIO INGESTION & CONDITIONING
% =========================================================================
function [conditioned_sig, fs_target] = ingest_and_condition_audio(d_meta, cfg)
% Reads audio files up to the target duration or generates a synthetic benchmark.
fs_target = cfg.fs_common;
dur = cfg.dur_common;
target_samples = round(dur * fs_target);

raw_data = [];
fs_file = fs_target;

if exist(d_meta.path, 'file') == 2
    fprintf('  Loading raw data starting from: %s\n', d_meta.path);
    [dir_path, name, ext] = fileparts(d_meta.path);
    info = audioinfo(d_meta.path);
    fs_file = info.SampleRate;

    % If a single file satisfies the duration, center the extraction
    if info.Duration >= dur
        t_start = max(0, (info.Duration - dur) / 2);
        sample_bounds = round([t_start * fs_file + 1, (t_start + dur) * fs_file]);
        sample_bounds(2) = min(sample_bounds(2), info.TotalSamples);
        [sig, ~] = audioread(d_meta.path, sample_bounds);
        if size(sig, 2) > 1, sig = mean(sig, 2); end
        raw_data = sig;
        fprintf('    Loaded centered segment: %s\n', [name, ext]);
    else
        % We need to read this file and subsequent files from the directory
        [sig, ~] = audioread(d_meta.path);
        if size(sig, 2) > 1, sig = mean(sig, 2); end
        raw_data = sig;
        fprintf('    Loaded initial segment: %s\n', [name, ext]);

        % Get list of files in directory
        wavs = dir(fullfile(dir_path, '*.wav'));

        % Find the starting file index
        start_idx = 1;
        for w = 1:length(wavs)
            if strcmp(wavs(w).name, [name, ext])
                start_idx = w + 1;
                break;
            end
        end

        % Load subsequent files
        for w = start_idx:length(wavs)
            samples_needed = target_samples - length(raw_data);
            if samples_needed <= 0
                break;
            end

            file_path = fullfile(wavs(w).folder, wavs(w).name);
            info = audioinfo(file_path);
            read_len = min(info.TotalSamples, samples_needed);

            [sig, ~] = audioread(file_path, [1, read_len]);
            if size(sig, 2) > 1, sig = mean(sig, 2); end

            raw_data = [raw_data; sig];
            fprintf('    Loaded appended segment: %s\n', wavs(w).name);
        end
    end
end

if isempty(raw_data)
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


% STREAMING_CHUNK:Segmenting macro-lobes with ambient baseline valley tracking...
% =========================================================================
% MODULE 6: PROMINENCE-BASED MACRO-LOBE WATERSHED SEGMENTATION
% =========================================================================
function [macro_lobes, dom_lobe, ocean_floor_smooth, ocean_ambient_db] = segment_macro_lobes(psd_db, f_grid, df, prom_split_db, floor_return_db, floor_dist_db)
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

        is_ambient_floor_return = (delta_ambient_db(idx_v) <= floor_return_db);
        is_isolated_carrier_split = (min_drop >= prom_split_db) && (delta_ambient_db(idx_v) <= floor_dist_db);

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

% STREAMING_CHUNK:Deriving watershed bandwidth on time-domain slices...
function out = compute_watershed_bandwidth(signal, fs, f_low, f_high, psd_db_global, f_grid_global, macro_lobes_global, ocean_floor_smooth_global, slice_dur_sec, fairness_win)
if isempty(signal)
    out = struct('found', false, 'all_main_bws', [], 'all_fairness', []);
    return;
end

slice_len = floor(fs * slice_dur_sec);
total_samples = length(signal);
num_slices = floor(total_samples / slice_len);

all_main_bws = [];
slice_outputs = cell(num_slices, 1);
for i = 1:num_slices
    idx = (i-1)*slice_len + (1:slice_len);
    sig_slice = signal(idx);
    slice_out = compute_single_slice_watershed_bandwidth(sig_slice, fs, f_low, f_high, psd_db_global, f_grid_global, macro_lobes_global, ocean_floor_smooth_global);
    slice_out.slice_idx = i;
    slice_outputs{i} = slice_out;
    if slice_out.found && isfinite(slice_out.main_bw)
        all_main_bws = [all_main_bws; slice_out.main_bw];
    end
end

all_fairness = compute_successive_jains(all_main_bws, fairness_win);

% Extract Time-Domain Slice Centered on Midpoint for detailed visualization
center_idx = round(total_samples / 2);
start_idx  = max(1, center_idx - floor(slice_len / 2));
end_idx    = min(total_samples, start_idx + slice_len - 1);

sig_slice_center = signal(start_idx:end_idx);
if length(sig_slice_center) < slice_len
    sig_slice_center = [sig_slice_center; zeros(slice_len - length(sig_slice_center), 1)];
end

out = compute_single_slice_watershed_bandwidth(sig_slice_center, fs, f_low, f_high, psd_db_global, f_grid_global, macro_lobes_global, ocean_floor_smooth_global);
out.all_main_bws = all_main_bws;
out.all_fairness = all_fairness;
out.slice_outputs = slice_outputs;
end

function rolling_fairness = compute_successive_jains(x, window_size)
if numel(x) < window_size
    rolling_fairness = [];
    return;
end

rolling_fairness = NaN(numel(x)-window_size+1, 1);
for i = 1:numel(rolling_fairness)
    values = x(i:i+window_size-1);
    if all(isfinite(values) & values > 0)
        rolling_fairness(i) = sum(values)^2 / (window_size * sum(values.^2));
    end
end
end

function out = compute_single_slice_watershed_bandwidth(sig_slice, fs, f_low, f_high, psd_db_global, f_grid_global, macro_lobes_global, ocean_floor_smooth_global)
out = struct('found', false, 'main_bw', NaN, 'f_segment', [], 'psd_segment', [], ...
    'noise_floor_db', NaN, 'main_f', NaN, 'main_mag_db', NaN, ...
    'l_freq', NaN, 'r_freq', NaN, 'ocean_floor_smooth', []);

out.f_segment = f_grid_global;
out.psd_segment = psd_db_global;
out.ocean_floor_smooth = ocean_floor_smooth_global;

slice_len = length(sig_slice);
win = hann(slice_len);
sig_win = sig_slice .* win;
sig_fft = fft(sig_win);
f_axis = (0 : slice_len - 1)' * (fs / slice_len);
pos_mask = (f_axis >= f_low) & (f_axis <= f_high);
f_pos = f_axis(pos_mask);
mag_pos = abs(sig_fft(pos_mask));

if numel(mag_pos) < 2
    return;
end

[pk_mag, pk_idx] = max(mag_pos);
local_peak_freq = f_pos(pk_idx);

matched_lobe = [];
for m = 1:length(macro_lobes_global)
    lobe = macro_lobes_global(m);
    if local_peak_freq >= lobe.f_start && local_peak_freq <= lobe.f_end
        matched_lobe = lobe;
        break;
    end
end

if isempty(matched_lobe) && ~isempty(macro_lobes_global)
    % Fallback to closest lobe
    freq_diffs = arrayfun(@(l) min(abs(local_peak_freq - l.f_start), abs(local_peak_freq - l.f_end)), macro_lobes_global);
    [~, min_idx] = min(freq_diffs);
    matched_lobe = macro_lobes_global(min_idx);
end

if ~isempty(matched_lobe) && matched_lobe.bandwidth > 0
    f_start = max(f_low, matched_lobe.f_start - 50);
    f_end   = min(f_high, matched_lobe.f_end + 50);
    
    idx_mask = (f_pos >= f_start) & (f_pos <= f_end);
    f_segment = f_pos(idx_mask);
    mag_segment = mag_pos(idx_mask);
    
    if numel(mag_segment) < 3
        return;
    end
    
    mag_smooth = smoothdata(mag_segment, 'gaussian', 5);
    mag_smooth_db = 20 * log10(mag_smooth + eps);
    
    [pk_mag_smooth, pk_idx_smooth] = max(mag_smooth);
    local_peak_freq = f_segment(pk_idx_smooth);
    
    [v_mag, v_loc] = findpeaks(-mag_smooth_db, f_segment);
    v_mag = -v_mag;
    
    left_valleys_idx = find(v_loc < local_peak_freq);
    if isempty(left_valleys_idx)
        l_freq = f_segment(1);
    else
        l_freq = v_loc(left_valleys_idx(end));
    end
    
    right_valleys_idx = find(v_loc > local_peak_freq);
    if isempty(right_valleys_idx)
        r_freq = f_segment(end);
    else
        r_freq = v_loc(right_valleys_idx(1));
    end

    out.found = true;
    out.main_bw = r_freq - l_freq;
    out.main_f = local_peak_freq;
    out.main_mag_db = 20 * log10(pk_mag_smooth + eps);
    out.l_freq = l_freq;
    out.r_freq = r_freq;

    % Find the baseline noise floor at the local peak
    out.noise_floor_db = interp1(f_grid_global, ocean_floor_smooth_global, local_peak_freq, 'linear', 'extrap');
end
end

% STREAMING_CHUNK:Deriving adaptive peak -3dB bandwidth and side-lobes on time-domain slice...
function out = compute_adaptive_peak_bandwidth(signal, fs, f_low, f_high, f_grid_global, ocean_floor_smooth_global, macro_lobes_global, slice_dur_sec, prom_db, fairness_win)
if isempty(signal)
    out = struct('found', false, 'all_main_bws', [], 'all_fairness', []);
    return;
end

slice_len = floor(fs * slice_dur_sec);
total_samples = length(signal);
num_slices = floor(total_samples / slice_len);

all_main_bws = [];
slice_outputs = cell(num_slices, 1);
for i = 1:num_slices
    idx = (i-1)*slice_len + (1:slice_len);
    sig_slice = signal(idx);
    slice_out = compute_single_slice_adaptive_peak_bandwidth(sig_slice, fs, f_low, f_high, f_grid_global, ocean_floor_smooth_global, macro_lobes_global, prom_db);
    slice_out.slice_idx = i;
    slice_outputs{i} = slice_out;
    if slice_out.found && isfinite(slice_out.main_bw)
        all_main_bws = [all_main_bws; slice_out.main_bw];
    end
end

all_fairness = compute_successive_jains(all_main_bws, fairness_win);

% Extract Time-Domain Slice Centered on Midpoint for detailed visualization
center_idx = round(total_samples / 2);
start_idx  = max(1, center_idx - floor(slice_len / 2));
end_idx    = min(total_samples, start_idx + slice_len - 1);


sig_slice_center = signal(start_idx:end_idx);
if length(sig_slice_center) < slice_len
    sig_slice_center = [sig_slice_center; zeros(slice_len - length(sig_slice_center), 1)];
end

out = compute_single_slice_adaptive_peak_bandwidth(sig_slice_center, fs, f_low, f_high, f_grid_global, ocean_floor_smooth_global, macro_lobes_global, prom_db);
out.all_main_bws = all_main_bws;
out.all_fairness = all_fairness;
out.slice_outputs = slice_outputs;
end

function out = compute_single_slice_adaptive_peak_bandwidth(sig_slice, fs, f_low, f_high, f_grid_global, ocean_floor_smooth_global, macro_lobes_global, prom_db)
out = struct('found', false, 'main_bw', NaN, 'f_segment', [], 'mag_segment', [], ...
    'noise_floor', NaN, 'main_f', NaN, 'main_mag', NaN, ...
    'l_freq', NaN, 'r_freq', NaN);

slice_len = length(sig_slice);
win = hann(slice_len);
sig_win = sig_slice .* win;

sig_fft = fft(sig_win);
f_axis = (0 : slice_len - 1)' * (fs / slice_len);
pos_mask = (f_axis >= 0) & (f_axis <= fs / 2);
f_pos = f_axis(pos_mask);
mag_pos = abs(sig_fft(pos_mask));

% First, find the peak in the whole passband
f_start_full = f_low;
f_end_full   = f_high;

idx_mask_full = (f_pos >= f_start_full) & (f_pos <= f_end_full);
f_segment_full = f_pos(idx_mask_full);
mag_segment_full = mag_pos(idx_mask_full);

if numel(mag_segment_full) < 10
    return;
end

[~, pk_idx_full] = max(mag_segment_full);
pk_f_full = f_segment_full(pk_idx_full);

% Find which global macro_lobe this peak belongs to
matched_lobe = [];
for m = 1:length(macro_lobes_global)
    lobe = macro_lobes_global(m);
    if pk_f_full >= lobe.f_start && pk_f_full <= lobe.f_end
        matched_lobe = lobe;
        break;
    end
end

if isempty(matched_lobe) && ~isempty(macro_lobes_global)
    % Fallback to closest lobe
    freq_diffs = arrayfun(@(l) min(abs(pk_f_full - l.f_start), abs(pk_f_full - l.f_end)), macro_lobes_global);
    [~, min_idx] = min(freq_diffs);
    matched_lobe = macro_lobes_global(min_idx);
end

% Focus on the specified passband bounded by the matched lobe
if ~isempty(matched_lobe)
    f_start = max(f_low, matched_lobe.f_start - 50);
    f_end   = min(f_high, matched_lobe.f_end + 50);
else
    f_start = f_low;
    f_end   = f_high;
end

idx_mask = (f_pos >= f_start) & (f_pos <= f_end);
f_segment = f_pos(idx_mask);
mag_segment = mag_pos(idx_mask);

if numel(mag_segment) < 10
    return;
end

% Smooth linear magnitude
mag_smooth = smoothdata(mag_segment, 'gaussian', 5);

[pk_mag_smooth, pk_idx] = max(mag_smooth);
pk_f = f_segment(pk_idx);
pk_mag = mag_segment(pk_idx);

% Lookup noise floor from global smoothed floor instead of edge estimation
noise_floor_db = interp1(f_grid_global, ocean_floor_smooth_global, pk_f, 'linear', 'extrap');
noise_floor = 10^(noise_floor_db / 20); % convert dB back to linear magnitude

excess_peak = pk_mag_smooth - noise_floor;
if excess_peak <= 0
    return;
end

out.found = true;
out.f_segment = f_segment;
out.mag_segment = mag_segment;
out.noise_floor = noise_floor;
out.main_f = pk_f;
out.main_mag = pk_mag;

% Compute dynamic threshold based on half-prominence using MATLAB's findpeaks
mag_smooth_db = 20 * log10(mag_smooth + eps);
[pks, locs, w, p] = findpeaks(mag_smooth_db, f_segment);

if isempty(pks)
    % Fallback
    pk_db = 20 * log10(pk_mag + eps);
    nf_db = noise_floor_db;
    target_db = nf_db + 0.5 * (pk_db - nf_db);
else
    % Match closest peak to our identified max peak
    [~, match_idx] = min(abs(locs - pk_f));
    pk_db = pks(match_idx);
    
    nf_db = noise_floor_db;
    actual_prom_db = pk_db - nf_db;
    
    % Target is half-prominence relative to the global noise floor
    target_db = nf_db + (actual_prom_db / 2);
end

target_mag = 10^(target_db / 20);

% Search left for target magnitude intersection on RAW magnitude
nf_left_cross = find(mag_segment(1:pk_idx) <= target_mag, 1, 'last');
if isempty(nf_left_cross), [~, nf_left_cross] = min(mag_segment(1:pk_idx)); end

% Search right for target magnitude intersection on RAW magnitude
nf_right_rel = find(mag_segment(pk_idx:end) <= target_mag, 1, 'first');
if isempty(nf_right_rel), [~, nf_right_rel] = min(mag_segment(pk_idx:end)); end
nf_right_cross = pk_idx + nf_right_rel - 1;

f_left = interpolate_crossing(f_segment, mag_segment, nf_left_cross, nf_left_cross+1, target_mag, 'left');
f_right = interpolate_crossing(f_segment, mag_segment, nf_right_cross-1, nf_right_cross, target_mag, 'right');

out.l_freq = f_left;
out.r_freq = f_right;
out.target_mag = target_mag;
out.main_bw = f_right - f_left;
end

function crossing_frequency = interpolate_crossing(f, y, i1, i2, level, side)
if i1 < 1 || i2 > numel(y) || y(i2) == y(i1)
    if strcmp(side, 'left')
        crossing_frequency = f(max(1, min(numel(f), i1)));
    else
        crossing_frequency = f(max(1, min(numel(f), i2)));
    end
    return;
end
crossing_frequency = f(i1) + (level-y(i1)) * (f(i2)-f(i1))/(y(i2)-y(i1));
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
c_amb  = [0.50 0.55 0.65];  % Steel Gray

figure('Name', 'Figure 1: Macro-Lobe Watershed & Ambient Baseline', ...
    'Color', c_bg, 'Position', [30, 40, 1600, 470]);

for k = 1:num_data
    r = results{k};

    % Top Row: PSD with Macro-Lobes and Baselines
    ax_top = subplot(1, num_data, k);
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

    % Traces: PSD, Ambient Floor
    plot(ax_top, r.f_grid, r.psd_db, 'Color', c_psd, 'LineWidth', 1.2, 'DisplayName', 'Welch PSD (50 ms)');
    plot(ax_top, r.f_grid, r.ocean_floor_smooth, 'Color', c_amb, 'LineWidth', 1.2, 'LineStyle', ':', ...
        'DisplayName', sprintf('Ambient Baseline (%0.1f dB)', r.ocean_ambient_db));

    xlim(ax_top, [r.meta.f_low, r.meta.f_high]);
    ylabel(ax_top, 'PSD (dB/Hz)', 'FontSize', 9, 'FontWeight', 'bold', 'Color', c_text);
    title(ax_top, sprintf('%s\nMacro-Lobe Segmentation', r.meta.name), ...
        'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
    legend(ax_top, 'Location', 'northeast', 'TextColor', c_text, 'Color', [0.08 0.10 0.15], ...
        'EdgeColor', c_grid, 'FontSize', 7.5);
end
end

% STREAMING_CHUNK:Plotting Figure 2 with side-by-side slice bandwidths...
% =========================================================================
% MODULE 9B: FIGURE 2 - SLICE BANDWIDTH COMPARISON (ADAPTIVE PEAK VS WATERSHED)
% =========================================================================
function render_slice_comparison_figures(results, cfg)
num_data = length(results);
c_bg   = [0.07 0.09 0.13];
c_ax   = [0.10 0.12 0.18];
c_text = [0.92 0.94 0.97];
c_grid = [0.20 0.24 0.32];

figure('Name', 'Figure 2: Time-Domain Slice Bandwidth Comparison', ...
    'Color', c_bg, 'Position', [60, 80, 1600, 800]);

for k = 1:num_data
    r = results{k};

    % --- Column 1: Adaptive Peak Intersection Bandwidth ---
    h_adap = r.adaptive_peak_bw;
    ax_adap = subplot(num_data, 2, 2*k - 1);
    set(ax_adap, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, ...
        'GridColor', c_grid, 'GridAlpha', 0.5, 'LineWidth', 1.0);
    hold(ax_adap, 'on'); grid(ax_adap, 'on');

    if h_adap.found
        plot(ax_adap, h_adap.f_segment, 20*log10(h_adap.mag_segment+eps), 'Color', [0.75 0.80 0.88], 'LineWidth', 1.4, ...
            'DisplayName', 'Signal FFT Slice');

        yline(ax_adap, 20*log10(h_adap.noise_floor+eps), 'Color', [1.00 0.78 0.25], 'LineWidth', 1.4, 'LineStyle', ':', ...
            'DisplayName', 'Local Noise Floor');

        yline(ax_adap, 20*log10(h_adap.target_mag+eps), 'Color', [1.0 0.4 0.6], 'LineWidth', 1.2, 'LineStyle', '--', ...
            'DisplayName', 'Adaptive Intersection Threshold');

        plot(ax_adap, [h_adap.l_freq, h_adap.r_freq], 20*log10([h_adap.target_mag, h_adap.target_mag]+eps), 'd', ...
            'MarkerEdgeColor', [1.0 0.2 0.2], 'MarkerFaceColor', [1.0 0.2 0.2], 'MarkerSize', 8, ...
            'DisplayName', sprintf('Adaptive Peak BW: %.1f Hz', h_adap.main_bw));

        plot(ax_adap, h_adap.main_f, 20*log10(h_adap.main_mag+eps), 'v', ...
            'MarkerFaceColor', [0.20 0.90 0.55], 'MarkerEdgeColor', 'none', 'MarkerSize', 8, 'HandleVisibility', 'off');

        title(ax_adap, sprintf('%s (Adaptive Peak)\nMain Peak = %0.1f Hz | Base BW = %0.1f Hz', ...
            r.meta.name, h_adap.main_f, h_adap.main_bw), 'FontSize', 10.5, 'FontWeight', 'bold', 'Color', c_text);
    else
        title(ax_adap, sprintf('%s: Peak Not Found', r.meta.name), 'FontSize', 10.5, 'FontWeight', 'bold', 'Color', c_text);
    end
    xlabel(ax_adap, 'Frequency (Hz)', 'FontSize', 9.5, 'FontWeight', 'bold', 'Color', c_text);
    ylabel(ax_adap, 'Magnitude (dB)', 'FontSize', 9.5, 'FontWeight', 'bold', 'Color', c_text);
    legend(ax_adap, 'Location', 'best', 'TextColor', c_text, 'Color', [0.08 0.10 0.15], 'EdgeColor', c_grid, 'FontSize', 8);

    % --- Column 2: Watershed Bandwidth ---
    h_wat = r.watershed_bw;
    ax_wat = subplot(num_data, 2, 2*k);
    set(ax_wat, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, ...
        'GridColor', c_grid, 'GridAlpha', 0.5, 'LineWidth', 1.0);
    hold(ax_wat, 'on'); grid(ax_wat, 'on');

    if h_wat.found
        plot(ax_wat, h_wat.f_segment, h_wat.psd_segment, 'Color', [0.75 0.80 0.88], 'LineWidth', 1.4, ...
            'DisplayName', 'Signal Welch PSD Slice');

        plot(ax_wat, h_wat.f_segment, h_wat.ocean_floor_smooth, 'Color', [1.00 0.78 0.25], 'LineWidth', 1.4, 'LineStyle', ':', ...
            'DisplayName', 'Local Ambient Baseline');

        l_mag_wat = interp1(h_wat.f_segment, h_wat.psd_segment, h_wat.l_freq);
        r_mag_wat = interp1(h_wat.f_segment, h_wat.psd_segment, h_wat.r_freq);
        plot(ax_wat, [h_wat.l_freq, h_wat.r_freq], [l_mag_wat, r_mag_wat], 'd', ...
            'MarkerEdgeColor', [1.0 0.2 0.2], 'MarkerFaceColor', [1.0 0.2 0.2], 'MarkerSize', 8, ...
            'DisplayName', sprintf('Watershed BW: %.1f Hz', h_wat.main_bw));

        plot(ax_wat, h_wat.main_f, h_wat.main_mag_db, 'v', ...
            'MarkerFaceColor', [0.20 0.90 0.55], 'MarkerEdgeColor', 'none', 'MarkerSize', 8, 'HandleVisibility', 'off');

        title(ax_wat, sprintf('%s (Watershed)\nMain Peak = %0.1f Hz | Base BW = %0.1f Hz', ...
            r.meta.name, h_wat.main_f, h_wat.main_bw), 'FontSize', 10.5, 'FontWeight', 'bold', 'Color', c_text);
    else
        title(ax_wat, sprintf('%s: Peak Not Found', r.meta.name), 'FontSize', 10.5, 'FontWeight', 'bold', 'Color', c_text);
    end
    xlabel(ax_wat, 'Frequency (Hz)', 'FontSize', 9.5, 'FontWeight', 'bold', 'Color', c_text);
    ylabel(ax_wat, 'PSD (dB/Hz)', 'FontSize', 9.5, 'FontWeight', 'bold', 'Color', c_text);
    legend(ax_wat, 'Location', 'best', 'TextColor', c_text, 'Color', [0.08 0.10 0.15], 'EdgeColor', c_grid, 'FontSize', 8);

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
    end

    dom = r.dom_lobe;
    fprintf('  ----------------------------------------------------------\n');
    fprintf('  DOMINANT ENERGETIC LOBE:      [%0.1f - %0.1f Hz] (BW: %0.1f Hz)\n', ...
        dom.f_start, dom.f_end, dom.bandwidth);
    fprintf('    Summit Peak:                %0.2f dB/Hz @ %0.1f Hz\n', dom.peak_psd, dom.peak_freq);
    fprintf('    Acoustic Energy Fraction:   %0.2f%% OF TOTAL BAND POWER\n', dom.pct_energy);

    h_adap = r.adaptive_peak_bw;
    if h_adap.found
        fprintf('  ----------------------------------------------------------\n');
        fprintf('  ADAPTIVE PEAK BANDWIDTH:\n');
        fprintf('    MAIN PEAK       %0.2f Hz (Mag: %0.2f dB) | Base BW: %0.2f Hz\n', h_adap.main_f, 20*log10(h_adap.main_mag+eps), h_adap.main_bw);
    end

    h_wat = r.watershed_bw;
    if h_wat.found
        fprintf('  ----------------------------------------------------------\n');
        fprintf('  WATERSHED MAIN PEAK BANDWIDTH:\n');
        fprintf('    MAIN PEAK       %0.2f Hz (PSD: %0.2f dB/Hz) | Base BW: %0.2f Hz\n', h_wat.main_f, h_wat.main_mag_db, h_wat.main_bw);
    end


end
fprintf('\n============================================================\n\n');
end

% STREAMING_CHUNK:Rendering Figure 4 with bandwidth distribution histograms...
% =========================================================================
% MODULE 9D: FIGURE 4 - BANDWIDTH DISTRIBUTION HISTOGRAMS
% =========================================================================
function render_bandwidth_distribution(results, cfg)
num_data = length(results);
if num_data < 2
    return;
end

c_bg   = [0.07 0.09 0.13];
c_ax   = [0.10 0.12 0.18];
c_text = [0.92 0.94 0.97];
c_grid = [0.20 0.24 0.32];

figure('Name', 'Figure 4: Base Bandwidth & Fairness Distribution Comparison', ...
    'Color', c_bg, 'Position', [120, 160, 1500, 800]);

% --- Row 1: Adaptive Peak Metrics ---
ax1_adap = subplot(2, 2, 1);
set(ax1_adap, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, 'GridColor', c_grid, 'LineWidth', 1.0);
hold(ax1_adap, 'on'); grid(ax1_adap, 'on');

plot_kde(ax1_adap, results{1}.adaptive_peak_bw.all_main_bws, results{2}.adaptive_peak_bw.all_main_bws, ...
    results{1}.meta.name, results{2}.meta.name, 2.0);
title(ax1_adap, 'Adaptive Peak Main Peak Base BW Distribution', 'FontSize', 11, 'FontWeight', 'bold', 'Color', c_text);
xlabel(ax1_adap, 'Bandwidth (Hz)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
ylabel(ax1_adap, 'Probability Density', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
legend(ax1_adap, 'Location', 'best', 'TextColor', c_text, 'Color', [0.08 0.10 0.15], 'EdgeColor', c_grid);

ax2_adap = subplot(2, 2, 2);
set(ax2_adap, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, 'GridColor', c_grid, 'LineWidth', 1.0);
hold(ax2_adap, 'on'); grid(ax2_adap, 'on');

plot_kde(ax2_adap, results{1}.adaptive_peak_bw.all_fairness, results{2}.adaptive_peak_bw.all_fairness, ...
    results{1}.meta.name, results{2}.meta.name, 0.02);
title(ax2_adap, sprintf('Adaptive Peak Rolling Fairness (Window = %d)', cfg.fairness_window), 'FontSize', 11, 'FontWeight', 'bold', 'Color', c_text);
xlabel(ax2_adap, 'Jain''s Index', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
ylabel(ax2_adap, 'Probability Density', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
legend(ax2_adap, 'Location', 'best', 'TextColor', c_text, 'Color', [0.08 0.10 0.15], 'EdgeColor', c_grid);


% --- Row 2: Watershed Metrics ---
ax1_wat = subplot(2, 2, 3);
set(ax1_wat, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, 'GridColor', c_grid, 'LineWidth', 1.0);
hold(ax1_wat, 'on'); grid(ax1_wat, 'on');

plot_kde(ax1_wat, results{1}.watershed_bw.all_main_bws, results{2}.watershed_bw.all_main_bws, ...
    results{1}.meta.name, results{2}.meta.name, 2.0);
title(ax1_wat, 'Watershed Main Peak Base BW Distribution', 'FontSize', 11, 'FontWeight', 'bold', 'Color', c_text);
xlabel(ax1_wat, 'Bandwidth (Hz)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
ylabel(ax1_wat, 'Probability Density', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
legend(ax1_wat, 'Location', 'best', 'TextColor', c_text, 'Color', [0.08 0.10 0.15], 'EdgeColor', c_grid);

ax2_wat = subplot(2, 2, 4);
set(ax2_wat, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, 'GridColor', c_grid, 'LineWidth', 1.0);
hold(ax2_wat, 'on'); grid(ax2_wat, 'on');

plot_kde(ax2_wat, results{1}.watershed_bw.all_fairness, results{2}.watershed_bw.all_fairness, ...
    results{1}.meta.name, results{2}.meta.name, 0.02);
title(ax2_wat, sprintf('Watershed Rolling Fairness (Window = %d)', cfg.fairness_window), 'FontSize', 11, 'FontWeight', 'bold', 'Color', c_text);
xlabel(ax2_wat, 'Jain''s Index', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
ylabel(ax2_wat, 'Probability Density', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
legend(ax2_wat, 'Location', 'best', 'TextColor', c_text, 'Color', [0.08 0.10 0.15], 'EdgeColor', c_grid);
end

function plot_kde(ax, data_a, data_b, name_a, name_b, bw_kde)
data_a = data_a(isfinite(data_a) & data_a > 0);
data_b = data_b(isfinite(data_b) & data_b > 0);
if ~isempty(data_a)
    [f_a, xi_a] = ksdensity(data_a, 'Bandwidth', bw_kde);
    fill(ax, xi_a, f_a, [0.8 0.3 0.3], 'FaceAlpha', 0.5, 'EdgeColor', [0.6 0.2 0.2], 'LineWidth', 2, 'DisplayName', name_a);
end
if ~isempty(data_b)
    [f_b, xi_b] = ksdensity(data_b, 'Bandwidth', bw_kde);
    fill(ax, xi_b, f_b, [0.2 0.6 0.8], 'FaceAlpha', 0.5, 'EdgeColor', [0.1 0.4 0.6], 'LineWidth', 2, 'DisplayName', name_b);
end
end

% STREAMING_CHUNK:Rendering Figure 5 for Outlier Analysis...
% =========================================================================
% MODULE 9E: FIGURE 5 - OUTLIER SIGNAL SEGMENTS
% =========================================================================
function render_outlier_figures(results, cfg)
num_data = length(results);
c_bg   = [0.07 0.09 0.13];
c_ax   = [0.10 0.12 0.18];
c_text = [0.92 0.94 0.97];
c_grid = [0.20 0.24 0.32];

figure('Name', 'Figure 5: Outlier Signal Segments (Furthest from Mean BW)', ...
    'Color', c_bg, 'Position', [150, 180, 1600, 470]);

for k = 1:num_data
    r = results{k};
    % --- Adaptive Peak Outlier ---
    slices_adap = r.adaptive_peak_bw.slice_outputs;
    [valid_adap, bws_adap] = extract_valid_bws(slices_adap);

    if ~isempty(valid_adap)
        mean_bw_adap = mean(bws_adap);
        [~, max_dev_idx] = max(abs(bws_adap - mean_bw_adap));
        outlier_adap = slices_adap{valid_adap(max_dev_idx)};

        ax_adap = subplot(num_data, 2, 2*k - 1);
        set(ax_adap, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, 'GridColor', c_grid, 'LineWidth', 1.0);
        hold(ax_adap, 'on'); grid(ax_adap, 'on');

        plot(ax_adap, outlier_adap.f_segment, 20 * log10(outlier_adap.mag_segment + eps), 'Color', [0.20 0.82 1.00], 'LineWidth', 1.2, ...
            'DisplayName', sprintf('Slice %d (BW: %.1f Hz)', outlier_adap.slice_idx, outlier_adap.main_bw));
        yline(ax_adap, 20 * log10(outlier_adap.noise_floor + eps), 'Color', [0.8 0.4 0.4], 'LineStyle', '--', 'LineWidth', 1.2, 'DisplayName', 'Ambient Noise Floor');
        yline(ax_adap, 20 * log10(outlier_adap.target_mag + eps), 'Color', [1.0 0.4 0.6], 'LineWidth', 1.2, 'LineStyle', '--', 'DisplayName', 'Adaptive Threshold');
        plot(ax_adap, outlier_adap.l_freq, 20 * log10(outlier_adap.target_mag + eps), 'd', 'MarkerEdgeColor', [1.0 0.2 0.2], 'MarkerFaceColor', [1.0 0.2 0.2], 'MarkerSize', 6, 'HandleVisibility', 'off');
        plot(ax_adap, outlier_adap.r_freq, 20 * log10(outlier_adap.target_mag + eps), 'd', 'MarkerEdgeColor', [1.0 0.2 0.2], 'MarkerFaceColor', [1.0 0.2 0.2], 'MarkerSize', 6, 'HandleVisibility', 'off');

        title(ax_adap, sprintf('%s (Adaptive Peak Outlier)\nDev: %.1f Hz from Mean %.1f Hz', r.meta.name, abs(outlier_adap.main_bw - mean_bw_adap), mean_bw_adap), ...
            'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
        xlabel(ax_adap, 'Frequency (Hz)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
        ylabel(ax_adap, 'Magnitude (dB)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
        legend(ax_adap, 'Location', 'best', 'TextColor', c_text, 'Color', [0.08 0.10 0.15], 'EdgeColor', c_grid);
    end

    % --- Watershed Outlier ---
    slices_wat = r.watershed_bw.slice_outputs;
    [valid_wat, bws_wat] = extract_valid_bws(slices_wat);

    if ~isempty(valid_wat)
        mean_bw_wat = mean(bws_wat);
        [~, max_dev_idx] = max(abs(bws_wat - mean_bw_wat));
        outlier_wat = slices_wat{valid_wat(max_dev_idx)};

        ax_wat = subplot(num_data, 2, 2*k);
        set(ax_wat, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, 'GridColor', c_grid, 'LineWidth', 1.0);
        hold(ax_wat, 'on'); grid(ax_wat, 'on');

        plot(ax_wat, outlier_wat.f_segment, outlier_wat.psd_segment, 'Color', [0.20 0.82 1.00], 'LineWidth', 1.2, ...
            'DisplayName', sprintf('Slice %d (BW: %.1f Hz)', outlier_wat.slice_idx, outlier_wat.main_bw));
        yline(ax_wat, outlier_wat.noise_floor_db, 'Color', [0.8 0.4 0.4], 'LineStyle', '--', 'LineWidth', 1.2, 'DisplayName', 'Ambient Noise Floor');
        l_mag_out = interp1(outlier_wat.f_segment, outlier_wat.psd_segment, outlier_wat.l_freq);
        r_mag_out = interp1(outlier_wat.f_segment, outlier_wat.psd_segment, outlier_wat.r_freq);
        plot(ax_wat, outlier_wat.l_freq, l_mag_out, 'd', 'MarkerEdgeColor', [1.0 0.2 0.2], 'MarkerFaceColor', [1.0 0.2 0.2], 'MarkerSize', 6, 'HandleVisibility', 'off');
        plot(ax_wat, outlier_wat.r_freq, r_mag_out, 'd', 'MarkerEdgeColor', [1.0 0.2 0.2], 'MarkerFaceColor', [1.0 0.2 0.2], 'MarkerSize', 6, 'HandleVisibility', 'off');


        title(ax_wat, sprintf('%s (Watershed Outlier)\nDev: %.1f Hz from Mean %.1f Hz', r.meta.name, abs(outlier_wat.main_bw - mean_bw_wat), mean_bw_wat), ...
            'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
        xlabel(ax_wat, 'Frequency (Hz)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
        ylabel(ax_wat, 'PSD (dB/Hz)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
        legend(ax_wat, 'Location', 'best', 'TextColor', c_text, 'Color', [0.08 0.10 0.15], 'EdgeColor', c_grid);
    end
end
end

function [valid_slices, bws] = extract_valid_bws(slices)
valid_slices = [];
bws = [];
for i = 1:length(slices)
    if ~isempty(slices{i}) && slices{i}.found && isfinite(slices{i}.main_bw)
        valid_slices = [valid_slices; i];
        bws = [bws; slices{i}.main_bw];
    end
end
end