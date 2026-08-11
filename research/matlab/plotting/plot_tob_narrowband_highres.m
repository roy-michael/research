% plot_tob_narrowband_highres.m
% Performs narrowband Welch PSD analysis (with high frequency resolution) and One-Third-Octave Band (TOB / decidecade)
% filtering (IEC 61260) from 50 Hz to 20 kHz over the entire run time.
% This version excludes the Petrol dataset, increases the frequency resolution,
% leaves only the Welch PSD, Zoomed Welch PSD (0-4 kHz), Reflection Envelope PSD (showing intersections), and STD subplots, and uses linear rulers.

% Resolve output directory relative to script folder
script_dir = fileparts(mfilename('fullpath'));
output_dir = fullfile(script_dir, '..', '..', 'output', 'garda');

DATASETS = {
    'D:\RoyStudies\Recordings\Garda_2_26\2_Deep Water\Electric', 'Garda_Electric_DWL';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692\leg1_straight_line_2_8m_s_6922_827-837.wav', 'AUV_Leg1_DWL';
    'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\2407_2_snake', 'Croatia_2407_2_DWL';
    'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\2307_free', 'Croatia_2307_free_DWL'
};

% Calibration factor (conversion to micro-Pascals)
calibFactor = 1e6;

% Define 1/3-octave band center frequencies (IEC 61260) from 50 Hz to 20 kHz
fc_standard = [50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, ...
               1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, ...
               10000, 12500, 16000, 20000];

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
    
    % 1. Narrowband Welch PSD (65536 window for higher frequency resolution, 50% overlap)
    fprintf('  Computing Narrowband Welch PSD...\n');
    windowLength = 65536; 
    noverlap = windowLength / 2;
    [psd_est, freq_psd] = pwelch(y_cal, windowLength, noverlap, windowLength, fs, 'power');
    
    idx_band = (freq_psd >= 50 & freq_psd <= 20000);
    f_nb = freq_psd(idx_band);
    psd_nb_db = 10 * log10(psd_est(idx_band));
    
    % Compute reflection envelope of the PSD using Hilbert transform (with DC bias offset correction)
    psd_mean = mean(psd_nb_db);
    psd_env = abs(hilbert(psd_nb_db - psd_mean)) + psd_mean;
    
    % Calculate intersection points (zero-crossings of original PSD and its envelope)
    diff_sig = psd_nb_db - psd_env;
    intersect_idx = find(diff_sig(1:end-1) .* diff_sig(2:end) <= 0);
    
    nb_results.(clean_name).freq = f_nb;
    nb_results.(clean_name).psd = psd_nb_db;
    nb_results.(clean_name).envelope = psd_env;
    nb_results.(clean_name).intersect_freq = f_nb(intersect_idx);
    nb_results.(clean_name).intersect_val = psd_nb_db(intersect_idx);
    
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
fid = fopen(fullfile(output_dir, 'garda_auv_tob_data_highres.json'), 'w');
fprintf(fid, '%s', json_str);
fclose(fid);
fprintf('Saved garda_auv_tob_data_highres.json to output directory\n');

% -------------------------------------------------------------
% 3. Plotting Comparative Plots
% -------------------------------------------------------------

fig = figure('Name', 'Narrowband PSD & Decidecade Band Analysis', 'Position', [100, 100, 1400, 1500], 'Visible', 'off');

% Define high density ticks/labels for linear rulers up to 20 kHz (every 1 kHz or 2 kHz)
ruler_ticks = [50, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000, 11000, 12000, 13000, 14000, 15000, 16000, 17000, 18000, 19000, 20000];
ruler_labels = {'50', '1k', '2k', '3k', '4k', '5k', '6k', '7k', '8k', '9k', '10k', '11k', '12k', '13k', '14k', '15k', '16k', '17k', '18k', '19k', '20k'};

% Define ticks/labels for zoomed 0-4 kHz plot
zoom_ticks = [50, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000];
zoom_labels = {'50', '500', '1k', '1.5k', '2k', '2.5k', '3k', '3.5k', '4k'};

% Helper function to get style settings for consistency
get_style = @(name) helper_get_style(name);

% --- Subplot 1: Narrowband Welch PSD (Full 20 kHz) ---
ax1 = subplot(4, 1, 1, 'Parent', fig);
hold(ax1, 'on');
fields = fieldnames(nb_results);
for i = 1:length(fields)
    fn = fields{i};
    style = get_style(fn);
    plot(ax1, nb_results.(fn).freq, nb_results.(fn).psd, 'Color', style.color, 'LineStyle', style.linestyle, 'LineWidth', 1.2, 'DisplayName', style.displayName);
end
hold(ax1, 'off');
grid(ax1, 'on');
set(ax1, 'XScale', 'linear'); 
xlim(ax1, [50, 20000]);
set(ax1, 'XTick', ruler_ticks);
set(ax1, 'XTickLabel', ruler_labels);
xlabel(ax1, 'Frequency [Hz] (Linear Scale)');
ylabel(ax1, 'PSD [dB re 1 \muPa^2/Hz]');
title(ax1, 'Narrowband Welch PSD (Full Range: 50 Hz - 20 kHz)');
legend(ax1, 'Location', 'northeast');

% --- Subplot 2: Narrowband Welch PSD (Zoomed 0-4 kHz) ---
ax2 = subplot(4, 1, 2, 'Parent', fig);
hold(ax2, 'on');
for i = 1:length(fields)
    fn = fields{i};
    style = get_style(fn);
    plot(ax2, nb_results.(fn).freq, nb_results.(fn).psd, 'Color', style.color, 'LineStyle', style.linestyle, 'LineWidth', 1.2, 'DisplayName', style.displayName);
end
hold(ax2, 'off');
grid(ax2, 'on');
set(ax2, 'XScale', 'linear'); 
xlim(ax2, [50, 4000]);
set(ax2, 'XTick', zoom_ticks);
set(ax2, 'XTickLabel', zoom_labels);
xlabel(ax2, 'Frequency [Hz] (Linear Scale)');
ylabel(ax2, 'PSD [dB re 1 \muPa^2/Hz]');
title(ax2, 'Narrowband Welch PSD (Zoomed: 50 Hz - 4 kHz)');
legend(ax2, 'Location', 'northeast');

% --- Subplot 3: Welch PSD Reflection Envelope & Intersections (Full 20 kHz) ---
ax3 = subplot(4, 1, 3, 'Parent', fig);
hold(ax3, 'on');
for i = 1:length(fields)
    fn = fields{i};
    style = get_style(fn);
    % Plot original PSD with transparency
    plot(ax3, nb_results.(fn).freq, nb_results.(fn).psd, 'Color', [style.color 0.25], 'LineStyle', ':', 'LineWidth', 0.8, 'HandleVisibility', 'off');
    % Plot envelope
    plot(ax3, nb_results.(fn).freq, nb_results.(fn).envelope, 'Color', style.color, 'LineStyle', style.linestyle, 'LineWidth', 1.5, 'DisplayName', [style.displayName ' Env']);
    % Plot intersection points
    plot(ax3, nb_results.(fn).intersect_freq, nb_results.(fn).intersect_val, 'o', 'Color', style.color, 'MarkerFaceColor', style.color, 'MarkerSize', 3.5, 'LineStyle', 'none', 'HandleVisibility', 'off');
end
% Add a dummy plot to display "Intersections" clearly in the legend
plot(ax3, NaN, NaN, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 4.5, 'DisplayName', 'Intersections');

hold(ax3, 'off');
grid(ax3, 'on');
set(ax3, 'XScale', 'linear'); 
xlim(ax3, [50, 20000]);
set(ax3, 'XTick', ruler_ticks);
set(ax3, 'XTickLabel', ruler_labels);
xlabel(ax3, 'Frequency [Hz] (Linear Scale)');
ylabel(ax3, 'PSD / Envelope [dB re 1 \muPa^2/Hz]');
title(ax3, 'Narrowband Welch PSD with Reflection Envelope & Intersection Points');
legend(ax3, 'Location', 'northeast');

% --- Subplot 4: Standard Deviation of Decidecade Band Levels ---
ax4 = subplot(4, 1, 4, 'Parent', fig);
hold(ax4, 'on');
for i = 1:length(fields)
    fn = fields{i};
    style = get_style(fn);
    plot(ax4, fc_standard, tob_results.(fn).std_levels, 'Color', style.color, 'LineStyle', style.linestyle, 'LineWidth', 1.5, ...
         'Marker', style.marker, 'MarkerFaceColor', style.color, 'MarkerSize', 5, 'DisplayName', style.displayName);
end
hold(ax4, 'off');
grid(ax4, 'on');
set(ax4, 'XScale', 'linear');
xlim(ax4, [50, 20000]);
set(ax4, 'XTick', ruler_ticks);
set(ax4, 'XTickLabel', ruler_labels);
xlabel(ax4, 'Decidecade Band Center Frequency [Hz] (Linear Scale)');
ylabel(ax4, 'Standard Deviation [dB]');
title(ax4, 'Standard Deviation of Decidecade Band Levels (Temporal Variability)');
legend(ax4, 'Location', 'northeast');

% Save output plot
saveas(fig, fullfile(output_dir, 'garda_auv_tob_comparison_highres.png'));
fprintf('Saved garda_auv_tob_comparison_highres.png to output directory\n');
close(fig);

function style = helper_get_style(fn)
    if strcmp(fn, 'Garda_Electric_DWL')
        style.color = [0.0000 0.4470 0.7410]; % Blue
        style.linestyle = '-';
        style.marker = 'o';
        style.displayName = 'Garda Electric (DWL, 16 kts, away)';
    elseif strcmp(fn, 'AUV_Leg1_DWL')
        style.color = [0.4660 0.6740 0.1880]; % Green
        style.linestyle = ':';
        style.marker = '^';
        style.displayName = 'AUV Leg 1 (DWL, 5.4 kts, straight)';
    elseif strcmp(fn, 'Croatia_2407_2_DWL')
        style.color = [0.4940 0.1840 0.5560]; % Purple
        style.linestyle = '--';
        style.marker = 'd';
        style.displayName = 'Croatia 2407_2 (snake route)';
    elseif strcmp(fn, 'Croatia_2307_free_DWL')
        style.color = [0.9290 0.6940 0.1250]; % Yellow-orange
        style.linestyle = '--';
        style.marker = 'x';
        style.displayName = 'Croatia 2307 (freediving Suex VR, 2.1 kts)';
    else
        style.color = [0.5 0.5 0.5];
        style.linestyle = '-';
        style.marker = 'none';
        style.displayName = strrep(fn, '_', ' ');
    end
end
