% plot_croatia_snake_spectrogram.m
% Reads all WAV files directly under the 2407_2_snake folder 
% (ignoring the "out" subfolder) and plots a high-resolution, low-noise LOFAR gram.
% Employs time-integration averaging to suppress noise while maintaining sharp frequency lines.

% Resolve paths relative to script location
script_dir = fileparts(mfilename('fullpath'));
output_dir = fullfile(script_dir, '..', 'output');
dir_path = 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\2407_2_snake';

fprintf('Listing WAV files directly in: %s\n', dir_path);
all_files = dir(fullfile(dir_path, '*.wav'));

if isempty(all_files)
    error('No WAV files found in %s', dir_path);
end

% Sort files alphabetically by name to ensure chronological concatenation
[~, sortIdx] = sort({all_files.name});
files = all_files(sortIdx);

fprintf('Found %d WAV files directly in folder. Concatenating...\n', length(files));

% Pre-calculate total samples
total_samples = 0;
sample_rate = [];
for i = 1:length(files)
    info = audioinfo(fullfile(files(i).folder, files(i).name));
    total_samples = total_samples + info.TotalSamples;
    if i == 1
        sample_rate = info.SampleRate;
    end
end

fprintf('Total samples to load: %d. Loading audio data...\n', total_samples);
data = zeros(total_samples, 1);
current_idx = 1;

for i = 1:length(files)
    file_path = fullfile(files(i).folder, files(i).name);
    fprintf('  Reading [%d/%d]: %s\n', i, length(files), files(i).name);
    [y, fs] = audioread(file_path);
    if size(y, 2) > 1
        y = mean(y, 2);
    end
    num_samples = length(y);
    data(current_idx : current_idx + num_samples - 1) = y;
    current_idx = current_idx + num_samples;
end

% Remove non-finite values
data = data(isfinite(data));
% Apply calibration (to uPa)
calibFactor = 1e6;
data_cal = data * calibFactor;
clear data; % Free raw data memory

% -------------------------------------------------------------
% LOFAR Gram Computation
% -------------------------------------------------------------
fprintf('Computing LOFAR gram...\n');
nfft = 16384; % Large NFFT for high frequency resolution
noverlap = round(nfft * 0.90); % 90% overlap
step_size = nfft - noverlap;
window = hann(nfft);

total_len = length(data_cal);
total_cols = fix((total_len - noverlap) / step_size);

% Time and Frequency vectors
T = ((0:total_cols-1) * step_size + nfft/2) / sample_rate;
[~, F, ~, ~] = spectrogram(data_cal(1:nfft), window, noverlap, nfft, sample_rate);

% Target OpenGL size compression to avoid rendering crashes
target_shape = [8000, 8000];
step_y = max(1, floor(length(F) / target_shape(1)));
step_x = max(1, floor(total_cols / target_shape(2)));

pad_y = mod(-length(F), step_y);
num_y_bins = (length(F) + pad_y) / step_y;

if step_y > 1
    F_padded = [F; F(end) * ones(pad_y, 1)];
    F = mean(reshape(F_padded, step_y, num_y_bins), 1)';
end

% Pre-allocate compressed spectrogram matrix
Sxx_dB = zeros(num_y_bins, total_cols, 'single');
cols_per_chunk = 500;
col_idx = 1;

fprintf('Processing chunks (Total time bins: %d)...\n', total_cols);
while col_idx <= total_cols
    cols_to_do = min(cols_per_chunk, total_cols - col_idx + 1);
    start_sample = (col_idx - 1) * step_size + 1;
    end_sample = start_sample + nfft - 1 + (cols_to_do - 1) * step_size;
    
    chunk_data = data_cal(start_sample:end_sample);
    [~, ~, ~, P_chunk] = spectrogram(chunk_data, window, noverlap, nfft, sample_rate);
    S_chunk_dB = 10 * log10(P_chunk + eps);
    
    if step_y > 1
        if pad_y > 0
            pad_val = min(S_chunk_dB(:));
            S_chunk_dB = [S_chunk_dB; pad_val * ones(pad_y, size(S_chunk_dB, 2), 'single')];
        end
        S_chunk_dB = reshape(S_chunk_dB, step_y, num_y_bins, cols_to_do);
        S_chunk_dB = reshape(max(S_chunk_dB, [], 1), num_y_bins, cols_to_do);
    end
    
    Sxx_dB(:, col_idx : col_idx + cols_to_do - 1) = single(S_chunk_dB);
    col_idx = col_idx + cols_to_do;
end

% --- LOFAR Time-Integration (Averaging along time axis) ---
fprintf('Applying LOFAR time integration...\n');
Sxx_dB = movmean(Sxx_dB, 12, 2); % 12-frame moving average along the time dimension

% Downsample time axis for safe rendering if needed
if step_x > 1
    fprintf('Downsampling time axis (%dx%d)...\n', size(Sxx_dB, 1), size(Sxx_dB, 2));
    display_data = Sxx_dB(:, 1:step_x:end);
    T_display = T(1:step_x:end);
else
    display_data = Sxx_dB;
    T_display = T;
end

% Optimal contrast calculation
sub_Sxx = display_data(1:10:end, 1:10:end);
sorted_Sxx = sort(sub_Sxx(:));
len = length(sorted_Sxx);
min_dB = sorted_Sxx(max(1, round(len * 0.15)));
max_dB = sorted_Sxx(max(1, round(len * 0.999)));

% --- Plotting ---
fprintf('Rendering figure...\n');
fig = figure('Name', 'Croatia Snake LOFAR Gram', 'Position', [100, 100, 1200, 700], 'Visible', 'off');
ax = axes(fig);
imagesc(ax, [T_display(1), T_display(end)], [F(1)/1000, F(end)/1000], display_data);
axis(ax, 'xy');
axis(ax, 'tight');
ylim(ax, [0, 4]); % Focus on 0 to 4 kHz range

try colormap(ax, 'viridis'); catch, colormap(ax, 'parula'); end
try clim(ax, double([min_dB, max_dB])); catch, caxis(ax, double([min_dB, max_dB])); end

ylabel(ax, 'Frequency [kHz]');
xlabel(ax, 'Time [sec]');
title(ax, 'Croatia Snake LOFAR Gram (Excluding "out" Folder, NFFT=16384, Integrated)');
cb = colorbar(ax);
cb.Label.String = 'Power/Frequency (dB re 1\muPa^2/Hz)';

% Save image
saveas(fig, fullfile(output_dir, 'croatia_snake_spectrogram.png'));
fprintf('Saved croatia_snake_spectrogram.png to output directory\n');
close(fig);
