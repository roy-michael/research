dataset_path = 'D:\RoyStudies\Recordings\Ashdod\scooter_exp';

% class_path = fullfile(dataset_path, class_name);    
files = dir(fullfile(dataset_path, '*.wav'));
duration = 10;

% fig = figure('Name', 'AUV Dominant Frequency (Centroid) Histograms', 'Position', [100, 100, 1200, 800]);

for j = 1:length(files)
    file_path = fullfile(dataset_path, files(j).name);
    try
        [data, fs] = audioread(file_path);
        x_axis = linspace(-fs/2, fs/2, duration * fs);
        num_samples = duration * fs;
        duration_short = 1.0; 
        
        for i = 1:size(data, 2)
            samples_short = min(length(data), floor(duration_short * fs));
            y_short = data(1:samples_short, i);
            
            % dd = fftshift(abs(fft(dd)));            
            % figure;plot(x_axis, dd, 'b-', 'LineWidth', 1.5);
            
            % 2. Downsample aggressively (e.g., to 8000 Hz)
            target_sr = 8000;
            if fs > target_sr
                [P, Q] = rat(target_sr / fs);
                y_short = resample(y_short, P, Q);
            end

            % 3. NOW run the ambiguity function
            % y_short is now only 4,000 samples, which creates a tiny 128MB array instead of 6.8TB!
            [afmag, delay, doppler] = ambgfun(y_short, target_sr, 1.0);

            % 4. Plot the surface
            figure;
            contour(delay, doppler, afmag);
            xlabel('Delay (seconds)');
            ylabel('Doppler Shift (Hz)');
            title('Auto-Ambiguity Function (0.5s chunk, 8kHz)');
            
            % plot_2(dd, fs);
        end
    catch ME
        fprintf('  Failed %s: %s\n', files(j).name, ME.message);
        centroids(j) = NaN;
        bandwidths(j) = NaN;
    end
end


% read_and_process(data_scooter, sr_ship, 'Scooter');
% read_and_process(data_ship, sr_ship, 'Motor Boat');

function read_and_process(data, sr, name)

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

function plot_2(data, sr)
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
    
    % Use a lighter grey [0.8 0.8 0.8] so the raw spectrum doesn't hide the envelopes
    plot(Faxis, data_mag, 'Color', [0.8 0.8 0.8]); 
    hold on;
    plot(Faxis, envelope_upper, 'r', 'LineWidth', 2); 
    plot(Faxis, envelope_lower, 'b', 'LineWidth', 2); 
    
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