% =========================================================================
% Multi-Target Acoustic Tracker (Concatenated Analysis)
%
% 1. Concatenates all chronological .wav files.
% 2. Generates a combined spectrogram (Memory Optimized).
% 3. Discovers up to 4 dynamic fundamental targets (50Hz - 2000Hz).
% 4. Extracts tracking bandwidth, relative intensity, and temporal presence.
% =========================================================================
clear; clc; close all;

% --- CONFIGURATION ---
dataset_path = 'D:\RoyStudies\Recordings\Ashdod\boat_exp';

% Define global search bounds
f_min_global = 50;

f_max_global = 2000;

% Get dataset name safely
clean_dir = dataset_path;
if endsWith(clean_dir, filesep), clean_dir = clean_dir(1:end-1); end
[~, datasetName, ~] = fileparts(clean_dir);

% --- MAIN EXECUTION LOOP ---
files = dir(fullfile(dataset_path, '*.wav'));
if isempty(files), error('No .wav files found.'); end

% Sort alphanumerically to guarantee chronological order
fileNames = {files.name};
[~, sortIdx] = sort(fileNames);
files = files(sortIdx);

% 1. Load Data, Concatenate, & Select Best Channel
concatenated_signal = [];
global_fs = 0;

fprintf('\n========================================\n');
fprintf('Concatenating %d files from: %s\n', length(files), datasetName);

for j = 1:length(files)
file_name = files(j).name;
file_path = fullfile(dataset_path, file_name);

[sig, fs] = audioread(file_path);
if j == 1
    global_fs = fs;
elseif fs ~= global_fs
    warning('Sample rate mismatch in file %s.', file_name);
end

concatenated_signal = [concatenated_signal; sig];


end

fprintf('Total recording length: %.2f seconds\n', size(concatenated_signal, 1) / global_fs);

% Select best channel from the combined recording
[signal, best_idx] = select_best_channel(concatenated_signal);
fprintf('Selected Channel: %d (Highest RMS)\n', best_idx);

% 2. High-Resolution STFT (Memory Optimized)
fprintf('Computing high-resolution spectrogram...\n');
[P, F, T] = compute_spectrogram(signal, global_fs);

% --- VISUALIZATION: Plot the combined spectrogram ---
figure('Name', 'Concatenated Spectrogram', 'NumberTitle', 'off');

% Crop the data to the bounds before plotting to prevent rendering crash
plot_idx = find(F >= f_min_global & F <= f_max_global);
F_plot = F(plot_idx);
P_plot_dB = 10 * log10(P(plot_idx, :));

% Use imagesc which is vastly more efficient than surf for large matrices
imagesc(T, F_plot, P_plot_dB);
axis xy; axis tight; colormap(jet);
ylabel('Frequency (Hz)');
xlabel('Time (s)');
title(sprintf('Spectrogram of Concatenated Recording (%s)', datasetName));
colorbar;
drawnow;

% 3. Identify Distinct Fundamental Targets (Up to 4)
[target_freqs, target_powers, num_targets] = find_fundamental_targets(P, F, f_min_global, f_max_global);

% Enforce the maximum of 4 targets
if num_targets > 4
fprintf('Found %d targets, limiting to the 4 strongest.\n', num_targets);
[~, sort_idx] = sort(target_powers, 'descend');
target_freqs = target_freqs(sort_idx(1:4));
target_powers = target_powers(sort_idx(1:4));

[target_freqs, resort_idx] = sort(target_freqs);
target_powers = target_powers(resort_idx);
num_targets = 4;


else
fprintf('Found %d distinct target(s).\n', num_targets);
end

% 4. Track and Extract Features For Each Target
if num_targets > 0
max_power = max(target_powers);
rel_intensities = target_powers - max_power;

track_and_extract_features(P, F, T, target_freqs, rel_intensities);


else
fprintf('No valid targets found in the specified frequency band.\n');
end

fprintf('\nProcessing Complete.\n');

% =========================================================================
%                         LOCAL FUNCTIONS
% =========================================================================

function [signal_out, best_idx] = select_best_channel(sig_matrix)
best_idx = 1;
if size(sig_matrix, 2) > 1
channel_power = rms(sig_matrix, 1);
[~, best_idx] = max(channel_power);
sig_matrix = sig_matrix(:, best_idx);
end
signal_out = sig_matrix;
end

function [P, F, T] = compute_spectrogram(signal, fs)
% FIX: Reduced overlap to prevent out-of-memory errors on long files
% while maintaining the massive 65536 nfft for sub-Hz frequency tracking.
window_size = round(fs * 0.25); % 0.25 seconds per window
noverlap = round(window_size * 0.5); % 50% overlap
nfft = 65536; % Maintains ~0.73 Hz resolution

[S, F, T] = spectrogram(signal, window_size, noverlap, nfft, fs);
P = abs(S).^2;


end

function [fundamentals, fund_powers, num_targets] = find_fundamental_targets(P, F, f_min, f_max)
composite_P = prctile(P, 95, 2);
composite_P_dB = 10 * log10(composite_P);

valid_idx = find(F >= f_min & F <= f_max);
min_dist_bins = round(20 / (F(2) - F(1))); 

[peaks_dB, peak_locs] = findpeaks(composite_P_dB(valid_idx), ...
    'MinPeakProminence', 2.5, ... 
    'MinPeakDistance', min_dist_bins);
    
raw_freqs = F(valid_idx(peak_locs));

fundamentals = [];
fund_powers = [];
tolerance = 5.0; 

[raw_freqs, sort_idx] = sort(raw_freqs);
peaks_dB = peaks_dB(sort_idx);

for i = 1:length(raw_freqs)
    curr_f = raw_freqs(i);
    curr_db = peaks_dB(i);
    is_harmonic = false;
    
    for j = 1:length(fundamentals)
        fund = fundamentals(j);
        fund_db = composite_P_dB(abs(F - fund) < 1e-3); 
        ratio = curr_f / fund;
        
        if abs(ratio - round(ratio)) * fund < tolerance
            if curr_db < fund_db(1)
                is_harmonic = true;
                break;
            end
        end
    end
    
    if ~is_harmonic
        fundamentals = [fundamentals, curr_f];
        fund_powers = [fund_powers, curr_db];
    end
end

num_targets = length(fundamentals);


end

function track_and_extract_features(P, F, T, target_freqs, rel_intensities)
track_margin = 30;
dt = T(2) - T(1);
track_fs = 1 / dt;

for i = 1:length(target_freqs)
    target_f = target_freqs(i);
    
    track_idx = find(F >= (target_f - track_margin) & F <= (target_f + track_margin));
    
    [track_power, local_max_idx] = max(P(track_idx, :), [], 1); 
    global_max_idx = track_idx(local_max_idx);
    raw_track = F(global_max_idx);
    
    track_power_dB = 10 * log10(track_power);
    p95_dB = prctile(track_power_dB, 95); 
    p10_dB = prctile(track_power_dB, 10); 
    
    if (p95_dB - p10_dB) < 3.0
        pct_active = 100.0;
    else
        active_thresh_dB = p10_dB + ((p95_dB - p10_dB) * 0.4); 
        pct_active = (sum(track_power_dB > active_thresh_dB) / length(T)) * 100;
    end
    
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
    
    fprintf('  --- Target %d ---\n', i);
    fprintf('  Base Anchor Freq   : %.2f Hz\n', target_f);
    fprintf('  Tracked Center Freq: %.2f Hz\n', center_f);
    fprintf('  Relative Intensity : %.2f dB (0 is loudest)\n', rel_intensities(i));
    fprintf('  Temporal Presence  : %.1f%% of file length\n', pct_active);
    fprintf('  Carson Bandwidth   : %.2f Hz (Delta f: %.2f, fm: %.2f)\n', carson_bw, delta_f, f_m);
end


end