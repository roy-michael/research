close all; clear all; clc;
function [l_idx, r_idx, lower_env, trend] = find_hilbert_intersections(signal, peak_idx, trend_window, smooth_window)
% FIND_HILBERT_INTERSECTIONS Finds the left and right intersection points of a signal peak
%   using a padded Hilbert transform lower envelope.
%
%   Inputs:
%       signal       - The 1D signal array
%       peak_idx     - The index of the peak within the signal
%       trend_window - (Optional) Window size for movmedian trend. Default: 41
%       smooth_window- (Optional) Window size for gaussian smoothing. Default: 11
%
%   Outputs:
%       l_idx        - Left intersection index
%       r_idx        - Right intersection index
%       lower_env    - The calculated lower envelope
%       trend        - The median trend of the signal

l_idx = []; r_idx = []; lower_env = []; trend = [];
if nargin == 0
    run_demo();
    return;
end

if nargin < 3
    trend_window = 41;
end
if nargin < 4
    smooth_window = 11;
end

is_row = isrow(signal);
signal_col = signal(:);

% 1. THE TREND FIX: Use movmedian
% A median filter ignores the massive peak and tracks the true noise floor beneath it.
trend = movmedian(signal_col, trend_window);
ac_signal = signal_col - trend;

% 2. THE HILBERT FIX: Symmetric Padding
% Mirror the segment to eliminate boundary artifacts/Gibbs phenomenon in the analytic signal
pad_len = length(ac_signal);
ac_padded = [flipud(ac_signal); ac_signal; flipud(ac_signal)];

% Compute analytic envelope on the padded signal, then extract the original center
env_padded = abs(hilbert(ac_padded));
analytic_env = env_padded(pad_len+1 : 2*pad_len);

% Smooth the envelope slightly to guarantee a stable boundary line
analytic_env = smoothdata(analytic_env, 'gaussian', smooth_window);

% Calculate the true lower envelope
lower_env = trend - analytic_env;

% 3. FIND TRUE INTERSECTIONS
% Create intersection mask
is_touching = signal_col <= lower_env;

% -- Find Left Boundary --
left_side = is_touching(1:peak_idx);
left_crossings = find(left_side);
if ~isempty(left_crossings)
    % Grab the crossing closest to the peak
    l_idx = left_crossings(end);
else
    [~, l_idx] = min(abs(signal_col(1:peak_idx) - lower_env(1:peak_idx)));
end

% -- Find Right Boundary --
right_side = is_touching(peak_idx:end);
right_crossings = find(right_side);
if ~isempty(right_crossings)
    % Grab the crossing closest to the peak
    r_idx = peak_idx + right_crossings(1) - 1;
else
    [~, temp_idx] = min(abs(signal_col(peak_idx:end) - lower_env(peak_idx:end)));
    r_idx = peak_idx + temp_idx - 1;
end

if is_row
    lower_env = lower_env.';
    trend = trend.';
end

end

% =========================================================================
% --- Demo and Helper Functions ---
% =========================================================================

function run_demo()
% RUN_DEMO Runs a demonstration of the intersection finding algorithm
disp('Running demo with sample audio files...');

% --- 1. Load Audio Files ---
% Make sure these paths are accessible or update them to valid paths
try
    recordingsBasePath = "C:\Users\Roy\Recordings";
    ship_path = fullfile(recordingsBasePath, "hear_my_ship", "V1", "Motor Boats", "Motorboat_08.08.23_142223_20secCPA.wav");
    scooter_path = fullfile(recordingsBasePath, "Croatia", "Ocean Sonics", "2407_1_600m", "RBW6737_20250724_093000.wav");

    [data_ship, sr_ship] = audioread(ship_path);
    [data_scooter, sr_scooter] = audioread(scooter_path);
catch ME
    warning('Demo requires specific audio files that could not be found. Please update the paths in run_demo().');
    return;
end

% --- 2. Parameters ---
sr = min(sr_scooter, sr_ship);
slice_duration_sec = 0.25;
slice_len = floor(sr * slice_duration_sec); % Ensure integer length
start_idx = 1;

% --- 3. Extract and Resample ---
ship_part = resample_and_split(data_ship, sr_ship, sr, start_idx, slice_len);
scooter_part = resample_and_split(data_scooter, sr_scooter, sr, start_idx, slice_len);

% --- 4. Apply Hann Window (Prevents Spectral Leakage) ---
win = hann(slice_len);
ship_part_win = ship_part .* win;
scooter_part_win = scooter_part .* win;

% --- 5. Compute FFT and Frequency Axis ---
ship_fft = fft(ship_part_win);
scooter_fft = fft(scooter_part_win);

N = slice_len;
Faxis_fft = (0:N-1) * (sr/N);

% Use only positive frequencies up to Nyquist
pos_mask = Faxis_fft >= 0 & Faxis_fft <= sr/2;
f_pos = Faxis_fft(pos_mask);

% --- 6. Convert to Logarithmic (dB) Scale ---
% Adds a tiny offset (1e-12) to prevent log10(0)
ship_pos_db = 20 * log10(abs(ship_fft(pos_mask)) + 1e-12);
scooter_pos_db = 20 * log10(abs(scooter_fft(pos_mask)) + 1e-12);

% --- 7. Scooter Processing ---
[sc_dom_freq, ~] = find_dominant_freq_in_fft(scooter_pos_db, f_pos, 500, 1000);
fprintf('=== Scooter: Bandwidth for Strongest Dominant Frequency (capped at 1.5 kHz) ===\n');
process_and_plot(sc_dom_freq, scooter_pos_db, f_pos, 'Scooter');

% --- 8. Ship Processing ---
[sp_dom_freq, ~] = find_dominant_freq_in_fft(ship_pos_db, f_pos, 50, 1000);
fprintf('\n=== Ship: Bandwidth for Strongest Dominant Frequency (capped at 1.5 kHz) ===\n');
process_and_plot(sp_dom_freq, ship_pos_db, f_pos, 'Ship');
end

function process_and_plot(dom_freqs, spec_pos, f_pos, label_name)
if isempty(dom_freqs)
    disp('No peaks found within the specified frequency range.');
    return;
end

figure('Name', [label_name ' - Strongest Dominant Peak & Envelope'], 'Position', [100, 100, 800, 500]);

% Process the single dominant frequency
peak_freq = dom_freqs(1);
[~, peak_idx] = min(abs(f_pos - peak_freq));

% Extract local spectral window (Wider radius to ensure we see the true background)
window_radius = 80;
seg_start = max(1, peak_idx - window_radius);
seg_end = min(length(spec_pos), peak_idx + window_radius);

f_segment = f_pos(seg_start:seg_end);
fft_segment = spec_pos(seg_start:seg_end);

peak_local_idx = peak_idx - seg_start + 1;

% CALL THE MAIN INTERSECTION FUNCTION
[~, ~, lower_env, trend] = find_hilbert_intersections(fft_segment, peak_local_idx);

% --- Calculate exact interpolated intersections for plotting ---
[l_f_env, l_y_env, r_f_env, r_y_env] = compute_exact_intersections(fft_segment, lower_env, f_segment, peak_local_idx);
[l_f_med, l_y_med, r_f_med, r_y_med] = compute_exact_intersections(fft_segment, trend, f_segment, peak_local_idx);

bandwidth = abs(r_f_env - l_f_env);
fprintf('Strongest Peak: %.2f Hz -> Env Bandwidth: %.2f Hz\n', peak_freq, bandwidth);

% Plotting single chart
plot(f_segment, fft_segment, 'Color', [.6 .6 .6], 'LineWidth', 1.5); hold on;
plot(f_segment, trend, 'k:', 'LineWidth', 1.5);
plot(f_segment, lower_env, 'b--', 'LineWidth', 1.5);
plot([l_f_env, r_f_env], [l_y_env, r_y_env], 'ro', 'MarkerSize', 8, 'LineWidth', 2);
plot([l_f_med, r_f_med], [l_y_med, r_y_med], 'go', 'MarkerSize', 8, 'LineWidth', 2);
xline(peak_freq, 'g-.', 'LineWidth', 2);

title(sprintf('%s Strongest Peak: %.1f Hz (BW: %.1f Hz)', label_name, peak_freq, bandwidth));
xlabel('Frequency (Hz)'); ylabel('Magnitude (dB)');
legend('FFT Segment', 'Robust Trend (Median)', 'Lower Envelope (Padded Hilbert)', ...
    'Hilbert Intersections', 'Median Intersections', 'Peak Freq', 'Location', 'best');
grid on;
end

function result = resample_and_split(data, sr_orig, sr_target, start_idx, num_samples)
if sr_orig > sr_target
    [P, Q] = rat(sr_target / sr_orig);
    data = resample(data, P, Q);
end

% Ensure data is a column vector (take channel 1 if stereo)
if size(data, 2) > 1
    data = data(:, 1);
end

result = data(start_idx:min(start_idx+num_samples-1, length(data)));

% Zero pad if the segment is shorter than expected
if length(result) < num_samples
    result = [result; zeros(num_samples - length(result), 1)];
end
end

function [dominantFreqs, maxPowers] = find_dominant_freq_in_fft(fft_db, faxis, min_freq, max_freq)
pos_mask = (faxis >= min_freq) & (faxis <= max_freq);
pos_faxis = faxis(pos_mask);
pos_fft_db = fft_db(pos_mask);

if isempty(pos_fft_db)
    dominantFreqs = [];
    maxPowers = [];
    return;
end

% Detrending in dB space using a moving median to flatten the slope
baseline = movmedian(pos_fft_db, 51);
detrended_db = pos_fft_db - baseline;

% Look for peaks that stick out at least 3 dB from the local noise floor
[pks, locs] = findpeaks(detrended_db, 'MinPeakDistance', 20, 'MinPeakProminence', 3);

if isempty(locs)
    dominantFreqs = [];
    maxPowers = [];
    return;
end

% Sort by the true absolute dB power of the peaks
peak_amps_db = pos_fft_db(locs);
[~, sort_idx] = sort(peak_amps_db, 'descend');

% Extracted the single strongest peak
num_peaks_to_find = 1;
num_peaks = min(num_peaks_to_find, length(sort_idx));

dominantFreqs = pos_faxis(locs(sort_idx(1:num_peaks)));
maxPowers = pos_fft_db(locs(sort_idx(1:num_peaks)));
end

function [l_exact_f, l_exact_y, r_exact_f, r_exact_y] = compute_exact_intersections(signal, env, f_segment, peak_idx)
% Find left boundary
is_touching = signal <= env;
left_side = is_touching(1:peak_idx);
left_crossings = find(left_side);
if ~isempty(left_crossings)
    l_idx = left_crossings(end);
else
    [~, l_idx] = min(abs(signal(1:peak_idx) - env(1:peak_idx)));
end

% Find right boundary
right_side = is_touching(peak_idx:end);
right_crossings = find(right_side);
if ~isempty(right_crossings)
    r_idx = peak_idx + right_crossings(1) - 1;
else
    [~, temp_idx] = min(abs(signal(peak_idx:end) - env(peak_idx:end)));
    r_idx = peak_idx + temp_idx - 1;
end

% Interpolate Left
l_exact_f = f_segment(l_idx); l_exact_y = signal(l_idx);
if l_idx < peak_idx && l_idx < length(signal)
    d1 = signal(l_idx) - env(l_idx);
    d2 = signal(l_idx+1) - env(l_idx+1);
    if d1 ~= d2
        l_frac = d1 / (d1 - d2);
        l_exact_f = f_segment(l_idx) + l_frac * (f_segment(l_idx+1) - f_segment(l_idx));
        l_exact_y = signal(l_idx) + l_frac * (signal(l_idx+1) - signal(l_idx));
    end
end

% Interpolate Right
r_exact_f = f_segment(r_idx); r_exact_y = signal(r_idx);
if r_idx > peak_idx && r_idx > 1
    d1 = signal(r_idx-1) - env(r_idx-1);
    d2 = signal(r_idx) - env(r_idx);
    if d1 ~= d2
        r_frac = d1 / (d1 - d2);
        r_exact_f = f_segment(r_idx-1) + r_frac * (f_segment(r_idx) - f_segment(r_idx-1));
        r_exact_y = signal(r_idx-1) + r_frac * (signal(r_idx) - signal(r_idx-1));
    end
end
end
