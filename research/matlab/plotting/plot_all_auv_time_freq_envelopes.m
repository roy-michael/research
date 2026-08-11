% plot_all_auv_time_freq_envelopes.m
% Processes ALL 10 AUV datasets found in the AUV directory and creates 
% unified 4-panel interactive figures visualizing time & frequency domain envelopes, 
% peak tracking, and bandwidth measurements for each dataset.

% Resolve paths relative to script location
script_dir = fileparts(mfilename('fullpath'));
output_dir = fullfile(script_dir, '..', '..', 'output', 'AUV');

% Define all 10 AUV datasets across Hydrophone 6922 (30m) and 6695 (5m)
DATASETS = {
    % Hydrophone 6922 (30m Depth)
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692\leg1_straight_line_2_8m_s_6922_827-837.wav', 'AUV_H6922_Straight_Leg1', 'AUV Straight Leg 1 (H6922 - 30m, 5.4 kts)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692\leg2_straight_line_1_8m_s_6922_840-857.wav', 'AUV_H6922_Straight_Leg2', 'AUV Straight Leg 2 (H6922 - 30m, 3.5 kts)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692\leg3_straight_line_1_112m_s_6922_900-910.wav', 'AUV_H6922_Straight_Leg3', 'AUV Straight Leg 3 (H6922 - 30m, 2.2 kts)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part2_Poligon\IcListen6692\leg1_Polygon_6922_921-929.wav', 'AUV_H6922_Polygon_Leg1', 'AUV Polygon Leg 1 (H6922 - 30m)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part2_Poligon\IcListen6692\leg2_Polygon_6922_934-955.wav', 'AUV_H6922_Polygon_Leg2', 'AUV Polygon Leg 2 (H6922 - 30m)';
    
    % Hydrophone 6695 (5m Depth)
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6695\leg1_straight_line_2_8m_s_6695_827-837.wav', 'AUV_H6695_Straight_Leg1', 'AUV Straight Leg 1 (H6695 - 5m, 5.4 kts)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6695\leg2_straight_line_1_8m_s_6695_840-857.wav', 'AUV_H6695_Straight_Leg2', 'AUV Straight Leg 2 (H6695 - 5m, 3.5 kts)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6695\leg3_straight_line_1_112m_s_6695_900-910.wav', 'AUV_H6695_Straight_Leg3', 'AUV Straight Leg 3 (H6695 - 5m, 2.2 kts)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part2_Poligon\IcListen6695\leg1_Polygon_6695_921-929.wav', 'AUV_H6695_Polygon_Leg1', 'AUV Polygon Leg 1 (H6695 - 5m)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part2_Poligon\IcListen6695\leg2_Polygon_6695_934-955.wav', 'AUV_H6695_Polygon_Leg2', 'AUV Polygon Leg 2 (H6695 - 5m)';
};

calibFactor = 1e6; % Calibration factor (conversion to micro-Pascals)

for d = 1:size(DATASETS, 1)
    file_path = DATASETS{d, 1};
    tag_name = DATASETS{d, 2};
    display_name = DATASETS{d, 3};
    
    fprintf('\n======================================================\n');
    fprintf('Processing Dataset [%d/%d]: %s\n', d, size(DATASETS, 1), display_name);
    fprintf('======================================================\n');
    
    try
        if ~exist(file_path, 'file')
            warning('File not found: %s. Skipping...', file_path);
            continue;
        end
        
        [y_all, fs] = audioread(file_path);
        if size(y_all, 2) > 1
            y_all = mean(y_all, 2);
        end
        
        y_cal = y_all * calibFactor;
        clear y_all;
        
        % Remove DC offset
        y_cal = y_cal - mean(y_cal);
        
        % =============================================================
        % 1. TIME DOMAIN ENVELOPE COMPUTATION (Block max/min)
        % =============================================================
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
        num_seconds = floor(length(y_cal) / fs);
        y_cal_sec = reshape(y_cal(1 : num_seconds * fs), fs, num_seconds);
        
        time_sec_vec = (1:num_seconds)';
        peak_freq_time = zeros(num_seconds, 1);
        
        nfft_sec = 4096;
        noverlap_sec = 2048;
        
        for s = 1:num_seconds
            [psd_sec, freq_sec] = pwelch(y_cal_sec(:, s), nfft_sec, noverlap_sec, nfft_sec, fs, 'power');
            idx_sec_band = (freq_sec >= 50 & freq_sec <= 4000);
            f_sec_sub = freq_sec(idx_sec_band);
            psd_sec_sub = psd_sec(idx_sec_band);
            [~, max_sec_idx] = max(psd_sec_sub);
            peak_freq_time(s) = f_sec_sub(max_sec_idx);
        end
        
        % =============================================================
        % 3. FREQUENCY DOMAIN ENVELOPE COMPUTATION (PSD + Moving Average)
        % =============================================================
        windowLength = 65536;
        noverlap = windowLength / 2;
        [psd_est, freq_psd] = pwelch(y_cal, windowLength, noverlap, windowLength, fs, 'power');
        
        idx_band = (freq_psd >= 50 & freq_psd <= 4000);
        f_nb = freq_psd(idx_band);
        psd_nb_db = 10 * log10(psd_est(idx_band));
        
        psd_env = movmean(psd_nb_db, 151);
        
        diff_sig = psd_nb_db - psd_env;
        intersect_idx = find(diff_sig(1:end-1) .* diff_sig(2:end) <= 0);
        intersect_freqs = f_nb(intersect_idx);
        intersect_vals = psd_nb_db(intersect_idx);
        
        peak_range_idx = (f_nb >= 100 & f_nb <= 2000);
        f_subset = f_nb(peak_range_idx);
        psd_subset = psd_nb_db(peak_range_idx);
        [pks, locs] = findpeaks(psd_subset, f_subset, 'MinPeakDistance', 10, 'SortStr', 'descend');
        
        if isempty(pks)
            [peak_val, max_i] = max(psd_subset);
            peak_freq = f_subset(max_i);
        else
            peak_freq = locs(1);
            peak_val = pks(1);
        end
        
        left_intersections = intersect_freqs(intersect_freqs < peak_freq);
        right_intersections = intersect_freqs(intersect_freqs > peak_freq);
        
        if isempty(left_intersections) || isempty(right_intersections)
            f_lower = max(50, peak_freq - 10);
            f_upper = min(4000, peak_freq + 10);
        else
            f_lower = max(left_intersections);
            f_upper = min(right_intersections);
        end
        
        val_lower = psd_nb_db(f_nb == f_lower);
        val_upper = psd_nb_db(f_nb == f_upper);
        if isempty(val_lower), val_lower = peak_val - 3; end
        if isempty(val_upper), val_upper = peak_val - 3; end
        bandwidth = f_upper - f_lower;
        
        % =============================================================
        % 4. PLOTTING MULTI-PANEL INTERACTIVE FIGURE
        % =============================================================
        fig = figure('Name', sprintf('[%d/10] %s - Interactive Analysis', d, display_name), ...
                     'Position', [50 + (d-1)*30, 30, 1400, 1000]);
        
        % --- Subplot 1: Time-Domain Envelopes ---
        ax1 = subplot(4, 1, 1, 'Parent', fig);
        hold(ax1, 'on');
        plot(ax1, t_ds, y_ds, 'Color', [0.85 0.85 0.85], 'LineWidth', 0.5, 'DisplayName', 'Signal');
        plot(ax1, t_ds, env_up_ds, 'Color', [0.4660 0.6740 0.1880], 'LineWidth', 1.2, 'DisplayName', 'Upper Envelope');
        plot(ax1, t_ds, env_lo_ds, 'Color', [0.9290 0.6940 0.1250], 'LineWidth', 1.2, 'DisplayName', 'Lower Envelope');
        hold(ax1, 'off');
        grid(ax1, 'on');
        axis(ax1, 'tight');
        xlabel(ax1, 'Time [sec]');
        ylabel(ax1, 'Amplitude [\muPa]');
        title(ax1, sprintf('1. %s - Time-Domain Envelopes (DC Removed)', display_name));
        legend(ax1, 'Location', 'northeast');
        
        % --- Subplot 2: Dominant Peak Frequency Over Time ---
        ax2 = subplot(4, 1, 2, 'Parent', fig);
        plot(ax2, time_sec_vec, peak_freq_time, '.-', 'Color', [0.4660 0.6740 0.1880], 'LineWidth', 1.0, 'MarkerSize', 8, 'DisplayName', 'Dominant Peak Frequency');
        grid(ax2, 'on');
        axis(ax2, 'tight');
        ylim(ax2, [50, 4000]);
        xlabel(ax2, 'Time [sec]');
        ylabel(ax2, 'Peak Frequency [Hz]');
        title(ax2, '2. Tracked Dominant Peak Frequency Over Time (Second-by-Second)');
        legend(ax2, 'Location', 'northeast');
        linkaxes([ax1, ax2], 'x');
        
        % --- Subplot 3: Frequency-Domain Spectrum & Baseline Envelope ---
        ax3 = subplot(4, 1, 3, 'Parent', fig);
        hold(ax3, 'on');
        plot(ax3, f_nb, psd_nb_db, 'Color', [0.4660 0.6740 0.1880], 'LineWidth', 1.0, 'DisplayName', 'Welch PSD');
        plot(ax3, f_nb, psd_env, 'Color', [0.9290 0.6940 0.1250], 'LineStyle', '--', 'LineWidth', 1.5, 'DisplayName', 'Noise Floor Envelope');
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
        plot(ax4, f_nb(zoom_range), psd_nb_db(zoom_range), 'Color', [0.4660 0.6740 0.1880], 'LineWidth', 1.5, 'DisplayName', 'Welch PSD');
        plot(ax4, f_nb(zoom_range), psd_env(zoom_range), 'Color', [0.9290 0.6940 0.1250], 'LineStyle', '--', 'LineWidth', 1.5, 'DisplayName', 'Noise Floor Envelope');
        plot(ax4, peak_freq, peak_val, 'gp', 'MarkerFaceColor', 'g', 'MarkerSize', 12, 'DisplayName', 'Peak');
        plot(ax4, [f_lower, f_upper], [val_lower, val_upper], 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 8, 'DisplayName', 'Boundaries');
        
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
        
        % Enable interactive zoom mode on the figure
        zoom(fig, 'on');
        
        % Save image output
        saveas(fig, fullfile(output_dir, [tag_name '_envelopes.png']));
        fprintf('Saved %s_envelopes.png to output directory and kept figure window live.\n', tag_name);
        
    catch e
        fprintf('An error occurred for %s: %s\n', tag_name, e.message);
        disp(e.getReport());
    end
end

fprintf('\nAll 10 interactive AUV dataset figures are ready!\n');
