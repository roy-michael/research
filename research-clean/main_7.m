% main_7.m
% Structured and Configurable Bandwidth Stability Analysis

function main_7()
% 1. Load Configuration
config = get_default_config();

% 2. Find Datasets
datasets = find_datasets(config);
if isempty(datasets)
    error('No datasets found in any base directories.');
end

% 2.5 Determine Global Target Sample Rate
fprintf('Scanning datasets to determine minimum sample rate...\n');
global_target_sr = get_minimum_sample_rate(datasets);
if isinf(global_target_sr)
    error('Could not determine sample rate from any provided files.');
end
fprintf('Global Target Sample Rate set to %d Hz\n', global_target_sr);

overall_jains_all = zeros(length(datasets), config.num_peaks);

% 3. Process and Plot
for s = 1:length(datasets)
    dataset = datasets(s);

    results = process_dataset(dataset, config, global_target_sr);

    if ~isempty(results.dataset_overall_jains)
        overall_jains_all(s, :) = results.dataset_overall_jains;
    end

    if ~isempty(results.all_bw)
        plot_dataset_results(dataset, results, config);
    end
end
end

% =========================================================================
% CONFIGURATION
% =========================================================================
function config = get_default_config()
config = struct();

% Data directories
config.base_dirs = [
    "C:\Users\Roy\Recordings\hear_my_ship\V1\Motor Boats\Motorboat_08.08.23_142223_20secCPA.wav",
    "C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_1_600m\RBW6737_20250724_093000.wav"
    ];

% Analysis parameters
config.num_peaks = 5;
config.window_sec = 0.5;
config.step_sec = 0.25;
config.duration_sec = 20;
config.nfft = 1024;
config.overlap = 0.5;

% Default display settings
config.plot_env_default = false;

% Dataset-specific configurations (rule-based overrides)
% We handle dataset specific logic like Croatia vs Hear My Ship inside
% process_dataset based on the path.
end

% =========================================================================
% DATA DISCOVERY
% =========================================================================
function datasets = find_datasets(config)
datasets = [];

for b = 1:length(config.base_dirs)
    bpath = config.base_dirs(b);

    if isfile(bpath)
        [~, name, ext] = fileparts(bpath);
        if strcmpi(ext, '.wav')
            ds = struct();
            ds.name = string(name);
            ds.path = string(bpath);
            ds.is_croatia = contains(string(bpath), 'Croatia', 'IgnoreCase', true);
            ds.is_file = true;
            datasets = [datasets; ds];
        else
            warning('File is not a .wav file: %s', bpath);
        end
        continue;
    end

    if ~isfolder(bpath)
        warning('Directory not found: %s\nPlease check that the path is correct.', bpath);
        continue;
    end

    subdirs = dir(bpath);
    subdirs = subdirs([subdirs.isdir]);
    subdirs = subdirs(~ismember({subdirs.name}, {'.', '..'}));

    for s = 1:length(subdirs)
        sub_path = fullfile(bpath, subdirs(s).name);
        is_croatia = contains(string(bpath), 'Croatia', 'IgnoreCase', true);

        ds = struct();
        ds.name = string(subdirs(s).name);
        ds.path = string(sub_path);
        ds.is_croatia = is_croatia;
        ds.is_file = false;

        if is_croatia
            if isfile(fullfile(sub_path, 'merged_output.wav'))
                datasets = [datasets; ds];
            end
        else
            wavs = dir(fullfile(sub_path, '**\*.wav'));
            wavs = wavs(~[wavs.isdir]);
            if length(wavs) >= 10
                datasets = [datasets; ds];
            end
        end
    end
end
end

function min_sr = get_minimum_sample_rate(datasets)
    min_sr = Inf;
    for s = 1:length(datasets)
        dataset = datasets(s);
        if isfield(dataset, 'is_file') && dataset.is_file
            wav_files = dir(dataset.path);
        else
            merged_file = fullfile(dataset.path, 'merged_output.wav');
            if isfile(merged_file)
                wav_files = dir(merged_file);
            else
                wav_files = dir(fullfile(dataset.path, '**\*.wav'));
                wav_files = wav_files(~[wav_files.isdir]);
            end
        end
        
        for i = 1:length(wav_files)
            filepath = fullfile(wav_files(i).folder, wav_files(i).name);
            try
                info = audioinfo(filepath);
                if info.SampleRate < min_sr
                    min_sr = info.SampleRate;
                end
            catch
                % ignore
            end
        end
    end
end

% =========================================================================
% PROCESSING
% =========================================================================
function results = process_dataset(dataset, config, global_target_sr)
if isfield(dataset, 'is_file') && dataset.is_file
    wav_files = dir(dataset.path);
    fprintf('\n=== Processing Sub-dataset (Single File): %s ===\n', dataset.name);
else
    merged_file = fullfile(dataset.path, 'merged_output.wav');
    if isfile(merged_file)
        wav_files = dir(merged_file);
        fprintf('\n=== Processing Sub-dataset: %s (using merged_output.wav) ===\n', dataset.name);
    else
        wav_files = dir(fullfile(dataset.path, '**\*.wav'));
        wav_files = wav_files(~[wav_files.isdir]);
        fprintf('\n=== Processing Sub-dataset: %s (%d files) ===\n', dataset.name, length(wav_files));
    end
end

results = struct();
results.all_bw = [];
results.all_freqs = [];
results.all_file_mean_bws = [];
results.file_names = {};
results.dataset_overall_jains = nan(1, config.num_peaks);
results.wav_files_count = length(wav_files);

if isempty(wav_files)
    return;
end

% Dataset specific config
if dataset.is_croatia
    freq_band = [400, 1000];
    plot_env = true;
    [~, parent_dir, ~] = fileparts(fileparts(dataset.path));
    dataset_name_display = sprintf('%s/%s', parent_dir, dataset.name);
else
    freq_band = [50, 24000];
    plot_env = config.plot_env_default;
    dataset_name_display = dataset.name;
end

results.dataset_name_display = dataset_name_display;

for i = 1:length(wav_files)
    filepath = fullfile(wav_files(i).folder, wav_files(i).name);
    try
        info = audioinfo(filepath);
        fprintf('  [%d/%d] %s (%.1fs)\n', i, length(wav_files), wav_files(i).name, info.Duration);

        [bw, freqs, time_arr] = process_stability(filepath, info, config, freq_band, plot_env, global_target_sr);

        file_mean_bws = mean(bw, 1, 'omitnan');

        fprintf('    Mean Frequency : P1=%.0fHz, P2=%.0fHz, P3=%.0fHz, P4=%.0fHz, P5=%.0fHz\n', ...
            mean(freqs(:,1),'omitnan'), mean(freqs(:,2),'omitnan'), mean(freqs(:,3),'omitnan'), mean(freqs(:,4),'omitnan'), mean(freqs(:,5),'omitnan'));
        fprintf('    Mean Bandwidth : P1=%.0fHz, P2=%.0fHz, P3=%.0fHz, P4=%.0fHz, P5=%.0fHz\n', ...
            file_mean_bws(1), file_mean_bws(2), file_mean_bws(3), file_mean_bws(4), file_mean_bws(5));

        results.all_file_mean_bws = [results.all_file_mean_bws; file_mean_bws];
        results.file_names{end+1} = wav_files(i).name;

        results.all_bw = [results.all_bw; bw];
        results.all_freqs = [results.all_freqs; freqs];
    catch e
        fprintf('  Error processing %s: %s\n', wav_files(i).name, e.message);
    end
end

% Calculate Overall Jain's for dataset
for p = 1:config.num_peaks
    if size(results.all_bw, 2) >= p
        results.dataset_overall_jains(p) = compute_jains_fairness(results.all_bw(:, p));
    end
end
end

% =========================================================================
% PLOTTING
% =========================================================================
function plot_dataset_results(dataset, results, config)
dataset_name = dataset.name;
dataset_name_display = results.dataset_name_display;

% 1. Plot Histograms (Aggregated for Sub-dataset)
figure('Name', sprintf('%s - Overall Window Histograms', dataset_name), 'Position', [100, 50, 1000, 1000]);
set(gcf, 'Color', [0.12 0.12 0.12]);

for p = 1:config.num_peaks
    if size(results.all_bw, 2) >= p
        ax = subplot(config.num_peaks, 1, p);
        bw_data = results.all_bw(:, p);
        jains_fairness = results.dataset_overall_jains(p);

        histogram(bw_data, 30, 'FaceColor', [0 1 1], 'EdgeColor', 'w', 'Normalization', 'probability');
        mean_freq = mean(results.all_freqs(:, p), 'omitnan');
        title(sprintf('%s - Peak %d Overall BW Stability (Mean Freq: %.0f Hz, Jain''s: %.4f)', dataset_name, p, mean_freq, jains_fairness), 'Color', 'w', 'Interpreter', 'none');
        xlabel('Total Bandwidth (Hz)', 'Color', 'w');
        ylabel('Probability', 'Color', 'w');

        set(ax, 'Color', [0.18 0.18 0.18], 'XColor', [0.8 0.8 0.8], 'YColor', [0.8 0.8 0.8]);
        grid(ax, 'on');
        ax.GridColor = [0.4 0.4 0.4];
    end
end

% 2. Plot Histograms (Between-Files Mean Bandwidths)
if ~isempty(results.all_file_mean_bws) && results.wav_files_count > 1
    figure('Name', sprintf('%s - Bandwidth Mean (Hz) Distribution', dataset_name), 'Position', [150, 100, 1000, 1000]);
    set(gcf, 'Color', [0.12 0.12 0.12]);

    for p = 1:config.num_peaks
        if size(results.all_file_mean_bws, 2) >= p
            ax = subplot(config.num_peaks, 1, p);
            bw_data = results.all_file_mean_bws(:, p);
            jains_fairness = compute_jains_fairness(bw_data);

            histogram(bw_data, 15, 'FaceColor', [1 0.5 0], 'EdgeColor', 'w', 'Normalization', 'probability');
            title(sprintf('%s - Peak %d Bandwidth Mean (Hz) (Jain''s Fairness: %.4f)', dataset_name, p, jains_fairness), 'Color', 'w', 'Interpreter', 'none');
            xlabel('Mean File Bandwidth (Hz)', 'Color', 'w');
            ylabel('Probability', 'Color', 'w');

            set(ax, 'Color', [0.18 0.18 0.18], 'XColor', [0.8 0.8 0.8], 'YColor', [0.8 0.8 0.8]);
            grid(ax, 'on');
            ax.GridColor = [0.4 0.4 0.4];
        end
    end
end

% 3. Plot Histograms (Pairwise Segment Bandwidth Fairness)
if ~isempty(results.all_file_mean_bws) && results.wav_files_count >= 1
    figure('Name', sprintf('%s - Pairwise Bandwidth Fairness Distribution', dataset_name_display), 'Position', [200, 150, 1000, 1000]);
    set(gcf, 'Color', [0.12 0.12 0.12]);

    for p = 1:config.num_peaks
        if size(results.all_file_mean_bws, 2) >= p
            ax = subplot(config.num_peaks, 1, p);

            if dataset.is_croatia
                bw_data = results.all_bw(:, p);
            else
                bw_data = results.all_file_mean_bws(:, p);
            end

            [pairwise_fairness, title_prefix] = compute_pairwise_fairness(bw_data, dataset.is_croatia);

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

% =========================================================================
% FAIRNESS METRICS
% =========================================================================
function j = compute_jains_fairness(x)
x_clean = x(~isnan(x));
if isempty(x_clean) || sum(x_clean) == 0
    j = NaN;
else
    j = (sum(x_clean)^2) / (length(x_clean) * sum(x_clean.^2));
end
end

function [pairwise_fairness, title_prefix] = compute_pairwise_fairness(x, is_successive)
x_clean = x(~isnan(x));
pairwise_fairness = [];

if length(x_clean) > 1
    if is_successive
        for i = 1:length(x_clean)-1
            x1 = x_clean(i); x2 = x_clean(i+1);
            if (x1^2 + x2^2) > 0
                pairwise_fairness(end+1) = (x1 + x2)^2 / (2 * (x1^2 + x2^2));
            end
        end
        title_prefix = 'Successive Buffer';
    else
        for i = 1:length(x_clean)-1
            for j = i+1:length(x_clean)
                x1 = x_clean(i); x2 = x_clean(j);
                if (x1^2 + x2^2) > 0
                    pairwise_fairness(end+1) = (x1 + x2)^2 / (2 * (x1^2 + x2^2));
                end
            end
        end
        title_prefix = 'Pairwise Segment';
    end
else
    title_prefix = 'Segment';
end
end

% =========================================================================
% SIGNAL PROCESSING HELPERS
% =========================================================================
function [bw_array, freq_array, time_array] = process_stability(filename, info, config, freq_band, plot_env, target_sr)
max_process_time = min(config.duration_sec, info.Duration);
actual_window = min(config.window_sec, max_process_time);
start_times = 0:config.step_sec:(max_process_time - actual_window);
if isempty(start_times), start_times = 0; end

bw_array = zeros(length(start_times), config.num_peaks);
freq_array = zeros(length(start_times), config.num_peaks);
time_array = start_times;

[full_data, sr] = audioread(filename);
if size(full_data, 2) > 1, full_data = mean(full_data, 2); end

if sr > target_sr
    fprintf('    Downsampling from %d Hz to %d Hz...\n', sr, target_sr);
    full_data = resample(full_data, target_sr, sr);
    sr = target_sr;
end

for i = 1:length(start_times)
    start_sample = max(1, round(start_times(i) * sr));
    end_sample = min(length(full_data), start_sample + round(actual_window * sr) - 1);

    data = full_data(start_sample:end_sample);
    do_plot = plot_env && (i == 1);
    [bw_array(i, :), freq_array(i, :)] = calculate_total_bandwidth(data, sr, freq_band, config, do_plot, filename);
end
end

function [bws, dom_freqs] = calculate_total_bandwidth(data, sr, freq_band, config, do_plot, filename)
[bws, dom_freqs, plot_data] = compute_bandwidth_metrics(data, sr, freq_band, config);

if do_plot
    plot_bandwidth_envelopes(plot_data, filename);
end
end

function [bws, dom_freqs, plot_data] = compute_bandwidth_metrics(data, sr, freq_band, config)
noverlap = round(config.nfft * config.overlap);

% Fallback in case window is too small for nfft
if length(data) < config.nfft
    nfft_actual = length(data);
    noverlap = round(nfft_actual * config.overlap);
else
    nfft_actual = config.nfft;
end

[S, Faxis, ~] = spectrogram(data, nfft_actual, noverlap, nfft_actual, sr);

data_mag_blocks = abs(S);
data_mag_upper = max(data_mag_blocks, [], 2);
data_mag_lower = min(data_mag_blocks, [], 2);
data_mag_plot = mean(data_mag_blocks, 2);

valid_idx = (Faxis >= freq_band(1)) & (Faxis <= freq_band(2));
Faxis = Faxis(valid_idx);
data_mag_upper = data_mag_upper(valid_idx);
data_mag_lower = data_mag_lower(valid_idx);
data_mag_plot = data_mag_plot(valid_idx);

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

bws = nan(1, config.num_peaks);
dom_freqs = nan(1, config.num_peaks);
bounds = [];

for k = 1:min(config.num_peaks, length(sort_idx))
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

    bounds = [bounds; flo_idx, fhi_idx];
end

plot_data = struct();
plot_data.Faxis = Faxis;
plot_data.data_mag_plot = data_mag_plot;
plot_data.envelope_upper = envelope_upper;
plot_data.envelope_lower = envelope_lower;
plot_data.bounds = bounds;
end

function plot_bandwidth_envelopes(plot_data, filename)
Faxis = plot_data.Faxis;
data_mag_plot = plot_data.data_mag_plot;
envelope_upper = plot_data.envelope_upper;
envelope_lower = plot_data.envelope_lower;
bounds = plot_data.bounds;

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
