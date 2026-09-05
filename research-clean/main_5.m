% main_5.m
% Bandwidth Stability Analysis with Jain's Fairness Index

% Define directory
merged_dir = "D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\";
merged_files = dir(fullfile(merged_dir, '*.wav'));

% We use a 30-second window. 
% We slide by 15 seconds (50% overlap) to speed up processing while still generating multiple samples.
window_sec = 30;
step_sec = 15; 
num_peaks = 5;

% Aggregate arrays
all_merged_bw = [];
all_merged_freqs = [];

all_file_jains = [];
file_names = {};

fprintf('Processing %d Merged files...\n', length(merged_files));
for i = 1:length(merged_files)
    filepath = fullfile(merged_files(i).folder, merged_files(i).name);
    try
        info = audioinfo(filepath);
        fprintf('  [%d/%d] %s (%.1fs)\n', i, length(merged_files), merged_files(i).name, info.Duration);
        
        % Assume scooter -> [400, 1000] Hz band
        [bw, freqs, ~] = process_stability(filepath, info, window_sec, step_sec, [400, 1000], num_peaks); 
        
        % Calculate Jain's fairness for each peak in this specific file
        file_jains = zeros(1, num_peaks);
        for p = 1:num_peaks
            bw_data = bw(:, p);
            bw_clean = bw_data(~isnan(bw_data));
            if ~isempty(bw_clean) && sum(bw_clean) > 0
                file_jains(p) = (sum(bw_clean)^2) / (length(bw_clean) * sum(bw_clean.^2));
            else
                file_jains(p) = NaN;
            end
        end
        
        fprintf('    Jain''s Fairness: P1=%.3f, P2=%.3f, P3=%.3f, P4=%.3f, P5=%.3f\n', ...
            file_jains(1), file_jains(2), file_jains(3), file_jains(4), file_jains(5));
        fprintf('    Mean Frequency : P1=%.0fHz, P2=%.0fHz, P3=%.0fHz, P4=%.0fHz, P5=%.0fHz\n', ...
            mean(freqs(:,1),'omitnan'), mean(freqs(:,2),'omitnan'), mean(freqs(:,3),'omitnan'), mean(freqs(:,4),'omitnan'), mean(freqs(:,5),'omitnan'));
        fprintf('    Mean Bandwidth : P1=%.0fHz, P2=%.0fHz, P3=%.0fHz, P4=%.0fHz, P5=%.0fHz\n', ...
            mean(bw(:,1),'omitnan'), mean(bw(:,2),'omitnan'), mean(bw(:,3),'omitnan'), mean(bw(:,4),'omitnan'), mean(bw(:,5),'omitnan'));
        
        all_file_jains = [all_file_jains; file_jains];
        file_names{end+1} = merged_files(i).name;
        
        all_merged_bw = [all_merged_bw; bw];
        all_merged_freqs = [all_merged_freqs; freqs];
    catch e
        fprintf('  Error processing %s: %s\n', merged_files(i).name, e.message);
    end
end

% Plot Histograms (Aggregated)
figure('Position', [100, 50, 1000, 1000]);
set(gcf, 'Color', [0.12 0.12 0.12]);

for p = 1:num_peaks
    if size(all_merged_bw, 2) >= p
        ax = subplot(num_peaks, 1, p);
        bw_data = all_merged_bw(:, p);
        
        % Remove NaNs for Fairness calculation
        bw_clean = bw_data(~isnan(bw_data));
        
        % Calculate Jain's Fairness Index for Bandwidth Stability (Aggregated)
        if ~isempty(bw_clean) && sum(bw_clean) > 0
            jains_fairness = (sum(bw_clean)^2) / (length(bw_clean) * sum(bw_clean.^2));
        else
            jains_fairness = NaN;
        end
        
        histogram(bw_data, 30, 'FaceColor', [0 1 1], 'EdgeColor', 'w', 'Normalization', 'probability');
        mean_freq = mean(all_merged_freqs(:, p), 'omitnan');
        title(sprintf('Aggregated Peak %d BW Stability (Mean Freq: %.0f Hz, Jain''s: %.4f)', p, mean_freq, jains_fairness), 'Color', 'w');
        xlabel('Total Bandwidth (Hz)', 'Color', 'w');
        ylabel('Probability', 'Color', 'w');
        
        set(ax, 'Color', [0.18 0.18 0.18], 'XColor', [0.8 0.8 0.8], 'YColor', [0.8 0.8 0.8]);
        grid(ax, 'on');
        ax.GridColor = [0.4 0.4 0.4];
    end
end

% Plot Bar Chart (Per-File Jain's Fairness)
if ~isempty(all_file_jains)
    figure('Position', [150, 100, 1000, 600]);
    set(gcf, 'Color', [0.12 0.12 0.12]);
    b = bar(all_file_jains, 'grouped');
    
    % Use distinct colors for the 5 peaks
    colors = [0 1 1; 1 1 0; 0 1 0; 1 0.5 0; 1 0 1]; 
    for k = 1:min(num_peaks, length(b))
        b(k).FaceColor = colors(k,:);
        b(k).EdgeColor = 'none';
    end
    
    ax = gca;
    set(ax, 'Color', [0.18 0.18 0.18], 'XColor', 'w', 'YColor', 'w', 'XTick', 1:length(file_names), 'XTickLabel', file_names);
    xtickangle(45);
    title('Per-File Jain''s Fairness of Bandwidth', 'Color', 'w');
    ylabel('Jain''s Fairness Index', 'Color', 'w');
    legend('Peak 1', 'Peak 2', 'Peak 3', 'Peak 4', 'Peak 5', 'TextColor', 'w', 'Color', 'none', 'Location', 'best');
    grid on; ax.GridColor = [0.4 0.4 0.4];
end

function [bw_array, freq_array, time_array] = process_stability(filename, info, window_sec, step_sec, freq_band, num_freqs)
    actual_window = min(window_sec, info.Duration);
    start_times = 0:step_sec:(info.Duration - actual_window);
    if isempty(start_times), start_times = 0; end
    
    bw_array = zeros(length(start_times), num_freqs);
    freq_array = zeros(length(start_times), num_freqs);
    time_array = start_times;
    
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
    data_mag_full = abs(fft(data));
    N = length(data);
    data_mag = data_mag_full(1:floor(N/2));
    Faxis = linspace(0, sr/2, floor(N/2))';
    if size(data_mag, 2) > 1, data_mag = data_mag'; end
    
    valid_idx = (Faxis >= freq_band(1)) & (Faxis <= freq_band(2));
    Faxis = Faxis(valid_idx);
    data_mag = data_mag(valid_idx);
    
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
    
    freq_res = Faxis(2) - Faxis(1);
    min_dist = max(1, round(5 / freq_res));
    
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
    
    delta = envelope_upper - envelope_lower;
    [~, locs_min_delta] = findpeaks(-delta);
    
    [env_peaks, env_locs] = findpeaks(envelope_upper);
    if isempty(env_locs), [env_peaks, env_locs] = max(envelope_upper); end
    
    [~, sort_idx] = sort(env_peaks, 'descend');
    
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
