% Script to analyze all WAV files in a directory similar to analyze_single_file.m
clear; close all; clc;

target_dir = 'D:\RoyStudies\Recordings\Croatia\wav';
files = dir(fullfile(target_dir, '**', '*.wav'));

if isempty(files)
    fprintf('No WAV files found in %s\n', target_dir);
    return;
end

all_dom_freqs_cell = cell(length(files), 1);
all_bws_cell = cell(length(files), 1);
all_psd_db_cell = cell(length(files), 1);
all_times_cell = cell(length(files), 1);
global_f_grid = [];

% Setup Directories
script_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(script_dir, '..'));

for f_idx = 1:length(files)
    cfg = struct();
    cfg.target_file = fullfile(files(f_idx).folder, files(f_idx).name);
    cfg.target_fs = 8000;          % Target sampling rate for processing (Hz)

    % Spectrogram Parameters
    cfg.window_dur_sec = 1.00;     % Window duration in seconds
    cfg.overlap_ratio = 0.90;      % Overlap ratio for smooth time axis (0 to 1)
    cfg.f_low = 400;                % Lower frequency bound (Hz)
    cfg.f_high = 1600;              % Upper frequency bound (Hz)
    cfg.nfft = [];                 % Custom NFFT size. Leave empty `[]` to auto-calculate
    cfg.remove_transients = true;  % Erase vertical broadband clicks using a horizontal median filter
    cfg.transient_filter_width = 10;% Number of time-pixels to look across when filtering transients
    cfg.prctile_clip = 99.5;       % Percentile for upper color limit contrast (e.g. 99.5)

    % SpectralEngine Batch Tracking Parameters
    cfg.segment_duration = 60;    % Duration of each Welch segment (seconds)
    cfg.step_duration = 60;        % Sliding window step size (seconds)
    cfg.twin_welch = 0.050;        % Welch window size (seconds)
    cfg.df_eval = 0.50;            % Frequency interpolation grid size (Hz)
    cfg.prom_split_db = 3.0;       % Peak prominence for lobe segmentation

    % Bandwidth Tracker Parameters
    cfg.bw_slice_dur_sec = 0.500;
    cfg.bw_watershed_prom_max_db = 8.0;
    cfg.bw_watershed_prom_min_db = 3.0;
    cfg.bw_watershed_prom_ratio = 0.40;
    cfg.bw_watershed_noise_fallback_margin = 0.90;
    cfg.bw_smooth_method = 'welch';
    cfg.bw_smooth_window = 5;
    cfg.bw_tib_tolerance_hz = 10;
    cfg.bw_fairness_window = 5;

    [~, filename, ~] = fileparts(cfg.target_file);
    out_dir = fullfile(script_dir, 'output', 'Croatia', filename);
    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end

    %% Load Audio
    fprintf('Loading and downsampling %s...\n', filename);

    try
        info = audioinfo(cfg.target_file);
    catch ME
        fprintf('Error reading file: %s\n', ME.message);
        continue;
    end

    fs = info.SampleRate;
    if isfield(info, 'TotalSamples') && info.TotalSamples == 0
        fprintf('File has 0 samples, skipping...\n');
        continue;
    end
    try
        sig = audioread(cfg.target_file);
    catch ME
        fprintf('Failed to audioread file: %s\n', ME.message);
        continue;
    end
    if isempty(sig)
        continue;
    end
    if size(sig, 2) > 1
        sig = mean(sig, 2);
    end
    sig = sig - mean(sig);

    if fs > cfg.target_fs || fs < cfg.target_fs
        [p_res, q_res] = rat(cfg.target_fs / fs);
        sig = resample(sig, p_res, q_res);
    end

    fs = cfg.target_fs;
    total_duration = length(sig) / fs;
    fprintf('Finished loading. Total duration: %.2f minutes.\n', total_duration/60);

    % Extract base datetime from the file name (e.g. merged_record_20250722_183004)
    time_str = regexp(filename, '\d{8}_\d{6}', 'match', 'once');
    if ~isempty(time_str)
        base_time = datetime(time_str, 'InputFormat', 'yyyyMMdd_HHmmss');
    else
        base_time = datetime('today'); % Fallback
    end

    %% 1. PLOT HIGH-RES SPECTROGRAM
    if false
        fprintf('Computing high-resolution spectrogram...\n');

        window = round(fs * cfg.window_dur_sec);
        noverlap = round(window * cfg.overlap_ratio);

        if isempty(cfg.nfft)
            nfft = 2^nextpow2(window * 2);
        else
            nfft = cfg.nfft;
        end

        [~, f_spec, t_spec, p_spec] = spectrogram(sig, window, noverlap, nfft, fs);

        f_mask = (f_spec >= cfg.f_low) & (f_spec <= cfg.f_high);
        f_band = f_spec(f_mask);
        p_band = p_spec(f_mask, :);

        p_db = 10 * log10(p_band + eps);

        % --- TRANSIENT NOISE REMOVAL ---
        if cfg.remove_transients
            p_db = medfilt1(p_db, cfg.transient_filter_width, [], 2);
        end

        median_profile = median(p_db, 2);
        p_db_clean = bsxfun(@minus, p_db, median_profile);
        p_db_clean(p_db_clean < 0) = 0;

        p_max = prctile(p_db_clean(:), cfg.prctile_clip);
        if p_max <= 0; p_max = 1; end

        % Convert relative seconds to absolute datenum
        t_absolute = datenum(base_time + seconds(t_spec));

        fig1 = figure('Name', 'Continuous Spectrogram', 'Position', [50, 50, 1800, 600], 'Color', 'w');
        imagesc(t_absolute, f_band, p_db_clean);
        axis xy;
        caxis([0, p_max]);
        colormap jet;
        ylim([cfg.f_low, cfg.f_high]);
        c = colorbar;
        c.Label.String = 'Relative Power (dB above median)';

        datetick('x', 'HH:MM', 'keepticks', 'keeplimits');

        title(sprintf('Continuous High-Res Spectrogram (Start: %%s UTC)', datestr(base_time, 'yyyy-mm-dd HH:MM:SS')), 'FontSize', 14);
        xlabel('Time (UTC)', 'FontSize', 12);
        ylabel('Frequency (Hz)', 'FontSize', 12);

        spec_out = fullfile(out_dir, 'continuous_spectrogram.png');
        exportgraphics(fig1, spec_out, 'Resolution', 300);
        close(fig1);
        fprintf('Saved continuous spectrogram: %s\n', spec_out);
    end

    %% 2. RUN BATCH LOBE ANALYSIS (SpectralEngine)
    fprintf('Running sliding-window lobe analysis on continuous signal...\n');

    cfg_bw = struct();
    cfg_bw.slice_dur_sec = cfg.bw_slice_dur_sec;
    cfg_bw.watershed_prom_max_db = cfg.bw_watershed_prom_max_db;
    cfg_bw.watershed_prom_min_db = cfg.bw_watershed_prom_min_db;
    cfg_bw.watershed_prom_ratio = cfg.bw_watershed_prom_ratio;
    cfg_bw.watershed_noise_fallback_margin = cfg.bw_watershed_noise_fallback_margin;
    cfg_bw.bw_smooth_method = cfg.bw_smooth_method;
    cfg_bw.bw_smooth_window = cfg.bw_smooth_window;
    cfg_bw.twin_welch = cfg.twin_welch;
    cfg_bw.tib_tolerance_hz = cfg.bw_tib_tolerance_hz;
    cfg_bw.fairness_window = cfg.bw_fairness_window;

    start_times = 0:cfg.step_duration:(total_duration - cfg.segment_duration);
    if isempty(start_times)
        start_times = 0; % If file is shorter than segment duration
    end
    num_segments = length(start_times);

    report_path = fullfile(out_dir, 'dominant_frequencies_report.txt');
    fid = fopen(report_path, 'w');
    fprintf(fid, 'Analysis of: %s\n', cfg.target_file);
    fprintf(fid, 'Total Duration: %.2f seconds (%.2f minutes)\n', total_duration, total_duration/60);
    fprintf(fid, '======================================================\n');
    fprintf(fid, 'Segment Index | Start Time (m) | End Time (m) | Dominant Freq (Hz) | Peak PSD (dB) | Bandwidth (Hz)\n');

    results = struct('start_time', {}, 'end_time', {}, 'dom_freq', {}, 'peak_psd', {}, 'bw', {}, 'psd_db', {});



    % Filter the entire signal once for Welch
    [b_hp, a_hp] = butter(4, 20.0 / (fs / 2), 'high');
    sig_filt = filtfilt(b_hp, a_hp, sig);



    for i = 1:num_segments
        start_time = start_times(i);
        end_time = min(total_duration, start_time + cfg.segment_duration);

        start_sample = max(1, round(start_time * fs) + 1);
        end_sample = round(end_time * fs);

        segment_sig = sig_filt(start_sample:end_sample);

        [psd_db, f_grid, df, k_welch] = SpectralEngine.compute_welch_psd(segment_sig, fs, cfg.f_low, cfg.f_high, cfg.twin_welch, cfg.df_eval);

        f_notch_low = 300;
        f_notch_high = 360;
        mask_interf = (f_grid >= f_notch_low) & (f_grid <= f_notch_high);
        idx_left = find(f_grid < f_notch_low, 1, 'last');
        idx_right = find(f_grid > f_notch_high, 1, 'first');
        if ~isempty(idx_left) && ~isempty(idx_right)
            psd_db(mask_interf) = interp1([f_grid(idx_left), f_grid(idx_right)], ...
                [psd_db(idx_left), psd_db(idx_right)], f_grid(mask_interf), 'linear');
        end

        [macro_lobes, dom_lobe, ocean_floor_smooth, ocean_ambient_db] = ...
            SpectralEngine.segment_macro_lobes(psd_db, f_grid, df, cfg.prom_split_db);

        slice_bw = BandwidthTracker.compute_watershed_slice_bandwidth(segment_sig, fs, dom_lobe, cfg_bw);
        med_bw = median(slice_bw.all_main_bws, 'omitnan');

        % Grouping disabled per user request

        results(i).start_time = start_time;
        results(i).end_time = end_time;
        results(i).dom_freq = dom_lobe.peak_freq;
        results(i).peak_psd = dom_lobe.peak_psd;
        results(i).bw = med_bw;
        results(i).psd_db = psd_db;

        fprintf(fid, '  %4d       | %12.2f | %10.2f | %18.2f | %12.2f | %14.2f\n', ...
            i, start_time/60, end_time/60, dom_lobe.peak_freq, dom_lobe.peak_psd, med_bw);



    end
    fclose(fid);

    fig2 = figure('Name', 'Dominant Frequency & Bandwidth Over Time', 'Position', [50, 100, 1800, 500], 'Color', 'w', 'Visible', 'off');
    time_centers_sec = ([results.start_time] + [results.end_time]) / 2;
    time_centers_abs = datenum(base_time + seconds(time_centers_sec));

    dom_freqs = [results.dom_freq];
    bw_vals = [results.bw];

    yyaxis left
    plot(time_centers_abs, dom_freqs, '.', 'MarkerSize', 8, 'Color', [0.2 0.5 0.8]);
    ylabel('Dominant Frequency (Hz)');
    ylim([cfg.f_low, cfg.f_high]);

    yyaxis right
    plot(time_centers_abs, bw_vals, '-', 'LineWidth', 1.5, 'Color', [0.8 0.2 0.2 0.5]);
    ylabel('Bandwidth (Hz)');
    ylim([0, max(max(bw_vals)*1.2, 50)]);

    grid on;
    datetick('x', 'HH:MM', 'keepticks', 'keeplimits');
    xlabel('Time (UTC)');
    title(sprintf('Continuous Signal Tracking (Start: %%s UTC)', datestr(base_time, 'yyyy-mm-dd HH:MM:SS')));

    plot_path = fullfile(out_dir, 'continuous_freq_bw_plot.png');
    exportgraphics(fig2, plot_path, 'Resolution', 300);
    close(fig2);

    all_dom_freqs_cell{f_idx} = dom_freqs;
    all_bws_cell{f_idx} = bw_vals;
    all_psd_db_cell{f_idx} = single([results.psd_db]);
    all_times_cell{f_idx} = time_centers_abs;
    if isempty(global_f_grid) && exist('f_grid', 'var')
        global_f_grid = f_grid;
    end

    fprintf('Analysis completed for %s!\n', filename);
end

all_dom_freqs = cat(2, all_dom_freqs_cell{:});
all_bws = cat(2, all_bws_cell{:});

% Plot overall histograms
fig_overall = figure('Name', 'Overall Distributions', 'Position', [100, 100, 1200, 500], 'Color', 'w');

subplot(1, 2, 1);
histogram(all_dom_freqs, 'BinWidth', 50);
title('Overall Dominant Frequency Distribution');
xlabel('Dominant Frequency (Hz)');
ylabel('Count');
grid on;

subplot(1, 2, 2);
histogram(all_bws, 20);
title('Overall Bandwidth Distribution');
xlabel('Bandwidth (Hz)');
ylabel('Count');
grid on;

overall_out = fullfile(script_dir, 'output', 'Croatia', 'overall_histograms.png');
exportgraphics(fig_overall, overall_out, 'Resolution', 300);
close(fig_overall);

all_psd_db = cat(2, all_psd_db_cell{:});
all_times = cat(2, all_times_cell{:});

if ~isempty(all_psd_db)
    fig_ltsa = figure('Name', 'Cumulative Spectrogram', 'Position', [50, 50, 1800, 600], 'Color', 'w');
    % Clean up broadband transients per frequency bin
    median_profile = median(all_psd_db, 2);
    ltsa_clean = bsxfun(@minus, all_psd_db, median_profile);
    ltsa_clean(ltsa_clean < 0) = 0;
    p_max = prctile(ltsa_clean(:), 99.5);
    
    imagesc(all_times, global_f_grid, ltsa_clean);
    axis xy;
    caxis([0, max(p_max, 1)]);
    colormap jet;
    c = colorbar;
    c.Label.String = 'Relative Power (dB)';
    datetick('x', 'mm-dd HH:MM', 'keepticks', 'keeplimits');
    title('Cumulative Long-Term Spectrogram (LTSA)');
    xlabel('Time (UTC)');
    ylabel('Frequency (Hz)');
    
    ltsa_out = fullfile(script_dir, 'output', 'Croatia', 'cumulative_spectrogram.png');
    exportgraphics(fig_ltsa, ltsa_out, 'Resolution', 300);
    close(fig_ltsa);
end

fprintf('All analysis completed!\n');
