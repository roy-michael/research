% plot_auv_welch_comparison.m
% Computes and compares high-resolution Welch PSD for all 10 AUV runs across both hydrophones:
% - IcListen 6922 (30m depth)
% - IcListen 6695 (5m depth)
% Removes DC offset, uses NFFT=65536 for high frequency resolution, and saves auv_all_welch_comparison.png.

% Resolve output directory relative to script folder
script_dir = fileparts(mfilename('fullpath'));
output_dir = fullfile(script_dir, '..', '..', 'output', 'AUV');

% Define AUV datasets
DATASETS = {
    % Hydrophone 6922 (30m)
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692\leg1_straight_line_2_8m_s_6922_827-837.wav', 'H6922_Straight_Leg1_5_4kts', 'IcListen 6922 (30m)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692\leg2_straight_line_1_8m_s_6922_840-857.wav', 'H6922_Straight_Leg2_3_5kts', 'IcListen 6922 (30m)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692\leg3_straight_line_1_112m_s_6922_900-910.wav', 'H6922_Straight_Leg3_2_2kts', 'IcListen 6922 (30m)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part2_Poligon\IcListen6692\leg1_Polygon_6922_921-929.wav', 'H6922_Polygon_Leg1', 'IcListen 6922 (30m)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part2_Poligon\IcListen6692\leg2_Polygon_6922_934-955.wav', 'H6922_Polygon_Leg2', 'IcListen 6922 (30m)';
    
    % Hydrophone 6695 (5m)
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6695\leg1_straight_line_2_8m_s_6695_827-837.wav', 'H6695_Straight_Leg1_5_4kts', 'IcListen 6695 (5m)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6695\leg2_straight_line_1_8m_s_6695_840-857.wav', 'H6695_Straight_Leg2_3_5kts', 'IcListen 6695 (5m)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6695\leg3_straight_line_1_112m_s_6695_900-910.wav', 'H6695_Straight_Leg3_2_2kts', 'IcListen 6695 (5m)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part2_Poligon\IcListen6695\leg1_Polygon_6695_921-929.wav', 'H6695_Polygon_Leg1', 'IcListen 6695 (5m)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part2_Poligon\IcListen6695\leg2_Polygon_6695_934-955.wav', 'H6695_Polygon_Leg2', 'IcListen 6695 (5m)';
};

calibFactor = 1e6;
results = struct();

for d = 1:size(DATASETS, 1)
    file_path = DATASETS{d, 1};
    clean_name = DATASETS{d, 2};
    hydrophone = DATASETS{d, 3};
    
    fprintf('Processing %s...\n', clean_name);
    [y, fs] = audioread(file_path);
    if size(y, 2) > 1, y = mean(y, 2); end
    
    y_cal = y * calibFactor;
    clear y;
    
    % DC Offset removal
    y_cal = y_cal - mean(y_cal);
    
    % High frequency resolution window size
    windowLength = 65536; 
    noverlap = windowLength / 2;
    [psd_est, freq_psd] = pwelch(y_cal, windowLength, noverlap, windowLength, fs, 'power');
    psd_db = 10 * log10(psd_est);
    
    % Save results up to 4 kHz
    idx_4k = (freq_psd >= 50 & freq_psd <= 4000);
    results.(clean_name).freq = freq_psd(idx_4k);
    results.(clean_name).psd = psd_db(idx_4k);
    results.(clean_name).hydrophone = hydrophone;
end

% Save results to JSON
export_json = struct();
export_json.results = results;
json_str = jsonencode(export_json);
fid = fopen(fullfile(output_dir, 'auv_welch_comparison_data.json'), 'w');
fprintf(fid, '%s', json_str);
fclose(fid);
fprintf('Saved auv_welch_comparison_data.json to output directory\n');

% --- Static Plotting ---
colors = [
    0.0000 0.4470 0.7410; % Blue (Leg 1 / Straight)
    0.8500 0.3250 0.0980; % Orange (Leg 2 / Straight)
    0.9290 0.6940 0.1250; % Yellow-orange (Leg 3 / Straight)
    0.4940 0.1840 0.5560; % Purple (Polygon Leg 1)
    0.4660 0.6740 0.1880  % Green (Polygon Leg 2)
];

zoom_ticks = [50, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000];
zoom_labels = {'50', '500', '1k', '1.5k', '2k', '2.5k', '3k', '3.5k', '4k'};

fig = figure('Name', 'All AUV Welch PSD Comparison', 'Position', [100, 100, 1400, 950], 'Visible', 'off');

% Subplot 1: H6922 (30m depth)
ax1 = subplot(2, 1, 1, 'Parent', fig);
hold(ax1, 'on');
plot_keys_1 = {
    'H6922_Straight_Leg1_5_4kts', 'Straight Line Leg 1 (5.4 kts)';
    'H6922_Straight_Leg2_3_5kts', 'Straight Line Leg 2 (3.5 kts)';
    'H6922_Straight_Leg3_2_2kts', 'Straight Line Leg 3 (2.2 kts)';
    'H6922_Polygon_Leg1', 'Polygon Leg 1';
    'H6922_Polygon_Leg2', 'Polygon Leg 2'
};

for i = 1:size(plot_keys_1, 1)
    key = plot_keys_1{i, 1};
    label = plot_keys_1{i, 2};
    col = colors(i, :);
    plot(ax1, results.(key).freq, results.(key).psd, 'Color', col, 'LineWidth', 1.5, 'DisplayName', label);
end
hold(ax1, 'off');
grid(ax1, 'on');
xlim(ax1, [50, 4000]);
set(ax1, 'XTick', zoom_ticks);
set(ax1, 'XTickLabel', zoom_labels);
xlabel(ax1, 'Frequency [Hz]');
ylabel(ax1, 'PSD [dB re 1 \muPa^2/Hz]');
title(ax1, 'IcListen 6922 (30m Depth) - All AUV Runs Welch PSD (High Resolution)');
legend(ax1, 'Location', 'northeast');

% Subplot 2: H6695 (5m depth)
ax2 = subplot(2, 1, 2, 'Parent', fig);
hold(ax2, 'on');
plot_keys_2 = {
    'H6695_Straight_Leg1_5_4kts', 'Straight Line Leg 1 (5.4 kts)';
    'H6695_Straight_Leg2_3_5kts', 'Straight Line Leg 2 (3.5 kts)';
    'H6695_Straight_Leg3_2_2kts', 'Straight Line Leg 3 (2.2 kts)';
    'H6695_Polygon_Leg1', 'Polygon Leg 1';
    'H6695_Polygon_Leg2', 'Polygon Leg 2'
};

for i = 1:size(plot_keys_2, 1)
    key = plot_keys_2{i, 1};
    label = plot_keys_2{i, 2};
    col = colors(i, :);
    plot(ax2, results.(key).freq, results.(key).psd, 'Color', col, 'LineWidth', 1.5, 'DisplayName', label);
end
hold(ax2, 'off');
grid(ax2, 'on');
xlim(ax2, [50, 4000]);
set(ax2, 'XTick', zoom_ticks);
set(ax2, 'XTickLabel', zoom_labels);
xlabel(ax2, 'Frequency [Hz]');
ylabel(ax2, 'PSD [dB re 1 \muPa^2/Hz]');
title(ax2, 'IcListen 6695 (5m Depth) - All AUV Runs Welch PSD (High Resolution)');
legend(ax2, 'Location', 'northeast');

saveas(fig, fullfile(output_dir, 'auv_all_welch_comparison.png'));
fprintf('Saved auv_all_welch_comparison.png to output directory\n');
close(fig);
