clear; clc; close all;

% --- 1. Load Audio Files ---
[data_scooter, sr_scooter] = audioread("D:\RoyStudies\Recordings\Croatia\Ocean Sonics\2407_1_600m\RBW6737_20250724_093000.wav");

boat_paths = {
    "D:\RoyStudies\Recordings\hear-my-ship\V1\Motor Boats\Motorboat_08.08.23_142223_20secCPA.wav", ...
    "D:\RoyStudies\Recordings\hear-my-ship\V1\Motor Boats\Motorboat_06.09.23_113554_20secCPA.wav", ...
    "D:\RoyStudies\Recordings\hear-my-ship\V1\Motor Boats\Motorboat_08.08.23_105220_20secCPA.wav", ...
    "D:\RoyStudies\Recordings\hear-my-ship\V1\Motor Boats\Motorboat_08.08.23_110517_20secCPA.wav", ...
    "D:\RoyStudies\Recordings\hear-my-ship\V1\Motor Boats\Motorboat_08.08.23_105220_20secCPA.wav"
};

% --- 2. Parameters (0.5 second slice) ---
sr_target = 48000;
slice_duration_sec = 0.5; 
slice_len = floor(sr_target * slice_duration_sec);
win = hann(slice_len);
target_duration_sec = 60; 
samples_needed = sr_target * target_duration_sec;

% --- 3. Process Scooter & Compute Metrics ---
disp('Processing Scooter...');
scooter_full = resample_full(data_scooter, sr_scooter, sr_target);
scooter_full = scooter_full(1:min(length(scooter_full), samples_needed));
scooter_bws = process_vessel_audio_tracked(scooter_full, sr_target, slice_len, win, 500, 1000);
scooter_successive_fairness = compute_successive_jains(scooter_bws, 5); 

% --- 4. Process Ships & Compute Metrics ---
disp('Processing Motor Boats...');
all_ship_bws = [];
all_ship_fairness = [];

for k = 1:length(boat_paths)
    try
        [data_b, sr_b] = audioread(boat_paths{k});
        b_full = resample_full(data_b, sr_b, sr_target);
        b_full = b_full(1:min(length(b_full), samples_needed));
        
        b_bws = process_vessel_audio_tracked(b_full, sr_target, slice_len, win, 50, 1000);
        b_fairness = compute_successive_jains(b_bws, 5);
        
        all_ship_bws = [all_ship_bws; b_bws];
        all_ship_fairness = [all_ship_fairness; b_fairness];
    catch ME
        fprintf('  -> Warning: Could not process file %s. Error: %s\n', boat_paths{k}, ME.message);
    end
end

% --- 5. Plot Both Figures Side-by-Side or Stacked ---
figure('Name', 'Bandwidth Distributions and Rolling Fairness', 'Position', [100, 100, 1100, 600]);

% Plot 1: Bandwidth Distribution
subplot(1, 2, 1);
[f_scooter_bw, xi_scooter_bw] = ksdensity(scooter_bws, 'Bandwidth', 1.5);
[f_ship_bw, xi_ship_bw] = ksdensity(all_ship_bws, 'Bandwidth', 1.5);

fill(xi_scooter_bw, f_scooter_bw, [0.2 0.6 0.8], 'FaceAlpha', 0.5, 'EdgeColor', [0.1 0.4 0.6], 'LineWidth', 2); hold on;
fill(xi_ship_bw, f_ship_bw, [0.8 0.3 0.3], 'FaceAlpha', 0.4, 'EdgeColor', [0.6 0.2 0.2], 'LineWidth', 2);

title('Comparative Bandwidth Distribution');
xlabel('Bandwidth (Hz)');
ylabel('Density Probability');
legend('Scooter', 'Surface Ships', 'Location', 'northeast');
grid on; box on;

% Plot 2: Successive Fairness Distribution
subplot(1, 2, 2);
[f_scooter_f, xi_scooter_f] = ksdensity(scooter_successive_fairness, 'Bandwidth', 0.02);
[f_ship_f, xi_ship_f] = ksdensity(all_ship_fairness, 'Bandwidth', 0.02);

fill(xi_scooter_f, f_scooter_f, [0.2 0.6 0.8], 'FaceAlpha', 0.5, 'EdgeColor', [0.1 0.4 0.6], 'LineWidth', 2); hold on;
fill(xi_ship_f, f_ship_f, [0.8 0.3 0.3], 'FaceAlpha', 0.4, 'EdgeColor', [0.6 0.2 0.2], 'LineWidth', 2);

title('Rolling Successive Fairness (Window = 5)');
xlabel('Jain''s Fairness Index');
ylabel('Density Probability');
legend('Scooter', 'Surface Ships', 'Location', 'northwest');
grid on; box on;

disp('Execution complete.');


% =========================================================================
% --- Helper Functions ---
% =========================================================================

function data_out = resample_full(data, sr_orig, sr_target)
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

function bws = process_vessel_audio_tracked(data, sr, slice_len, win, min_freq, max_freq)
    num_slices = floor(length(data) / slice_len);
    if num_slices < 1, bws = []; return; end
    
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
        bws = []; return;
    end
    
    target_freq = global_dom_freq(1);
    bws = NaN(num_slices, 1);
    track_tolerance = 25; 
    
    for i = 1:num_slices
        chunk_db = all_ffts_db(:, i);
        [local_freq, ~] = find_dominant_freq_in_fft(chunk_db, f_pos, target_freq - track_tolerance, target_freq + track_tolerance);
        
        if ~isempty(local_freq)
            bws(i) = get_peak_bandwidth(local_freq(1), chunk_db, f_pos);
        end
    end
end

function [dominantFreqs, maxPowers] = find_dominant_freq_in_fft(fft_db, faxis, min_freq, max_freq)
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

function bandwidth = get_peak_bandwidth(peak_freq, spec_db, f_pos)
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