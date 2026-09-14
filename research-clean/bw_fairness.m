clear; clc; close all;

% =========================================================================
% --- 1. Configuration & Parameters ---
% =========================================================================


% File Paths
recordingsBasePath = 'D:\RoyStudies\Recordings';

SCOOTER_FILES = {
    fullfile(recordingsBasePath, "Croatia", "Ocean Sonics", "2407_1_600m", ...
    "RBW6737_20250724_093000.wav")
    };

MOTORBOAT_FILES = {
    fullfile(recordingsBasePath, "hear_my_ship", "V1", "Motor Boats", ...
    "Motorboat_08.08.23_142223_20secCPA.wav"), ...
    fullfile(recordingsBasePath, "hear_my_ship", "V1", "Motor Boats", ...
    "Motorboat_06.09.23_113554_20secCPA.wav"), ...
    fullfile(recordingsBasePath, "hear_my_ship", "V1", "Motor Boats", ...
    "Motorboat_08.08.23_105220_20secCPA.wav"), ...
    fullfile(recordingsBasePath, "hear_my_ship", "V1", "Motor Boats", ...
    "Motorboat_08.08.23_110517_20secCPA.wav"), ...
    fullfile(recordingsBasePath, "hear_my_ship", "V1", "Motor Boats", ...
    "Motorboat_08.08.23_105220_20secCPA.wav")
    };

% Processing Parameters
SR_TARGET = 48000;              % Target sampling rate (Hz)
SLICE_DURATION_SEC = 0.5;       % Window duration for processing (seconds)
ROBUST_FRAME_DURATION_SEC = 0.25; % Overlapping frame length within each processing window
TARGET_DURATION_SEC = 20;       % Maximum audio length to process per file (seconds)
FAIRNESS_WINDOW = 5;            % Window size for successive Jain's fairness

% Frequency Analysis Bounds (Hz)
SCOOTER_FREQ_RANGE = [500, 1000];
MOTORBOAT_FREQ_RANGE = [50, 1000];

% Derived Parameters
slice_len = floor(SR_TARGET * SLICE_DURATION_SEC);
robust_frame_len = floor(SR_TARGET * ROBUST_FRAME_DURATION_SEC);
win_func = hann(robust_frame_len);
samples_needed = SR_TARGET * TARGET_DURATION_SEC;


% =========================================================================
% --- 2. Process Audio Files ---
% =========================================================================

disp('Processing Scooter...');
[scooter_bws, scooter_fairness] = process_audio_files(...
    SCOOTER_FILES, SR_TARGET, samples_needed, slice_len, win_func, ...
    SCOOTER_FREQ_RANGE(1), SCOOTER_FREQ_RANGE(2), FAIRNESS_WINDOW);

disp('Processing Motor Boats...');
[ship_bws, ship_fairness] = process_audio_files(...
    MOTORBOAT_FILES, SR_TARGET, samples_needed, slice_len, win_func, ...
    MOTORBOAT_FREQ_RANGE(1), MOTORBOAT_FREQ_RANGE(2), FAIRNESS_WINDOW);


% =========================================================================
% --- 3. Plotting Histograms (Lobe Width) ---
% =========================================================================

figure('Name', 'Bandwidth Distributions and Rolling Fairness (Lobe Width)', 'Position', [50, 50, 1100, 600]);

% Plot 1: Bandwidth Distribution
subplot(1, 2, 1);
plot_distribution(scooter_bws, ship_bws, 1.5, ...
    'Comparative Bandwidth Distribution (Lobe Width)', 'Bandwidth (Hz)');

% Plot 2: Successive Fairness Distribution
subplot(1, 2, 2);
plot_distribution(scooter_fairness, ship_fairness, 0.02, ...
    sprintf('Rolling Successive Fairness (Window = %d)', FAIRNESS_WINDOW), ...
    'Jain''s Fairness Index');


% =========================================================================
% =========================================================================
% --- 4. Plotting Examples (Lower-Envelope Lobe Width) ---
% =========================================================================

figure('Name', 'Bandwidth Calculation Examples (Lower-Envelope Lobe Width)', 'Position', [150, 150, 1100, 500]);

% Plot Scooter Example
subplot(1, 2, 1);
plot_example_bandwidth(SCOOTER_FILES{1}, SR_TARGET, samples_needed, slice_len, win_func, SCOOTER_FREQ_RANGE(1), SCOOTER_FREQ_RANGE(2), 'Scooter');

% Plot Motor Boat Example
subplot(1, 2, 2);
plot_example_bandwidth(MOTORBOAT_FILES{1}, SR_TARGET, samples_needed, slice_len, win_func, MOTORBOAT_FREQ_RANGE(1), MOTORBOAT_FREQ_RANGE(2), 'Motor Boat');

disp('Execution complete.');


% =========================================================================
% --- Helper Functions ---
% =========================================================================

% -------------------------------------------------------------------------
% Core Audio Processing
% -------------------------------------------------------------------------

function [all_bws, all_fairness] = process_audio_files(file_paths, sr_target, samples_needed, slice_len, win, min_freq, max_freq, fairness_win)
% High-level loop to process multiple audio files and aggregate bandwidth and fairness metrics.
all_bws = [];
all_fairness = [];

for k = 1:length(file_paths)
    try
        [data, sr] = audioread(file_paths{k});
        data_resampled = resample_full(data, sr, sr_target);
        data_resampled = data_resampled(1:min(length(data_resampled), samples_needed));

        bws = process_vessel_audio_tracked(data_resampled, sr_target, slice_len, win, min_freq, max_freq);
        fairness = compute_successive_jains(bws, fairness_win);

        % Keep the time series (including missing values) for fairness, but
        % do not pass missing bandwidth estimates to the distribution plot.
        all_bws = [all_bws; bws(isfinite(bws) & bws > 0)];
        all_fairness = [all_fairness; fairness];
    catch ME
        fprintf('  -> Warning: Could not process file %s. Error: %s\n', file_paths{k}, ME.message);
    end
end
end

function bws = process_vessel_audio_tracked(data, sr, slice_len, win, min_freq, max_freq)
% Analyzes an audio file in sequential time slices to track and extract the peak bandwidth of the dominant frequency.
num_slices = floor(length(data) / slice_len);
if num_slices < 1; bws = []; return; end

N = slice_len;
Faxis_fft = (0:N-1) * (sr/N);
pos_mask = Faxis_fft >= 0 & Faxis_fft <= sr/2;
f_pos = Faxis_fft(pos_mask);

all_ffts_db = zeros(sum(pos_mask), num_slices);

for i = 1:num_slices
    idx_start = (i-1)*slice_len + 1;
    idx_end = i*slice_len;
    chunk = data(idx_start:idx_end);
    all_ffts_db(:, i) = robust_slice_spectrum(chunk, slice_len, win);
end

global_spec_db = median(all_ffts_db, 2);
[global_dom_freq, ~] = find_dominant_freq_in_fft(global_spec_db, f_pos, min_freq, max_freq);

if isempty(global_dom_freq)
    bws = []; return;
end

target_freq = global_dom_freq(1);
bws = NaN(num_slices, 1);
track_tolerance = 25;

for i = 1:num_slices
    chunk_db = all_ffts_db(:, i);
    local_min_freq = max(min_freq, target_freq - track_tolerance);
    local_max_freq = min(max_freq, target_freq + track_tolerance);
    [local_freq, ~] = find_dominant_freq_in_fft(chunk_db, f_pos, local_min_freq, local_max_freq);

    if ~isempty(local_freq)
        bws(i) = get_peak_bandwidth(local_freq(1), chunk_db, f_pos, min_freq, max_freq);
    end
end
end

function spectrum_db = robust_slice_spectrum(chunk, nfft, frame_win)
% Builds a robust spectrum from overlapping detrended short frames.
% The median power spectrum suppresses one-off impulsive events in a slice.
frame_len = numel(frame_win);
if numel(chunk) < frame_len
    error('The processing slice must be at least as long as the robust frame.');
end

hop_len = floor(frame_len / 2);
frame_starts = 1:hop_len:(numel(chunk) - frame_len + 1);
last_start = numel(chunk) - frame_len + 1;
if frame_starts(end) ~= last_start
    frame_starts = [frame_starts, last_start];
end

positive_bins = nfft / 2 + 1;
frame_powers = zeros(positive_bins, numel(frame_starts));
for j = 1:numel(frame_starts)
    start_idx = frame_starts(j);
    frame = chunk(start_idx:start_idx + frame_len - 1);
    frame = detrend(frame, 'linear') .* frame_win;
    frame_fft = fft(frame, nfft);
    frame_powers(:, j) = abs(frame_fft(1:positive_bins)).^2;
end

spectrum_db = 10 * log10(median(frame_powers, 2) + 1e-24);
end

function data_out = resample_full(data, sr_orig, sr_target)
% Utility to convert audio to mono and resample it to the requested rate.
% Resampling only on downsampling leaves files recorded below sr_target on a
% different frequency grid, despite the rest of the analysis assuming sr_target.
if size(data, 2) > 1
    data = mean(data, 2);
end
if sr_orig ~= sr_target
    [P, Q] = rat(sr_target / sr_orig, 1e-12);
    data = resample(data, P, Q);
end
data_out = data;
end

% -------------------------------------------------------------------------
% Bandwidth & Frequency Extraction
% -------------------------------------------------------------------------

function [dominantFreqs, maxPowers] = find_dominant_freq_in_fft(fft_db, faxis, min_freq, max_freq)
% Identifies the most prominent frequency peaks in a spectrum using a moving median baseline detrending.
pos_mask = (faxis >= min_freq) & (faxis <= max_freq);
pos_faxis = faxis(pos_mask);
pos_fft_db = fft_db(pos_mask);
len = length(pos_fft_db);

if len < 3
    dominantFreqs = []; maxPowers = []; return;
end

med_span = min(51, max(3, floor(len/2)*2 - 1));
baseline = movmedian(pos_fft_db, med_span);
detrended_db = pos_fft_db - baseline;

peak_dist = min(20, max(1, floor(len/3)));
[pks, locs] = findpeaks(detrended_db, 'MinPeakDistance', peak_dist, 'MinPeakProminence', 3);

if isempty(locs)
    dominantFreqs = []; maxPowers = []; return;
end

peak_amps_db = pos_fft_db(locs);
[~, sort_idx] = sort(peak_amps_db, 'descend');

dominantFreqs = pos_faxis(locs(sort_idx));
maxPowers = pos_fft_db(locs(sort_idx));
end

function [bandwidth, f_segment, fft_segment, lower_envelope, threshold_curve, left_freq, right_freq] = get_peak_bandwidth(peak_freq, spec_db, f_pos, min_freq, max_freq)
% Computes the full width at 20% of the lower-envelope-relative peak level.
segment_mask = f_pos >= min_freq & f_pos <= max_freq;
f_segment = f_pos(segment_mask);
fft_segment = spec_db(segment_mask);

bandwidth = NaN;
left_freq = NaN;
right_freq = NaN;
if numel(f_segment) < 5
    lower_envelope = fft_segment;
    threshold_curve = fft_segment;
    return;
end

[~, peak_local_idx] = min(abs(f_segment - peak_freq));
df = f_segment(2) - f_segment(1);
% The envelope span must exceed the lobe itself; 200 Hz avoids treating a
% broad motorboat lobe as background.
baseline_span = min(numel(fft_segment), max(5, 2 * ceil(100 / df) + 1));
if mod(baseline_span, 2) == 0
    baseline_span = baseline_span - 1;
end

% Morphological opening forms a true lower envelope: movmin follows local
% troughs and movmax removes narrow downward notches without spline artifacts.
lower_envelope = movmax(movmin(fft_segment, baseline_span), baseline_span);
lower_envelope = smoothdata(lower_envelope, 'movmean', min(11, numel(lower_envelope)));
lobe_spectrum = smoothdata(fft_segment, 'gaussian', 3);

% The lower envelope itself is a floor and normally does not intersect the
% lobe. Twenty percent of the peak-to-envelope height captures the full lobe.
peak_level = lobe_spectrum(peak_local_idx);
threshold_curve = lower_envelope + 0.20 * (peak_level - lower_envelope);
difference = lobe_spectrum - threshold_curve;

for i = peak_local_idx-1:-1:1
    if difference(i) <= 0 && difference(i+1) > 0
        left_freq = interpolate_intersection(f_segment(i), difference(i), f_segment(i+1), difference(i+1));
        break;
    end
end
for i = peak_local_idx:numel(difference)-1
    if difference(i) > 0 && difference(i+1) <= 0
        right_freq = interpolate_intersection(f_segment(i), difference(i), f_segment(i+1), difference(i+1));
        break;
    end
end

if isfinite(left_freq) && isfinite(right_freq)
    bandwidth = right_freq - left_freq;
end
end

function crossing_freq = interpolate_intersection(f1, d1, f2, d2)
% Linear interpolation gives a crossing frequency finer than an FFT bin.
crossing_freq = f1 - d1 * (f2 - f1) / (d2 - d1);
end

% -------------------------------------------------------------------------
% Fairness Metrics
% -------------------------------------------------------------------------

function rolling_fairness = compute_successive_jains(x, window_size)
% Calculates the rolling Jain's Fairness Index over a sliding window of sequential bandwidth measurements.
if window_size < 1 || window_size ~= floor(window_size)
    error('window_size must be a positive integer.');
end

% Invalid estimates break a consecutive sequence; removing them would make
% measurements on opposite sides of a failed slice appear successive.
valid = isfinite(x) & x > 0;
if nnz(valid) < window_size
    rolling_fairness = [];
    return;
end

rolling_fairness = [];
for i = 1:(length(x) - window_size + 1)
    win_vals = x(i:i + window_size - 1);
    if all(isfinite(win_vals) & win_vals > 0)
        rolling_fairness(end+1, 1) = (sum(win_vals)^2) / ...
            (window_size * sum(win_vals.^2));
    end
end
end

% -------------------------------------------------------------------------
% Visualization & Plotting
% -------------------------------------------------------------------------

function plot_distribution(data_scooter, data_ship, bw, title_str, xlabel_str)
% Helper to plot comparative Kernel Density Estimation (KDE) distributions for datasets.
data_scooter = data_scooter(isfinite(data_scooter));
data_ship = data_ship(isfinite(data_ship));
if isempty(data_scooter) || isempty(data_ship)
    title(title_str);
    xlabel(xlabel_str);
    ylabel('Density Probability');
    text(0.5, 0.5, 'Insufficient valid data to estimate a distribution', ...
        'Units', 'normalized', 'HorizontalAlignment', 'center');
    grid on; box on;
    return;
end
[f_scooter, xi_scooter] = ksdensity(data_scooter, 'Bandwidth', bw);
[f_ship, xi_ship] = ksdensity(data_ship, 'Bandwidth', bw);

fill(xi_scooter, f_scooter, [0.2 0.6 0.8], 'FaceAlpha', 0.5, 'EdgeColor', [0.1 0.4 0.6], 'LineWidth', 2); hold on;
fill(xi_ship, f_ship, [0.8 0.3 0.3], 'FaceAlpha', 0.4, 'EdgeColor', [0.6 0.2 0.2], 'LineWidth', 2);

title(title_str);
xlabel(xlabel_str);
ylabel('Density Probability');
legend('Scooter', 'Motor Boat', 'Location', 'best');
grid on; box on;
end

function plot_example_bandwidth(file_path, sr_target, samples_needed, slice_len, win, min_freq, max_freq, title_prefix)
% Plots the lower envelope and its two bandwidth-defining valleys.

[data, sr] = audioread(file_path);
data = resample_full(data, sr, sr_target);
data = data(1:min(length(data), samples_needed));

num_slices = floor(length(data) / slice_len);
if num_slices < 1; return; end

N = slice_len;
Faxis_fft = (0:N-1) * (sr_target/N);
pos_mask = Faxis_fft >= 0 & Faxis_fft <= sr_target/2;
f_pos = Faxis_fft(pos_mask);

all_ffts_db = zeros(sum(pos_mask), num_slices);
for i = 1:num_slices
    idx_start = (i-1)*slice_len + 1;
    idx_end = i*slice_len;
    chunk = data(idx_start:idx_end);
    all_ffts_db(:, i) = robust_slice_spectrum(chunk, slice_len, win);
end

global_spec_db = median(all_ffts_db, 2);
[global_dom_freq, ~] = find_dominant_freq_in_fft(global_spec_db, f_pos, min_freq, max_freq);

if isempty(global_dom_freq)
    disp(['No dominant frequency found for ' title_prefix]);
    return;
end

target_freq = global_dom_freq(1);

% Find slice with highest energy near target_freq
[~, target_idx] = min(abs(f_pos - target_freq));
search_range = max(1, target_idx-5):min(length(f_pos), target_idx+5);
% dB values cannot be summed as energy. Convert back to linear power before
% selecting the slice with the strongest target-frequency content.
energy_near_target = sum(10.^(all_ffts_db(search_range, :) / 10), 1);
[~, best_slice_idx] = max(energy_near_target);

chunk_db = all_ffts_db(:, best_slice_idx);
track_tolerance = 25;
local_min_freq = max(min_freq, target_freq - track_tolerance);
local_max_freq = min(max_freq, target_freq + track_tolerance);
[local_freq, ~] = find_dominant_freq_in_fft(chunk_db, f_pos, local_min_freq, local_max_freq);

if isempty(local_freq)
    disp(['No local dominant frequency found for ' title_prefix ' in best slice']);
    return;
end

peak_freq = local_freq(1);

% Calculate the 20%-of-prominence lobe width from the lower envelope.
[bw, f_segment, fft_segment, lower_envelope, threshold_curve, left_freq, right_freq] = ...
    get_peak_bandwidth(peak_freq, chunk_db, f_pos, min_freq, max_freq);

plot(f_segment, fft_segment, 'Color', [0.5 0.5 0.5], 'LineWidth', 1.2, 'DisplayName', 'Spectrum'); hold on;
plot(f_segment, lower_envelope, 'Color', [0.2 0.8 0.4], 'LineWidth', 1.5, 'DisplayName', 'Lower Envelope');
plot(f_segment, threshold_curve, 'Color', [1.0 0.65 0.0], 'LineStyle', '--', 'LineWidth', 1.2, 'DisplayName', '20% Lobe Threshold');
left_value = interp1(f_segment, threshold_curve, left_freq);
right_value = interp1(f_segment, threshold_curve, right_freq);
plot([left_freq right_freq], [left_value right_value], 'ro', 'MarkerFaceColor', 'r', 'DisplayName', 'Bandwidth Limits');

title(sprintf('%s Example: Peak=%.1f Hz\n20%% Lower-Envelope Bandwidth=%.1f Hz', title_prefix, peak_freq, bw));
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');
legend('Location', 'best');
grid on; box on;
end
