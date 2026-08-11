% plot_croatia_concat_welch_live.m
% Recursively finds ALL WAV files across ALL subdirectories under D:\RoyStudies\Recordings\Croatia
% 1. Subplot 1: Overlaid Welch PSDs for all valid WAV files found in Croatia subdirectories
% 2. Subplot 2: Overall Concatenated Welch PSD for all Croatia subdirectories combined (50 Hz - 4 kHz)
% AUTOMATIC CACHING: Saves computed diagram data to cache_croatia_concat_welch.mat so future runs load instantly without re-reading audio files.

% Resolve output directory relative to script folder
script_dir = fileparts(mfilename('fullpath'));
output_dir = fullfile(script_dir, '..', '..', 'output', 'croatia');
cache_file = fullfile(output_dir, 'cache_croatia_concat_welch.mat');

CROATIA_ROOT = 'D:\RoyStudies\Recordings\Croatia';
calibFactor = 1e6;

try
    if exist(cache_file, 'file')
        fprintf('======================================================\n');
        fprintf('Loading pre-computed diagram data from cache:\n  %s\n', cache_file);
        fprintf('======================================================\n');
        load(cache_file);
    else
        fprintf('Cache not found. Searching for WAV files in: %s\n', CROATIA_ROOT);
        files = dir(fullfile(CROATIA_ROOT, '**', '*.wav'));
        if isempty(files)
            error('No WAV files found under %s', CROATIA_ROOT);
        end
        
        [~, sortIdx] = sort({files.folder});
        files = files(sortIdx);
        num_files = length(files);
        
        fprintf('Found %d total WAV files across all subdirectories in Croatia.\n', num_files);
        
        windowLength = 65536; 
        noverlap = windowLength / 2;
        step_size = windowLength - noverlap;
        
        % Unified reference frequency grid: 50 Hz to 4000 Hz with 0.5 Hz resolution
        f_nb = (50:0.5:4000)';
        
        psd_all_files = {};
        freq_all_files = {};
        file_labels = {};
        
        P_sum = zeros(length(f_nb), 1);
        total_windows = 0;
        valid_count = 0;
        
        for i = 1:num_files
            file_path = fullfile(files(i).folder, files(i).name);
            [~, parent_dir] = fileparts(files(i).folder);
            lbl = sprintf('%s / %s', parent_dir, files(i).name);
            
            try
                [y, fs] = audioread(file_path);
                if isempty(y), continue; end
                if size(y, 2) > 1, y = mean(y, 2); end
                
                y_cal = y * calibFactor;
                clear y;
                
                % Remove DC offset
                y_cal = y_cal - mean(y_cal);
                
                num_wins = floor((length(y_cal) - noverlap) / step_size);
                if num_wins < 1, continue; end
                
                [psd_file, f_file] = pwelch(y_cal, windowLength, noverlap, windowLength, fs, 'power');
                
                idx_4k_file = (f_file >= 50 & f_file <= 4000);
                f_sub = f_file(idx_4k_file);
                psd_sub_db = 10 * log10(psd_file(idx_4k_file));
                
                psd_interp_db = interp1(f_sub, psd_sub_db, f_nb, 'linear', 'extrap');
                psd_interp_linear = interp1(f_sub, psd_file(idx_4k_file), f_nb, 'linear', 'extrap');
                
                valid_count = valid_count + 1;
                psd_all_files{valid_count, 1} = psd_interp_db;
                freq_all_files{valid_count, 1} = f_nb;
                file_labels{valid_count, 1} = lbl;
                
                P_sum = P_sum + psd_interp_linear * num_wins;
                total_windows = total_windows + num_wins;
                
                if mod(valid_count, 100) == 0
                    fprintf('  Processed [%d/%d valid files]...\n', valid_count, num_files);
                end
                
            catch read_err
                warning('Skipping unreadable or corrupt file [%s]: %s', lbl, read_err.message);
                continue;
            end
        end
        
        fprintf('Successfully processed %d valid WAV files across all Croatia subdirectories.\n', valid_count);
        
        if valid_count == 0 || total_windows == 0
            error('No valid WAV audio data could be read.');
        end
        
        psd_concat_est = P_sum / total_windows;
        psd_concat_db = 10 * log10(psd_concat_est);
        
        % Noise floor moving average envelope
        psd_env = movmean(psd_concat_db, 151);
        
        diff_sig = psd_concat_db - psd_env;
        intersect_idx = find(diff_sig(1:end-1) .* diff_sig(2:end) <= 0);
        intersect_freqs = f_nb(intersect_idx);
        intersect_vals = psd_concat_db(intersect_idx);
        
        % Save to cache MAT file
        save(cache_file, 'f_nb', 'psd_concat_db', 'psd_env', 'intersect_freqs', 'intersect_vals', ...
             'psd_all_files', 'freq_all_files', 'file_labels', 'valid_count', '-v7.3');
        fprintf('Saved diagram data to cache: %s\n', cache_file);
    end
    
    % --- Interactive Plotting ---
    fig = figure('Name', 'All Croatia Subdirectories - Welch PSD Comparison (50 Hz - 4 kHz)', 'Position', [100, 100, 1400, 950]);
    
    file_colors = hsv(valid_count);
    zoom_ticks = [50, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000];
    zoom_labels = {'50', '500', '1k', '1.5k', '2k', '2.5k', '3k', '3.5k', '4k'};
    
    % Subplot 1: Overlaid individual files
    ax1 = subplot(2, 1, 1, 'Parent', fig);
    hold(ax1, 'on');
    for i = 1:valid_count
        plot(ax1, freq_all_files{i}, psd_all_files{i}, 'Color', file_colors(i, :), 'LineWidth', 0.5, 'HandleVisibility', 'off');
    end
    hold(ax1, 'off');
    grid(ax1, 'on');
    xlim(ax1, [50, 4000]);
    set(ax1, 'XTick', zoom_ticks);
    set(ax1, 'XTickLabel', zoom_labels);
    xlabel(ax1, 'Frequency [Hz]');
    ylabel(ax1, 'PSD [dB re 1 \muPa^2/Hz]');
    title(ax1, sprintf('All Croatia Subdirectories - Individual WAV Files Welch PSD (%d Valid Files)', valid_count));
    
    % Subplot 2: Overall Concatenated PSD & Baseline Noise Floor
    ax2 = subplot(2, 1, 2, 'Parent', fig);
    hold(ax2, 'on');
    plot(ax2, f_nb, psd_concat_db, 'Color', [0.4940 0.1840 0.5560], 'LineWidth', 1.2, 'DisplayName', 'Overall Welch PSD');
    plot(ax2, f_nb, psd_env, 'Color', [0.9290 0.6940 0.1250], 'LineStyle', '--', 'LineWidth', 1.5, 'DisplayName', 'Noise Floor Envelope');
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
    title(ax2, sprintf('Croatia Parent Directory - Overall Concatenated Welch PSD & Baseline Envelope (%d Valid Files Combined)', valid_count));
    legend(ax2, 'Location', 'northeast');
    
    % Link X-axes
    linkaxes([ax1, ax2], 'x');
    
    % Enable interactive zoom
    zoom(fig, 'on');
    
    % Save image output
    saveas(fig, fullfile(output_dir, 'croatia_all_subdirs_welch.png'));
    fprintf('Saved croatia_all_subdirs_welch.png to output directory.\n');
    
    fprintf('Interactive Croatia All-Subdirectories Welch diagram is live!\n');
    
catch e
    fprintf('An error occurred: %s\n', e.message);
    disp(e.getReport());
end
