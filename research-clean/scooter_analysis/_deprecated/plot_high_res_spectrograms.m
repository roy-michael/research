% Script to plot high resolution spectrograms for a directory of files as a single continuous recording
clear; close all; clc;

%% Configuration Parameters
cfg = struct();
cfg.target_dir = 'D:\RoyStudies\Recordings\DepartmentalCruise-2025-06-12\icListen\wav';
cfg.recursive_search = false;  % Set to true to search all subdirectories
cfg.target_fs = 8000;          % Target sampling rate for processing (Hz)
cfg.window_dur_sec = 1.00;     % Window duration in seconds (e.g. 0.1 gives 10Hz freq resolution)
cfg.overlap_ratio = 0.90;      % Overlap ratio for smooth time axis (0 to 1)
cfg.f_low = 100;               % Lower frequency bound to plot (Hz)
cfg.f_high = 2000;             % Upper frequency bound to plot (Hz)
cfg.nfft = [];                 % Custom NFFT size. Leave empty `[]` to auto-calculate (recommended)
cfg.remove_transients = true;  % Erase vertical broadband clicks using a horizontal median filter
cfg.transient_filter_width = 10; % Number of time-pixels to look across when filtering transients
cfg.prctile_clip = 99.5;       % Percentile for upper color limit contrast (e.g. 99.5)

%% Setup
if cfg.recursive_search
    files = dir(fullfile(cfg.target_dir, '**', '*.wav'));
else
    files = dir(fullfile(cfg.target_dir, '*.wav'));
end

if isempty(files)
    fprintf('No WAV files found in %s\n', cfg.target_dir);
    return;
end

% Sort chronologically just in case
[~, sort_idx] = sort({files.name});
files = files(sort_idx);

out_dir = fullfile(fileparts(mfilename('fullpath')), 'output', 'spectrograms');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

%% Process Files into Continuous Array
fprintf('Loading and downsampling %d files into a single continuous array...\n', length(files));
continuous_sig = [];

for i = 1:length(files)
    filepath = fullfile(files(i).folder, files(i).name);
    
    try
        info = audioinfo(filepath);
    catch ME
        fprintf('WARNING: Skipping corrupted file %s (%s)\n', files(i).name, ME.message);
        continue;
    end
    
    sig = audioread(filepath);
    if size(sig, 2) > 1
        sig = mean(sig, 2);
    end
    sig = sig - mean(sig);
    
    % Decimate the signal
    fs = info.SampleRate;
    if fs > cfg.target_fs
        [p_res, q_res] = rat(cfg.target_fs / fs);
        sig = resample(sig, p_res, q_res);
    end
    
    continuous_sig = [continuous_sig; sig];
    
    if mod(i, 20) == 0
        fprintf('  Loaded %d/%d files...\n', i, length(files));
    end
end

fs = cfg.target_fs; % Final sample rate of the continuous array
total_mins = (length(continuous_sig) / fs) / 60;
fprintf('Finished loading. Total continuous duration: %.2f minutes.\n', total_mins);
fprintf('Computing massive high-resolution spectrogram...\n');

%% High Resolution Spectrogram
window = round(fs * cfg.window_dur_sec);
noverlap = round(window * cfg.overlap_ratio);

if isempty(cfg.nfft)
    nfft = 2^nextpow2(window * 2);
else
    nfft = cfg.nfft;
end

[~, f, t, p] = spectrogram(continuous_sig, window, noverlap, nfft, fs);

% Filter out frequencies outside our band of interest
f_mask = (f >= cfg.f_low) & (f <= cfg.f_high);
f_band = f(f_mask);
p_band = p(f_mask, :);

figure('Name', 'Continuous Spectrogram', 'Position', [100, 100, 1800, 600], 'Color', 'w');

% Convert to dB
p_db = 10 * log10(p_band + eps);

% --- TRANSIENT NOISE REMOVAL ---
if cfg.remove_transients
    fprintf('Applying median filter to erase vertical transient spikes...\n');
    p_db = medfilt1(p_db, cfg.transient_filter_width, [], 2);
end

% --- SPECTRAL WHITENING (STATIONARY AMBIENT DENOISING) ---
median_profile = median(p_db, 2);
p_db_clean = bsxfun(@minus, p_db, median_profile);

% Set floor to 0 to completely black out background noise
p_db_clean(p_db_clean < 0) = 0;

% Clip color limits for contrast
p_max = prctile(p_db_clean(:), cfg.prctile_clip);
if p_max <= 0; p_max = 1; end % safety fallback

% Parse start time from the first file name (e.g. RBW6922_20250612_060000.wav)
try
    parts = split(files(1).name, '_');
    date_str = parts{2};
    time_str = parts{3}(1:6);
    start_time_datenum = datenum([date_str time_str], 'yyyymmddHHMMSS');
catch
    fprintf('Could not parse time from filename %s. Using relative time.\n', files(1).name);
    start_time_datenum = 0;
end

% Convert relative time t (seconds) to absolute MATLAB days
t_abs = start_time_datenum + (t / 86400);

imagesc(t_abs, f_band, p_db_clean);
axis xy;
caxis([0, p_max]);
colormap jet;

ylim([cfg.f_low, cfg.f_high]);

c = colorbar;
c.Label.String = 'Relative Power (dB above median)';

title(sprintf('Continuous High Resolution Spectrogram (%d files)', length(files)), 'FontSize', 14);

% Format the x-axis to show HH:MM time
if start_time_datenum > 0
    datetick('x', 'HH:MM', 'keepticks', 'keeplimits');
    xlabel('Time (UTC)', 'FontSize', 12);
else
    xlabel('Time (seconds)', 'FontSize', 12);
end
ylabel('Frequency (Hz)', 'FontSize', 12);

out_file = fullfile(out_dir, 'continuous_spectrogram.png');
exportgraphics(gcf, out_file, 'Resolution', 300);
close(gcf);

fprintf('Saved continuous spectrogram: %s\n', out_file);

%% Extract and Plot Dominant Frequency & Bandwidth from Spectrogram
fprintf('Extracting dominant frequency and bandwidth directly from the spectrogram matrix...\n');
num_cols = size(p_db_clean, 2);
dom_freqs = zeros(1, num_cols);
bandwidths = zeros(1, num_cols);

for col = 1:num_cols
    col_data = p_db_clean(:, col);
    [max_val, max_idx] = max(col_data);
    
    if max_val > 0
        dom_freqs(col) = f_band(max_idx);
        
        % Measure -3dB Bandwidth around the peak
        thresh = max_val - 3;
        
        left_idx = max_idx;
        while left_idx > 1 && col_data(left_idx) >= thresh
            left_idx = left_idx - 1;
        end
        
        right_idx = max_idx;
        while right_idx < length(col_data) && col_data(right_idx) >= thresh
            right_idx = right_idx + 1;
        end
        
        bandwidths(col) = f_band(right_idx) - f_band(left_idx);
    else
        % If pixel column is empty (e.g. no signal above noise floor)
        dom_freqs(col) = NaN;
        bandwidths(col) = NaN;
    end
end

% Apply a mild median filter to smooth the tracking lines
dom_freqs = medfilt1(dom_freqs, cfg.transient_filter_width, 'omitnan');
bandwidths = medfilt1(bandwidths, cfg.transient_filter_width, 'omitnan');

% Plot the tracking data
figure('Name', 'Frequency & BW Tracking', 'Position', [150, 150, 1400, 800], 'Color', 'w');

subplot(2,1,1);
plot(t_abs, dom_freqs, 'b-', 'LineWidth', 1.5);
if start_time_datenum > 0
    datetick('x', 'HH:MM', 'keepticks', 'keeplimits');
end
grid on;
ylim([cfg.f_low, cfg.f_high]);
ylabel('Dominant Frequency (Hz)', 'FontSize', 12);
title('Dominant Lobe Frequency Tracking', 'FontSize', 14);

subplot(2,1,2);
plot(t_abs, bandwidths, 'r-', 'LineWidth', 1.5);
if start_time_datenum > 0
    datetick('x', 'HH:MM', 'keepticks', 'keeplimits');
    xlabel('Time (UTC)', 'FontSize', 12);
else
    xlabel('Time (seconds)', 'FontSize', 12);
end
grid on;
ylim([0, 100]); % Assuming bandwidth of narrowband tonals rarely exceeds 100Hz
ylabel('Bandwidth (Hz)', 'FontSize', 12);
title('-3dB Bandwidth Tracking', 'FontSize', 14);

out_file_bw = fullfile(out_dir, 'continuous_freq_bw_plot.png');
exportgraphics(gcf, out_file_bw, 'Resolution', 300);
close(gcf);

fprintf('Saved frequency and bandwidth graph: %s\n', out_file_bw);
