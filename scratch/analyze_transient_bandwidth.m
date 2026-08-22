% Script to find the dominant time-domain transient and calculate its frequency-domain bandwidth
% Method: Locate time peak -> extract window -> compute PSD -> apply Diamant envelope method

motorboat_dir = 'D:\RoyStudies\Recordings\hear-my-ship\V1\Motor Boats';
wav_files = dir(fullfile(motorboat_dir, '*.wav'));

% Let's process the specific file from the screenshot as an example, if it exists, or just the first few
target_file = 'Motorboat_01.09.23_073809_20secCPA.wav';
file_idx = find(strcmp({wav_files.name}, target_file));

if isempty(file_idx)
    file_idx = 1; % Fallback to first file
end

wav_path = fullfile(motorboat_dir, wav_files(file_idx).name);
[data, fs] = audioread(wav_path);

if size(data, 2) > 1
    data = data(:, 1);
end

time_vec = (0:length(data)-1) / fs;

% 1. Find the time-domain peak (transient)
[~, t_hat_time] = max(abs(data));
peak_time = time_vec(t_hat_time);

% 2. Extract a short window around the time-domain peak
% Let's take a 100 ms window (50 ms before and after)
window_sec = 0.05; 
idx_min = max(1, t_hat_time - round(window_sec * fs));
idx_max = min(length(data), t_hat_time + round(window_sec * fs));

transient_data = data(idx_min:idx_max);

% 3. Compute the PSD of this short transient
nfft = 8192; % Increased NFFT for finer frequency resolution (Hz/bin)
[pxx, f] = pwelch(transient_data, rectwin(length(transient_data)), 0, nfft, fs);

% Limit to 0-4000 Hz for analysis
mask = f >= 0 & f <= 4000;
f_zoom = f(mask);
v = pxx(mask);

% 4. Apply the Diamant method in the frequency domain
% Compute envelope of the PSD
v_tilde = abs(hilbert(v));

% Find dominant frequency of the transient
[~, f_hat_idx] = max(v);
dominant_freq = f_zoom(f_hat_idx);

% Find l1 and l2 (intersections) by finding the *first local minimum* of the difference
% moving away from the peak, rather than the global minimum.
diff_v = abs(v - v_tilde);

% Find all local minima of the difference
[~, locs_min] = findpeaks(-diff_v); % Local minima

% Right edge l1: first local minimum to the right
locs_right = locs_min(locs_min > f_hat_idx);
if ~isempty(locs_right)
    l1 = locs_right(1);
else
    l1 = f_hat_idx;
end

% Left edge l2: first local minimum to the left
locs_left = locs_min(locs_min < f_hat_idx);
if ~isempty(locs_left)
    l2 = locs_left(end);
else
    l2 = f_hat_idx;
end

bw = f_zoom(l1) - f_zoom(l2);

% --- Plotting ---
fig = figure('Position', [100, 100, 1200, 1000], 'Visible', 'off');

% Plot 1: Time domain window
subplot(3, 1, 1);
t_window = time_vec(idx_min:idx_max);
plot(t_window, transient_data, 'b-', 'LineWidth', 1.5); hold on;
plot(peak_time, data(t_hat_time), 'ko', 'MarkerSize', 8, 'LineWidth', 2);
title(sprintf('Time-Domain Transient (Peak at %.3f s) | File: %s', peak_time, wav_files(file_idx).name));
xlabel('Time (s)');
ylabel('Amplitude');
grid on;

% Plot 2: Frequency domain wide view
subplot(3, 1, 2);
plot(f_zoom, v, 'b-', 'LineWidth', 1.5); hold on;
plot(f_zoom, v_tilde, 'r--', 'LineWidth', 1.5);
plot(dominant_freq, v(f_hat_idx), 'ko', 'MarkerSize', 8, 'LineWidth', 2);
plot(f_zoom(l1), v(l1), 'kx', 'MarkerSize', 8, 'LineWidth', 2);
plot(f_zoom(l2), v(l2), 'kx', 'MarkerSize', 8, 'LineWidth', 2);
xlim([0, 2000]);
title('Frequency-Domain Wide View (0 - 2000 Hz)');
xlabel('Frequency (Hz)');
ylabel('PSD');
legend('PSD', 'Envelope', 'Peak', 'Bandwidth Edges');
grid on;

% Plot 3: Frequency domain tightly zoomed on bandwidth
subplot(3, 1, 3);
plot(f_zoom, v, 'b-', 'LineWidth', 1.5); hold on;
plot(f_zoom, v_tilde, 'r--', 'LineWidth', 1.5);
plot(dominant_freq, v(f_hat_idx), 'ko', 'MarkerSize', 8, 'LineWidth', 2);
plot(f_zoom(l1), v(l1), 'kx', 'MarkerSize', 8, 'LineWidth', 2);
plot(f_zoom(l2), v(l2), 'kx', 'MarkerSize', 8, 'LineWidth', 2);

% Tightly focus around the bandwidth
zoom_range = max(50, bw * 2.5); % Ensure it's zoomed in close to the bandwidth
f_min = max(0, dominant_freq - zoom_range);
f_max = dominant_freq + zoom_range;
xlim([f_min, f_max]);

% Clearly mark the bandwidth with a shaded region and vertical lines
y_lims = ylim;
patch([f_zoom(l2) f_zoom(l1) f_zoom(l1) f_zoom(l2)], [y_lims(1) y_lims(1) y_lims(2) y_lims(2)], 'g', 'FaceAlpha', 0.2, 'EdgeColor', 'none');
xline(f_zoom(l2), 'k--', 'LineWidth', 1.5);
xline(f_zoom(l1), 'k--', 'LineWidth', 1.5);

% Add a double-headed arrow for bandwidth
y_pos = y_lims(1) + 0.15 * (y_lims(2) - y_lims(1));
plot([f_zoom(l2), f_zoom(l1)], [y_pos, y_pos], 'k-', 'LineWidth', 2);
plot(f_zoom(l2), y_pos, 'k<', 'MarkerFaceColor', 'k', 'MarkerSize', 8);
plot(f_zoom(l1), y_pos, 'k>', 'MarkerFaceColor', 'k', 'MarkerSize', 8);
text(mean([f_zoom(l2), f_zoom(l1)]), y_pos + 0.08 * (y_lims(2) - y_lims(1)), sprintf('Bandwidth = %.1f Hz', bw), 'HorizontalAlignment', 'center', 'FontWeight', 'bold', 'BackgroundColor', 'w', 'EdgeColor', 'k');

title(sprintf('Frequency-Domain ZOOMED | Dominant Freq: %.1f Hz | Bandwidth Calculation', dominant_freq));
xlabel('Frequency (Hz)');
ylabel('PSD');
grid on;

output_img = 'C:\Users\gorke\.gemini\antigravity-ide\brain\e1650f41-21c9-4f66-bd63-a6f32140d912\transient_bandwidth_plot.png';
saveas(fig, output_img);
fprintf('Plot saved to %s\n', output_img);
