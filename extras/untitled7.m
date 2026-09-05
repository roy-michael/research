% =========================================================================
% Underwater Acoustic FM Tracking & Carson Bandwidth Pipeline
% =========================================================================
clear; clc; close all;

% --- 1. Configuration ---
dataset_path = 'D:\RoyStudies\Recordings\Ashdod\scooter_exp';
track_margin = 30; % +/- Hz dynamic corridor for ridge tracking
harmonic_tolerance = 5.0; % +/- Hz variance allowed when flagging harmonics

% Determine dataset name and frequency bounds safely
clean_path = dataset_path;
if endsWith(clean_path, filesep), clean_path = clean_path(1:end-1); end
[~, datasetName, ~] = fileparts(clean_path);

if contains(lower(datasetName), 'boat')
f_min = 120;
f_max = 220;
elseif contains(lower(datasetName), 'scooter')
f_min = 400;
f_max = 1000;
else
f_min = 100;
f_max = 1500;
end

% Get all wav files
files = dir(fullfile(dataset_path, '*.wav'));
if isempty(files)
error('No .wav files found in %s', dataset_path);
end

% --- 2. Main Processing Loop ---
for j = 1:length(files)
file_name = files(j).name;
file_path = fullfile(dataset_path, file_name);

fprintf('\n=========================================\n');
fprintf('Processing: %s (Dataset: %s)\n', file_name, datasetName);

% Step A: Load audio and select best SNR channel
[raw_signal, fs] = audioread(file_path);
[signal, best_channel] = select_best_channel(raw_signal);
fprintf('Selected Channel: %d (Highest RMS)\n', best_channel);

% Step B: Generate High-Resolution Spectrogram
[P, F, T] = compute_highres_spectrogram(signal, fs);

% Step C: Discover Fundamental Targets (Harmonic Filtering)
target_freqs = find_fundamental_targets(F, P, f_min, f_max, harmonic_tolerance);
num_targets = length(target_freqs);

fprintf('Found %d Fundamental Target(s).\n', num_targets);

% Step D: Parallel Ridge Tracking & Carson Bandwidth
for i = 1:num_targets
    anchor_freq = target_freqs(i);
    
    [center_f, delta_f, f_m, carson_bw] = track_fm_parameters(P, F, T, anchor_freq, track_margin);
    
    fprintf('  --- Target %d ---\n', i);
    fprintf('  Base Anchor Freq: %.2f Hz\n', anchor_freq);
    fprintf('  Tracked Center Freq: %.2f Hz\n', center_f);
    fprintf('  Carson Bandwidth: %.2f Hz (Delta f: %.2f, fm: %.2f)\n', carson_bw, delta_f, f_m);
end


end
fprintf('\nPipeline Complete.\n');

% =========================================================================
% LOCAL FUNCTIONS
% =========================================================================

function [sig_mono, best_idx] = select_best_channel(sig_matrix)
% Evaluates a multi-channel matrix and returns the channel with the highest power
if size(sig_matrix, 2) > 1
channel_power = rms(sig_matrix, 1);
[~, best_idx] = max(channel_power);
sig_mono = sig_matrix(:, best_idx);
else
sig_mono = sig_matrix;
best_idx = 1;
end
end

function [P, F, T] = compute_highres_spectrogram(signal, fs)
% Generates a power spectrogram with extreme zero-padding for sub-bin tracking
window_size = round(fs * 0.1);
noverlap = round(window_size * 0.9);
nfft = 65536; % High zero-padding for sub-Hz resolution

[S, F, T] = spectrogram(signal, window_size, noverlap, nfft, fs);
P = abs(S).^2; % Power spectrum


end

function fundamentals = find_fundamental_targets(F, P, f_min, f_max, tolerance)
% Finds peaks in the time-averaged spectrum and filters out integer harmonics
mean_P_dB = 10 * log10(mean(P, 2));

% Restrict search area
valid_idx = find(F >= f_min & F <= f_max);
min_dist_bins = round(20 / (F(2) - F(1))); % Require targets to be >= 20Hz apart

% Find all distinct peaks
[~, peak_locs] = findpeaks(mean_P_dB(valid_idx), ...
    'MinPeakProminence', 5, ... 
    'MinPeakDistance', min_dist_bins);

raw_freqs = sort(F(valid_idx(peak_locs)));
fundamentals = [];

% Integer-Ratio Harmonic Filter
for i = 1:length(raw_freqs)
    curr_f = raw_freqs(i);
    is_harmonic = false;
    
    for j = 1:length(fundamentals)
        fund = fundamentals(j);
        ratio = curr_f / fund;
        
        % Check if it sits on an exact integer multiple (within tolerance)
        if abs(ratio - round(ratio)) * fund < tolerance
            is_harmonic = true;
            break;
        end
    end
    
    if ~is_harmonic
        fundamentals = [fundamentals, curr_f];
    end
end


end

function [center_f, delta_f, f_m, carson_bw] = track_fm_parameters(P, F, T, target_f, margin)
% Runs ridge tracking within a tight corridor and computes FM properties

% 1. Create narrow tracking corridor
track_idx = find(F >= (target_f - margin) & F <= (target_f + margin));

% 2. Ridge tracking (find max power bin at each time step)
[~, local_max_idx] = max(P(track_idx, :), [], 1); 
global_max_idx = track_idx(local_max_idx);
raw_track = F(global_max_idx);

% 3. Smooth track to ignore transients and calculate deviation
smooth_track = medfilt1(raw_track, 50);
center_f = median(smooth_track);
delta_f = prctile(abs(smooth_track - center_f), 95);

% 4. Extract modulation rate (f_m) via FFT of the frequency track
dt = T(2) - T(1);
track_fs = 1 / dt;

mod_signal = smooth_track - center_f;
N = length(mod_signal);
mod_fft = abs(fft(mod_signal));

half_idx = floor(N/2);
mod_fft = mod_fft(1:half_idx);
mod_freqs = (0:half_idx-1) * (track_fs / N);

% Skip DC offset (index 1) and find strongest modulation frequency
[~, mod_peak_idx] = max(mod_fft(2:end));
f_m = mod_freqs(mod_peak_idx + 1);

% 5. Compute Bandwidth
carson_bw = 2 * (delta_f + f_m);


end