% plot_lofar_full.m
DIR_PATH = 'C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_1_600m';
files = dir(fullfile(DIR_PATH, '*.wav'));
if isempty(files), error('No .wav files found'); end
[~, sortIdx] = sort({files.name});
files = files(sortIdx);

fprintf('Scanning %d files to determine total size...\n', length(files));
total_samples = 0;
for i = 1:length(files)
    info = audioinfo(fullfile(files(i).folder, files(i).name));
    total_samples = total_samples + info.TotalSamples;
    if i == 1, fs = info.SampleRate; end
end

fprintf('Loading continuous timeline (%.1f minutes)...\n', total_samples / fs / 60);
continuous_data = zeros(total_samples, 1, 'single');
current_idx = 1;
for i = 1:length(files)
    [y, ~] = audioread(fullfile(files(i).folder, files(i).name));
    if size(y, 2) > 1, y = mean(y, 2); end
    continuous_data(current_idx : current_idx + length(y) - 1) = single(y);
    current_idx = current_idx + length(y);
end

% Convert to uPa
calibFactor = 1e6;
continuous_data = continuous_data * calibFactor;

fprintf('Applying high-pass filter (150 Hz) to reduce noise...\n');
[b, a] = butter(4, 150 / (fs/2), 'high');
continuous_data = filtfilt(b, a, double(continuous_data));

% LOFAR parameters: Ultra-high frequency resolution (0.5 Hz)
window_len = fs * 2; 
nfft = fs * 2; 
window = hann(window_len);
noverlap = round(window_len * 0.85);
step_size = window_len - noverlap;

% Compute frequency vector to determine index limit
F = (0:nfft/2)' * (fs/nfft);
freq_idx = find(F <= 3500); % Only keep 0 to 3500 Hz
F_lofar = F(freq_idx);

total_cols = floor((total_samples - window_len) / step_size) + 1;
% Decimate time axis to limit image width to ~4000 pixels
time_downsample = max(1, floor(total_cols / 4000));
final_cols = ceil(total_cols / time_downsample);

fprintf('Pre-allocating spectrogram matrix (%d freqs x %d time bins)...\n', length(freq_idx), final_cols);
Sxx_dB_lofar = zeros(length(freq_idx), final_cols, 'single');

fprintf('Computing LOFAR spectrogram in chunks...\n');
current_col = 1;
chunk_cols = 1000; % Process 1000 overlapping windows at a time
for col_start = 1:chunk_cols:total_cols
    col_end = min(col_start + chunk_cols - 1, total_cols);
    cols_to_do = col_end - col_start + 1;
    
    start_sample = (col_start - 1) * step_size + 1;
    end_sample = start_sample + window_len - 1 + (cols_to_do - 1) * step_size;
    
    % Compute spectrogram for chunk
    [~, ~, ~, P_chunk] = spectrogram(continuous_data(start_sample:end_sample), window, noverlap, nfft, fs);
    
    % Crop to target frequencies and convert to dB
    P_lofar = P_chunk(freq_idx, :);
    P_dB = 10 * log10(P_lofar + eps);
    
    % Downsample in time by taking every Nth column
    downsampled_P = P_dB(:, 1:time_downsample:end);
    
    % Insert into final matrix
    cols_inserted = size(downsampled_P, 2);
    Sxx_dB_lofar(:, current_col : current_col + cols_inserted - 1) = downsampled_P;
    current_col = current_col + cols_inserted;
    
    fprintf('  Processed %d / %d windows (%.1f%%)\n', col_end, total_cols, (col_end/total_cols)*100);
end

% Plotting
fprintf('Rendering plot...\n');
figure('Position', [100, 100, 1600, 600]);
time_axis = linspace(0, total_samples/fs/60, current_col - 1); % in minutes

% Note: imagesc displays y-axis top-down by default, 'axis xy' flips it
imagesc(time_axis, F_lofar, Sxx_dB_lofar(:, 1:current_col-1));
axis xy;
ylim([0 3500]);
ylabel('Frequency (Hz)');
xlabel('Time (Minutes)');
title('Full Timeline LOFAR Spectrogram (Ultra-Res, Denoised)');
colormap jet;

% Dynamic noise thresholding
c = clim;
clim([c(1)+15, c(2)-5]);
colorbar;

saveas(gcf, 'lofar_plot_full.png');
fprintf('Saved lofar_plot_full.png successfully!\n');
