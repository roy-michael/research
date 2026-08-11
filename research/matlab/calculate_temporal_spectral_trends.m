function calculate_temporal_spectral_trends()
    datasets = {
        struct('name', 'Croatia 2307 Free', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2307_free.wav', 'isFile', true, 'filename_out', 'croatia_2307_free_trends.png'), ...
        struct('name', 'Croatia 2407_1 600m', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2407_1_600m.wav', 'isFile', true, 'filename_out', 'croatia_2407_1_600m_trends.png'), ...
        struct('name', 'Croatia 2407_2 Snake', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2407_2_snake.wav', 'isFile', true, 'filename_out', 'croatia_2407_2_snake_trends.png'), ...
        struct('name', 'Croatia 2507_1 1k', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2507_1_1k.wav', 'isFile', true, 'filename_out', 'croatia_2507_1_1k_trends.png'), ...
        struct('name', 'Croatia 2507_2 Joint', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2507_2_joint.wav', 'isFile', true, 'filename_out', 'croatia_2507_2_joint_trends.png'), ...
        struct('name', 'Garda Shallow Electric', 'path', 'D:\RoyStudies\Recordings\Garda_2_26\1_Shallow Water\Electric', 'isFile', false, 'filename_out', 'garda_shallow_electric_trends.png'), ...
        struct('name', 'Garda Shallow Petrol', 'path', 'D:\RoyStudies\Recordings\Garda_2_26\1_Shallow Water\Petrol', 'isFile', false, 'filename_out', 'garda_shallow_petrol_trends.png'), ...
        struct('name', 'Garda Deep Electric', 'path', 'D:\RoyStudies\Recordings\Garda_2_26\2_Deep Water\Electric', 'isFile', false, 'filename_out', 'garda_deep_electric_trends.png'), ...
        struct('name', 'Garda Deep Petrol', 'path', 'D:\RoyStudies\Recordings\Garda_2_26\2_Deep Water\Petrol', 'isFile', false, 'filename_out', 'garda_deep_petrol_trends.png')
    };
    
    artifact_dir = 'C:\Users\gorke\.gemini\antigravity-ide\brain\a09a1b5f-d3a3-40cf-b59b-54d19ca16f61';
    if ~exist(artifact_dir, 'dir')
        mkdir(artifact_dir);
    end
    
    block_len_sec = 30; % 30-second blocks for both Croatia and Garda
    
    for d = 1:length(datasets)
        ds = datasets{d};
        fprintf('Extracting trends for: %s...\n', ds.name);
        
        if ds.isFile
            if ~exist(ds.path, 'file')
                fprintf('  Warning: File not found %s. Skipping.\n', ds.path);
                continue;
            end
            info = audioinfo(ds.path);
            fs = info.SampleRate;
            total_samples = info.TotalSamples;
            block_samples = block_len_sec * fs;
            num_blocks = floor(total_samples / block_samples);
            max_lag = round(0.5 * fs);
            
            t_timeline = (0:num_blocks-1) * block_len_sec / 60;
            sampen_trend = zeros(num_blocks, 1);
            coh_trend = zeros(num_blocks, 1);
            hj_complexity_trend = zeros(num_blocks, 1);
            hj_mobility_trend = zeros(num_blocks, 1);
            spec_entropy_trend = zeros(num_blocks, 1);
            spec_centroid_trend = zeros(num_blocks, 1);
            spec_bandwidth_trend = zeros(num_blocks, 1);
            
            for b = 1:num_blocks
                start_sample = (b - 1) * block_samples + 1;
                end_sample = b * block_samples;
                y = audioread(ds.path, [start_sample, end_sample]);
                if size(y, 2) > 1, y = mean(y, 2); end
                
                y_sub = y(1:min(fs, length(y)));
                y_sub_ds = resample(y_sub, 1000, fs);
                sampen_trend(b) = calculate_sampen(y_sub_ds, 2, 0.2);
                
                y_det = y - mean(y);
                [acf, ~] = xcorr(y_det, max_lag, 'coeff');
                acf_pos = acf(max_lag + 1:end);
                idx = find(acf_pos <= exp(-1), 1, 'first');
                if ~isempty(idx)
                    coh_trend(b) = (idx - 1) / fs;
                else
                    coh_trend(b) = max_lag / fs;
                end
                
                [~, mob, comp] = calculate_hjorth(y);
                hj_complexity_trend(b) = comp;
                hj_mobility_trend(b) = mob;
                
                [pxx, f] = periodogram(y, [], [], fs);
                p = pxx / (sum(pxx) + eps);
                spec_entropy_trend(b) = -sum(p .* log(p + eps)) / log(length(p));
                spec_centroid_trend(b) = sum(f .* p);
                spec_bandwidth_trend(b) = sqrt(sum(((f - spec_centroid_trend(b)).^2) .* p));
            end
        else
            if ~exist(ds.path, 'dir')
                fprintf('  Warning: Directory not found %s. Skipping.\n', ds.path);
                continue;
            end
            files = dir(fullfile(ds.path, '*.wav'));
            if isempty(files)
                fprintf('  Warning: No WAV files in %s. Skipping.\n', ds.path);
                continue;
            end
            
            num_files = length(files);
            t_timeline = [];
            sampen_trend = [];
            coh_trend = [];
            hj_complexity_trend = [];
            hj_mobility_trend = [];
            spec_entropy_trend = [];
            spec_centroid_trend = [];
            spec_bandwidth_trend = [];
            
            cum_time_sec = 0;
            for f_idx = 1:num_files
                filepath = fullfile(files(f_idx).folder, files(f_idx).name);
                info = audioinfo(filepath);
                fs = info.SampleRate;
                block_samples = block_len_sec * fs;
                max_lag = round(0.5 * fs);
                
                num_file_blocks = floor(info.TotalSamples / block_samples);
                for b = 1:num_file_blocks
                    start_sample = (b - 1) * block_samples + 1;
                    end_sample = b * block_samples;
                    
                    t_timeline = [t_timeline; (cum_time_sec + (start_sample - 1)/fs) / 60];
                    
                    y = audioread(filepath, [start_sample, end_sample]);
                    if size(y, 2) > 1, y = mean(y, 2); end
                    
                    y_sub = y(1:min(fs, length(y)));
                    y_sub_ds = resample(y_sub, 1000, fs);
                    sampen_trend = [sampen_trend; calculate_sampen(y_sub_ds, 2, 0.2)];
                    
                    y_det = y - mean(y);
                    [acf, ~] = xcorr(y_det, max_lag, 'coeff');
                    acf_pos = acf(max_lag + 1:end);
                    idx = find(acf_pos <= exp(-1), 1, 'first');
                    if ~isempty(idx)
                        coh_trend = [coh_trend; (idx - 1) / fs];
                    else
                        coh_trend = [coh_trend; max_lag / fs];
                    end
                    
                    [~, mob, comp] = calculate_hjorth(y);
                    hj_complexity_trend = [hj_complexity_trend; comp];
                    hj_mobility_trend = [hj_mobility_trend; mob];
                    
                    [pxx, f] = periodogram(y, [], [], fs);
                    p = pxx / (sum(pxx) + eps);
                    spec_entropy_trend = [spec_entropy_trend; -sum(p .* log(p + eps)) / log(length(p))];
                    spec_centroid = sum(f .* p);
                    spec_centroid_trend = [spec_centroid_trend; spec_centroid];
                    spec_bandwidth_trend = [spec_bandwidth_trend; sqrt(sum(((f - spec_centroid).^2) .* p))];
                end
                cum_time_sec = cum_time_sec + info.TotalSamples / fs;
            end
        end
        
        % Plotting the comparative trend lines (5x1 layout)
        fig = figure('Visible', 'off', 'Position', [100, 100, 1400, 1300]);
        
        % Subplot 1: Temporal Chaos (SampEn vs Hjorth Complexity)
        subplot(5, 1, 1);
        yyaxis left;
        plot(t_timeline, sampen_trend, 'LineWidth', 2, 'Color', '#D95319');
        ylabel('Sample Entropy (Temporal Chaos)');
        yyaxis right;
        plot(t_timeline, hj_complexity_trend, '--', 'LineWidth', 1.8, 'Color', '#7E2F8E');
        ylabel('Hjorth Complexity (Proxy)');
        grid on;
        title(sprintf('Temporal Chaos Trend Analysis\n%s', ds.name), 'FontSize', 12);
        xlabel('Time (minutes)');
        xlim([0, t_timeline(end)]);
        
        % Subplot 2: Coherence Time (1/e)
        subplot(5, 1, 2);
        plot(t_timeline, coh_trend * 1000, 'LineWidth', 2, 'Color', '#77AC30');
        grid on;
        title('Coherence Time Trend (1/e)', 'FontSize', 12);
        xlabel('Time (minutes)');
        ylabel('Coherence Time (ms)');
        xlim([0, t_timeline(end)]);
        
        % Subplot 3: Spectral Smearness (Spectral Entropy)
        subplot(5, 1, 3);
        plot(t_timeline, spec_entropy_trend, 'LineWidth', 2, 'Color', '#0072BD');
        grid on;
        title('Spectral Smearness Trend (Spectral Entropy)', 'FontSize', 12);
        xlabel('Time (minutes)');
        ylabel('Spectral Entropy (0 to 1)');
        xlim([0, t_timeline(end)]);
        
        % Subplot 4: Spectral Bandwidth vs Hjorth Complexity (Proxy)
        subplot(5, 1, 4);
        yyaxis left;
        plot(t_timeline, spec_bandwidth_trend / 1000, 'LineWidth', 2, 'Color', '#2CA02C');
        ylabel('Spectral Spread (Bandwidth in kHz)');
        yyaxis right;
        plot(t_timeline, hj_complexity_trend, '--', 'LineWidth', 1.8, 'Color', '#7E2F8E');
        ylabel('Hjorth Complexity (Proxy)');
        grid on;
        title('Spectral Bandwidth Trend Analysis', 'FontSize', 12);
        xlabel('Time (minutes)');
        xlim([0, t_timeline(end)]);
        
        % Subplot 5: dominant frequency (Spectral Centroid vs Hjorth Mobility)
        subplot(5, 1, 5);
        yyaxis left;
        plot(t_timeline, spec_centroid_trend / 1000, 'LineWidth', 2, 'Color', '#4DBEEE');
        ylabel('Spectral Centroid (Dominant Freq in kHz)');
        yyaxis right;
        plot(t_timeline, (hj_mobility_trend * fs) / (2 * pi * 1000), '--', 'LineWidth', 1.8, 'Color', '#A2142F');
        ylabel('Hjorth Mobility (Proxy in kHz)');
        grid on;
        title('Dominant Frequency Trend Analysis', 'FontSize', 12);
        xlabel('Time (minutes)');
        xlim([0, t_timeline(end)]);
        
        out_path = fullfile(artifact_dir, ds.filename_out);
        saveas(fig, out_path);
        close(fig);
        
        fprintf('  Saved 5-panel trend plots to %s\n', out_path);
    end
    fprintf('All trend analyses completed successfully.\n');
end

% --- Helper Functions ---

function [activity, mobility, complexity] = calculate_hjorth(x)
    dx = diff(x);
    ddx = diff(dx);
    
    var_x = var(x);
    var_dx = var(dx);
    var_ddx = var(ddx);
    
    activity = var_x;
    if var_x > 0
        mobility = sqrt(var_dx / var_x);
    else
        mobility = 0;
    end
    
    if var_dx > 0 && mobility > 0
        complexity = sqrt(var_ddx / var_dx) / mobility;
    else
        complexity = 0;
    end
end

function se = calculate_sampen(x, m, r)
    N = length(x);
    r_val = r * std(x);
    if r_val == 0
        se = NaN;
        return;
    end
    
    X2 = [x(1:N-2), x(2:N-1)];
    X3 = [x(1:N-2), x(2:N-1), x(3:N)];
    
    B = 0;
    A = 0;
    
    for i = 1:(N - m)
        diff_m = max(abs(X2 - X2(i, :)), [], 2);
        B = B + sum(diff_m < r_val) - 1;
        
        if i <= N - (m + 1)
            diff_m1 = max(abs(X3 - X3(i, :)), [], 2);
            A = A + sum(diff_m1 < r_val) - 1;
        end
    end
    
    if A > 0 && B > 0
        se = -log(A / B);
    else
        se = NaN;
    end
end
