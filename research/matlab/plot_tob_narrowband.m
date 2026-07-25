% plot_tob_narrowband.m
% Performs narrowband Welch PSD analysis and One-Third-Octave Band (TOB / decidecade)
% filtering (IEC 61260) from 50 Hz to 40 kHz over the entire run time.
% Computes both the mean level and the temporal standard deviation of the decidecade bands
% (calculated second-by-second) and plots them in a 3-panel figure.

% Resolve output directory relative to script folder
script_dir = fileparts(mfilename('fullpath'));
output_dir = fullfile(script_dir, '..', 'output');

DATASETS = {
    'C:\Users\Roy\Recordings\Garda_2_26\2_Deep Water\Electric', 'Garda_Electric_DWL';
    'C:\Users\Roy\Recordings\Garda_2_26\2_Deep Water\Petrol', 'Garda_Petrol_DWL';
    'C:\Users\Roy\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692\leg1_straight_line_2_8m_s_6922_827-837.wav', 'AUV_Leg1_DWL';
    'C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_2_snake', 'Croatia_2407_2_DWL';
    'C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2307_free', 'Croatia_2307_free_DWL'
};

% Calibration factor (conversion to micro-Pascals)
calibFactor = 1e6;

% Define 1/3-octave band center frequencies (IEC 61260) from 50 Hz to 40 kHz
fc_standard = [50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, ...
               1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, ...
               10000, 12500, 16000, 20000, 25000, 31500, 40000];

tob_results = struct();
nb_results = struct();

for d = 1:size(DATASETS, 1)
    PATH_OR_DIR = DATASETS{d, 1};
    DATASET_NAME = DATASETS{d, 2};
    clean_name = regexprep(DATASET_NAME, '[^\w]', '_');
    
    fprintf('Processing entire run for %s...\n', DATASET_NAME);
    
    % Concatenate all files for the entire run
    if exist(PATH_OR_DIR, 'dir')
        files = dir(fullfile(PATH_OR_DIR, '*.wav'));
        [~, sortIdx] = sort({files.name});
        files = files(sortIdx);
        
        % Calculate total samples
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
            [y, ~] = audioread(file_path);
            if size(y, 2) > 1, y = mean(y, 2); end
            num_s = length(y);
            y_all(current_idx : current_idx + num_s - 1) = y;
            current_idx = current_idx + num_s;
        end
        fs = sample_rate;
    else
        % Single file
        [y_all, fs] = audioread(PATH_OR_DIR);
        if size(y_all, 2) > 1, y_all = mean(y_all, 2); end
    end
    
    % Calibration
    y_cal = y_all * calibFactor;
    clear y_all; % Free memory
    
    % Limit to first 120 seconds to prevent Out of Memory in pwelch
    max_samples = 120 * fs;
    if length(y_cal) > max_samples
        y_cal = y_cal(1:max_samples);
    end
    
    % 1. Narrowband Welch PSD (16384 window, 50% overlap, over entire run)
    fprintf('  Computing Narrowband Welch PSD...\n');
    windowLength = 16384; 
    noverlap = windowLength / 2;
    [psd_est, freq_psd] = pwelch(y_cal, windowLength, noverlap, windowLength, fs, 'power');
    
    idx_band = (freq_psd >= 50 & freq_psd <= 40000);
    f_nb = freq_psd(idx_band);
    psd_nb_db = 10 * log10(psd_est(idx_band));
    
    nb_results.(clean_name).freq = f_nb;
    nb_results.(clean_name).psd = psd_nb_db;
    
    % 2. Second-by-second decidecade band level calculation
    fprintf('  Calculating second-by-second decidecade levels...\n');
    % Segment into non-overlapping 1-second chunks (fs samples each)
    num_seconds = floor(length(y_cal) / fs);
    y_cal_reshaped = reshape(y_cal(1 : num_seconds * fs), fs, num_seconds);
    
    % Prepare storage for each second's TOB levels
    second_tob_levels = zeros(length(fc_standard), num_seconds);
    f_ratio = 2^(1/6);
    
    for s = 1:num_seconds
        % Compute Welch PSD for this 1 second segment
        [psd_sec, freq_sec] = pwelch(y_cal_reshaped(:, s), 4096, 2048, 4096, fs, 'power');
        df_sec = freq_sec(2) - freq_sec(1);
        
        for f = 1:length(fc_standard)
            fc = fc_standard(f);
            f_low = fc / f_ratio;
            f_high = fc * f_ratio;
            
            idx_tob = (freq_sec >= f_low & freq_sec <= f_high);
            band_power = sum(psd_sec(idx_tob)) * df_sec;
            second_tob_levels(f, s) = 10 * log10(band_power + eps);
        end
    end
    
    % Calculate mean and standard deviation across time (columns)
    mean_tob_levels = mean(second_tob_levels, 2);
    std_tob_levels = std(second_tob_levels, 0, 2);
    
    tob_results.(clean_name).fc = fc_standard;
    tob_results.(clean_name).mean_levels = mean_tob_levels;
    tob_results.(clean_name).std_levels = std_tob_levels;
end

% Export computed results to JSON
export_data = struct('narrowband', nb_results, 'tob', tob_results);
json_str = jsonencode(export_data);
fid = fopen(fullfile(output_dir, 'garda_auv_tob_data.json'), 'w');
fprintf(fid, '%s', json_str);
fclose(fid);
fprintf('Saved garda_auv_tob_data.json to output directory\n');

% -------------------------------------------------------------
% 3. Plotting Comparative Plots
% -------------------------------------------------------------
colors = [
    0.0000 0.4470 0.7410; % Blue (Electric DWL)
    0.8500 0.3250 0.0980; % Orange (Petrol DWL)
    0.4660 0.6740 0.1880; % Green (AUV Leg 1 DWL)
    0.4940 0.1840 0.5560; % Purple (Croatia 2407_2 DWL)
    0.9290 0.6940 0.1250  % Yellow-orange (Croatia 2307 free DWL)
];

lineStyles = {'-', '-', ':', '--', '--'};
markers = {'o', 's', '^', 'd', 'x'};

fig = figure('Name', 'Narrowband PSD & Decidecade Band Analysis', 'Position', [100, 100, 1400, 1100], 'Visible', 'off');

log_ticks = [50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000, 40000];
log_labels = {'50 Hz', '100 Hz', '200 Hz', '500 Hz', '1 kHz', '2 kHz', '5 kHz', '10 kHz', '20 kHz', '40 kHz'};

% --- Subplot 1: Narrowband PSD ---
ax1 = subplot(3, 1, 1, 'Parent', fig);
hold(ax1, 'on');
fields = fieldnames(nb_results);
for i = 1:length(fields)
    fn = fields{i};
    col = colors(mod(i-1, 5)+1, :);
    ls = lineStyles{mod(i-1, 5)+1};
    
    if strcmp(fn, 'Garda_Electric_DWL')
        displayName = 'Garda Electric (DWL, 16 kts, away)';
    elseif strcmp(fn, 'Garda_Petrol_DWL')
        displayName = 'Garda Petrol (DWL, 4 kts, away)';
    elseif strcmp(fn, 'AUV_Leg1_DWL')
        displayName = 'AUV Leg 1 (DWL, 5.4 kts, straight)';
    elseif strcmp(fn, 'Croatia_2407_2_DWL')
        displayName = 'Croatia 2407_2 (snake route)';
    elseif strcmp(fn, 'Croatia_2307_free_DWL')
        displayName = 'Croatia 2307 (freediving Suex VR, 2.1 kts)';
    else
        displayName = strrep(fn, '_', ' ');
    end
    
    plot(ax1, nb_results.(fn).freq, nb_results.(fn).psd, 'Color', col, 'LineStyle', ls, 'LineWidth', 1.2, 'DisplayName', displayName);
end
hold(ax1, 'off');
grid(ax1, 'on');
set(ax1, 'XScale', 'linear'); 
xlim(ax1, [50, 40000]);
xlabel(ax1, 'Frequency [Hz] (Linear Scale)');
ylabel(ax1, 'PSD [dB re 1 \muPa^2/Hz]');
title(ax1, 'Narrowband Welch PSD (16384 window, 50% overlap, entire run)');
legend(ax1, 'Location', 'northeast');

% --- Subplot 2: Decidecade Band (TOB) Mean Levels ---
ax2 = subplot(3, 1, 2, 'Parent', fig);
hold(ax2, 'on');
for i = 1:length(fields)
    fn = fields{i};
    col = colors(mod(i-1, 5)+1, :);
    ls = lineStyles{mod(i-1, 5)+1};
    mk = markers{mod(i-1, 5)+1};
    
    if strcmp(fn, 'Garda_Electric_DWL')
        displayName = 'Garda Electric (DWL, 16 kts, away)';
    elseif strcmp(fn, 'Garda_Petrol_DWL')
        displayName = 'Garda Petrol (DWL, 4 kts, away)';
    elseif strcmp(fn, 'AUV_Leg1_DWL')
        displayName = 'AUV Leg 1 (DWL, 5.4 kts, straight)';
    elseif strcmp(fn, 'Croatia_2407_2_DWL')
        displayName = 'Croatia 2407_2 (snake route)';
    elseif strcmp(fn, 'Croatia_2307_free_DWL')
        displayName = 'Croatia 2307 (freediving Suex VR, 2.1 kts)';
    else
        displayName = strrep(fn, '_', ' ');
    end
    
    plot(ax2, fc_standard, tob_results.(fn).mean_levels, 'Color', col, 'LineStyle', ls, 'LineWidth', 1.5, ...
         'Marker', mk, 'MarkerFaceColor', col, 'MarkerSize', 5, 'DisplayName', displayName);
end
hold(ax2, 'off');
grid(ax2, 'on');
set(ax2, 'XScale', 'linear');
xlim(ax2, [50, 40000]);
xlabel(ax2, 'Decidecade Band Center Frequency [Hz] (Linear Scale)');
ylabel(ax2, 'SPL [dB re 1 \muPa]');
title(ax2, 'Decidecade Band Levels (TOB Mean, IEC 61260, second-by-second)');
legend(ax2, 'Location', 'northeast');

% --- Subplot 3: Standard Deviation of Decidecade Band Levels ---
ax3 = subplot(3, 1, 3, 'Parent', fig);
hold(ax3, 'on');
for i = 1:length(fields)
    fn = fields{i};
    col = colors(mod(i-1, 5)+1, :);
    ls = lineStyles{mod(i-1, 5)+1};
    mk = markers{mod(i-1, 5)+1};
    
    if strcmp(fn, 'Garda_Electric_DWL')
        displayName = 'Garda Electric (DWL, 16 kts, away)';
    elseif strcmp(fn, 'Garda_Petrol_DWL')
        displayName = 'Garda Petrol (DWL, 4 kts, away)';
    elseif strcmp(fn, 'AUV_Leg1_DWL')
        displayName = 'AUV Leg 1 (DWL, 5.4 kts, straight)';
    elseif strcmp(fn, 'Croatia_2407_2_DWL')
        displayName = 'Croatia 2407_2 (snake route)';
    elseif strcmp(fn, 'Croatia_2307_free_DWL')
        displayName = 'Croatia 2307 (freediving Suex VR, 2.1 kts)';
    else
        displayName = strrep(fn, '_', ' ');
    end
    
    plot(ax3, fc_standard, tob_results.(fn).std_levels, 'Color', col, 'LineStyle', ls, 'LineWidth', 1.5, ...
         'Marker', mk, 'MarkerFaceColor', col, 'MarkerSize', 5, 'DisplayName', displayName);
end
hold(ax3, 'off');
grid(ax3, 'on');
set(ax3, 'XScale', 'linear');
xlim(ax3, [50, 40000]);
xlabel(ax3, 'Decidecade Band Center Frequency [Hz] (Linear Scale)');
ylabel(ax3, 'Standard Deviation [dB]');
title(ax3, 'Standard Deviation of Decidecade Band Levels (Temporal Variability)');
legend(ax3, 'Location', 'northeast');

% Save output plot
saveas(fig, fullfile(output_dir, 'garda_auv_tob_comparison.png'));
fprintf('Saved garda_auv_tob_comparison.png to output directory\n');
close(fig);
