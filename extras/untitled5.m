% 1. Setup and Extract Dataset Name
dataDir = 'D:\RoyStudies\Recordings\Ashdod\boat_exp';
cleanDir = dataDir;
if endsWith(cleanDir, filesep), cleanDir = cleanDir(1:end-1); end
[~, datasetName, ~] = fileparts(cleanDir); 

% 2. Dynamic Frequency Bounds
if contains(datasetName, 'boat')
    f_min = 120;
    f_max = 220;
elseif contains(datasetName, 'scooter')
    f_min = 400;
    f_max = 1000;
else
    error('Unknown dataset. Cannot assign frequency bounds.');
end

% 3. List and Chronologically Sort Files
files = dir(fullfile(dataDir, '*.wav'));
if isempty(files), error('No .wav files found.'); end

% Sort alphanumerically to guarantee chronological order
fileNames = {files.name};
[~, sortIdx] = sort(fileNames);
files = files(sortIdx);

% 4. Filter Noisy Scooter Files
if contains(datasetName, 'scooter')
    targetFile = 'record_20260824_123438.wav';
    startIdx = 1;
    for i = 1:length(files)
        if strcmp(files(i).name, targetFile)
            startIdx = i; % Start processing exactly from this file onward
            break;
        end
    end
    files = files(startIdx:end);
end

% 5. Process the First Valid File
filePath = fullfile(dataDir, files(1).name);
[signal, fs] = audioread(filePath);

% Safe Channel Selection
if size(signal, 2) > 1
    channel_power = rms(signal, 1);
    [~, best_idx] = max(channel_power);
    signal = signal(:, best_idx);
end

% 6. Spectrogram and Constrained Ridge Tracking
window_size = round(fs * 0.1); 
noverlap = round(window_size * 0.9);
nfft = 65536;
[S, F, T] = spectrogram(signal, window_size, noverlap, nfft, fs);
P = abs(S).^2;

% --- 1. Find the continuous fundamental using the time-averaged spectrum ---
% Average the power across all time bins
mean_P = mean(P, 2); 

% Look only within the broad expected band
broad_idx = find(F >= f_min & F <= f_max);

% The absolute maximum in the average spectrum will be the continuous scooter tonal, 
% because the transient 660Hz beep harmonic averages out over time.
[~, max_broad_idx] = max(mean_P(broad_idx));
estimated_fundamental = F(broad_idx(max_broad_idx));

% --- 2. Create a dynamic, tight tracking corridor ---
% A +/- 30 Hz margin is plenty for a drifting motor, but tight enough to exclude the 660Hz harmonic
dynamic_margin = 30; 
f_min_dynamic = estimated_fundamental - dynamic_margin;
f_max_dynamic = estimated_fundamental + dynamic_margin;

valid_idx = find(F >= f_min_dynamic & F <= f_max_dynamic);

% --- 3. Track strictly within the tight corridor ---
[~, local_max_idx] = max(P(valid_idx, :), [], 1); 
global_max_idx = valid_idx(local_max_idx);
raw_track = F(global_max_idx);

% 4. Smooth and Calculate Delta F (Proceed as normal)
smooth_track = medfilt1(raw_track, 50);
center_f = median(smooth_track);
delta_f = prctile(abs(smooth_track - center_f), 95);

% Calculate Modulating Frequency (fm)
mod_signal = smooth_track - center_f;
dt = T(2) - T(1);
track_fs = 1 / dt;
N = length(mod_signal);
mod_fft = abs(fft(mod_signal));
half_idx = floor(N/2);
mod_fft = mod_fft(1:half_idx);
mod_freqs = (0:half_idx-1) * (track_fs / N);
[~, peak_idx] = max(mod_fft(2:end));
f_m = mod_freqs(peak_idx + 1);

carson_bw = 2 * (delta_f + f_m);

fprintf('Dataset: %s\n', datasetName);
fprintf('File: %s\n', files(1).name);
fprintf('Bounds: %d Hz - %d Hz\n', f_min, f_max);
fprintf('Tracked Center Freq: %.2f Hz\n', center_f);
fprintf('Carson Bandwidth: %.2f Hz (Delta f: %.2f Hz, fm: %.2f Hz)\n', carson_bw, delta_f, f_m);