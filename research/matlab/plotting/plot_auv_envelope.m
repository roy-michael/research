% plot_auv_envelope.m
% Reads the AUV Leg 1 recording, removes the DC offset, computes the upper and lower envelopes
% of the calibrated signal using block max/min, and plots them in an interactive figure window.

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
    
    fprintf('Data loaded. Total samples: %d. Applying calibration...\n', length(y_all));
    y_cal = y_all * calibFactor;
    clear y_all; % Free raw data memory
    
    % Apply DC offset removal to center the signal at 0
    fprintf('Removing DC offset...\n');
    y_cal = y_cal - mean(y_cal);
    
    % Create Time vector
    t = (0:length(y_cal)-1)' / fs;
    
    fprintf('Computing upper and lower peak envelopes (optimized block max/min)...\n');
    % Compute peak envelopes using block-wise max/min for speed (interval = 200 samples)
    peak_interval = 200;
    num_blocks = floor(length(y_cal) / peak_interval);
    
    % Reshape and compute max/min on columns
    y_reshaped = reshape(y_cal(1 : num_blocks * peak_interval), peak_interval, num_blocks);
    env_up_ds = max(y_reshaped, [], 1)';
    env_lo_ds = min(y_reshaped, [], 1)';
    
    % Downsample the raw data and time vector to match the envelopes
    y_ds = y_cal(1 : peak_interval : num_blocks * peak_interval);
    t_ds = t(1 : peak_interval : num_blocks * peak_interval);
    
    fprintf('Setting up interactive plot...\n');
    fig = figure('Name', 'AUV Leg 1 Amplitude Envelopes (DC Removed)', 'Position', [150, 100, 1400, 700]);
    ax = axes('Parent', fig);
    hold(ax, 'on');
    
    % Plot raw signal in light grey
    plot(ax, t_ds, y_ds, 'Color', [0.85 0.85 0.85], 'LineWidth', 0.5, 'DisplayName', 'Signal');
    
    % Plot upper envelope in vibrant green (matching AUV Leg 1 styling)
    plot(ax, t_ds, env_up_ds, 'Color', [0.4660 0.6740 0.1880], 'LineWidth', 1.5, 'DisplayName', 'Upper Envelope');
    
    % Plot lower envelope in a warm contrast color
    plot(ax, t_ds, env_lo_ds, 'Color', [0.9290 0.6940 0.1250], 'LineWidth', 1.5, 'DisplayName', 'Lower Envelope');
    
    hold(ax, 'off');
    grid(ax, 'on');
    axis(ax, 'tight');
    
    xlabel(ax, 'Time [sec]');
    ylabel(ax, 'Amplitude [\muPa]');
    title(ax, 'AUV Leg 1 Recording - Signal Envelopes (DC Removed, Time Domain)');
    legend(ax, 'Location', 'northeast');
    
    % Enable native zoom/pan interaction automatically
    zoom(fig, 'on');
    
    fprintf('Interactive plot is live!\n');
    
catch e
    fprintf('An error occurred: %s\n', e.message);
    disp(e.getReport());
end
