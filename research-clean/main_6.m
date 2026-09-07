% main_5.m
% Bandwidth Stability Analysis with Jain's Fairness Index

% Define directories
base_dirs = [
    "C:\Users\Roy\Recordings\hear_my_ship\V1\",
    "C:\Users\Roy\Recordings\Croatia\Ocean Sonics\"
    ];

all_datasets_paths = [];
all_datasets_names = [];

for b = 1:length(base_dirs)
    bdir = base_dirs(b);
    if ~isfolder(bdir)
        warning('Directory not found: %s\nPlease check that the path is correct.', bdir);
        continue;
    end

    subdirs = dir(bdir);
    subdirs = subdirs([subdirs.isdir]);
    subdirs = subdirs(~ismember({subdirs.name}, {'.', '..'}));

    for s = 1:length(subdirs)
        sub_path = fullfile(bdir, subdirs(s).name);
        is_croatia = contains(string(bdir), 'Croatia', 'IgnoreCase', true);
        
        if is_croatia
            if isfile(fullfile(sub_path, 'merged_output.wav'))
                all_datasets_names = [all_datasets_names; string(subdirs(s).name)];
                all_datasets_paths = [all_datasets_paths; string(sub_path)];
            end
        else
            wavs = dir(fullfile(sub_path, '**\*.wav'));
            wavs = wavs(~[wavs.isdir]);
            if length(wavs) >= 10
                all_datasets_names = [all_datasets_names; string(subdirs(s).name)];
                all_datasets_paths = [all_datasets_paths; string(sub_path)];
            end
        end
    end
end

if isempty(all_datasets_paths)
    error('No datasets found in any base directories.');
end

num_peaks = 5;
num_peaks = 5;

overall_jains_all = zeros(length(all_datasets_paths), num_peaks);

for s = 1:length(all_datasets_paths)
    dataset_name = all_datasets_names(s);
    dataset_dir = all_datasets_paths(s);

    merged_file = fullfile(dataset_dir, 'merged_output.wav');
    if isfile(merged_file)
        wav_files = dir(merged_file);
        fprintf('\n=== Processing Sub-dataset: %s (using merged_output.wav) ===\n', dataset_name);
    else
        wav_files = dir(fullfile(dataset_dir, '**\*.wav'));
        wav_files = wav_files(~[wav_files.isdir]);
        fprintf('\n=== Processing Sub-dataset: %s (%d files) ===\n', dataset_name, length(wav_files));
    end

    if isempty(wav_files)
        continue;
    end

    % Determine frequency band
    is_croatia = contains(dataset_dir, 'Croatia', 'IgnoreCase', true);
    % Reverting to 20s window globally for all datasets
    window_sec = 20;
    step_sec = 10;
    
    if is_croatia
        freq_band = [400, 1000];
        plot_env = true;
        [~, parent_dir, ~] = fileparts(fileparts(dataset_dir));
        dataset_name_display = sprintf('%s/%s', parent_dir, dataset_name);
    else
        freq_band = [50, 24000];
        plot_env = false;
        dataset_name_display = dataset_name;
    end
    
    % Aggregate arrays for this sub-dataset
    all_bw = [];
    all_freqs = [];
    all_file_jains = [];
    all_file_mean_bws = [];
    file_names = {};

    for i = 1:length(wav_files)
        filepath = fullfile(wav_files(i).folder, wav_files(i).name);
        try
            info = audioinfo(filepath);
            fprintf('  [%d/%d] %s (%.1fs)\n', i, length(wav_files), wav_files(i).name, info.Duration);

            [bw, freqs, time_arr] = process_stability(filepath, info, window_sec, step_sec, freq_band, num_peaks, plot_env);

            file_mean_bws = mean(bw, 1, 'omitnan');

            fprintf('    Mean Frequency : P1=%.0fHz, P2=%.0fHz, P3=%.0fHz, P4=%.0fHz, P5=%.0fHz\n', ...
                mean(freqs(:,1),'omitnan'), mean(freqs(:,2),'omitnan'), mean(freqs(:,3),'omitnan'), mean(freqs(:,4),'omitnan'), mean(freqs(:,5),'omitnan'));
            fprintf('    Mean Bandwidth : P1=%.0fHz, P2=%.0fHz, P3=%.0fHz, P4=%.0fHz, P5=%.0fHz\n', ...
                file_mean_bws(1), file_mean_bws(2), file_mean_bws(3), file_mean_bws(4), file_mean_bws(5));

            all_file_mean_bws = [all_file_mean_bws; file_mean_bws];
            file_names{end+1} = wav_files(i).name;

            all_bw = [all_bw; bw];
            all_freqs = [all_freqs; freqs];
        catch e
            fprintf('  Error processing %s: %s\n', wav_files(i).name, e.message);
        end
    end

    % Plot Histograms (Aggregated for Sub-dataset)
    figure('Name', sprintf('%s - Overall Window Histograms', dataset_name), 'Position', [100, 50, 1000, 1000]);
    set(gcf, 'Color', [0.12 0.12 0.12]);

    dataset_overall_jains = nan(1, num_peaks);

    for p = 1:num_peaks
        if size(all_bw, 2) >= p
            ax = subplot(num_peaks, 1, p);
            bw_data = all_bw(:, p);

            % Remove NaNs for Fairness calculation
            bw_clean = bw_data(~isnan(bw_data));

            % Calculate overall Jain's Fairness for this peak across the sub-dataset windows
            if ~isempty(bw_clean) && sum(bw_clean) > 0
                jains_fairness = (sum(bw_clean)^2) / (length(bw_clean) * sum(bw_clean.^2));
            else
                jains_fairness = NaN;
            end

            dataset_overall_jains(p) = jains_fairness;

            histogram(bw_data, 30, 'FaceColor', [0 1 1], 'EdgeColor', 'w', 'Normalization', 'probability');
            mean_freq = mean(all_freqs(:, p), 'omitnan');
            title(sprintf('%s - Peak %d Overall BW Stability (Mean Freq: %.0f Hz, Jain''s: %.4f)', dataset_name, p, mean_freq, jains_fairness), 'Color', 'w');
            xlabel('Total Bandwidth (Hz)', 'Color', 'w');
            ylabel('Probability', 'Color', 'w');

            set(ax, 'Color', [0.18 0.18 0.18], 'XColor', [0.8 0.8 0.8], 'YColor', [0.8 0.8 0.8]);
            grid(ax, 'on');
            ax.GridColor = [0.4 0.4 0.4];
        end
    end

    overall_jains_all(s, :) = dataset_overall_jains;

    % Plot Histograms (Between-Files Mean Bandwidths) - Skip if using merged output
    if ~isempty(all_file_mean_bws) && length(wav_files) > 1
        figure('Name', sprintf('%s - Bandwidth Mean (Hz) Distribution', dataset_name), 'Position', [150, 100, 1000, 1000]);
        set(gcf, 'Color', [0.12 0.12 0.12]);

        for p = 1:num_peaks
            if size(all_file_mean_bws, 2) >= p
                ax = subplot(num_peaks, 1, p);
                bw_data = all_file_mean_bws(:, p);
                bw_clean = bw_data(~isnan(bw_data));

                % Calculate Jain's Fairness of the mean bandwidths between files
                if ~isempty(bw_clean) && sum(bw_clean) > 0
                    jains_fairness = (sum(bw_clean)^2) / (length(bw_clean) * sum(bw_clean.^2));
                else
                    jains_fairness = NaN;
                end

                histogram(bw_data, 15, 'FaceColor', [1 0.5 0], 'EdgeColor', 'w', 'Normalization', 'probability');
                mean_freq = mean(all_freqs(:, p), 'omitnan');
                title(sprintf('%s - Peak %d Bandwidth Mean (Hz) (Jain''s Fairness: %.4f)', dataset_name, p, jains_fairness), 'Color', 'w', 'Interpreter', 'none');
                xlabel('Mean File Bandwidth (Hz)', 'Color', 'w');
                ylabel('Probability', 'Color', 'w');

                set(ax, 'Color', [0.18 0.18 0.18], 'XColor', [0.8 0.8 0.8], 'YColor', [0.8 0.8 0.8]);
                grid(ax, 'on');
                ax.GridColor = [0.4 0.4 0.4];
            end
        end
    end

    % Plot Histograms (Pairwise Segment Bandwidth Fairness)
    if ~isempty(all_file_mean_bws) && length(wav_files) >= 1
        figure('Name', sprintf('%s - Pairwise Bandwidth Fairness Distribution', dataset_name_display), 'Position', [200, 150, 1000, 1000]);
        set(gcf, 'Color', [0.12 0.12 0.12]);

        for p = 1:num_peaks
            if size(all_file_mean_bws, 2) >= p
                ax = subplot(num_peaks, 1, p);
                
                % Extract all segment bandwidths for this peak
                if is_croatia
                    % For Croatia, all_bw contains all the 20s windows from the merged file
                    bw_data = all_bw(:, p);
                else
                    % For hear_my_ship, all_file_mean_bws contains the 20s mean for each file
                    bw_data = all_file_mean_bws(:, p);
                end
                
                bw_clean = bw_data(~isnan(bw_data));

                % Compute Fairness
                pairwise_fairness = [];
                if length(bw_clean) > 1
                    if is_croatia
                        % For Croatia: compute fairness between SUCCESSIVE buffers
                        for i = 1:length(bw_clean)-1
                            x1 = bw_clean(i);
                            x2 = bw_clean(i+1);
                            if (x1^2 + x2^2) > 0
                                f = (x1 + x2)^2 / (2 * (x1^2 + x2^2));
                                pairwise_fairness(end+1) = f;
                            end
                        end
                        title_prefix = 'Successive Buffer';
                        plot_title = sprintf('%%s - Peak %%d %%s Fairness (Mean: %%.4f)', dataset_name_display, p, title_prefix);
                    else
                        % For hear_my_ship: compute fairness between ALL PAIRS of files
                        for i = 1:length(bw_clean)-1
                            for j = i+1:length(bw_clean)
                                x1 = bw_clean(i);
                                x2 = bw_clean(j);
                                if (x1^2 + x2^2) > 0
                                    f = (x1 + x2)^2 / (2 * (x1^2 + x2^2));
                                    pairwise_fairness(end+1) = f;
                                end
                            end
                        end
                        title_prefix = 'Pairwise Segment';
                        plot_title = sprintf('%%s - Peak %%d %%s Fairness (Mean: %%.4f)', dataset_name_display, p, title_prefix);
                    end
                end

                if ~isempty(pairwise_fairness)
                    histogram(pairwise_fairness, 30, 'FaceColor', [0.2 0.8 0.2], 'EdgeColor', 'w', 'Normalization', 'probability');
                    mean_fair = mean(pairwise_fairness, 'omitnan');
                    title(sprintf('%s - Peak %d %s Fairness (Mean: %.4f)', dataset_name_display, p, title_prefix, mean_fair), 'Color', 'w', 'Interpreter', 'none');
                    xlabel(sprintf('%s Jain''s Fairness Index', title_prefix), 'Color', 'w');
                    ylabel('Probability', 'Color', 'w');
                else
                    title(sprintf('%s - Peak %d Segment Fairness (Not enough data)', dataset_name_display, p), 'Color', 'w', 'Interpreter', 'none');
                end

                set(ax, 'Color', [0.18 0.18 0.18], 'XColor', [0.8 0.8 0.8], 'YColor', [0.8 0.8 0.8]);
                grid(ax, 'on');
                ax.GridColor = [0.4 0.4 0.4];
            end
        end
    end
end

function [bw_array, freq_array, time_array] = process_stability(filename, info, window_sec, step_sec, freq_band, num_freqs, plot_env)
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
    do_plot = plot_env && (i == 1);
    [bw_array(i, :), freq_array(i, :)] = calculate_total_bandwidth(data, sr, freq_band, num_freqs, do_plot, filename);
end
end

function [bws, dom_freqs] = calculate_total_bandwidth(data, sr, freq_band, num_freqs, do_plot, filename)
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
    data_mag_plot = mean(data_mag_blocks, 1)';
else
    data_mag_upper = data_mag;
    data_mag_lower = data_mag;
    data_mag_plot = data_mag;
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
bounds = [];

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

    if do_plot
        bounds = [bounds; flo_idx, fhi_idx];
    end
end

if do_plot
    [parent_path, name, ~] = fileparts(filename);
    [~, parent_dir, ~] = fileparts(parent_path);
    plot_name = sprintf('%s/%s', parent_dir, name);
    
    figure('Name', sprintf('Envelopes & BW - %s', plot_name), 'Position', [100, 100, 1000, 500]);
    set(gcf, 'Color', [0.12 0.12 0.12]);
    ax = axes();
    hold on;

    plot(Faxis, data_mag_plot, 'Color', [0 1 1 0.4], 'LineWidth', 0.5);
    plot(Faxis, envelope_upper, 'Color', [1 0.8 0], 'LineWidth', 2.0);
    plot(Faxis, envelope_lower, 'Color', [1 0 1], 'LineWidth', 2.0);

    y_min = min(envelope_lower);
    y_max = max(envelope_upper);

    for k = 1:size(bounds, 1)
        flo = Faxis(bounds(k, 1));
        fhi = Faxis(bounds(k, 2));

        plot([flo, fhi], [y_min, y_min], 'Color', [0 1 0], 'LineWidth', 4);
        plot([flo, flo], [y_min, y_max], 'Color', [0 1 0], 'LineStyle', '--');
        plot([fhi, fhi], [y_min, y_max], 'Color', [0 1 0], 'LineStyle', '--');

        plot(flo, envelope_upper(bounds(k, 1)), 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 5);
        plot(flo, envelope_lower(bounds(k, 1)), 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 5);
        plot(fhi, envelope_upper(bounds(k, 2)), 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 5);
        plot(fhi, envelope_lower(bounds(k, 2)), 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 5);
    end

    title(sprintf('Magnitude Spectrum & Envelopes - %s', strrep(plot_name, '_', '\_')), 'Color', 'w');
    xlabel('Frequency (Hz)', 'Color', 'w');
    ylabel('Magnitude', 'Color', 'w');
    set(ax, 'Color', [0.18 0.18 0.18], 'XColor', [0.8 0.8 0.8], 'YColor', [0.8 0.8 0.8]);
    grid(ax, 'on');
    ax.GridColor = [0.4 0.4 0.4];
end
end
