clear; clc; close all;

% =========================================================================
% Corrected bandwidth analysis
% =========================================================================
% Bandwidth definition used here:
%   - The peak is detected in a robust median spectrum.
%   - The bandwidth is measured on a LINEAR amplitude spectrum.
%   - The local noise floor is estimated from the edges of the local segment.
%   - The limits are the first crossings of a relative-amplitude threshold.
%   - Default threshold is -3 dB relative to the peak above the noise floor.
%
% The previous Hilbert-on-dB method was removed because a Hilbert envelope
% of a dB spectrum is not a physically meaningful spectral bandwidth.

% =========================================================================
% Configuration
% =========================================================================

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
    "Motorboat_08.08.23_110517_20secCPA.wav")
    };

SR_TARGET = 48000;
SLICE_DURATION_SEC = 0.5;
TARGET_DURATION_SEC = 60;
FAIRNESS_WINDOW = 5;

SCOOTER_FREQ_RANGE = [500, 1000];
MOTORBOAT_FREQ_RANGE = [50, 1000];

% Bandwidth settings
BW_THRESHOLD_DB = -3;       % -3 dB bandwidth
BW_SEARCH_HALF_WIDTH_HZ = 150;
BW_SMOOTHING_BINS = 5;
MIN_PEAK_PROMINENCE_DB = 3;
TRACK_TOLERANCE_HZ = 25;

slice_len = floor(SR_TARGET * SLICE_DURATION_SEC);
win_func = hann(slice_len, 'periodic');
samples_needed = SR_TARGET * TARGET_DURATION_SEC;

% =========================================================================
% Process files
% =========================================================================

disp('Processing Scooter...');
[scooter_bws, scooter_fairness] = process_audio_files(...
    SCOOTER_FILES, SR_TARGET, samples_needed, slice_len, win_func, ...
    SCOOTER_FREQ_RANGE(1), SCOOTER_FREQ_RANGE(2), FAIRNESS_WINDOW, ...
    BW_THRESHOLD_DB, BW_SEARCH_HALF_WIDTH_HZ, BW_SMOOTHING_BINS, ...
    MIN_PEAK_PROMINENCE_DB, TRACK_TOLERANCE_HZ);

disp('Processing Motor Boats...');
[ship_bws, ship_fairness] = process_audio_files(...
    MOTORBOAT_FILES, SR_TARGET, samples_needed, slice_len, win_func, ...
    MOTORBOAT_FREQ_RANGE(1), MOTORBOAT_FREQ_RANGE(2), FAIRNESS_WINDOW, ...
    BW_THRESHOLD_DB, BW_SEARCH_HALF_WIDTH_HZ, BW_SMOOTHING_BINS, ...
    MIN_PEAK_PROMINENCE_DB, TRACK_TOLERANCE_HZ);

% =========================================================================
% Plots
% =========================================================================

figure('Name', 'Corrected Bandwidth and Consistency', 'Position', [50, 50, 1100, 600]);

subplot(1, 2, 1);
plot_distribution(scooter_bws, ship_bws, 1.5, ...
    'Corrected Bandwidth Distribution', 'Bandwidth (Hz)');

subplot(1, 2, 2);
plot_distribution(scooter_fairness, ship_fairness, 0.02, ...
    sprintf('Rolling Bandwidth Consistency (Window = %d)', FAIRNESS_WINDOW), ...
    'Jain''s Index');

figure('Name', 'Corrected Bandwidth Examples', 'Position', [150, 150, 1100, 500]);

subplot(1, 2, 1);
plot_example_bandwidth(SCOOTER_FILES{1}, SR_TARGET, samples_needed, slice_len, ...
    win_func, SCOOTER_FREQ_RANGE(1), SCOOTER_FREQ_RANGE(2), 'Scooter', ...
    BW_THRESHOLD_DB, BW_SEARCH_HALF_WIDTH_HZ, BW_SMOOTHING_BINS, ...
    MIN_PEAK_PROMINENCE_DB, TRACK_TOLERANCE_HZ);

subplot(1, 2, 2);
plot_example_bandwidth(MOTORBOAT_FILES{1}, SR_TARGET, samples_needed, slice_len, ...
    win_func, MOTORBOAT_FREQ_RANGE(1), MOTORBOAT_FREQ_RANGE(2), 'Motor Boat', ...
    BW_THRESHOLD_DB, BW_SEARCH_HALF_WIDTH_HZ, BW_SMOOTHING_BINS, ...
    MIN_PEAK_PROMINENCE_DB, TRACK_TOLERANCE_HZ);

disp('Execution complete.');

% =========================================================================
% Audio processing
% =========================================================================

function [all_bws, all_fairness] = process_audio_files(file_paths, sr_target, samples_needed, slice_len, win, min_freq, max_freq, fairness_win, threshold_db, search_half_width_hz, smoothing_bins, min_prominence_db, track_tolerance_hz)

all_bws = [];

for k = 1:numel(file_paths)
    try
        [data, sr] = audioread(file_paths{k});
        data = resample_full(data, sr, sr_target);
        data = data(1:min(numel(data), samples_needed));

        bws = process_vessel_audio_tracked(data, sr_target, slice_len, win, ...
            min_freq, max_freq, threshold_db, search_half_width_hz, ...
            smoothing_bins, min_prominence_db, track_tolerance_hz);

        all_bws = [all_bws; bws]; %#ok<AGROW>
    catch ME
        fprintf('Warning: Could not process file %s. Error: %s\n', ...
            file_paths{k}, ME.message);
    end
end

all_fairness = compute_successive_jains(all_bws, fairness_win);
end

function bws = process_vessel_audio_tracked(data, sr, slice_len, win, min_freq, max_freq, threshold_db, search_half_width_hz, smoothing_bins, min_prominence_db, track_tolerance_hz)

num_slices = floor(numel(data) / slice_len);
if num_slices < 1
    bws = [];
    return;
end

N = slice_len;
faxis = (0:N-1)' * (sr/N);
pos_mask = faxis >= 0 & faxis <= sr/2;
f_pos = faxis(pos_mask);

num_bins = sum(pos_mask);
all_mag = zeros(num_bins, num_slices);

for i = 1:num_slices
    idx = (i-1)*slice_len + (1:slice_len);
    chunk = data(idx) .* win;
    X = fft(chunk, N);
    all_mag(:, i) = abs(X(pos_mask));
end

% Median in linear magnitude domain, then convert only for detection/display.
global_mag = median(all_mag, 2);
global_db = 20*log10(global_mag + eps);

global_freqs = find_dominant_freq_in_spectrum(global_db, f_pos, min_freq, max_freq, min_prominence_db);
if isempty(global_freqs)
    bws = NaN(num_slices, 1);
    return;
end

target_freq = global_freqs(1);
bws = NaN(num_slices, 1);

for i = 1:num_slices
    slice_db = 20*log10(all_mag(:, i) + eps);
    local_freqs = find_dominant_freq_in_spectrum(...
        slice_db, f_pos, target_freq-track_tolerance_hz, ...
        target_freq+track_tolerance_hz, min_prominence_db);

    if ~isempty(local_freqs)
        bws(i) = measure_bandwidth_3db(...
            local_freqs(1), all_mag(:, i), f_pos, threshold_db, ...
            search_half_width_hz, smoothing_bins);
    end
end
end

function data_out = resample_full(data, sr_orig, sr_target)
if size(data, 2) > 1
    data = mean(data, 2);
end

if sr_orig ~= sr_target
    [P, Q] = rat(sr_target/sr_orig, 1e-12);
    data = resample(data, P, Q);
end

data_out = data(:);
end

% =========================================================================
% Peak detection
% =========================================================================

function [dominant_freqs, peak_values] = find_dominant_freq_in_spectrum(spec_db, faxis, min_freq, max_freq, min_prominence_db)

mask = faxis >= min_freq & faxis <= max_freq;
f = faxis(mask);
y = spec_db(mask);

if numel(y) < 5
    dominant_freqs = [];
    peak_values = [];
    return;
end

span = min(51, 2*floor(numel(y)/2)-1);
span = max(span, 3);
baseline = movmedian(y, span);
detrended = y - baseline;

peak_distance_hz = 20;
df = mean(diff(f));
peak_distance_bins = max(1, round(peak_distance_hz/df));

[~, locs] = findpeaks(detrended, ...
    'MinPeakDistance', peak_distance_bins, ...
    'MinPeakProminence', min_prominence_db);

if isempty(locs)
    dominant_freqs = [];
    peak_values = [];
    return;
end

peak_values = y(locs);
[peak_values, order] = sort(peak_values, 'descend');
dominant_freqs = f(locs(order));
end

% =========================================================================
% Correct bandwidth calculation
% =========================================================================

function [bandwidth, f_segment, mag_segment, threshold_mag, left_idx, right_idx] = measure_bandwidth_3db(peak_freq, mag, faxis, threshold_db, search_half_width_hz, smoothing_bins)

[~, peak_idx] = min(abs(faxis - peak_freq));
df = mean(diff(faxis));
search_radius = max(2, round(search_half_width_hz/df));

seg_start = max(1, peak_idx-search_radius);
seg_end = min(numel(faxis), peak_idx+search_radius);

f_segment = faxis(seg_start:seg_end);
mag_segment = mag(seg_start:seg_end);

% Smooth in linear magnitude, not in dB.
if smoothing_bins > 1
    mag_smooth = smoothdata(mag_segment, 'gaussian', smoothing_bins);
else
    mag_smooth = mag_segment;
end

peak_local_idx = peak_idx - seg_start + 1;
peak_mag = mag_smooth(peak_local_idx);

% Estimate noise floor from the outer 20% of the local segment.
n = numel(mag_smooth);
edge_count = max(2, round(0.20*n));
edge_values = [mag_smooth(1:edge_count); mag_smooth(end-edge_count+1:end)];
noise_floor = median(edge_values);

% Remove the floor before defining relative bandwidth.
excess_peak = peak_mag - noise_floor;
if ~isfinite(excess_peak) || excess_peak <= 0
    bandwidth = NaN;
    threshold_mag = NaN;
    left_idx = NaN;
    right_idx = NaN;
    return;
end

% For -3 dB, use the corresponding amplitude ratio.
relative_level = 10^(threshold_db/20);
threshold_mag = noise_floor + relative_level*excess_peak;

% Search left and right from the peak.
left_cross = find(mag_smooth(1:peak_local_idx) <= threshold_mag, 1, 'last');
right_rel = find(mag_smooth(peak_local_idx:end) <= threshold_mag, 1, 'first');

if isempty(left_cross) || isempty(right_rel)
    bandwidth = NaN;
    left_idx = NaN;
    right_idx = NaN;
    return;
end

right_cross = peak_local_idx + right_rel - 1;

% Interpolate the crossing locations for sub-bin precision.
f_left = interpolate_crossing(...
    f_segment, mag_smooth, left_cross, left_cross+1, threshold_mag, 'left');
f_right = interpolate_crossing(...
    f_segment, mag_smooth, right_cross-1, right_cross, threshold_mag, 'right');

bandwidth = f_right - f_left;
left_idx = left_cross;
right_idx = right_cross;
end

function crossing_frequency = interpolate_crossing(f, y, i1, i2, level, side)

if i1 < 1 || i2 > numel(y) || y(i2) == y(i1)
    if strcmp(side, 'left')
        crossing_frequency = f(max(1, min(numel(f), i1)));
    else
        crossing_frequency = f(max(1, min(numel(f), i2)));
    end
    return;
end

crossing_frequency = f(i1) + (level-y(i1)) * ...
    (f(i2)-f(i1))/(y(i2)-y(i1));
end

% =========================================================================
% Jain consistency
% =========================================================================

function rolling_fairness = compute_successive_jains(x, window_size)

if numel(x) < window_size
    rolling_fairness = [];
    return;
end

rolling_fairness = NaN(numel(x)-window_size+1, 1);

for i = 1:numel(rolling_fairness)
    values = x(i:i+window_size-1);
    if all(isfinite(values) & values > 0)
        rolling_fairness(i) = sum(values)^2 / ...
            (window_size * sum(values.^2));
    end
end
end

% =========================================================================
% Plotting
% =========================================================================

function plot_distribution(data_a, data_b, bw, title_str, xlabel_str)

data_a = data_a(isfinite(data_a) & data_a > 0);
data_b = data_b(isfinite(data_b) & data_b > 0);

if isempty(data_a) || isempty(data_b)
    warning('One or both distributions are empty.');
    title(title_str);
    xlabel(xlabel_str);
    return;
end

[f_a, xi_a] = ksdensity(data_a, 'Bandwidth', bw);
[f_b, xi_b] = ksdensity(data_b, 'Bandwidth', bw);

fill(xi_a, f_a, [0.2 0.6 0.8], 'FaceAlpha', 0.5, ...
    'EdgeColor', [0.1 0.4 0.6], 'LineWidth', 2); hold on;
fill(xi_b, f_b, [0.8 0.3 0.3], 'FaceAlpha', 0.4, ...
    'EdgeColor', [0.6 0.2 0.2], 'LineWidth', 2);

title(title_str);
xlabel(xlabel_str);
ylabel('Density');
legend('Scooter', 'Motor Boat', 'Location', 'best');
grid on; box on;
end

function plot_example_bandwidth(file_path, sr_target, samples_needed, slice_len, win, min_freq, max_freq, title_prefix, threshold_db, search_half_width_hz, smoothing_bins, min_prominence_db, track_tolerance_hz)

[data, sr] = audioread(file_path);
data = resample_full(data, sr, sr_target);
data = data(1:min(numel(data), samples_needed));

num_slices = floor(numel(data)/slice_len);
if num_slices < 1
    return;
end

N = slice_len;
faxis = (0:N-1)'*(sr_target/N);
pos_mask = faxis >= 0 & faxis <= sr_target/2;
f_pos = faxis(pos_mask);

all_mag = zeros(sum(pos_mask), num_slices);
for i = 1:num_slices
    idx = (i-1)*slice_len + (1:slice_len);
    X = fft(data(idx).*win, N);
    all_mag(:, i) = abs(X(pos_mask));
end

global_mag = median(all_mag, 2);
global_db = 20*log10(global_mag+eps);
global_freqs = find_dominant_freq_in_spectrum(global_db, f_pos, min_freq, max_freq, min_prominence_db);

if isempty(global_freqs)
    title([title_prefix ': no dominant peak']);
    return;
end

target_freq = global_freqs(1);
[~, target_idx] = min(abs(f_pos-target_freq));
search_range = max(1,target_idx-5):min(numel(f_pos),target_idx+5);
energy_near_target = sum(all_mag(search_range,:), 1);
[~, best_slice_idx] = max(energy_near_target);

slice_mag = all_mag(:, best_slice_idx);
slice_db = 20*log10(slice_mag+eps);
local_freqs = find_dominant_freq_in_spectrum(slice_db, f_pos, ...
    target_freq-track_tolerance_hz, target_freq+track_tolerance_hz, min_prominence_db);

if isempty(local_freqs)
    title([title_prefix ': no local peak']);
    return;
end

peak_freq = local_freqs(1);
[bw, f_seg, mag_seg, threshold_mag, left_idx, right_idx] = measure_bandwidth_3db(...
    peak_freq, slice_mag, f_pos, threshold_db, search_half_width_hz, smoothing_bins);

% Plot spectrum in dB.
plot(f_pos, 20*log10(slice_mag+eps), 'Color', [0.85 0.85 0.85], ...
    'DisplayName', 'Magnitude Spectrum'); hold on;

plot(f_seg, 20*log10(mag_seg+eps), 'k', 'LineWidth', 1.5, ...
    'DisplayName', 'Local Peak Segment');

if isfinite(threshold_mag)
    yline(20*log10(threshold_mag+eps), 'r--', 'LineWidth', 1.2, ...
        'DisplayName', sprintf('Threshold (%g dB)', threshold_db));
end

if isfinite(bw) && ~isnan(left_idx) && ~isnan(right_idx)
    plot(f_seg(left_idx), 20*log10(mag_seg(left_idx)+eps), ...
        'bo', 'MarkerFaceColor', 'b', 'DisplayName', 'Left BW Limit');
    plot(f_seg(right_idx), 20*log10(mag_seg(right_idx)+eps), ...
        'bo', 'MarkerFaceColor', 'b', 'HandleVisibility', 'off');
end

xlim([min_freq max_freq]);
title(sprintf('%s: Peak = %.1f Hz, BW = %.1f Hz', ...
    title_prefix, peak_freq, bw));
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');
legend('Location', 'best');
grid on; box on;
end