% plot_croatia_envelope.m
% Reads the entire run of Croatia 2407_1 recordings, removes the DC offset,
% computes the upper and lower envelopes of the calibrated signal using block max/min,
% and plots them in an interactive figure window.

% Resolve paths relative to script location
script_dir = fileparts(mfilename('fullpath'));
output_dir = fullfile(script_dir, '..', 'output');

DIR_PATH = 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\2407_2_snake';
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

    fprintf('Found %d WAV files. Concatenating...\n', length(files));

    % Pre-calculate total samples
    total_samples = 0;
    sample_rate = [];
    for i = 1:length(files)
        info = audioinfo(fullfile(files(i).folder, files(i).name));
        total_samples = total_samples + info.TotalSamples;
        if i == 1, sample_rate = info.SampleRate; end
    end

    y_all = zeros(total_samples, 1);
    current_idx = 1;

    for i = 1:length(files)
        file_path = fullfile(files(i).folder, files(i).name);
        fprintf('  Reading [%d/%d]: %s\n', i, length(files), files(i).name);
        [y, fs] = audioread(file_path);
        if size(y, 2) > 1
            y = mean(y, 2);
        end
        num_samples = length(y);
        y_all(current_idx : current_idx + num_samples - 1) = y;
        current_idx = current_idx + num_samples;
    end

    fs = sample_rate;
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
    fig = figure('Name', 'Croatia 2407_1 Amplitude Envelopes (DC Removed)', 'Position', [200, 100, 1400, 700]);
    ax = axes('Parent', fig);
    hold(ax, 'on');

    % Plot raw signal in light grey
    plot(ax, t_ds, y_ds, 'Color', [0.85 0.85 0.85], 'LineWidth', 0.5, 'DisplayName', 'Signal');

    % Plot upper envelope in vibrant purple (matching Croatia 2407_1 styling)
    plot(ax, t_ds, env_up_ds, 'Color', [0.4940 0.1840 0.5560], 'LineWidth', 1.5, 'DisplayName', 'Upper Envelope');

    % Plot lower envelope in warm yellow-orange
    plot(ax, t_ds, env_lo_ds, 'Color', [0.9290 0.6940 0.1250], 'LineWidth', 1.5, 'DisplayName', 'Lower Envelope');

    hold(ax, 'off');
    grid(ax, 'on');
    axis(ax, 'tight');

    xlabel(ax, 'Time [sec]');
    ylabel(ax, 'Amplitude [\muPa]');
    title(ax, 'Croatia 2407\_1 Recording - Signal Envelopes (DC Removed, Time Domain)');
    legend(ax, 'Location', 'northeast');

    % Enable native zoom/pan interaction automatically
    zoom(fig, 'on');

    fprintf('Interactive plot is live!\n');

catch e
    fprintf('An error occurred: %s\n', e.message);
    disp(e.getReport());
end
