clear; clc; close all;

% =========================================================================
% --- 1. Configuration & Parameters ---
% =========================================================================

% File Paths
SCOOTER_FILES = {
    "D:\RoyStudies\Recordings\Croatia\Ocean Sonics\2407_1_600m\RBW6737_20250724_093000.wav"
    };

MOTORBOAT_FILES = {
    "D:\RoyStudies\Recordings\hear-my-ship\V1\Motor Boats\Motorboat_08.08.23_142223_20secCPA.wav", ...
    "D:\RoyStudies\Recordings\hear-my-ship\V1\Motor Boats\Motorboat_06.09.23_113554_20secCPA.wav", ...
    "D:\RoyStudies\Recordings\hear-my-ship\V1\Motor Boats\Motorboat_08.08.23_105220_20secCPA.wav", ...
    "D:\RoyStudies\Recordings\hear-my-ship\V1\Motor Boats\Motorboat_08.08.23_110517_20secCPA.wav", ...
    "D:\RoyStudies\Recordings\hear-my-ship\V1\Motor Boats\Motorboat_08.08.23_105220_20secCPA.wav"
    };

% Processing Parameters
SR_TARGET = 48000;              % Target sampling rate (Hz)
SLICE_DURATION_SEC = 0.5;       % Window duration for processing (seconds)
TARGET_DURATION_SEC = 60;       % Maximum audio length to process per file (seconds)
FAIRNESS_WINDOW = 5;            % Window size for successive Jain's fairness

% Frequency Analysis Bounds (Hz)
SCOOTER_FREQ_RANGE = [500, 1000];
MOTORBOAT_FREQ_RANGE = [50, 1000];

% Derived Parameters
slice_len = floor(SR_TARGET * SLICE_DURATION_SEC);
win_func = hann(slice_len);
samples_needed = SR_TARGET * TARGET_DURATION_SEC;


% =========================================================================
% --- 2. Process Audio Files ---
% =========================================================================

disp('Processing Scooter...');
[scooter_bws, scooter_fairness, scooter_bws_h, scooter_fairness_h] = process_audio_files(...
    SCOOTER_FILES, SR_TARGET, samples_needed, slice_len, win_func, ...
    SCOOTER_FREQ_RANGE(1), SCOOTER_FREQ_RANGE(2), FAIRNESS_WINDOW);

disp('Processing Motor Boats...');
[ship_bws, ship_fairness, ship_bws_h, ship_fairness_h] = process_audio_files(...
    MOTORBOAT_FILES, SR_TARGET, samples_needed, slice_len, win_func, ...
    MOTORBOAT_FREQ_RANGE(1), MOTORBOAT_FREQ_RANGE(2), FAIRNESS_WINDOW);


% =========================================================================
% --- 3. Plotting Histograms (Median) ---
% =========================================================================

figure('Name', 'Bandwidth Distributions and Rolling Fairness (Median)', 'Position', [50, 50, 1100, 600]);

% Plot 1: Bandwidth Distribution
subplot(1, 2, 1);
plot_distribution(scooter_bws, ship_bws, 1.5, ...
    'Comparative Bandwidth Distribution (Median)', 'Bandwidth (Hz)');

% Plot 2: Successive Fairness Distribution
subplot(1, 2, 2);
plot_distribution(scooter_fairness, ship_fairness, 0.02, ...
    sprintf('Rolling Successive Fairness (Window = %d)', FAIRNESS_WINDOW), ...
    'Jain''s Fairness Index');


% =========================================================================
% --- 4. Plotting Histograms (Hilbert) ---
% =========================================================================

figure('Name', 'Bandwidth Distributions and Rolling Fairness (Hilbert)', 'Position', [100, 100, 1100, 600]);

% Plot 1: Bandwidth Distribution
subplot(1, 2, 1);
plot_distribution(scooter_bws_h, ship_bws_h, 1.5, ...
    'Comparative Bandwidth Distribution (Hilbert)', 'Bandwidth (Hz)');

% Plot 2: Successive Fairness Distribution
subplot(1, 2, 2);
plot_distribution(scooter_fairness_h, ship_fairness_h, 0.02, ...
    sprintf('Rolling Successive Fairness (Window = %d)', FAIRNESS_WINDOW), ...
    'Jain''s Fairness Index');


% =========================================================================
% --- 5. Plotting Examples (Hilbert vs Median) ---
% =========================================================================

figure('Name', 'Bandwidth Calculation Examples (Hilbert vs Median)', 'Position', [150, 150, 1100, 500]);

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

function [all_bws, all_fairness, all_bws_hilbert, all_fairness_hilbert] = process_audio_files(file_paths, sr_target, samples_needed, slice_len, win, min_freq, max_freq, fairness_win)
% Processes a list of audio files and extracts bandwidth and fairness metrics.
all_bws = [];
all_fairness = [];
all_bws_hilbert = [];
all_fairness_hilbert = [];

for k = 1:length(file_paths)
    try
        [data, sr] = audioread(file_paths{k});
        data_resampled = resample_full(data, sr, sr_target);
        data_resampled = data_resampled(1:min(length(data_resampled), samples_needed));

        [bws, bws_hilbert] = process_vessel_audio_tracked(data_resampled, sr_target, slice_len, win, min_freq, max_freq);
        fairness = compute_successive_jains(bws, fairness_win);
        fairness_hilbert = compute_successive_jains(bws_hilbert, fairness_win);

        all_bws = [all_bws; bws];
        all_fairness = [all_fairness; fairness];
        all_bws_hilbert = [all_bws_hilbert; bws_hilbert];
        all_fairness_hilbert = [all_fairness_hilbert; fairness_hilbert];
    catch ME
        fprintf('  -> Warning: Could not process file %s. Error: %s\n', file_paths{k}, ME.message);
    end
end
end

function plot_distribution(data_scooter, data_ship, bw, title_str, xlabel_str)
% Helper to plot KDE distributions consistently
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

function data_out = resample_full(data, sr_orig, sr_target)
% Resamples and converts to mono if necessary
if sr_orig > sr_target
    [P, Q] = rat(sr_target / sr_orig);
    data = resample(data, P, Q);
end
if size(data, 2) > 1
    data = data(:, 1);
end
data_out = data;
end

function rolling_fairness = compute_successive_jains(x, window_size)
% Computes rolling Jain's fairness index
x = x(~isnan(x) & x > 0);
if length(x) < window_size
    rolling_fairness = [];
    return;
end

num_windows = length(x) - window_size + 1;
rolling_fairness = zeros(num_windows, 1);

for i = 1:num_windows
    win_vals = x(i:i+window_size-1);
    rolling_fairness(i) = (sum(win_vals)^2) / (length(win_vals) * sum(win_vals.^2));
end
end

function [bws, bws_hilbert] = process_vessel_audio_tracked(data, sr, slice_len, win, min_freq, max_freq)
% Analyzes audio in slices to track peak bandwidth of a dominant frequency
num_slices = floor(length(data) / slice_len);
if num_slices < 1; bws = []; bws_hilbert = []; return; end

N = slice_len;
Faxis_fft = (0:N-1) * (sr/N);
pos_mask = Faxis_fft >= 0 & Faxis_fft <= sr/2;
f_pos = Faxis_fft(pos_mask);

all_ffts_db = zeros(sum(pos_mask), num_slices);

for i = 1:num_slices
    idx_start = (i-1)*slice_len + 1;
    idx_end = i*slice_len;
    chunk = data(idx_start:idx_end) .* win;
    chunk_fft = fft(chunk);
    all_ffts_db(:, i) = 20 * log10(abs(chunk_fft(pos_mask)) + 1e-12);
end

global_spec_db = median(all_ffts_db, 2);
[global_dom_freq, ~] = find_dominant_freq_in_fft(global_spec_db, f_pos, min_freq, max_freq);

if isempty(global_dom_freq)
    bws = []; bws_hilbert = []; return;
end

target_freq = global_dom_freq(1);
bws = NaN(num_slices, 1);
bws_hilbert = NaN(num_slices, 1);
track_tolerance = 25;

for i = 1:num_slices
    chunk_db = all_ffts_db(:, i);
    [local_freq, ~] = find_dominant_freq_in_fft(chunk_db, f_pos, target_freq - track_tolerance, target_freq + track_tolerance);

    if ~isempty(local_freq)
        bws(i) = get_peak_bandwidth(local_freq(1), chunk_db, f_pos);
        bws_hilbert(i) = get_peak_bandwidth_hilbert(local_freq(1), chunk_db, f_pos);
    end
end
end

function [dominantFreqs, maxPowers] = find_dominant_freq_in_fft(fft_db, faxis, min_freq, max_freq)
% Locates the dominant frequency peaks within a given frequency range
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

function [bandwidth, f_segment, fft_segment, lobe_shape, local_noise_floor, threshold_db, l_idx, r_idx] = get_peak_bandwidth(peak_freq, spec_db, f_pos)
% Calculates bandwidth by finding the width of the peak based on prominence
[~, peak_idx] = min(abs(f_pos - peak_freq));

df = f_pos(2) - f_pos(1);
window_radius = max(10, ceil(35 / df));

seg_start = max(1, peak_idx - window_radius);
seg_end = min(length(spec_db), peak_idx + window_radius);

f_segment = f_pos(seg_start:seg_end);
fft_segment = spec_db(seg_start:seg_end);

lobe_shape = smoothdata(fft_segment, 'gaussian', 3);
local_noise_floor = median(lobe_shape);

peak_local_idx = peak_idx - seg_start + 1;
peak_height = lobe_shape(peak_local_idx);
prominence = peak_height - local_noise_floor;

threshold_db = local_noise_floor + (prominence * 0.20);

l_idx = 1;
for i = peak_local_idx:-1:1
    if lobe_shape(i) <= threshold_db
        l_idx = i;
        break;
    end
end

r_idx = length(lobe_shape);
for i = peak_local_idx:1:length(lobe_shape)
    if lobe_shape(i) <= threshold_db
        r_idx = i;
        break;
    end
end

bandwidth = abs(f_segment(r_idx) - f_segment(l_idx));
end

function [bandwidth, f_segment, fft_segment, env_up, env_lo, threshold_curve, l_idx, r_idx] = get_peak_bandwidth_hilbert(peak_freq, spec_db, f_pos)
% Calculates bandwidth using a Hilbert-based lower envelope
[~, peak_idx] = min(abs(f_pos - peak_freq));

df = f_pos(2) - f_pos(1);
window_radius = max(10, ceil(35 / df));

seg_start = max(1, peak_idx - window_radius);
seg_end = min(length(spec_db), peak_idx + window_radius);

f_segment = f_pos(seg_start:seg_end);
fft_segment = spec_db(seg_start:seg_end);

% Compute analytic envelope (Hilbert based)
[env_up, env_lo] = envelope(fft_segment, 15, 'analytic');

peak_local_idx = peak_idx - seg_start + 1;
peak_height = env_up(peak_local_idx);
local_noise_floor = env_lo(peak_local_idx);
prominence = peak_height - local_noise_floor;

threshold_curve = env_lo + (prominence * 0.20);

l_idx = 1;
for i = peak_local_idx:-1:1
    if env_up(i) <= threshold_curve(i)
        l_idx = i;
        break;
    end
end

r_idx = length(env_up);
for i = peak_local_idx:1:length(env_up)
    if env_up(i) <= threshold_curve(i)
        r_idx = i;
        break;
    end
end

bandwidth = abs(f_segment(r_idx) - f_segment(l_idx));
end

function plot_example_bandwidth(file_path, sr_target, samples_needed, slice_len, win, min_freq, max_freq, title_prefix)
% Reads the file, finds the slice with the highest target frequency energy, and plots its bandwidth calculation.

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
    chunk = data(idx_start:idx_end) .* win;
    chunk_fft = fft(chunk);
    all_ffts_db(:, i) = 20 * log10(abs(chunk_fft(pos_mask)) + 1e-12);
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
energy_near_target = sum(all_ffts_db(search_range, :), 1);
[~, best_slice_idx] = max(energy_near_target);

chunk_db = all_ffts_db(:, best_slice_idx);
track_tolerance = 25;
[local_freq, ~] = find_dominant_freq_in_fft(chunk_db, f_pos, target_freq - track_tolerance, target_freq + track_tolerance);

if isempty(local_freq)
    disp(['No local dominant frequency found for ' title_prefix ' in best slice']);
    return;
end

peak_freq = local_freq(1);

% Calculate the full baseline/envelope used in find_dominant_freq_in_fft
full_mask = (f_pos >= min_freq) & (f_pos <= max_freq);
full_faxis = f_pos(full_mask);
full_fft_db = chunk_db(full_mask);
med_span = min(51, max(3, floor(length(full_fft_db)/2)*2 - 1));
baseline = movmedian(full_fft_db, med_span);

% Plot the full signal and full baseline
plot(full_faxis, full_fft_db, 'Color', [0.85 0.85 0.85], 'DisplayName', 'Full Segment Spectrum'); hold on;
plot(full_faxis, baseline, 'Color', [0.4 0.8 0.4], 'LineWidth', 1.5, 'DisplayName', 'Baseline Envelope (movmedian)');

% Calculate BOTH bandwidths
[bw_hilbert, f_seg_h, fft_seg_h, env_up, env_lo, thresh_h, l_idx_h, r_idx_h] = get_peak_bandwidth_hilbert(peak_freq, chunk_db, f_pos);
[bw_median, f_seg_m, fft_seg_m, lobe_shape, noise_floor, thresh_m, l_idx_m, r_idx_m] = get_peak_bandwidth(peak_freq, chunk_db, f_pos);

plot(f_seg_h, fft_seg_h, 'Color', [0.4 0.4 0.4], 'LineWidth', 1.5, 'DisplayName', 'Peak Bandwidth Segment');
plot(f_seg_h, env_lo, 'k:', 'LineWidth', 1.5, 'DisplayName', 'Lower Envelope (Hilbert)');

% Plot marks for Hilbert (red circles)
plot(f_seg_h(l_idx_h), fft_seg_h(l_idx_h), 'ro', 'MarkerFaceColor', 'r', 'DisplayName', 'Hilbert BW Limits');
plot(f_seg_h(r_idx_h), fft_seg_h(r_idx_h), 'ro', 'MarkerFaceColor', 'r', 'HandleVisibility', 'off');

% Plot marks for Median (blue squares)
plot(f_seg_m(l_idx_m), fft_seg_m(l_idx_m), 'bs', 'MarkerFaceColor', 'b', 'DisplayName', 'Median BW Limits');
plot(f_seg_m(r_idx_m), fft_seg_m(r_idx_m), 'bs', 'MarkerFaceColor', 'b', 'HandleVisibility', 'off');

title(sprintf('%s Example: Peak=%.1f Hz\nHilbert BW=%.1f Hz, Median BW=%.1f Hz', title_prefix, peak_freq, bw_hilbert, bw_median));
xlabel('Frequency (Hz)');
ylabel('Magnitude (dB)');
legend('Location', 'best');
grid on; box on;
end