% plot_bandwidth_measurement.m
% Computes the Narrowband Welch PSD and its local moving average envelope for the Garda Electric recording,
% automatically detects the most prominent spectral peak, identifies all the envelope 
% intersection boundaries, and plots them across the full 50 Hz - 4 kHz frequency range.

% Resolve paths relative to script location
script_dir = fileparts(mfilename('fullpath'));
output_dir = fullfile(script_dir, '..', 'output');

DIR_PATH = 'D:\RoyStudies\Recordings\Garda_2_26\2_Deep Water\Electric';
calibFactor = 1e6; % Calibration factor (conversion to micro-Pascals)

try
    fprintf('Listing WAV files in: %s\n', DIR_PATH);
    files = dir(fullfile(DIR_PATH, '*.wav'));
    if isempty(files)
        error('No WAV files found in %s', DIR_PATH);
    end
    
    % Sort files alphabetically by name
    [~, sortIdx] = sort({files.name});
    files = files(sortIdx);
    
    % Use the first file for quick computation and clear peak visualization
    file_path = fullfile(files(1).folder, files(1).name);
    fprintf('Reading first file for bandwidth analysis: %s\n', files(1).name);
    [y, fs] = audioread(file_path);
    if size(y, 2) > 1
        y = mean(y, 2);
    end
    
    y_cal = y * calibFactor;
    y_cal = y_cal - mean(y_cal); % Remove DC offset
    clear y;
    
    % Compute high resolution Welch PSD (65536 window)
    fprintf('Computing high-resolution Welch PSD...\n');
    windowLength = 65536; 
    noverlap = windowLength / 2;
    [psd_est, freq_psd] = pwelch(y_cal, windowLength, noverlap, windowLength, fs, 'power');
    
    % Restrict analysis range to 50 Hz - 4 kHz
    idx_band = (freq_psd >= 50 & freq_psd <= 4000);
    f_nb = freq_psd(idx_band);
    psd_nb_db = 10 * log10(psd_est(idx_band));
    
    % Compute a moving average envelope of the PSD curve (local background noise floor)
    % A window of 151 frequency bins provides a smooth local reference
    fprintf('Computing local moving average envelope...\n');
    psd_env = movmean(psd_nb_db, 151);
    
    % Find all intersection points where PSD crosses its moving average
    diff_sig = psd_nb_db - psd_env;
    intersect_idx = find(diff_sig(1:end-1) .* diff_sig(2:end) <= 0);
    intersect_freqs = f_nb(intersect_idx);
    intersect_vals = psd_nb_db(intersect_idx);
    
    fprintf('Total intersection points found: %d\n', length(intersect_freqs));
    
    % Auto-detect the most prominent peak in the range (e.g. between 100 Hz and 2000 Hz)
    peak_range_idx = (f_nb >= 100 & f_nb <= 2000);
    f_subset = f_nb(peak_range_idx);
    psd_subset = psd_nb_db(peak_range_idx);
    
    % Find local peaks
    [pks, locs] = findpeaks(psd_subset, f_subset, 'MinPeakDistance', 10, 'SortStr', 'descend');
    if isempty(pks)
        error('No peaks found in the specified range.');
    end
    
    % Use the highest peak for reference
    peak_freq = locs(1);
    peak_val = pks(1);
    
    fprintf('Detected Prominent Peak at: %.2f Hz (%.2f dB)\n', peak_freq, peak_val);
    
    fig = figure('Name', 'Bandwidth Boundaries via Envelope Intersections', 'Position', [100, 100, 1400, 800]);
    ax = axes('Parent', fig);
    hold(ax, 'on');
    
    % Plot original PSD (thin line)
    plot(ax, f_nb, psd_nb_db, 'Color', [0.0000 0.4470 0.7410], 'LineWidth', 1.0, 'DisplayName', 'Welch PSD');
    
    % Plot envelope (dashed orange line)
    plot(ax, f_nb, psd_env, 'Color', [0.8500 0.3250 0.0980], 'LineStyle', '--', 'LineWidth', 1.5, 'DisplayName', 'Moving Average Envelope');
    
    % Highlight all intersection boundaries in the 50 Hz - 4 kHz range
    if ~isempty(intersect_freqs)
        plot(ax, intersect_freqs, intersect_vals, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 4.5, 'DisplayName', 'Bandwidth Boundaries');
    end
    
    % Highlight the primary detected peak
    plot(ax, peak_freq, peak_val, 'gp', 'MarkerFaceColor', 'g', 'MarkerSize', 12, 'DisplayName', 'Primary Peak');
    
    hold(ax, 'off');
    grid(ax, 'on');
    xlim(ax, [50, 4000]);
    
    % Labels & annotations
    xlabel(ax, 'Frequency [Hz]');
    ylabel(ax, 'PSD [dB re 1 \muPa^2/Hz]');
    title(ax, 'Welch PSD & Moving Average Envelope with Intersection Boundaries (50 Hz - 4 kHz)');
    legend(ax, 'Location', 'northeast');
    
    % Enable zoom
    zoom(fig, 'on');
    
    fprintf('Full range bandwidth boundary plot is live!\n');
    
catch e
    fprintf('An error occurred: %s\n', e.message);
    disp(e.getReport());
end
