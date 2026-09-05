% =========================================================================
% Segmented Multi-Target Acoustic Tracker (Multi-Band Regional Search)
% =========================================================================
clear; clc; close all;

% --- 1. CONFIGURATION ---
dataset_path = 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\2307_free';


TARGET_FS = 5000; % Safely covers up to 2500 Hz while saving ~90% RAM
f_min_global = 100;
f_max_global = 2000;

SEGMENT_SEC = 120; % 2-minute processing blocks
OVERLAP_SEC = 30;  % 30-second overlap
MAX_TARGETS_PER_BLOCK = 12; % Increased capacity to capture multi-component lines

% Define sub-bands to guarantee regional targets (e.g., capturing 860Hz explicitly)
search_bands = [
100,  300;   % Low frequency band
300,  600;   % Mid-low band
600,  950;   % Target band explicitly covering ~860 Hz
950, 1400;   % Mid-high band
1400, 2000    % High frequency band
];

% --- 2. LOAD AND CONCATENATE ---
clean_dir = dataset_path;
if endsWith(clean_dir, filesep), clean_dir = clean_dir(1:end-1); end
[~, datasetName, ~] = fileparts(clean_dir);

files = dir(fullfile(dataset_path, '*.wav'));
if isempty(files), error('No .wav files found.'); end

fileNames = {files.name};
[~, sortIdx] = sort(fileNames);
files = files(sortIdx);

concatenated_signal = [];
global_fs = TARGET_FS;

fprintf('\n========================================\n');
fprintf('Concatenating & Downsampling %d files from: %s\n', length(files), datasetName);

for j = 1:length(files)
file_path = fullfile(dataset_path, files(j).name);
[sig, orig_fs] = audioread(file_path);

% Select Best Channel FIRST
sig = select_best_channel(sig);

% Downsample
if orig_fs > TARGET_FS
    [p, q] = rat(TARGET_FS / orig_fs);
    sig = resample(sig, p, q);
elseif j == 1
    global_fs = orig_fs;
end

concatenated_signal = [concatenated_signal; sig];


end

total_len_sec = length(concatenated_signal) / global_fs;
fprintf('Total recording length: %.2f seconds\n\n', total_len_sec);

% --- 3. SEGMENTED PROCESSING LOOP WITH MULTI-BAND SEARCH ---
step_samples = (SEGMENT_SEC - OVERLAP_SEC) * global_fs;
segment_samples = SEGMENT_SEC * global_fs;
num_blocks = floor((length(concatenated_signal) - segment_samples) / step_samples) + 1;

global_target_db = [];

for b = 1:num_blocks
start_idx = 1 + (b-1) * step_samples;
end_idx = start_idx + segment_samples - 1;
start_time_sec = start_idx / global_fs;

segment_sig = concatenated_signal(start_idx:end_idx);
[P, F, T] = compute_spectrogram(segment_sig, global_fs);

block_target_freqs = [];

% Perform regional search across defined sub-bands
for sb = 1:size(search_bands, 1)
    sub_min = search_bands(sb, 1);
    sub_max = search_bands(sb, 2);
    
    [band_freqs, ~] = find_fundamental_targets_morphological(P, F, T, sub_min, sub_max);
    if ~isempty(band_freqs)
        block_target_freqs = [block_target_freqs, band_freqs];
    end
end

if ~isempty(block_target_freqs)
    block_target_freqs = unique(block_target_freqs);
    if length(block_target_freqs) > MAX_TARGETS_PER_BLOCK
        block_target_freqs = block_target_freqs(1:MAX_TARGETS_PER_BLOCK);
    end
    
    valid_block_targets = track_and_extract_features(P, F, T, block_target_freqs);
    if ~isempty(valid_block_targets)
        global_target_db = [global_target_db; valid_block_targets];
    end
end


end

% --- 4. GLOBAL AGGREGATION & REPORTING ---
fprintf('\n========================================\n');
fprintf('AGGREGATING GLOBAL TARGETS...\n');

cluster_tolerance = 5.0;
final_targets = [];

while ~isempty(global_target_db)
base_f = global_target_db(1, 1);
idx = find(abs(global_target_db(:,1) - base_f) <= cluster_tolerance);
cluster = global_target_db(idx, :);

avg_f = mean(cluster(:, 1));
block_count = size(cluster, 1);
max_bw = max(cluster(:, 2));
max_df = max(cluster(:, 3));
avg_fm = mean(cluster(:, 4));
max_int = max(cluster(:, 5)); 

final_targets = [final_targets; avg_f, block_count, max_bw, max_df, avg_fm, max_int];
global_target_db(idx, :) = [];


end

if ~isempty(final_targets)
[~, sort_idx] = sort(final_targets(:, 2), 'descend');
final_targets = final_targets(sort_idx, :);

num_final = min(10, size(final_targets, 1));
final_targets = final_targets(1:num_final, :);
global_max_int = max(final_targets(:, 6));

fprintf('\nFINAL REPORT: TOP %d UNIQUE AGGREGATED TARGETS\n', num_final);
for i = 1:num_final
    f = final_targets(i, 1);
    pct_survived = (final_targets(i, 2) / num_blocks) * 100;
    bw = final_targets(i, 3);
    df = final_targets(i, 4);
    fm = final_targets(i, 5);
    int_db = final_targets(i, 6) - global_max_int;
    
    fprintf('Target %d: ~%.2f Hz\n', i, f);
    fprintf('  Active Time      : %5.1f%% of total recording\n', pct_survived);
    fprintf('  Peak Intensity   : %5.2f dB (relative to block maximums)\n', int_db);
    fprintf('  Max Carson BW    : %5.2f Hz (Max df: %.2f, Avg fm: %.2f)\n\n', bw, df, fm);
end


else
fprintf('No sustained targets found in the entire dataset.\n');
end

% --- 5. GLOBAL VISUALIZATION ---
fprintf('Rendering Global Annotated Spectrogram...\n');
figure('Name', 'Global Annotated Spectrogram', 'NumberTitle', 'off', 'Position', [100, 100, 1200, 600]);

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

plot_idx = find(F_glob >= f_min_global & F_glob <= f_max_global);
imagesc(T_glob_plot, F_glob(plot_idx), P_glob_dB_plot(plot_idx, :));
axis xy; axis tight; colormap(jet);
ylabel('Frequency (Hz)', 'FontWeight', 'bold');
xlabel('Time (s)', 'FontWeight', 'bold');
title(sprintf('Global Spectrogram: %s (Top %d Targets)', datasetName, size(final_targets,1)), 'Interpreter', 'none');
colorbar;

hold on;
if ~isempty(final_targets)
for i = 1:size(final_targets, 1)
target_freq = final_targets(i, 1);
yline(target_freq, 'W--', 'LineWidth', 1.5, 'Alpha', 0.8);
text(max(T_glob_plot) - (max(T_glob_plot)*0.02), target_freq + 25, sprintf('T%d', i), ...
'Color', 'white', 'FontWeight', 'bold', 'FontSize', 10);
end
end
hold off;

fprintf('Processing Complete.\n');

% =========================================================================
%                         LOCAL FUNCTIONS
% =========================================================================

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
nfft = 65536;
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

thresh_dB = prctile(P_valid_dB(:), 70); % Relaxed threshold to catch 860Hz lines
bw_img = P_valid_dB > thresh_dB; 

time_bins_per_sec = 1 / (T(2) - T(1));
horizontal_length = round(time_bins_per_sec * 6.0); % Shorter duration requirement

se = strel('rectangle', [1, horizontal_length]);
cleaned_img = imopen(bw_img, se); 

horizontal_energy = sum(cleaned_img, 2);
min_dist_bins = round(10 / (F(2) - F(1))); 

[peaks_energy, peak_locs] = findpeaks(horizontal_energy, ...
    'MinPeakDistance', min_dist_bins, ...
    'MinPeakHeight', horizontal_length * 0.2); 
    
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
    
    smooth_track = medfilt1(raw_track, 50);
    center_f = median(smooth_track);
    delta_f = prctile(abs(smooth_track - center_f), 95);
    
    mod_signal = smooth_track - center_f;
    N = length(mod_signal);
    mod_fft = abs(fft(mod_signal));
    half_idx = floor(N/2);
    mod_fft = mod_fft(1:half_idx);
    mod_freqs = (0:half_idx-1) * (track_fs / N);
    
    [~, mod_peak_idx] = max(mod_fft(2:end));
    f_m = mod_freqs(mod_peak_idx + 1);
    
    carson_bw = 2 * (delta_f + f_m);
    valid_targets = [valid_targets; center_f, carson_bw, delta_f, f_m, p95_dB];
end


end