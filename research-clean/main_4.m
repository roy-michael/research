% main_4.m
% Bandwidth Stability Analysis

% Define directories
scooter_dir = "D:\RoyStudies\Recordings\Croatia\Ocean Sonics\2407_1_600m\";
ship_dir = "D:\RoyStudies\Recordings\hear-my-ship\V1\Motor Boats\";
auv_dir = "D:\RoyStudies\Recordings\AUVExp_1_26\";

scooter_files = dir(fullfile(scooter_dir, '*.wav'));
ship_files = dir(fullfile(ship_dir, '*.wav'));
auv_files = dir(fullfile(auv_dir, '**', '*.wav'));

% We use a 30-second window. 
% We slide by 15 seconds (50% overlap) to speed up processing while still generating multiple samples.
window_sec = 30;
step_sec = 15; 

% Aggregate arrays
all_scooter_bw = [];
all_scooter_freqs = [];
all_auv_bw = [];
all_auv_freqs = [];
all_ship_bw = [];
all_ship_freq = [];

fprintf('Processing %d Scooter files...\n', length(scooter_files));
for i = 1:length(scooter_files)
    filepath = fullfile(scooter_files(i).folder, scooter_files(i).name);
    try
        info = audioinfo(filepath);
        fprintf('  [%d/%d] %s (%.1fs)\n', i, length(scooter_files), scooter_files(i).name, info.Duration);
        [bw, freqs, ~] = process_stability(filepath, info, window_sec, step_sec, [400, 1000], 3); % Track top 3 freqs
        all_scooter_bw = [all_scooter_bw; bw];
        all_scooter_freqs = [all_scooter_freqs; freqs];
    catch e
        fprintf('  Error processing %s: %s\n', scooter_files(i).name, e.message);
    end
end

fprintf('Processing %d AUV files...\n', length(auv_files));
for i = 1:length(auv_files)
    filepath = fullfile(auv_files(i).folder, auv_files(i).name);
    try
        info = audioinfo(filepath);
        fprintf('  [%d/%d] %s (%.1fs)\n', i, length(auv_files), auv_files(i).name, info.Duration);
        [bw, freqs, ~] = process_stability(filepath, info, window_sec, step_sec, [50, 5000], 3); % Track top 3 freqs
        all_auv_bw = [all_auv_bw; bw];
        all_auv_freqs = [all_auv_freqs; freqs];
    catch e
        fprintf('  Error processing %s: %s\n', auv_files(i).name, e.message);
    end
end

fprintf('Processing %d Motorboat files...\n', length(ship_files));
for i = 1:length(ship_files)
    filepath = fullfile(ship_files(i).folder, ship_files(i).name);
    try
        info = audioinfo(filepath);
        fprintf('  [%d/%d] %s (%.1fs)\n', i, length(ship_files), ship_files(i).name, info.Duration);
        [bw, freqs, ~] = process_stability(filepath, info, window_sec, step_sec, [50, 24000], 1); % Track top 1 freq
        all_ship_bw = [all_ship_bw; bw];
        all_ship_freq = [all_ship_freq; freqs];
    catch e
        fprintf('  Error processing %s: %s\n', ship_files(i).name, e.message);
    end
end

% Plot Histograms
figure('Position', [50, 50, 1000, 1300]);
set(gcf, 'Color', [0.12 0.12 0.12]);

% --- Scooter Peak 1 ---
ax1 = subplot(7, 2, 1);
if size(all_scooter_bw, 2) >= 1
    histogram(all_scooter_bw(:,1), 30, 'FaceColor', [0 1 1], 'EdgeColor', 'w', 'Normalization', 'probability');
    title(sprintf('Scooter Top Peak BW (Mean: %.0f Hz, Std: %.0f Hz)', mean(all_scooter_bw(:,1), 'omitnan'), std(all_scooter_bw(:,1), 'omitnan')), 'Color', 'w');
end
xlabel('Total Bandwidth (Hz)', 'Color', 'w');

ax2 = subplot(7, 2, 2);
if size(all_scooter_freqs, 2) >= 1
    histogram(all_scooter_freqs(:,1), 30, 'FaceColor', [0 1 1], 'EdgeColor', 'w', 'Normalization', 'probability');
    title(sprintf('Scooter Top Peak Freq (Mean: %.0f Hz, Std: %.0f Hz)', mean(all_scooter_freqs(:,1), 'omitnan'), std(all_scooter_freqs(:,1), 'omitnan')), 'Color', 'w');
end
xlabel('Dominant Frequency (Hz)', 'Color', 'w');

% --- Scooter Peak 2 ---
ax3 = subplot(7, 2, 3);
if size(all_scooter_bw, 2) >= 2
    histogram(all_scooter_bw(:,2), 30, 'FaceColor', [1 1 0], 'EdgeColor', 'w', 'Normalization', 'probability');
    title(sprintf('Scooter 2nd Peak BW (Mean: %.0f Hz, Std: %.0f Hz)', mean(all_scooter_bw(:,2), 'omitnan'), std(all_scooter_bw(:,2), 'omitnan')), 'Color', 'w');
end
xlabel('Total Bandwidth (Hz)', 'Color', 'w');

ax4 = subplot(7, 2, 4);
if size(all_scooter_freqs, 2) >= 2
    histogram(all_scooter_freqs(:,2), 30, 'FaceColor', [1 1 0], 'EdgeColor', 'w', 'Normalization', 'probability');
    title(sprintf('Scooter 2nd Peak Freq (Mean: %.0f Hz, Std: %.0f Hz)', mean(all_scooter_freqs(:,2), 'omitnan'), std(all_scooter_freqs(:,2), 'omitnan')), 'Color', 'w');
end
xlabel('Dominant Frequency (Hz)', 'Color', 'w');

% --- Scooter Peak 3 ---
ax5 = subplot(7, 2, 5);
if size(all_scooter_bw, 2) >= 3
    histogram(all_scooter_bw(:,3), 30, 'FaceColor', [0 1 0], 'EdgeColor', 'w', 'Normalization', 'probability');
    title(sprintf('Scooter 3rd Peak BW (Mean: %.0f Hz, Std: %.0f Hz)', mean(all_scooter_bw(:,3), 'omitnan'), std(all_scooter_bw(:,3), 'omitnan')), 'Color', 'w');
end
xlabel('Total Bandwidth (Hz)', 'Color', 'w');

ax6 = subplot(7, 2, 6);
if size(all_scooter_freqs, 2) >= 3
    histogram(all_scooter_freqs(:,3), 30, 'FaceColor', [0 1 0], 'EdgeColor', 'w', 'Normalization', 'probability');
    title(sprintf('Scooter 3rd Peak Freq (Mean: %.0f Hz, Std: %.0f Hz)', mean(all_scooter_freqs(:,3), 'omitnan'), std(all_scooter_freqs(:,3), 'omitnan')), 'Color', 'w');
end
xlabel('Dominant Frequency (Hz)', 'Color', 'w');

% --- AUV Peak 1 ---
ax7 = subplot(7, 2, 7);
if size(all_auv_bw, 2) >= 1
    histogram(all_auv_bw(:,1), 30, 'FaceColor', [0 0.5 1], 'EdgeColor', 'w', 'Normalization', 'probability');
    title(sprintf('AUV Top Peak BW (Mean: %.0f Hz, Std: %.0f Hz)', mean(all_auv_bw(:,1), 'omitnan'), std(all_auv_bw(:,1), 'omitnan')), 'Color', 'w');
end
xlabel('Total Bandwidth (Hz)', 'Color', 'w');

ax8 = subplot(7, 2, 8);
if size(all_auv_freqs, 2) >= 1
    histogram(all_auv_freqs(:,1), 30, 'FaceColor', [0 0.5 1], 'EdgeColor', 'w', 'Normalization', 'probability');
    title(sprintf('AUV Top Peak Freq (Mean: %.0f Hz, Std: %.0f Hz)', mean(all_auv_freqs(:,1), 'omitnan'), std(all_auv_freqs(:,1), 'omitnan')), 'Color', 'w');
end
xlabel('Dominant Frequency (Hz)', 'Color', 'w');

% --- AUV Peak 2 ---
ax9 = subplot(7, 2, 9);
if size(all_auv_bw, 2) >= 2
    histogram(all_auv_bw(:,2), 30, 'FaceColor', [1 0.5 0], 'EdgeColor', 'w', 'Normalization', 'probability');
    title(sprintf('AUV 2nd Peak BW (Mean: %.0f Hz, Std: %.0f Hz)', mean(all_auv_bw(:,2), 'omitnan'), std(all_auv_bw(:,2), 'omitnan')), 'Color', 'w');
end
xlabel('Total Bandwidth (Hz)', 'Color', 'w');

ax10 = subplot(7, 2, 10);
if size(all_auv_freqs, 2) >= 2
    histogram(all_auv_freqs(:,2), 30, 'FaceColor', [1 0.5 0], 'EdgeColor', 'w', 'Normalization', 'probability');
    title(sprintf('AUV 2nd Peak Freq (Mean: %.0f Hz, Std: %.0f Hz)', mean(all_auv_freqs(:,2), 'omitnan'), std(all_auv_freqs(:,2), 'omitnan')), 'Color', 'w');
end
xlabel('Dominant Frequency (Hz)', 'Color', 'w');

% --- AUV Peak 3 ---
ax11 = subplot(7, 2, 11);
if size(all_auv_bw, 2) >= 3
    histogram(all_auv_bw(:,3), 30, 'FaceColor', [0.5 1 0], 'EdgeColor', 'w', 'Normalization', 'probability');
    title(sprintf('AUV 3rd Peak BW (Mean: %.0f Hz, Std: %.0f Hz)', mean(all_auv_bw(:,3), 'omitnan'), std(all_auv_bw(:,3), 'omitnan')), 'Color', 'w');
end
xlabel('Total Bandwidth (Hz)', 'Color', 'w');

ax12 = subplot(7, 2, 12);
if size(all_auv_freqs, 2) >= 3
    histogram(all_auv_freqs(:,3), 30, 'FaceColor', [0.5 1 0], 'EdgeColor', 'w', 'Normalization', 'probability');
    title(sprintf('AUV 3rd Peak Freq (Mean: %.0f Hz, Std: %.0f Hz)', mean(all_auv_freqs(:,3), 'omitnan'), std(all_auv_freqs(:,3), 'omitnan')), 'Color', 'w');
end
xlabel('Dominant Frequency (Hz)', 'Color', 'w');

% --- Motorboat ---
ax13 = subplot(7, 2, 13);
if ~isempty(all_ship_bw)
    histogram(all_ship_bw(:,1), 30, 'FaceColor', [1 0 1], 'EdgeColor', 'w', 'Normalization', 'probability');
    title(sprintf('Motorboat BW (Mean: %.0f Hz, Std: %.0f Hz)', mean(all_ship_bw(:,1), 'omitnan'), std(all_ship_bw(:,1), 'omitnan')), 'Color', 'w');
end
xlabel('Total Bandwidth (Hz)', 'Color', 'w');

ax14 = subplot(7, 2, 14);
if ~isempty(all_ship_freq)
    histogram(all_ship_freq(:,1), 30, 'FaceColor', [1 0 1], 'EdgeColor', 'w', 'Normalization', 'probability');
    title(sprintf('Motorboat Freq (Mean: %.0f Hz, Std: %.0f Hz)', mean(all_ship_freq(:,1), 'omitnan'), std(all_ship_freq(:,1), 'omitnan')), 'Color', 'w');
end
xlabel('Dominant Frequency (Hz)', 'Color', 'w');

% Apply dark theme and labels to all axes
axes_list = [ax1, ax2, ax3, ax4, ax5, ax6, ax7, ax8, ax9, ax10, ax11, ax12, ax13, ax14];
for ax = axes_list
    set(ax, 'Color', [0.18 0.18 0.18], 'XColor', [0.8 0.8 0.8], 'YColor', [0.8 0.8 0.8]);
    grid(ax, 'on');
    ax.GridColor = [0.4 0.4 0.4];
    ylabel(ax, 'Probability', 'Color', 'w');
end

function [bw_array, freq_array, time_array] = process_stability(filename, info, window_sec, step_sec, freq_band, num_freqs)
    actual_window = min(window_sec, info.Duration);
    start_times = 0:step_sec:(info.Duration - actual_window);
    if isempty(start_times), start_times = 0; end
    
    bw_array = zeros(length(start_times), num_freqs);
    freq_array = zeros(length(start_times), num_freqs);
    time_array = start_times;
    
    % OPTIMIZATION: Load the entire file into memory once.
    % Repeatedly calling audioread for small chunks causes massive file-seeking overhead.
    [full_data, sr] = audioread(filename);
    if size(full_data, 2) > 1, full_data = mean(full_data, 2); end
    
    for i = 1:length(start_times)
        start_sample = max(1, round(start_times(i) * sr));
        end_sample = min(length(full_data), start_sample + round(actual_window * sr) - 1);
        
        data = full_data(start_sample:end_sample);
        [bw_array(i, :), freq_array(i, :)] = calculate_total_bandwidth(data, sr, freq_band, num_freqs);
    end
end

function [bws, dom_freqs] = calculate_total_bandwidth(data, sr, freq_band, num_freqs)
    % 1. Compute Raw FFT Magnitude
    data_mag_full = abs(fft(data));
    N = length(data);
    data_mag = data_mag_full(1:floor(N/2));
    Faxis = linspace(0, sr/2, floor(N/2))';
    if size(data_mag, 2) > 1, data_mag = data_mag'; end
    
    valid_idx = (Faxis >= freq_band(1)) & (Faxis <= freq_band(2));
    Faxis = Faxis(valid_idx);
    data_mag = data_mag(valid_idx);
    
    % OPTIMIZATION: Reduce to ~1 Hz resolution for massive findpeaks speedup
    % By taking the local maximum for the upper array and minimum for the lower array,
    % we perfectly preserve the exact peak heights and valley floors without filtering them.
    block_size = floor(N / sr); 
    if block_size > 1
        num_blocks = floor(length(data_mag) / block_size);
        trunc_len = num_blocks * block_size;
        
        data_mag_blocks = reshape(data_mag(1:trunc_len), block_size, []);
        data_mag_upper = max(data_mag_blocks, [], 1)';
        data_mag_lower = min(data_mag_blocks, [], 1)';
        Faxis = mean(reshape(Faxis(1:trunc_len), block_size, []), 1)';
    else
        data_mag_upper = data_mag;
        data_mag_lower = data_mag;
    end
    
    % 2. Envelopes
    freq_res = Faxis(2) - Faxis(1);
    min_dist = max(1, round(5 / freq_res)); % Enforce 5 Hz separation
    
    [peaks, locs_max] = findpeaks(data_mag_upper, 'MinPeakDistance', min_dist);
    if isempty(locs_max), locs_max = [1; length(data_mag_upper)]; peaks = [data_mag_upper(1); data_mag_upper(end)]; end
    if locs_max(1) > 1, locs_max = [1; locs_max]; peaks = [data_mag_upper(1); peaks]; end
    if locs_max(end) < length(data_mag_upper), locs_max = [locs_max; length(data_mag_upper)]; peaks = [peaks; data_mag_upper(end)]; end
    
    peak_freqs = Faxis(locs_max);
    envelope_upper = interp1(peak_freqs, peaks, Faxis, 'pchip');
    envelope_upper = max(envelope_upper, 0);
    
    [~, locs_min] = findpeaks(-data_mag_lower, 'MinPeakDistance', min_dist); 
    valleys = data_mag_lower(locs_min);
    if isempty(locs_min), locs_min = [1; length(data_mag_lower)]; valleys = [data_mag_lower(1); data_mag_lower(end)]; end
    if locs_min(1) > 1, locs_min = [1; locs_min]; valleys = [data_mag_lower(1); valleys]; end
    if locs_min(end) < length(data_mag_lower), locs_min = [locs_min; length(data_mag_lower)]; valleys = [valleys; data_mag_lower(end)]; end
    
    valley_freqs = Faxis(locs_min);
    envelope_lower = interp1(valley_freqs, valleys, Faxis, 'pchip');
    envelope_lower = max(envelope_lower, 0);
    
    % 3. Pinch Points
    delta = envelope_upper - envelope_lower;
    [~, locs_min_delta] = findpeaks(-delta);
    
    [env_peaks, env_locs] = findpeaks(envelope_upper);
    if isempty(env_locs), [env_peaks, env_locs] = max(envelope_upper); end
    
    [~, sort_idx] = sort(env_peaks, 'descend');
    
    % Bandwidth and Frequency is calculated for the top N peaks
    bws = nan(1, num_freqs);
    dom_freqs = nan(1, num_freqs);
    
    for k = 1:min(num_freqs, length(sort_idx))
        peak_idx = env_locs(sort_idx(k));
        dom_freqs(k) = Faxis(peak_idx);
        
        if isempty(locs_min_delta)
            flo_idx = 1; fhi_idx = length(Faxis);
        else
            left_mins = locs_min_delta(locs_min_delta <= peak_idx);
            if isempty(left_mins), flo_idx = 1; else, flo_idx = left_mins(end); end
            
            right_mins = locs_min_delta(locs_min_delta > peak_idx);
            if isempty(right_mins), fhi_idx = length(Faxis); else, fhi_idx = right_mins(1); end
        end
        bws(k) = Faxis(fhi_idx) - Faxis(flo_idx);
    end
end
