
files = [
    % "C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_2_snake\merged_output.wav"
    "C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_1_600m\merged_output.wav"
    % "C:\Users\Roy\Recordings\hear_my_ship\V1\Motor Boats\Motorboat_08.08.23_142223_20secCPA.wav"
    % "C:\\Users\\Roy\\Recordings\\hear_my_ship\\V1\\Motor Boats\\Motorboat_08.08.23_132757_20secCPA.wav"
    ];

[data_scooter, sr_scooter] = audioread("C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_1_600m\RBW6737_20250724_093000.wav");
% [data2, sr2] = audioread("C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_1_600m\RBW6737_20250724_093100.wav");
[data_ship, sr_ship] = audioread("C:\Users\Roy\Recordings\hear_my_ship\V1\Motor Boats\Motorboat_08.08.23_142223_20secCPA.wav");

[P, Q] = rat(sr_ship / sr_scooter);
buffer_resampled = resample(data_scooter, P, Q);

duration = 20;
num_samples = duration * sr_ship;

buffer_resampled = buffer_resampled(1:num_samples, :);
data_ship = data_ship(1:num_samples, :);

read_and_process(buffer_resampled, sr_ship, 'Scooter');
read_and_process(data_ship, sr_ship, 'Motor Boat');


function read_and_process(data, sr, name)
nperseg = 1024 * 32; % Increased window size for better true frequency resolution
window = hann(nperseg);
noverlap = round(nperseg * 0.9); % Round to integer
nfft = nperseg * 4; % Zero-padding for a much finer frequency grid

[psd, freqs] = pwelch(data, window, noverlap, nfft, sr);

% Truncate to 0-2000 Hz
idx = freqs <= 2000;
freqs = freqs(idx);
psd = psd(idx);

figure('Position', [100, 100, 800, 480]);
plot(freqs, psd, 'Color', 'blue', 'LineWidth', 1.5);

title("Power Spectral Density (" + name + ")");
xlabel("Frequency (Hz)");
ylabel("Power/Frequency (Density)");

grid on;
grid minor;
xlim([0, 2000]);

% Get spectrogram data and truncate
[s, f, t] = spectrogram(data, window, noverlap, nfft, sr);
idx_s = f <= 2000;
s = s(idx_s, :);
f = f(idx_s);

figure('Position', [150, 150, 800, 480]);
imagesc(t, f, 10*log10(abs(s).^2));
axis xy; % Ensure y-axis goes from bottom to top
title("Spectrogram (" + name + ")");
xlabel("Time (s)");
ylabel("Frequency (Hz)");
colormap jet;
end