close;clc;clear all;

files = [
    % "C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_2_snake\merged_output.wav"
    "D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2407_1_600m.wav"
    % "C:\Users\Roy\Recordings\hear_my_ship\V1\Motor Boats\Motorboat_08.08.23_142223_20secCPA.wav"
    % "C:\\Users\\Roy\\Recordings\\hear_my_ship\\V1\\Motor Boats\\Motorboat_08.08.23_132757_20secCPA.wav"
    ];

[data_scooter, sr_scooter] = audioread("D:\RoyStudies\Recordings\Croatia\Ocean Sonics\2407_1_600m\RBW6737_20250724_093000.wav");
[data_ship, sr_ship] = audioread("D:\RoyStudies\Recordings\hear-my-ship\V1\Motor Boats\Motorboat_08.08.23_142223_20secCPA.wav");


duration = 10;
num_samples = duration * sr_ship;

data_scooter = resample_and_split(data_scooter, sr_scooter, sr_ship, duration);
data_ship = resample_and_split(data_ship, sr_ship, sr_ship, duration);

plot_1(data_scooter, sr_ship, 'Scooter');
plot_welch(data_scooter, sr_scooter, "Scooter");

plot_1(data_ship, sr_ship, 'Motor Boat');
plot_welch(data_ship, sr_ship, 'Motor Boat');



% read_and_process(data_scooter, sr_ship, 'Scooter');
% read_and_process(data_ship, sr_ship, 'Motor Boat');


function plot_welch(data, sr, name)
    nperseg = 1024 * 16;
    window = hann(nperseg); 
    noverlap = nperseg / 2;
    
    [psd, freqs] = pwelch(data, window, noverlap, nperseg, sr);
    
    figure('Position', [100, 100, 800, 480]);
    % semilogy(freqs, psd, 'Color', 'blue', 'LineWidth', 1.5);
    plot(freqs, psd, 'Color', 'blue', 'LineWidth', 1.5);
    
    title("Power Spectral Density (" + name + ")");
    xlabel("Frequency (Hz)");
    ylabel("Power/Frequency (Density)");
    
    grid on;
    grid minor;

    xlim([0, sr / 2]); 
end


function result = resample_and_split(data, sr_orig, sr_target, duration)

    if sr_orig > sr_target
        [P, Q] = rat(sr_target / sr_orig);
        data = resample(data, P, Q);
    end

    num_samples = duration * sr_target;

    result = data(1:num_samples, :);
end

function plot_1(data, sr, name)
    data_mag = fftshift(abs(fft(data)));
    
    % Ensure data is a column vector so Faxis length matches perfectly
    if size(data_mag, 2) > 1, data_mag = data_mag'; end
    
    Faxis = linspace(-sr / 2, sr / 2, length(data));
    
    % 4. Plot both lines cleanly on the same figure using Faxis
    figure;
    plot(Faxis, data_mag, 'Color', [0.7 0.7 0.7]); % Draw spectrum in grey
    hold on;
    % plot(Faxis, spectral_envelope_true, 'r', 'LineWidth', 2); % Envelope in red
    
    title("Magnitude Spectrum & Spectral Envelope (" + name + ")");    
    xlabel('Frequency (Hz)');
    ylabel('Magnitude');
    xlim([-sr/2, sr/2]);
end

function plot_2(data, sr)
    data_mag = fftshift(abs(fft(data)));
    
    % Ensure data is a column vector so Faxis length matches perfectly
    if size(data_mag, 2) > 1, data_mag = data_mag'; end
    
    Faxis = linspace(-sr / 2, sr / 2, length(data));
    
    % 1. Find the peaks and their index locations
    [peaks, locs] = findpeaks(data_mag);
    
    % CRITICAL FIX: Convert index locations to actual Frequency values
    peak_freqs = Faxis(locs);
    
    % 2. Interpolate using matching frequency coordinates
    spectral_envelope_true = interp1(peak_freqs, peaks, Faxis, 'spline');
    
    % 3. Prevent the spline from dipping below zero
    spectral_envelope_true = max(spectral_envelope_true, 0);
    
    % 4. Plot both lines cleanly on the same figure using Faxis
    figure;
    plot(Faxis, data_mag, 'Color', [0.7 0.7 0.7]); % Draw spectrum in grey
    hold on;
    plot(Faxis, spectral_envelope_true, 'r', 'LineWidth', 2); % Envelope in red
    
    title('Magnitude Spectrum & Spectral Envelope');
    xlabel('Frequency (Hz)');
    ylabel('Magnitude');
    xlim([-sr/2, sr/2]);
end

function plot_3(data, sr)
    data_mag = fftshift(abs(fft(data)));
    
    if size(data_mag, 2) > 1, data_mag = data_mag'; end
    
    Faxis = linspace(-sr / 2, sr / 2, length(data));
    
    % Smooth out the tracing by forcing a minimum distance between peaks/valleys
    min_dist = 50; 
    
    % --- 1. UPPER ENVELOPE ---
    [peaks, locs_max] = findpeaks(data_mag, 'MinPeakDistance', min_dist);
    peak_freqs = Faxis(locs_max);
    
    % Use 'pchip' to prevent mathematical overshooting
    envelope_upper = interp1(peak_freqs, peaks, Faxis, 'pchip');
    envelope_upper = max(envelope_upper, 0);
    
    % --- 2. LOWER ENVELOPE ---
    [~, locs_min] = findpeaks(-data_mag, 'MinPeakDistance', min_dist); 
    valleys = data_mag(locs_min); 
    valley_freqs = Faxis(locs_min);
    
    envelope_lower = interp1(valley_freqs, valleys, Faxis, 'pchip');
    envelope_lower = max(envelope_lower, 0);
    
    % --- 3. FIND INTERSECTIONS ---
    % Subtract lower from upper. When the sign changes, they have crossed.
    delta = envelope_upper - envelope_lower;
    
    % diff(sign(delta)) is non-zero exactly where the curves cross
    cross_idx = find(diff(sign(delta)) ~= 0);
    
    % Get the coordinates of the intersections
    intersect_freqs = Faxis(cross_idx);
    intersect_mags = (envelope_upper(cross_idx) + envelope_lower(cross_idx)) / 2;
    
    % --- 4. PLOTTING ---
    figure;

    % Save handles (h1, h2, h3) for the plots
    h1 = plot(Faxis, data_mag, 'Color', [0.8 0.8 0.8]); 
    hold on;
    h2 = plot(Faxis, envelope_upper, 'r', 'LineWidth', 2); 
    h3 = plot(Faxis, envelope_lower, 'b', 'LineWidth', 2); 

    title('Cleaned Spectrum with PCHIP Envelopes');
    xlabel('Frequency (Hz)');
    ylabel('Magnitude');
    xlim([-sr/2, sr/2]);

    % Conditionally plot intersections and build the legend
    if ~isempty(intersect_freqs)
        h4 = plot(intersect_freqs, intersect_mags, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 6);
        legend([h1, h2, h3, h4], 'Magnitude Spectrum', 'Upper Envelope', 'Lower Envelope', 'Intersections');
    else
        % If no intersections exist, only label the first three handles
        legend([h1, h2, h3], 'Magnitude Spectrum', 'Upper Envelope', 'Lower Envelope');
    end
    % Plot intersections as solid black circles
    if ~isempty(intersect_freqs)
        plot(intersect_freqs, intersect_mags, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 6);
    end
    
    title('Cleaned Spectrum with PCHIP Envelopes & Intersections');
    xlabel('Frequency (Hz)');
    ylabel('Magnitude');
    xlim([-sr/2, sr/2]);
    legend('Magnitude Spectrum', 'Upper Envelope', 'Lower Envelope', 'Intersections');
end