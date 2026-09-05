
% 1. Define directory and extract the dataset name
dataDir = 'D:\RoyStudies\Recordings\Ashdod\boat_exp';

% Strip trailing slash if present to ensure fileparts works correctly
cleanDir = dataDir;
if endsWith(cleanDir, filesep)
    cleanDir = cleanDir(1:end-1);
end

% Extract the last folder name in the path
[~, datasetName, ~] = fileparts(cleanDir); 

% 2. Load the files
files = dir(fullfile(dataDir, '*.wav'));

if isempty(files)
    error('No .wav files found in %s', dataDir);
end

filePath = fullfile(dataDir, files(1).name);
[signal, fs] = audioread(filePath);

% 3. Safe Channel Selection (Avoid Destructive Interference)
if size(signal, 2) > 1
    channel_power = rms(signal, 1);
    [~, best_channel_idx] = max(channel_power);
    signal = signal(:, best_channel_idx);
end


% Optional: You may want to highpass filter here to remove heavy low-frequency 
% wave noise before calculating the spectrogram.

% 2. Compute the Spectrogram (STFT)
% Use a 100ms window to balance frequency resolution and time resolution
window_size = round(fs * 0.1); 
noverlap = round(window_size * 0.9); % 90% overlap for smooth tracking
nfft = 4096; % Zero-padding to interpolate frequency bins

[S, F, T] = spectrogram(signal, window_size, noverlap, nfft, fs);
P = abs(S).^2; % Convert to Power Spectrum

% 3. Extract the dominant frequency track (Ridge Tracking)
% Find the index of the maximum power bin for every single time step
[~, max_idx] = max(P, [], 1); 
raw_track = F(max_idx);

% 4. Smooth the track
% A median filter removes sudden noise spikes (e.g. transient clicks) 
% without blurring the actual frequency shifts of the scooter motor.
smooth_track = medfilt1(raw_track, 50);

% 5. Find Peak Frequency Deviation (Delta f) directly from the track
center_f = median(smooth_track);
delta_f = prctile(abs(smooth_track - center_f), 95);

% 6. Find Modulating Frequency (f_m)
mod_signal = smooth_track - center_f;

% CRITICAL: The sample rate of this track is the STFT update rate, NOT the audio fs!
dt = T(2) - T(1);
track_fs = 1 / dt;

N = length(mod_signal);
mod_fft = abs(fft(mod_signal));
half_idx = floor(N/2);
mod_fft = mod_fft(1:half_idx);

% Calculate frequency bins using the new track_fs
mod_freqs = (0:half_idx-1) * (track_fs / N);

% Ignore DC offset (index 1) by starting at index 2
[~, peak_idx] = max(mod_fft(2:end));
f_m = mod_freqs(peak_idx + 1);


% 4. Updated Output Print Statements
fprintf('Dataset: %s\n', datasetName);
fprintf('File: %s\n', files(1).name);

if exist('best_channel_idx', 'var')
    fprintf('Channel Used: %d (Highest RMS)\n', best_channel_idx);
end

% 7. Apply Carson's Rule
carson_bw = 2 * (delta_f + f_m);

fprintf('Tracked Center Freq: %.2f Hz\n', center_f);
fprintf('Carson Bandwidth: %.2f Hz (Delta f: %.2f Hz, fm: %.2f Hz)\n', carson_bw, delta_f, f_m);


% (Assuming you have already calculated 'mod_fft' and 'f_m' from the previous script)

% 1. Calculate the background "noise floor" of the frequency track
% We use the median of the FFT to ignore the dominant peaks
jitter_noise_floor = median(mod_fft(2:end)); 

% 2. Find the power of the dominant modulation peak
peak_power = max(mod_fft(2:end));

% 3. Calculate Modulation SNR (Linear scale)
fm_snr = peak_power / jitter_noise_floor;

% 4. Decision Logic
% A threshold of 5 to 10 is usually robust for underwater acoustics.
% If the peak is 8x stronger than the random jitter, it is undeniably FM.
fm_threshold = 8.0; 

fprintf('Modulation SNR: %.2f\n', fm_snr);

if fm_snr > fm_threshold
    disp('Result: CONFIRMED FM MODULATED.');
    fprintf('The signal is systematically modulated at %.2f Hz.\n', f_m);
else
    disp('Result: NO MODULATION DETECTED.');
    disp('The frequency variations are likely just random ocean noise jitter.');
end
