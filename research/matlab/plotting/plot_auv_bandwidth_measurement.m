% plot_auv_bandwidth_measurement.m
% Computes the Narrowband Welch PSD and its local moving average envelope for the AUV Leg 1 recording,
% automatically detects the most prominent spectral peak, identifies all the envelope 
% intersection boundaries, and plots them across the full 50 Hz - 4 kHz frequency range.

% Resolve paths relative to script location
script_dir = fileparts(mfilename('fullpath'));
output_dir = fullfile(script_dir, '..', '..', 'output', 'AUV');

FILE_PATH = 'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692\leg1_straight_line_2_8m_s_6922_827-837.wav';
calibFactor = 1e6; % Calibration factor (conversion to micro-Pascals)

try
    fprintf('Reading WAV file: %s\n', FILE_PATH);
    if ~exist(FILE_PATH, 'file')
        error('File not found: %s', FILE_PATH);
    end
    
    [y_all, fs] = audioread(FILE_PATH);
    if size(y_all, 2) > 1
        y_all = mean(y_all, 2);
    end
    
    y_cal = y_all * calibFactor;
    y_cal = y_cal - mean(y_cal); % Remove DC offset
    clear y_all; % Free raw data memory
    
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
    
    fig = figure('Name', 'AUV Bandwidth Boundaries via Envelope Intersections', 'Position', [150, 100, 1400, 800]);
    ax = axes('Parent', fig);
    hold(ax, 'on');
    
    % Plot original PSD (thin line, green styled for AUV)
    plot(ax, f_nb, psd_nb_db, 'Color', [0.4660 0.6740 0.1880], 'LineWidth', 1.0, 'DisplayName', 'Welch PSD');
    
    % Plot envelope (dashed orange line)
    plot(ax, f_nb, psd_env, 'Color', [0.9290 0.6940 0.1250], 'LineStyle', '--', 'LineWidth', 1.5, 'DisplayName', 'Moving Average Envelope');
    
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
    title(ax, 'AUV Leg 1 Welch PSD & Moving Average Envelope with Intersection Boundaries (50 Hz - 4 kHz)');
    legend(ax, 'Location', 'northeast');
    
    % Enable zoom
    zoom(fig, 'on');
    
    fprintf('Full range AUV bandwidth boundary plot is live!\n');
    
catch e
    fprintf('An error occurred: %s\n', e.message);
    disp(e.getReport());
end
