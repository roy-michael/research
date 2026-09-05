% =========================================================================
% Main Script: Focused Auto-Ambiguity Analysis
% =========================================================================
dataset_path = 'D:\RoyStudies\Recordings\Ashdod\scooter_exp';
files = dir(fullfile(dataset_path, '*.wav'));

duration = 10;
duration_short = 0.5; % Analyze 0.5s chunks to keep computation fast

% CRITICAL: Create ONE figure outside the loop to prevent graphics memory crashes
hFig = figure('Name', 'Focused Ambiguity', 'Position', [100, 100, 800, 600]);
% Create a second figure to avoid overwriting your contour plot
hFigTime = figure('Name', 'Time Domain Analysis', 'Position', [920, 100, 800, 480]);

for j = 1:length(files)
    file_path = fullfile(dataset_path, files(j).name);
    
    try
        [data, fs] = audioread(file_path);
        
        % Iterate through channels (stereo/mono)
        for i = 1:size(data, 2)
            samples_short = min(length(data), floor(duration_short * fs));
            y_short = data(1:samples_short, i); 
            
            % --- 1. Find the dominant frequency ---
            y_short = y_short - mean(y_short); % Remove DC offset
            
            N = length(y_short);
            Y = fft(y_short);
            Faxis = (0:N-1) * (fs / N);
            
            min_freq = 100;  
            max_freq = 2000; 
            
            start_idx = find(Faxis >= min_freq, 1); 
            end_idx = find(Faxis <= max_freq, 1, 'last');
            
            search_window = abs(Y(start_idx:end_idx));
            
            % Sort by prominence
            [pks, locs] = findpeaks(search_window, 'MinPeakProminence', mean(search_window)*2, 'SortStr', 'descend');
            
            if ~isempty(locs)
                max_idx_offset = locs(1); 
            else
                [~, max_idx_offset] = max(search_window);
            end
            
            f_dom = Faxis(max_idx_offset + start_idx - 1);
            
            % --- 2. Bandpass Filter around f_dom ---
            % Instead of basebanding, we just isolate a 400 Hz window around the motor
            low_cutoff = max(20, f_dom - 200);
            high_cutoff = min(fs/2 - 100, f_dom + 200);
            
            bp_filt = designfilt('bandpassiir', 'FilterOrder', 4, ...
                'HalfPowerFrequency1', low_cutoff, ...
                'HalfPowerFrequency2', high_cutoff, ...
                'SampleRate', fs);
            
            y_filt = filtfilt(bp_filt, y_short);
            
            % --- 3. Downsample to 4000 Hz ---
            % 4000 Hz yields 0.25ms resolution (perfect for echoes) and prevents memory crashes
            target_sr = 4000;
            if fs > target_sr
                [P, Q] = rat(target_sr / fs);
                y_filt = resample(y_filt, P, Q);
            end
            
            % --- 4. Run Ambiguity Function ---
            prf = 1 / duration_short; % For 0.5s, PRF = 2.0
            [afmag, delay, doppler] = ambgfun(y_filt, target_sr, prf);
            
            % --- 5. Plot securely in the reused figure ---
            figure(hFig); 
            clf; 
            
            % Zoom in on the relevant Doppler shift (-100 to +100 Hz)
            contour(delay, doppler, afmag);
            ylim([-100, 100]); 
            
            xlabel('Delay (seconds)');
            ylabel('Doppler Shift (Hz)');
            title(sprintf('File: %s (f_{dom} = %.1f Hz)', files(j).name, f_dom));
            
            drawnow; 
            
            clear y_filt Y afmag delay doppler;
        end
        
    catch ME
        fprintf('  Failed %s: %s\n', files(j).name, ME.message);
    end
end

disp('Processing Complete.');


% =========================================================================
% Auxiliary Functions
% =========================================================================

function read_and_process(data, sr, name)
    nperseg = 1024 * 16;
    window = hann(nperseg); 
    noverlap = nperseg / 2;
    
    [psd, freqs] = pwelch(data, window, noverlap, nperseg, sr);
    
    figure('Position', [100, 100, 800, 480]);
    plot(freqs, psd, 'Color', 'blue', 'LineWidth', 1.5);
    
    title("Power Spectral Density (" + name + ")");
    xlabel("Frequency (Hz)");
    ylabel("Power/Frequency (Density)");
    grid on; grid minor;
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
    min_dist = 50; 
    
    % Upper Envelope
    [peaks, locs_max] = findpeaks(data_mag, 'MinPeakDistance', min_dist);
    peak_freqs = Faxis(locs_max);
    envelope_upper = interp1(peak_freqs, peaks, Faxis, 'pchip');
    envelope_upper = max(envelope_upper, 0);
    
    % Lower Envelope
    [~, locs_min] = findpeaks(-data_mag, 'MinPeakDistance', min_dist); 
    valleys = data_mag(locs_min); 
    valley_freqs = Faxis(locs_min);
    envelope_lower = interp1(valley_freqs, valleys, Faxis, 'pchip');
    envelope_lower = max(envelope_lower, 0);
    
    % Intersections
    delta = envelope_upper - envelope_lower;
    cross_idx = find(diff(sign(delta)) ~= 0);
    intersect_freqs = Faxis(cross_idx);
    intersect_mags = (envelope_upper(cross_idx) + envelope_lower(cross_idx)) / 2;
    
    % Plotting
    figure;
    h1 = plot(Faxis, data_mag, 'Color', [0.8 0.8 0.8]); hold on;
    h2 = plot(Faxis, envelope_upper, 'r', 'LineWidth', 2); 
    h3 = plot(Faxis, envelope_lower, 'b', 'LineWidth', 2); 
    
    title('Cleaned Spectrum with PCHIP Envelopes');
    xlabel('Frequency (Hz)');
    ylabel('Magnitude');
    xlim([-sr/2, sr/2]);
    
    if ~isempty(intersect_freqs)
        h4 = plot(intersect_freqs, intersect_mags, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 6);
        legend([h1, h2, h3, h4], 'Magnitude Spectrum', 'Upper Envelope', 'Lower Envelope', 'Intersections');
    else
        legend([h1, h2, h3], 'Magnitude Spectrum', 'Upper Envelope', 'Lower Envelope');
    end
end