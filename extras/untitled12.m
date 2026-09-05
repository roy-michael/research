% =========================================================================
% Segmented Multi-Target Acoustic Tracker (Single-Pane Hierarchical Analysis)
% Recursively discovers all sub-directories within the parent path, treating
% each sub-directory as a completely separate dataset session. Combines the
% Carson Bandwidth KDE, Modulation Frequency KDE, and Global Annotated
% Spectrogram into a single unified figure pane per dataset. Uses high-contrast
% color generation to ensure distinct target coloring.
% =========================================================================
clear; clc; close all;

% STREAMING_CHUNK:Configuring parameters and discovering hierarchical datasets...
parent_dataset_path = 'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692';

TARGET_FS = 5000;          % Safely covers up to 2500 Hz
SEGMENT_SEC = 30;          % 30-second processing blocks
MAX_TRACKED_TARGETS = 10;  % Track up to 10 main targets simultaneously

search_bands = [
50,  300;
300,  600;
600,  950;
950, 1400;
1400, 2000
];

% Recursively find all directories containing .wav files
dataset_list = discover_datasets(parent_dataset_path);

if isempty(dataset_list)
error('No sub-directories containing .wav files found under %s.', parent_dataset_path);
end

fprintf('Found %d distinct dataset directory(ies) to process.\n', length(dataset_list));

% STREAMING_CHUNK:Executing main recursive dataset loop...
for d_idx = 1:length(dataset_list)
curr_dataset = dataset_list{d_idx};

% Construct a clean, distinct hierarchical name using parent folders
[parentDir, datasetName, ~] = fileparts(curr_dataset);
[~, parentName, ~] = fileparts(parentDir);
hierarchicalName = sprintf('%s / %s', parentName, datasetName);
if isempty(parentName)
    hierarchicalName = datasetName;
end

fprintf('\n====================================================\n');
fprintf('PROCESSING DATASET (%d/%d): %s\n', d_idx, length(dataset_list), hierarchicalName);
fprintf('Path: %s\n', curr_dataset);
fprintf('====================================================\n');

files = dir(fullfile(curr_dataset, '*.wav'));
if isempty(files)
    fprintf('No .wav files found in %s. Skipping.\n', hierarchicalName);
    continue;
end

fileNames = {files.name};
[~, sortIdx] = sort(fileNames);
files = files(sortIdx);

concatenated_signal = [];
global_fs = TARGET_FS;

% STREAMING_CHUNK:Loading and downsampling audio files...
fprintf('Loading & Downsampling %d file(s) for %s...\n', length(files), hierarchicalName);
for j = 1:length(files)
    file_path = fullfile(curr_dataset, files(j).name);
    [sig, orig_fs] = audioread(file_path);
    sig = select_best_channel(sig);
    
    if orig_fs > TARGET_FS
        [p, q] = rat(TARGET_FS / orig_fs);
        sig = resample(sig, p, q);
    elseif j == 1
        global_fs = orig_fs;
    end
    concatenated_signal = [concatenated_signal; sig];
end

total_len_sec = length(concatenated_signal) / global_fs;
fprintf('Total session length: %.2f seconds\n\n', total_len_sec);

% STREAMING_CHUNK:Executing 30-second segmented processing blocks...
step_samples = SEGMENT_SEC * global_fs;
segment_samples = SEGMENT_SEC * global_fs;
num_blocks = floor(length(concatenated_signal) / segment_samples);

if num_blocks < 1
    fprintf('Dataset recording is shorter than %d seconds. Skipping.\n', SEGMENT_SEC);
    continue;
end

target_bandwidths = cell(MAX_TRACKED_TARGETS, 1);
target_fms = cell(MAX_TRACKED_TARGETS, 1);
target_anchors = nan(MAX_TRACKED_TARGETS, 1);

fprintf('Processing %d blocks of %d seconds each...\n', num_blocks, SEGMENT_SEC);

for b = 1:num_blocks
    start_idx = 1 + (b-1) * step_samples;
    end_idx = start_idx + segment_samples - 1;
    
    segment_sig = concatenated_signal(start_idx:end_idx);
    [P, F, T] = compute_spectrogram(segment_sig, global_fs);
    
    block_target_freqs = [];
    for sb = 1:size(search_bands, 1)
        [band_freqs, ~] = find_fundamental_targets_morphological(P, F, T, search_bands(sb, 1), search_bands(sb, 2));
        if ~isempty(band_freqs)
            block_target_freqs = [block_target_freqs, band_freqs];
        end
    end
    
    if ~isempty(block_target_freqs)
        block_target_freqs = unique(block_target_freqs);
        valid_block_targets = track_and_extract_features(P, F, T, block_target_freqs);
        
        if ~isempty(valid_block_targets)
            % Filter targets strictly below 1000 Hz
            valid_block_targets(valid_block_targets(:, 1) > 1000, :) = [];
            
            if ~isempty(valid_block_targets)
                [~, sort_idx] = sort(valid_block_targets(:, 5), 'descend');
                valid_block_targets = valid_block_targets(sort_idx, :);
                num_to_save = min(MAX_TRACKED_TARGETS, size(valid_block_targets, 1));
                
                for t = 1:num_to_save
                    curr_f = valid_block_targets(t, 1);
                    curr_bw = valid_block_targets(t, 2);
                    curr_fm = valid_block_targets(t, 4);
                    
                    target_id = 0;
                    for id = 1:MAX_TRACKED_TARGETS
                        if isnan(target_anchors(id))
                            target_anchors(id) = curr_f;
                            target_id = id;
                            break;
                        elseif abs(curr_f - target_anchors(id)) <= 15.0
                            target_id = id;
                            target_anchors(id) = 0.9 * target_anchors(id) + 0.1 * curr_f;
                            break;
                        end
                    end
                    
                    if target_id > 0
                        target_bandwidths{target_id} = [target_bandwidths{target_id}; curr_bw];
                        target_fms{target_id} = [target_fms{target_id}; curr_fm];
                    end
                end
            end
        end
    end
end

% STREAMING_CHUNK:Printing final text report...
fprintf('\nFINAL REPORT FOR HIERARCHICAL DATASET: %s [<1000 Hz]:\n', hierarchicalName);
for id = 1:MAX_TRACKED_TARGETS
    if ~isnan(target_anchors(id)) && ~isempty(target_bandwidths{id})
        fprintf('  Target %d (~%.2f Hz): Count = %d blocks | BW = %.2f Hz | fm = %.2f Hz\n', ...
            id, target_anchors(id), length(target_bandwidths{id}), mean(target_bandwidths{id}), mean(target_fms{id}));
    end
end

% STREAMING_CHUNK:Rendering single unified figure pane containing spectrogram and KDE curves...
fig_title = sprintf('Acoustic Analysis Dashboard - [%s]', hierarchicalName);
figure('Name', fig_title, 'NumberTitle', 'off', 'Position', [50, 50, 1600, 900]);

% Use hsv colormap to generate guaranteed high-contrast, distinct colors per target
colors = hsv(MAX_TRACKED_TARGETS);

% Panel 1: Global Annotated Spectrogram (Top Half)
subplot(2, 2, [1, 2]);
window_size_global = round(global_fs * 1.5);
noverlap_global = round(window_size_global * 0.5);
nfft_global = 8192;

[S_glob, F_glob, T_glob] = spectrogram(concatenated_signal, window_size_global, noverlap_global, nfft_global, global_fs);
P_glob_dB = 10 * log10(abs(S_glob).^2);

max_plot_width = 2500;
if size(P_glob_dB, 2) > max_plot_width
    step_ds = ceil(size(P_glob_dB, 2) / max_plot_width);
    T_glob_plot = T_glob(1:step_ds:end);
    P_glob_dB_plot = P_glob_dB(:, 1:step_ds:end);
else
    T_glob_plot = T_glob;
    P_glob_dB_plot = P_glob_dB;
end

plot_idx = find(F_glob >= 50 & F_glob <= 2000);
imagesc(T_glob_plot, F_glob(plot_idx), P_glob_dB_plot(plot_idx, :));
axis xy; axis tight; colormap(jet);
ylabel('Frequency (Hz)', 'FontWeight', 'bold');
xlabel('Time (s)', 'FontWeight', 'bold');
title(sprintf('Global Spectrogram (50-2000 Hz) with Tracked Targets\n[%s]', hierarchicalName), 'Interpreter', 'none');
colorbar;

hold on;
for id = 1:MAX_TRACKED_TARGETS
    if ~isnan(target_anchors(id)) && ~isempty(target_bandwidths{id})
        target_freq = target_anchors(id);
        yline(target_freq, 'Color', colors(id, :), 'LineStyle', '--', 'LineWidth', 2.0);
        text(max(T_glob_plot) - (max(T_glob_plot)*0.02), target_freq + 25, sprintf('T%d', id), ...
            'Color', colors(id, :), 'FontWeight', 'bold', 'FontSize', 10);
    end
end
hold off;

% Panel 2: Carson Bandwidth Smooth KDE Curve (Bottom Left)
subplot(2, 2, 3);
hold on;
for id = 1:MAX_TRACKED_TARGETS
    if length(target_bandwidths{id}) >= 2
        [pdf_vals, x_grid] = ksdensity(target_bandwidths{id});
        plot(x_grid, pdf_vals, '-', 'Color', colors(id, :), 'LineWidth', 2.5, ...
            'DisplayName', sprintf('Target %d (~%.1f Hz)', id, target_anchors(id)));
    elseif length(target_bandwidths{id}) == 1
        plot(target_bandwidths{id}, 1, 'o', 'Color', colors(id, :), 'MarkerSize', 6, ...
            'DisplayName', sprintf('Target %d (~%.1f Hz)', id, target_anchors(id)));
    end
end
grid on;
xlabel('Carson Bandwidth (Hz)', 'FontWeight', 'bold');
ylabel('Probability Density (KDE)', 'FontWeight', 'bold');
title('Carson Bandwidth Distribution', 'Interpreter', 'none');
legend('Location', 'best');
hold off;

% Panel 3: Modulation Frequency Smooth KDE Curve (Bottom Right)
subplot(2, 2, 4);
hold on;
for id = 1:MAX_TRACKED_TARGETS
    if length(target_fms{id}) >= 2
        [pdf_vals, x_grid] = ksdensity(target_fms{id});
        plot(x_grid, pdf_vals, '-', 'Color', colors(id, :), 'LineWidth', 2.5, ...
            'DisplayName', sprintf('Target %d (~%.1f Hz)', id, target_anchors(id)));
    elseif length(target_fms{id}) == 1
        plot(target_fms{id}, 1, 'o', 'Color', colors(id, :), 'MarkerSize', 6, ...
            'DisplayName', sprintf('Target %d (~%.1f Hz)', id, target_anchors(id)));
    end
end
grid on;
xlabel('Modulation Frequency $f_m$ (Hz)', 'Interpreter', 'latex', 'FontWeight', 'bold');
ylabel('Probability Density (KDE)', 'FontWeight', 'bold');
title('Modulation Frequency ($f_m$) Distribution', 'Interpreter', 'none');
legend('Location', 'best');
hold off;


end

fprintf('\nAll hierarchical dataset sessions processed and plotted on single panes successfully.\n');

% =========================================================================
%                         LOCAL FUNCTIONS
% =========================================================================

function dataset_paths = discover_datasets(root_path)
dataset_paths = {};

% Check if root path itself contains .wav files
root_wavs = dir(fullfile(root_path, '*.wav'));
if ~isempty(root_wavs)
    dataset_paths{end+1} = root_path;
end

% Recursively check sub-directories
items = dir(root_path);
subfolders = items([items.isdir] & ~ismember({items.name}, {'.', '..'}));

for i = 1:length(subfolders)
    sub_path = fullfile(root_path, subfolders(i).name);
    sub_datasets = discover_datasets(sub_path);
    dataset_paths = [dataset_paths, sub_datasets];
end


end

function sig_mono = select_best_channel(sig_matrix)
if size(sig_matrix, 2) > 1
channel_power = rms(sig_matrix, 1);
[~, best_idx] = max(channel_power);
sig_mono = sig_matrix(:, best_idx);
else
sig_mono = sig_matrix;
end
end

function [P, F, T] = compute_spectrogram(signal, fs)
window_size = round(fs * 0.25);
noverlap = round(window_size * 0.5);
nfft = 16384;
[S, F, T] = spectrogram(signal, window_size, noverlap, nfft, fs);
P = abs(S).^2;
end

function [fundamentals, num_targets] = find_fundamental_targets_morphological(P, F, T, f_min, f_max)
valid_idx = find(F >= f_min & F <= f_max);
if isempty(valid_idx)
fundamentals = [];
num_targets = 0;
return;
end
F_valid = F(valid_idx);
P_valid_dB = 10 * log10(P(valid_idx, :));

thresh_dB = prctile(P_valid_dB(:), 75); 
bw_img = P_valid_dB > thresh_dB; 

time_bins_per_sec = 1 / (T(2) - T(1));
horizontal_length = round(time_bins_per_sec * 4.0); 

se = strel('rectangle', [1, horizontal_length]);
cleaned_img = imopen(bw_img, se); 

horizontal_energy = sum(cleaned_img, 2);
min_dist_bins = round(10 / (F(2) - F(1))); 

[peaks_energy, peak_locs] = findpeaks(horizontal_energy, ...
    'MinPeakDistance', min_dist_bins, ...
    'MinPeakHeight', horizontal_length * 0.1); 
    
raw_freqs = F_valid(peak_locs);
fundamentals = [];

[~, sort_idx] = sort(peaks_energy, 'descend');
raw_freqs = raw_freqs(sort_idx);

max_harmonic_order = 15;
tolerance = 4.0; 

for i = 1:length(raw_freqs)
    curr_f = raw_freqs(i);
    is_harmonic = false;
    
    for j = 1:length(fundamentals)
        fund = fundamentals(j);
        for m = 1:max_harmonic_order
            base_f = fund / m;
            if base_f < 15, break; end 
            n_ratio = curr_f / base_f;
            if abs(n_ratio - round(n_ratio)) * base_f < tolerance
                is_harmonic = true;
                break;
            end
        end
        if is_harmonic, break; end
    end
    
    if ~is_harmonic
        fundamentals = [fundamentals, curr_f];
    end
end
num_targets = length(fundamentals);


end

function valid_targets = track_and_extract_features(P, F, T, target_freqs)
track_margin = 25;
dt = T(2) - T(1);
track_fs = 1 / dt;
valid_targets = [];

for i = 1:length(target_freqs)
    target_f = target_freqs(i);
    track_idx = find(F >= (target_f - track_margin) & F <= (target_f + track_margin));
    if isempty(track_idx), continue; end
    
    [track_power, local_max_idx] = max(P(track_idx, :), [], 1); 
    global_max_idx = track_idx(local_max_idx);
    raw_track = F(global_max_idx);
    
    track_power_dB = 10 * log10(track_power);
    p95_dB = prctile(track_power_dB, 95); 
    
    smooth_track = medfilt1(raw_track, min(10, length(raw_track)));
    center_f = median(smooth_track);
    delta_f = prctile(abs(smooth_track - center_f), 95);
    
    mod_signal = smooth_track - center_f;
    N = length(mod_signal);
    mod_fft = abs(fft(mod_signal));
    half_idx = floor(N/2);
    mod_fft = mod_fft(1:half_idx);
    mod_freqs = (0:half_idx-1) * (track_fs / N);
    
    if length(mod_fft) > 1
        [~, mod_peak_idx] = max(mod_fft(2:end));
        f_m = mod_freqs(mod_peak_idx + 1);
    else
        f_m = 0;
    end
    
    carson_bw = 2 * (delta_f + f_m);
    valid_targets = [valid_targets; center_f, carson_bw, delta_f, f_m, p95_dB];
end


end