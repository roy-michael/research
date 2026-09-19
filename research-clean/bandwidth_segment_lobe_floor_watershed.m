% =========================================================================
% UNDERWATER ACOUSTIC LOBE & NOISE FLOOR ANALYZER
% High-Performance Modular Pipeline for Passive Acoustic Signal Analysis
% =========================================================================
% Modules:
%   1. Central Configuration & Target Parameter Setup (AudioCore)
%   2. Pipeline Orchestrator (Main Execution Loop)
%   3. Audio Ingestion, Resampling, and Signal Conditioning (AudioCore)
%   4. Welch Power Spectral Density Estimation (SpectralEngine)
%   5. Order-Statistic Noise Baseline Estimation (SpectralEngine)
%   6. Prominence-Based Macro-Lobe Watershed Segmentation (SpectralEngine)
%   7. Direct Time-Domain Watershed Bandwidth Tracking (BandwidthTracker)
%   8. Time-Frequency Spectrogram Computation (SpectralEngine)
%   9. Multi-Figure Interactive Visualizations (Visualizer)
%  10. Diagnostic Reporting & Spectral Metrics Summary (Visualizer)
% =========================================================================

clear; close all; clc;

% Defines all filepaths, frequency bounds, and algorithmic constants.
cfg = struct();



% Directory hierarchy
base_dir = 'D:\RoyStudies\Recordings';
dir_hear_my_ship = fullfile(base_dir, 'hear_my_ship', 'V1', 'Motor Boats');
dir_haifa        = fullfile(base_dir, '20250805_Haifa_bay_LME', 'extracted');
dir_croatia      = fullfile(base_dir, 'Croatia', 'Ocean Sonics', '2407_1_600m');
dir_cruise       = fullfile(base_dir, 'DepartmentalCruise-2025-06-12', 'icListen', 'wav')
% Dataset definitions with passband boundaries
cfg.datasets = struct(...
    'name',   {'Motorboat', ...
    'SUEX VR-X DVP', ...
    'SEACRAFT GO! DVP'}, ...
    'folder', {dir_hear_my_ship, dir_haifa, dir_cruise}, ...
    'path',   {
    % fullfile(dir_hear_my_ship, 'Motorboat_08.08.23_105220_20secCPA.wav'), ...
    fullfile(dir_haifa, 'channelA_2025-08-07_20-44-20_02.wav'), ...
    fullfile(dir_croatia, 'RBW6737_20250724_093800.wav'), ...
    fullfile(dir_cruise, 'RBW6922_20250612_063100.wav')}, ...
    'f_low',  {0,   400, 400}, ...
    'f_high', {2000, 2000, 2000} ...
    );

% Standardized digital signal processing parameters
cfg.fs_common      = 48000;   % Standardized sampling rate (Hz)
cfg.dur_common     = 60.0;    % Analysis window duration (seconds)
cfg.df_eval        = 0.25;     % Uniform spectral evaluation grid step (Hz)

% Spectral estimation window durations
cfg.twin_welch     = 0.050;   % Welch window length (50 ms -> ~20 Hz resolution)
cfg.slice_dur_sec  = 0.500;   % Time-domain FFT slice duration for Hilbert analysis (250 ms)

% Watershed & Macro-Lobe segmentation parameters
cfg.prom_split_db  = 5.0;     % Inter-peak prominence drop for independent lobes (dB)
cfg.fairness_window = 5;      % Window size for rolling Jain's fairness index
cfg.tib_tolerance_hz = 10;    % Tolerance for Time-in-Band stability metric (Hz)
cfg.bw_smooth_method = 'welch';    % Smoothing method for segmented signal before BW detection
cfg.bw_smooth_window = 5;          % Window size for smoothing the segmented signal
num_datasets = length(cfg.datasets);
analysis_results = cell(num_datasets, 1);

for k = 1:num_datasets
    d_meta = cfg.datasets(k);
    fprintf('\n============================================================\n');
    fprintf('PROCESSING: %s\n', d_meta.name);
    fprintf('============================================================\n');

    % 1. Audio Ingestion & Preconditioning
    [audio_sig, fs_actual] = AudioCore.ingest_and_condition_audio(d_meta, cfg);

    % 2. High-Resolution Welch PSD Estimation
    [psd_db, f_grid, df, k_welch] = SpectralEngine.compute_welch_psd(audio_sig, fs_actual, ...
        d_meta.f_low, d_meta.f_high, cfg.twin_welch, cfg.df_eval);

    % 3. Prominence-Based Macro-Lobe Watershed Segmentation
    [macro_lobes, dom_lobe, ocean_floor_smooth, ocean_ambient_db] = ...
        SpectralEngine.segment_macro_lobes(psd_db, f_grid, df, cfg.prom_split_db);

    % 4. Direct Time-Domain Watershed Bandwidth on 250ms Slices
    slice_bw = BandwidthTracker.compute_watershed_slice_bandwidth(audio_sig, fs_actual, ...
        dom_lobe, cfg.slice_dur_sec, cfg.fairness_window, cfg.bw_smooth_method, cfg.bw_smooth_window, cfg.tib_tolerance_hz);
    cfg.tib_tolerance_hz = 10;    % Tolerance for Time-in-Band stability metric (Hz)

    % 5. Time-Frequency 2D Spectrogram Computation
    [t_spec, f_spec, p_spec_db] = SpectralEngine.compute_spectrogram_matrix(audio_sig, fs_actual, ...
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
    res.slice_bw           = slice_bw;
    res.t_spec             = t_spec;
    res.f_spec             = f_spec;
    res.p_spec_db          = p_spec_db;

    analysis_results{k} = res;
end

% Rendering full graphical diagnostic figures
Visualizer.render_spectral_and_cfar_figures(analysis_results, cfg);
Visualizer.render_dominant_watershed_figures(analysis_results, cfg);
Visualizer.render_bandwidth_distribution(analysis_results, cfg);
Visualizer.render_outlier_figures(analysis_results, cfg);
Visualizer.render_spectrogram_figures(analysis_results, cfg);
Visualizer.print_diagnostic_summary(analysis_results);

