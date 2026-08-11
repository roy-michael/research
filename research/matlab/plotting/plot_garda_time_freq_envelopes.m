% plot_garda_time_freq_envelopes.m
% Loads the Garda Electric dataset and creates a unified multi-panel figure
% visualizing signal envelopes and peak frequency tracking in Time & Frequency domains:
% 1. Time-Domain Signal with Upper and Lower Envelopes (DC removed)
% 2. Dominant Peak Frequency Tracked Over Time (Second-by-Second)
% 3. Frequency-Domain Welch PSD with Baseline Envelope & Intersection Boundaries (50 Hz - 4 kHz)
% 4. Zoomed Spectral Peak with Measured Bandwidth

% Resolve paths relative to script location
script_dir = fileparts(mfilename('fullpath'));
output_dir = fullfile(script_dir, '..', '..', 'output', 'garda');

DIR_PATH = 'D:\RoyStudies\Recordings\Garda_2_26\2_Deep Water\Electric';
calibFactor = 1e6; % Calibration factor (conversion to micro-Pascals)

try
    fprintf('Listing WAV files in: %s\n', DIR_PATH);
    files = dir(fullfile(DIR_PATH, '*.wav'));
    if isempty(files)
        error('No WAV files found in %s', DIR_PATH);
    end
    
    % Sort files alphabetically by name
    [~, sortIdx] = sort({files.name});
    files = files(sortIdx);
    
    fprintf('Found %d WAV files. Concatenating...\n', length(files));
    
    % Pre-calculate total samples
    total_samples = 0;
    sample_rate = [];
    for i = 1:length(files)
        info = audioinfo(fullfile(files(i).folder, files(i).name));
        total_samples = total_samples + info.TotalSamples;
        if i == 1, sample_rate = info.SampleRate; end
    end
    
    y_all = zeros(total_samples, 1);
    current_idx = 1;
    
    for i = 1:length(files)
        file_path = fullfile(files(i).folder, files(i).name);
        fprintf('  Reading [%d/%d]: %s\n', i, length(files), files(i).name);
        [y, fs] = audioread(file_path);
        if size(y, 2) > 1
            y = mean(y, 2);
        end
        num_samples = length(y);
        y_all(current_idx : current_idx + num_samples - 1) = y;
        current_idx = current_idx + num_samples;
    end
    
    fs = sample_rate;
    fprintf('Data loaded. Total samples: %d. Applying calibration...\n', length(y_all));
    y_cal = y_all * calibFactor;
    clear y_all; % Free raw data memory
    
    % Apply DC offset removal to center signal at 0
    fprintf('Removing DC offset...\n');
    y_cal = y_cal - mean(y_cal);
    
    % =============================================================
    % 1. TIME DOMAIN ENVELOPE COMPUTATION (Block max/min)
    % =============================================================
    fprintf('Computing Time-Domain Upper and Lower Envelopes...\n');
    t_time = (0:length(y_cal)-1)' / fs;
    peak_interval = 200;
    num_blocks = floor(length(y_cal) / peak_interval);
    
    y_reshaped = reshape(y_cal(1 : num_blocks * peak_interval), peak_interval, num_blocks);
    env_up_ds = max(y_reshaped, [], 1)';
    env_lo_ds = min(y_reshaped, [], 1)';
    
    t_ds = t_time(1 : peak_interval : num_blocks * peak_interval);
    y_ds = y_cal(1 : peak_interval : num_blocks * peak_interval);
    
    % =============================================================
    % 2. SECOND-BY-SECOND PEAK FREQUENCY TRACKING OVER TIME
    % =============================================================
    fprintf('Tracking dominant peak frequency second-by-second over time...\n');
    num_seconds = floor(length(y_cal) / fs);
    y_cal_sec = reshape(y_cal(1 : num_seconds * fs), fs, num_seconds);
    
    time_sec_vec = (1:num_seconds)';
    peak_freq_time = zeros(num_seconds, 1);
    
    nfft_sec = 4096;
    noverlap_sec = 2048;
    
    for s = 1:num_seconds
        [psd_sec, freq_sec] = pwelch(y_cal_sec(:, s), nfft_sec, noverlap_sec, nfft_sec, fs, 'power');
        
        % Restrict search to 50 Hz - 4000 Hz for dominant acoustic tonals
        idx_sec_band = (freq_sec >= 50 & freq_sec <= 4000);
        f_sec_sub = freq_sec(idx_sec_band);
        psd_sec_sub = psd_sec(idx_sec_band);
        
        [~, max_sec_idx] = max(psd_sec_sub);
        peak_freq_time(s) = f_sec_sub(max_sec_idx);
    end
    
    % =============================================================
    % 3. FREQUENCY DOMAIN ENVELOPE COMPUTATION (PSD + Moving Average)
    % =============================================================
    fprintf('Computing High-Resolution Welch PSD & Frequency Envelope...\n');
    windowLength = 65536;
    noverlap = windowLength / 2;
    [psd_est, freq_psd] = pwelch(y_cal, windowLength, noverlap, windowLength, fs, 'power');
    
    idx_band = (freq_psd >= 50 & freq_psd <= 4000);
    f_nb = freq_psd(idx_band);
    psd_nb_db = 10 * log10(psd_est(idx_band));
    
    % Moving average baseline envelope
    psd_env = movmean(psd_nb_db, 151);
    
    % Find all boundary intersection points in 50 Hz - 4 kHz
    diff_sig = psd_nb_db - psd_env;
    intersect_idx = find(diff_sig(1:end-1) .* diff_sig(2:end) <= 0);
    intersect_freqs = f_nb(intersect_idx);
    intersect_vals = psd_nb_db(intersect_idx);
    
    % Find prominent peak around 100-2000 Hz for zoom analysis
    peak_range_idx = (f_nb >= 100 & f_nb <= 2000);
    f_subset = f_nb(peak_range_idx);
    psd_subset = psd_nb_db(peak_range_idx);
    [pks, locs] = findpeaks(psd_subset, f_subset, 'MinPeakDistance', 10, 'SortStr', 'descend');
    
    peak_freq = locs(1);
    peak_val = pks(1);
    
    left_intersections = intersect_freqs(intersect_freqs < peak_freq);
    right_intersections = intersect_freqs(intersect_freqs > peak_freq);
    f_lower = max(left_intersections);
    f_upper = min(right_intersections);
    val_lower = psd_nb_db(f_nb == f_lower);
    val_upper = psd_nb_db(f_nb == f_upper);
    bandwidth = f_upper - f_lower;
    
    % =============================================================
    % 4. PLOTTING MULTI-PANEL FIGURE
    % =============================================================
    fig = figure('Name', 'Garda Electric - Time & Frequency Envelopes and Peak Tracking', 'Position', [100, 30, 1400, 1050]);
    
    % --- Subplot 1: Time-Domain Envelopes ---
    ax1 = subplot(4, 1, 1, 'Parent', fig);
    hold(ax1, 'on');
    plot(ax1, t_ds, y_ds, 'Color', [0.85 0.85 0.85], 'LineWidth', 0.5, 'DisplayName', 'Signal');
    plot(ax1, t_ds, env_up_ds, 'Color', [0.0000 0.4470 0.7410], 'LineWidth', 1.2, 'DisplayName', 'Upper Envelope');
    plot(ax1, t_ds, env_lo_ds, 'Color', [0.8500 0.3250 0.0980], 'LineWidth', 1.2, 'DisplayName', 'Lower Envelope');
    hold(ax1, 'off');
    grid(ax1, 'on');
    axis(ax1, 'tight');
    xlabel(ax1, 'Time [sec]');
    ylabel(ax1, 'Amplitude [\muPa]');
    title(ax1, '1. Time-Domain Signal Envelopes (DC Removed)');
    legend(ax1, 'Location', 'northeast');
    
    % --- Subplot 2: Dominant Peak Frequency Over Time ---
    ax2 = subplot(4, 1, 2, 'Parent', fig);
    plot(ax2, time_sec_vec, peak_freq_time, '.-', 'Color', [0.4940 0.1840 0.5560], 'LineWidth', 1.0, 'MarkerSize', 8, 'DisplayName', 'Dominant Peak Frequency');
    grid(ax2, 'on');
    axis(ax2, 'tight');
    ylim(ax2, [50, 4000]);
    xlabel(ax2, 'Time [sec]');
    ylabel(ax2, 'Peak Frequency [Hz]');
    title(ax2, '2. Tracked Dominant Peak Frequency Over Time (Second-by-Second)');
    legend(ax2, 'Location', 'northeast');
    
    % Link X-axes of Time-domain plots
    linkaxes([ax1, ax2], 'x');
    
    % --- Subplot 3: Frequency-Domain Spectrum & Baseline Envelope ---
    ax3 = subplot(4, 1, 3, 'Parent', fig);
    hold(ax3, 'on');
    plot(ax3, f_nb, psd_nb_db, 'Color', [0.0000 0.4470 0.7410], 'LineWidth', 1.0, 'DisplayName', 'Welch PSD');
    plot(ax3, f_nb, psd_env, 'Color', [0.8500 0.3250 0.0980], 'LineStyle', '--', 'LineWidth', 1.5, 'DisplayName', 'Noise Floor Envelope');
    if ~isempty(intersect_freqs)
        plot(ax3, intersect_freqs, intersect_vals, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 4, 'DisplayName', 'Boundary Intersections');
    end
    plot(ax3, peak_freq, peak_val, 'gp', 'MarkerFaceColor', 'g', 'MarkerSize', 10, 'DisplayName', sprintf('Peak (%.1f Hz)', peak_freq));
    hold(ax3, 'off');
    grid(ax3, 'on');
    xlim(ax3, [50, 4000]);
    xlabel(ax3, 'Frequency [Hz]');
    ylabel(ax3, 'PSD [dB re 1 \muPa^2/Hz]');
    title(ax3, '3. Frequency-Domain Welch PSD & Local Baseline Noise Floor Envelope (50 Hz - 4 kHz)');
    legend(ax3, 'Location', 'northeast');
    
    % --- Subplot 4: Zoomed Peak & Bandwidth Measurement ---
    ax4 = subplot(4, 1, 4, 'Parent', fig);
    zoom_range = (f_nb >= peak_freq - 25 & f_nb <= peak_freq + 25);
    hold(ax4, 'on');
    plot(ax4, f_nb(zoom_range), psd_nb_db(zoom_range), 'Color', [0.0000 0.4470 0.7410], 'LineWidth', 1.5, 'DisplayName', 'Welch PSD');
    plot(ax4, f_nb(zoom_range), psd_env(zoom_range), 'Color', [0.8500 0.3250 0.0980], 'LineStyle', '--', 'LineWidth', 1.5, 'DisplayName', 'Noise Floor Envelope');
    plot(ax4, peak_freq, peak_val, 'gp', 'MarkerFaceColor', 'g', 'MarkerSize', 12, 'DisplayName', 'Peak');
    plot(ax4, [f_lower, f_upper], [val_lower, val_upper], 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 8, 'DisplayName', 'Boundaries');
    
    % Draw bandwidth horizontal arrow
    mid_val = (val_lower + val_upper) / 2;
    plot(ax4, [f_lower, f_upper], [mid_val, mid_val], 'k-', 'LineWidth', 2, 'HandleVisibility', 'off');
    plot(ax4, f_lower, mid_val, 'k<', 'MarkerFaceColor', 'k', 'MarkerSize', 6, 'HandleVisibility', 'off');
    plot(ax4, f_upper, mid_val, 'k>', 'MarkerFaceColor', 'k', 'MarkerSize', 6, 'HandleVisibility', 'off');
    plot(ax4, [f_lower, f_lower], [min(psd_nb_db(zoom_range)), val_lower], 'k:', 'LineWidth', 1, 'HandleVisibility', 'off');
    plot(ax4, [f_upper, f_upper], [min(psd_nb_db(zoom_range)), val_upper], 'k:', 'LineWidth', 1, 'HandleVisibility', 'off');
    
    hold(ax4, 'off');
    grid(ax4, 'on');
    xlabel(ax4, 'Frequency [Hz]');
    ylabel(ax4, 'PSD [dB re 1 \muPa^2/Hz]');
    title(ax4, sprintf('4. Zoomed Bandwidth Measurement at Peak %.1f Hz (Measured Bandwidth = %.1f Hz)', peak_freq, bandwidth));
    legend(ax4, 'Location', 'northeast');
    
    % Enable zoom mode
    zoom(fig, 'on');
    
    fprintf('Unified Garda Time & Frequency Envelope plot with Peak Tracking is live!\n');
    
catch e
    fprintf('An error occurred: %s\n', e.message);
    disp(e.getReport());
end
