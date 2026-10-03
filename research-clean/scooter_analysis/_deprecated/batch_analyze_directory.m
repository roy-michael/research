% Script to analyze dominant frequency for a directory of files
clear; close all; clc;

script_dir = fileparts(mfilename('fullpath'));
addpath(fullfile(script_dir, '..'));

target_dir = 'D:\RoyStudies\Recordings\DepartmentalCruise-2025-06-12\icListen\wav';
files = dir(fullfile(target_dir, '**', '*.wav'));

if isempty(files)
    fprintf('No WAV files found in %s\n', target_dir);
    return;
end

% Configuration 
segment_duration = 60;
step_duration = 15;
f_low = 100;
f_high = 2000;
twin_welch = 0.050;
df_eval = 0.50;
prom_split_db = 5.0;

% Configuration for Bandwidth Tracking
cfg_bw = struct();
cfg_bw.slice_dur_sec = 0.500;
cfg_bw.watershed_prom_max_db = 8.0;
cfg_bw.watershed_prom_min_db = 3.0;
cfg_bw.watershed_prom_ratio = 0.40;
cfg_bw.watershed_noise_fallback_margin = 0.90;
cfg_bw.bw_smooth_method = 'welch';
cfg_bw.bw_smooth_window = 5;
cfg_bw.twin_welch = 0.050;
cfg_bw.tib_tolerance_hz = 10;
cfg_bw.fairness_window = 5;

for f_idx = 1:length(files)
    filepath = fullfile(files(f_idx).folder, files(f_idx).name);
    [~, name, ~] = fileparts(filepath);
    
    fprintf('=== Processing File %d/%d: %s ===\n', f_idx, length(files), name);
    
    % Store output in a unique subdirectory for each file
    out_dir = fullfile(script_dir, 'output', name);
    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end
    
    try
        info = audioinfo(filepath);
    catch ME
        fprintf('WARNING: Skipping file %s (Could not read audio info: %s)\n', name, ME.message);
        continue;
    end
    fs = info.SampleRate;
    total_duration = info.Duration;
    
    start_times = 0:step_duration:(total_duration - segment_duration);
    if isempty(start_times)
        start_times = 0; % If file is shorter than segment duration
    end
    num_segments = length(start_times);
    
    report_path = fullfile(out_dir, sprintf('dominant_frequencies_report_%s.txt', name));
    fid = fopen(report_path, 'w');
    fprintf(fid, 'Analysis of: %s\n', filepath);
    fprintf(fid, 'Segment Duration: %d seconds\n', segment_duration);
    fprintf(fid, 'Total Duration: %.2f seconds\n', total_duration);
    fprintf(fid, 'Frequency Range: %d Hz - %d Hz\n', f_low, f_high);
    fprintf(fid, '======================================================\n');
    fprintf(fid, 'Segment Index | Start Time (s) | End Time (s) | Dominant Freq (Hz) | Peak PSD (dB) | Bandwidth (Hz)\n');
    
    results = struct('start_time', {}, 'end_time', {}, 'dom_freq', {}, 'peak_psd', {});
    
    h_fig_live = figure('Name', sprintf('Live Analysis: %s', name), 'Position', [100, 100, 1000, 500], 'Color', 'w');
    
    for i = 1:num_segments
        start_time = start_times(i);
        end_time = min(total_duration, start_time + segment_duration);
        
        start_sample = max(1, round(start_time * fs) + 1);
        end_sample = round(end_time * fs);
        
        [sig, fs_actual] = audioread(filepath, [start_sample, end_sample]);
        
        if size(sig, 2) > 1
            sig = mean(sig, 2);
        end
        sig = sig - mean(sig);
        [b_hp, a_hp] = butter(4, 20.0 / (fs / 2), 'high');
        sig = filtfilt(b_hp, a_hp, sig);
        
        [psd_db, f_grid, df, k_welch] = SpectralEngine.compute_welch_psd(sig, fs, f_low, f_high, twin_welch, df_eval);
        
        f_notch_low = 300;
        f_notch_high = 360;
        mask_interf = (f_grid >= f_notch_low) & (f_grid <= f_notch_high);
        idx_left = find(f_grid < f_notch_low, 1, 'last');
        idx_right = find(f_grid > f_notch_high, 1, 'first');
        if ~isempty(idx_left) && ~isempty(idx_right)
            psd_db(mask_interf) = interp1([f_grid(idx_left), f_grid(idx_right)], ...
                [psd_db(idx_left), psd_db(idx_right)], f_grid(mask_interf), 'linear');
        end
        
        [macro_lobes, dom_lobe, ocean_floor_smooth, ocean_ambient_db] = ...
            SpectralEngine.segment_macro_lobes(psd_db, f_grid, df, prom_split_db);
        
        slice_bw = BandwidthTracker.compute_watershed_slice_bandwidth(sig, fs, dom_lobe, cfg_bw);
        med_bw = median(slice_bw.all_main_bws, 'omitnan');
        
        results(i).start_time = start_time;
        results(i).end_time = end_time;
        results(i).dom_freq = dom_lobe.peak_freq;
        results(i).peak_psd = dom_lobe.peak_psd;
        results(i).bw = med_bw;
        
        fprintf(fid, '  %2d         | %12.2f | %10.2f | %18.2f | %12.2f | %14.2f\n', ...
            i, start_time, end_time, dom_lobe.peak_freq, dom_lobe.peak_psd, med_bw);
            
        figure(h_fig_live);
        y_floor = min(psd_db) - 3;
        idx_dom = (f_grid >= dom_lobe.f_start) & (f_grid <= dom_lobe.f_end);
        lobe_x = [f_grid(idx_dom); flipud(f_grid(idx_dom))];
        lobe_y = [psd_db(idx_dom); y_floor * ones(sum(idx_dom), 1)];
        
        bw_l = dom_lobe.peak_freq - med_bw/2;
        bw_r = dom_lobe.peak_freq + med_bw/2;
        bw_y = dom_lobe.peak_psd - 3;
        bw_x_line = [bw_l, bw_r, NaN, bw_l, bw_l, NaN, bw_r, bw_r];
        bw_y_line = [bw_y, bw_y, NaN, bw_y-1, bw_y+1, NaN, bw_y-1, bw_y+1];
        
        other_x_cells = cell(0);
        other_y_cells = cell(0);
        max_len = 0;
        for k = 1:length(macro_lobes)
            if macro_lobes(k).peak_freq ~= dom_lobe.peak_freq
                idx_l = (f_grid >= macro_lobes(k).f_start) & (f_grid <= macro_lobes(k).f_end);
                if any(idx_l)
                    cx = [f_grid(idx_l); flipud(f_grid(idx_l))];
                    cy = [psd_db(idx_l); y_floor * ones(sum(idx_l), 1)];
                    other_x_cells{end+1} = cx;
                    other_y_cells{end+1} = cy;
                    if length(cx) > max_len
                        max_len = length(cx);
                    end
                end
            end
        end
        if isempty(other_x_cells)
            other_x = NaN;
            other_y = NaN;
        else
            other_x = NaN(max_len, length(other_x_cells));
            other_y = NaN(max_len, length(other_x_cells));
            for k = 1:length(other_x_cells)
                len = length(other_x_cells{k});
                other_x(1:len, k) = other_x_cells{k};
                other_y(1:len, k) = other_y_cells{k};
            end
        end
        
        if i == 1
            clf(h_fig_live);
            hold on; grid on;
            h_base = plot(f_grid, ocean_floor_smooth, 'Color', [0.8 0.4 0.1], 'LineStyle', '--', 'LineWidth', 1.5, ...
                'DisplayName', sprintf('Ambient Baseline (%.1f dB)', ocean_ambient_db));
            h_other_lobes = patch('XData', other_x, 'YData', other_y, 'FaceColor', [0.6 0.6 0.6], 'FaceAlpha', 0.3, ...
                'EdgeColor', 'none', 'DisplayName', 'Secondary Lobes');
            h_lobe = fill(lobe_x, lobe_y, [0.90 0.25 0.35], 'FaceAlpha', 0.4, 'EdgeColor', 'none', ...
                'DisplayName', sprintf('Dominant Lobe (%.1f%% Energy)', dom_lobe.pct_energy));
            h_psd = plot(f_grid, psd_db, 'Color', [0.1 0.4 0.7], 'LineWidth', 1.2, 'DisplayName', 'Welch PSD');
            h_peak = plot(dom_lobe.peak_freq, dom_lobe.peak_psd, 'v', 'MarkerFaceColor', [1 0 0], 'MarkerEdgeColor', 'k', ...
                'MarkerSize', 8, 'DisplayName', sprintf('Peak: %.1f Hz (BW: %.1f Hz)', dom_lobe.peak_freq, med_bw));
            h_bw = plot(bw_x_line, bw_y_line, 'r-', 'LineWidth', 2, 'DisplayName', 'Computed BW Bounds');
            xlabel('Frequency (Hz)');
            ylabel('PSD (dB)');
            h_title = title(sprintf('Live Analysis: Segment %d/%d (%.1fs - %.1fs)', i, num_segments, start_time, end_time));
            legend('Location', 'northeast');
            xlim([f_low, f_high]);
        else
            set(h_base, 'YData', ocean_floor_smooth, 'DisplayName', sprintf('Ambient Baseline (%.1f dB)', ocean_ambient_db));
            set(h_other_lobes, 'XData', other_x, 'YData', other_y);
            set(h_lobe, 'XData', lobe_x, 'YData', lobe_y, 'DisplayName', sprintf('Dominant Lobe (%.1f%% Energy)', dom_lobe.pct_energy));
            set(h_psd, 'YData', psd_db);
            set(h_peak, 'XData', dom_lobe.peak_freq, 'YData', dom_lobe.peak_psd, 'DisplayName', sprintf('Peak: %.1f Hz (BW: %.1f Hz)', dom_lobe.peak_freq, med_bw));
            set(h_bw, 'XData', bw_x_line, 'YData', bw_y_line);
            set(h_title, 'String', sprintf('Live Analysis: Segment %d/%d (%.1fs - %.1fs)', i, num_segments, start_time, end_time));
            legend('Location', 'northeast');
        end
        ylim([y_floor, max(psd_db) + 5]);
        drawnow limitrate;
        
        fast_img_path = fullfile(out_dir, sprintf('Fig1_MacroLobe_Segment_%02d.png', i));
        exportgraphics(h_fig_live, fast_img_path, 'Resolution', 100);
    end
    fclose(fid);
    
    figure('Name', sprintf('Dominant Frequency & Bandwidth Over Time - %s', name), 'Position', [100, 100, 800, 400]);
    time_centers = ([results.start_time] + [results.end_time]) / 2 / 60;
    dom_freqs = [results.dom_freq];
    bw_vals = [results.bw];
    yyaxis left
    plot(time_centers, dom_freqs, '-o', 'LineWidth', 2, 'MarkerSize', 6, 'MarkerFaceColor', 'b', 'Color', [0.2 0.5 0.8]);
    ylabel('Dominant Frequency (Hz)');
    ylim([f_low, f_high]);
    yyaxis right
    plot(time_centers, bw_vals, '-s', 'LineWidth', 2, 'MarkerSize', 6, 'MarkerFaceColor', 'r', 'Color', [0.8 0.2 0.2]);
    ylabel('Bandwidth (Hz)');
    ylim([0, max(max(bw_vals)*1.2, 50)]);
    grid on;
    xlabel('Time (minutes)');
    title(sprintf('Dominant Signal Frequency & Bandwidth Over Time (%d-sec segments)', segment_duration));
    plot_path = fullfile(out_dir, sprintf('dominant_freq_bw_plot_%s.png', name));
    saveas(gcf, plot_path);
    close(gcf);
    close(h_fig_live);
end
fprintf('Batch analysis complete.\n');
