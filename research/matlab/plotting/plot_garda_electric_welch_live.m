% plot_garda_electric_welch_live.m
% Computes and compares high-resolution Welch PSDs for all WAV files in the Garda Electric dataset:
% 1. Subplot 1: Overlaid Welch PSDs for all 8 individual WAV files (1150, 1154, 1158, etc.)
% 2. Subplot 2: Overall Concatenated Welch PSD with local noise floor envelope & boundary crossings (50 Hz - 4 kHz)
% AUTOMATIC CACHING: Saves computed diagram data to cache_garda_electric_welch.mat so future runs load instantly.

% Resolve output directory relative to script folder
script_dir = fileparts(mfilename('fullpath'));
output_dir = fullfile(script_dir, '..', '..', 'output', 'garda');
cache_file = fullfile(output_dir, 'cache_garda_electric_welch.mat');

DIR_PATH = 'D:\RoyStudies\Recordings\Garda_2_26\2_Deep Water\Electric';
calibFactor = 1e6;

try
    if exist(cache_file, 'file')
        fprintf('======================================================\n');
        fprintf('Loading pre-computed diagram data from cache:\n  %s\n', cache_file);
        fprintf('======================================================\n');
        load(cache_file);
    else
        fprintf('Listing WAV files in: %s\n', DIR_PATH);
        files = dir(fullfile(DIR_PATH, '*.wav'));
        if isempty(files)
            error('No WAV files found in %s', DIR_PATH);
        end
        
        [~, sortIdx] = sort({files.name});
        files = files(sortIdx);
        num_files = length(files);
        
        fprintf('Found %d WAV files in Garda Electric dataset.\n', num_files);
        
        psd_all_files = cell(num_files, 1);
        file_names = cell(num_files, 1);
        
        windowLength = 65536; 
        noverlap = windowLength / 2;
        
        total_samples = 0;
        fs = [];
        
        % Process each file individually
        for i = 1:num_files
            file_path = fullfile(files(i).folder, files(i).name);
            file_names{i} = files(i).name;
            fprintf('Processing [%d/%d]: %s...\n', i, num_files, files(i).name);
            
            info = audioinfo(file_path);
            total_samples = total_samples + info.TotalSamples;
            if i == 1, fs = info.SampleRate; end
            
            [y, fs_in] = audioread(file_path);
            if size(y, 2) > 1, y = mean(y, 2); end
            y_cal = y * calibFactor;
            clear y;
            
            % Remove DC offset
            y_cal = y_cal - mean(y_cal);
            
            [psd_est, freq_psd] = pwelch(y_cal, windowLength, noverlap, windowLength, fs, 'power');
            
            idx_4k = (freq_psd >= 50 & freq_psd <= 4000);
            f_nb = freq_psd(idx_4k);
            psd_db = 10 * log10(psd_est(idx_4k));
            
            psd_all_files{i} = psd_db;
        end
        
        % Concatenate all files for total overall PSD
        fprintf('Computing overall concatenated Welch PSD...\n');
        y_concat = zeros(total_samples, 1);
        curr_idx = 1;
        for i = 1:num_files
            file_path = fullfile(files(i).folder, files(i).name);
            [y, ~] = audioread(file_path);
            if size(y, 2) > 1, y = mean(y, 2); end
            num_s = length(y);
            y_concat(curr_idx : curr_idx + num_s - 1) = y * calibFactor;
            curr_idx = curr_idx + num_s;
        end
        
        y_concat = y_concat - mean(y_concat); % Remove DC offset
        [psd_concat_est, freq_psd] = pwelch(y_concat, windowLength, noverlap, windowLength, fs, 'power');
        clear y_concat;
        
        idx_4k = (freq_psd >= 50 & freq_psd <= 4000);
        f_nb = freq_psd(idx_4k);
        psd_concat_db = 10 * log10(psd_concat_est(idx_4k));
        
        % Noise floor moving average envelope
        psd_env = movmean(psd_concat_db, 151);
        
        diff_sig = psd_concat_db - psd_env;
        intersect_idx = find(diff_sig(1:end-1) .* diff_sig(2:end) <= 0);
        intersect_freqs = f_nb(intersect_idx);
        intersect_vals = psd_concat_db(intersect_idx);
        
        % Save to MAT cache
        save(cache_file, 'f_nb', 'psd_concat_db', 'psd_env', 'intersect_freqs', 'intersect_vals', ...
             'psd_all_files', 'file_names', 'num_files', '-v7.3');
        fprintf('Saved diagram data to cache: %s\n', cache_file);
    end
    
    % --- Interactive Plotting ---
    fig = figure('Name', 'Garda Electric - Welch PSD Comparison (50 Hz - 4 kHz)', 'Position', [100, 100, 1400, 950]);
    
    file_colors = lines(num_files);
    zoom_ticks = [50, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000];
    zoom_labels = {'50', '500', '1k', '1.5k', '2k', '2.5k', '3k', '3.5k', '4k'};
    
    % Subplot 1: Overlaid individual files
    ax1 = subplot(2, 1, 1, 'Parent', fig);
    hold(ax1, 'on');
    for i = 1:num_files
        plot(ax1, f_nb, psd_all_files{i}, 'Color', file_colors(i, :), 'LineWidth', 1.0, 'DisplayName', file_names{i});
    end
    hold(ax1, 'off');
    grid(ax1, 'on');
    xlim(ax1, [50, 4000]);
    set(ax1, 'XTick', zoom_ticks);
    set(ax1, 'XTickLabel', zoom_labels);
    xlabel(ax1, 'Frequency [Hz]');
    ylabel(ax1, 'PSD [dB re 1 \muPa^2/Hz]');
    title(ax1, 'Garda Electric - Individual File Welch PSD Comparison (8 Files)');
    legend(ax1, 'Location', 'northeast');
    
    % Subplot 2: Overall Concatenated PSD & Baseline Noise Floor
    ax2 = subplot(2, 1, 2, 'Parent', fig);
    hold(ax2, 'on');
    plot(ax2, f_nb, psd_concat_db, 'Color', [0.0000 0.4470 0.7410], 'LineWidth', 1.2, 'DisplayName', 'Overall Welch PSD');
    plot(ax2, f_nb, psd_env, 'Color', [0.8500 0.3250 0.0980], 'LineStyle', '--', 'LineWidth', 1.5, 'DisplayName', 'Noise Floor Envelope');
    if ~isempty(intersect_freqs)
        plot(ax2, intersect_freqs, intersect_vals, 'ko', 'MarkerFaceColor', 'k', 'MarkerSize', 4, 'DisplayName', 'Boundary Intersections');
    end
    hold(ax2, 'off');
    grid(ax2, 'on');
    xlim(ax2, [50, 4000]);
    set(ax2, 'XTick', zoom_ticks);
    set(ax2, 'XTickLabel', zoom_labels);
    xlabel(ax2, 'Frequency [Hz]');
    ylabel(ax2, 'PSD [dB re 1 \muPa^2/Hz]');
    title(ax2, 'Garda Electric - Overall Concatenated Welch PSD & Baseline Envelope (50 Hz - 4 kHz)');
    legend(ax2, 'Location', 'northeast');
    
    % Link X-axes
    linkaxes([ax1, ax2], 'x');
    
    % Enable interactive zoom
    zoom(fig, 'on');
    
    % Save image output
    saveas(fig, fullfile(output_dir, 'garda_electric_welch_comparison.png'));
    fprintf('Saved garda_electric_welch_comparison.png to output directory.\n');
    
    fprintf('Interactive Garda Electric Welch diagram is live!\n');
    
catch e
    fprintf('An error occurred: %s\n', e.message);
    disp(e.getReport());
end
