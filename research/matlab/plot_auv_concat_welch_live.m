% plot_auv_concat_welch_live.m
% Computes and plots the Overall Concatenated Welch PSD for the AUV datasets:
% 1. Subplot 1: Overall Concatenated Welch PSD for Hydrophone 6922 (30m depth, all 5 legs)
% 2. Subplot 2: Overall Concatenated Welch PSD for Hydrophone 6695 (5m depth, all 5 legs)
% AUTOMATIC CACHING: Saves computed diagram data to cache_auv_concat_welch.mat so future runs load instantly.

% Resolve output directory relative to script folder
script_dir = fileparts(mfilename('fullpath'));
output_dir = fullfile(script_dir, '..', 'output');
cache_file = fullfile(output_dir, 'cache_auv_concat_welch.mat');

% Define AUV datasets grouped by Hydrophone
FILES_H6922 = {
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692\leg1_straight_line_2_8m_s_6922_827-837.wav';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692\leg2_straight_line_1_8m_s_6922_840-857.wav';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692\leg3_straight_line_1_112m_s_6922_900-910.wav';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part2_Poligon\IcListen6692\leg1_Polygon_6922_921-929.wav';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part2_Poligon\IcListen6692\leg2_Polygon_6922_934-955.wav'
};

FILES_H6695 = {
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6695\leg1_straight_line_2_8m_s_6695_827-837.wav';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6695\leg2_straight_line_1_8m_s_6695_840-857.wav';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6695\leg3_straight_line_1_112m_s_6695_900-910.wav';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part2_Poligon\IcListen6695\leg1_Polygon_6695_921-929.wav';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part2_Poligon\IcListen6695\leg2_Polygon_6695_934-955.wav'
};

calibFactor = 1e6;
windowLength = 65536; 
noverlap = windowLength / 2;

try
    if exist(cache_file, 'file')
        fprintf('======================================================\n');
        fprintf('Loading pre-computed diagram data from cache:\n  %s\n', cache_file);
        fprintf('======================================================\n');
        load(cache_file);
    else
        fprintf('Computing overall concatenated Welch PSD for Hydrophone 6922 (30m Depth)...\n');
        [f_nb_6922, psd_db_6922, env_6922, freqs_int_6922, vals_int_6922] = process_concat_group_mem_efficient(FILES_H6922, calibFactor, windowLength, noverlap);
        
        fprintf('Computing overall concatenated Welch PSD for Hydrophone 6695 (5m Depth)...\n');
        [f_nb_6695, psd_db_6695, env_6695, freqs_int_6695, vals_int_6695] = process_concat_group_mem_efficient(FILES_H6695, calibFactor, windowLength, noverlap);
        
        % Save to MAT cache
        save(cache_file, 'f_nb_6922', 'psd_db_6922', 'env_6922', 'freqs_int_6922', 'vals_int_6922', ...
             'f_nb_6695', 'psd_db_6695', 'env_6695', 'freqs_int_6695', 'vals_int_6695', '-v7.3');
        fprintf('Saved diagram data to cache: %s\n', cache_file);
    end
    
    % --- Interactive Plotting ---
    fig = figure('Name', 'Overall Concatenated AUV Welch PSD (30m vs 5m Depth)', 'Position', [100, 100, 1400, 950]);
    
    zoom_ticks = [50, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000];
    zoom_labels = {'50', '500', '1k', '1.5k', '2k', '2.5k', '3k', '3.5k', '4k'};
    
    % Subplot 1: Hydrophone 6922 (30m Depth)
    ax1 = subplot(2, 1, 1, 'Parent', fig);
    hold(ax1, 'on');
    plot(ax1, f_nb_6922, psd_db_6922, 'Color', [0.4660 0.6740 0.1880], 'LineWidth', 1.2, 'DisplayName', 'Overall Welch PSD');
    plot(ax1, f_nb_6922, env_6922, 'Color', [0.9290 0.6940 0.1250], 'LineStyle', '--', 'LineWidth', 1.5, 'DisplayName', 'Noise Floor Envelope');
    if ~isempty(freqs_int_6922)
        plot(ax1, freqs_int_6922, vals_int_6922, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 4, 'DisplayName', 'Boundary Intersections');
    end
    hold(ax1, 'off');
    grid(ax1, 'on');
    xlim(ax1, [50, 4000]);
    set(ax1, 'XTick', zoom_ticks);
    set(ax1, 'XTickLabel', zoom_labels);
    xlabel(ax1, 'Frequency [Hz]');
    ylabel(ax1, 'PSD [dB re 1 \muPa^2/Hz]');
    title(ax1, 'AUV IcListen 6922 (30m Depth) - Overall Concatenated Welch PSD (All 5 Legs)');
    legend(ax1, 'Location', 'northeast');
    
    % Subplot 2: Hydrophone 6695 (5m Depth)
    ax2 = subplot(2, 1, 2, 'Parent', fig);
    hold(ax2, 'on');
    plot(ax2, f_nb_6695, psd_db_6695, 'Color', [0.0000 0.4470 0.7410], 'LineWidth', 1.2, 'DisplayName', 'Overall Welch PSD');
    plot(ax2, f_nb_6695, env_6695, 'Color', [0.8500 0.3250 0.0980], 'LineStyle', '--', 'LineWidth', 1.5, 'DisplayName', 'Noise Floor Envelope');
    if ~isempty(freqs_int_6695)
        plot(ax2, freqs_int_6695, vals_int_6695, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 4, 'DisplayName', 'Boundary Intersections');
    end
    hold(ax2, 'off');
    grid(ax2, 'on');
    xlim(ax2, [50, 4000]);
    set(ax2, 'XTick', zoom_ticks);
    set(ax2, 'XTickLabel', zoom_labels);
    xlabel(ax2, 'Frequency [Hz]');
    ylabel(ax2, 'PSD [dB re 1 \muPa^2/Hz]');
    title(ax2, 'AUV IcListen 6695 (5m Depth) - Overall Concatenated Welch PSD (All 5 Legs)');
    legend(ax2, 'Location', 'northeast');
    
    % Link X-axes
    linkaxes([ax1, ax2], 'x');
    
    % Enable zoom
    zoom(fig, 'on');
    
    % Save image output
    saveas(fig, fullfile(output_dir, 'auv_overall_concatenated_welch.png'));
    fprintf('Saved auv_overall_concatenated_welch.png to output directory.\n');
    
    fprintf('Interactive AUV Overall Concatenated Welch diagram is live!\n');
    
catch e
    fprintf('An error occurred: %s\n', e.message);
    disp(e.getReport());
end

function [f_nb, psd_db, psd_env, intersect_freqs, intersect_vals] = process_concat_group_mem_efficient(file_list, calibFactor, windowLength, noverlap)
    step_size = windowLength - noverlap;
    
    P_sum = 0;
    total_windows = 0;
    freq_psd = [];
    
    for i = 1:length(file_list)
        fprintf('  Accumulating Welch PSD [%d/%d]: %s...\n', i, length(file_list), file_list{i});
        [y, fs] = audioread(file_list{i});
        if size(y, 2) > 1, y = mean(y, 2); end
        y_cal = y * calibFactor;
        clear y;
        
        % DC offset removal
        y_cal = y_cal - mean(y_cal);
        
        [psd_file, f_file] = pwelch(y_cal, windowLength, noverlap, windowLength, fs, 'power');
        num_wins = floor((length(y_cal) - noverlap) / step_size);
        
        if total_windows == 0
            P_sum = psd_file * num_wins;
            freq_psd = f_file;
        else
            P_sum = P_sum + psd_file * num_wins;
        end
        total_windows = total_windows + num_wins;
    end
    
    psd_est = P_sum / total_windows;
    
    idx_4k = (freq_psd >= 50 & freq_psd <= 4000);
    f_nb = freq_psd(idx_4k);
    psd_db = 10 * log10(psd_est(idx_4k));
    
    psd_env = movmean(psd_db, 151);
    
    diff_sig = psd_db - psd_env;
    intersect_idx = find(diff_sig(1:end-1) .* diff_sig(2:end) <= 0);
    intersect_freqs = f_nb(intersect_idx);
    intersect_vals = psd_db(intersect_idx);
end
