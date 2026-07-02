% plot_lofar.m
dirPath = 'C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_1_600m';
fileName = 'RBW6737_20250724_091100.wav';
fullFilePath = fullfile(dirPath, fileName);

fprintf('Loading audio data for LOFAR gram: %s\n', fileName);
[data, fs] = audioread(fullFilePath);

% Convert to uPa
calibFactor = 1e6;
data_uPa = data * calibFactor;

% Reduce noise by applying a High-Pass Filter (< 150 Hz)
% This eliminates ocean rumble, preventing the colormap from being skewed by massive low-frequency energy.
fprintf('Applying high-pass filter to reduce ambient noise...\n');
[b, a] = butter(4, 150 / (fs/2), 'high');
data_uPa_filtered = filtfilt(b, a, data_uPa);

% LOFAR parameters: Ultra-high frequency resolution
% Using nfft = fs * 2 gives exactly 0.5 Hz frequency resolution
nfft = fs * 2; 
window_len = fs * 2; % 2 second coherent integration window
window = hann(window_len);
noverlap = round(window_len * 0.85); % 85% overlap for smooth temporal continuity

fprintf('Computing ultra-high-resolution LOFAR spectrogram...\n');
figure('Position', [100, 100, 1200, 600]);

% Spectrogram computes and plots directly
spectrogram(data_uPa_filtered, window, noverlap, nfft, fs, 'yaxis');

% Constrain the y-axis to the region of interest (0 to 3.5 kHz)
ylim([0 3.5]); 
title(sprintf('LOFAR Spectrogram (Ultra-Res, Denoised): %s', fileName), 'Interpreter', 'none');
colormap jet;

% Dynamically clamp the colormap to reduce background visual noise
c = clim;
clim([c(1)+10, c(2)-5]); % Raise the noise floor and lower the ceiling slightly for high contrast

saveas(gcf, 'lofar_plot.png');
fprintf('Saved lofar_plot.png\n');
