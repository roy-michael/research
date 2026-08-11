function calculate_all_datasets_metrics()
    % Setup paths for the 9 raw/unfiltered datasets
    datasets = cell(9, 1);
    
    % 1. Croatia Raw (1-5)
    datasets{1} = struct('name', 'Croatia 2307 Free', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2307_free.wav', 'isFile', true, 'filter', false);
    datasets{2} = struct('name', 'Croatia 2407_1 600m', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2407_1_600m.wav', 'isFile', true, 'filter', false);
    datasets{3} = struct('name', 'Croatia 2407_2 Snake', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2407_2_snake.wav', 'isFile', true, 'filter', false);
    datasets{4} = struct('name', 'Croatia 2507_1 1k', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2507_1_1k.wav', 'isFile', true, 'filter', false);
    datasets{5} = struct('name', 'Croatia 2507_2 Joint', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2507_2_joint.wav', 'isFile', true, 'filter', false);
    
    % 2. Garda Raw (6-9)
    datasets{6} = struct('name', 'Garda Shallow Electric', 'path', 'D:\RoyStudies\Recordings\Garda_2_26\1_Shallow Water\Electric', 'isFile', false, 'filter', false);
    datasets{7} = struct('name', 'Garda Shallow Petrol', 'path', 'D:\RoyStudies\Recordings\Garda_2_26\1_Shallow Water\Petrol', 'isFile', false, 'filter', false);
    datasets{8} = struct('name', 'Garda Deep Electric', 'path', 'D:\RoyStudies\Recordings\Garda_2_26\2_Deep Water\Electric', 'isFile', false, 'filter', false);
    datasets{9} = struct('name', 'Garda Deep Petrol', 'path', 'D:\RoyStudies\Recordings\Garda_2_26\2_Deep Water\Petrol', 'isFile', false, 'filter', false);
    
    artifact_dir = 'C:\Users\gorke\.gemini\antigravity-ide\brain\a09a1b5f-d3a3-40cf-b59b-54d19ca16f61';
    if ~exist(artifact_dir, 'dir')
        mkdir(artifact_dir);
    end
    output_img = fullfile(artifact_dir, 'autocorrelation_comparison.png');
    
    % Calculation parameters
    block_len_sec = 10;
    target_blocks = 20;
    fs_expected = 128000;
    max_lag_raw = round(0.5 * fs_expected);
    
    fs_env = 2000;
    max_lag_env = round(1.0 * fs_env);
    
    % Preallocate result structures
    results = struct('name', {}, 'masd_raw', {}, 'coh_raw_1e', {}, 'coh_raw_05', {}, ...
                     'mcr_raw', {}, 'hj_act_raw', {}, 'hj_mob_raw', {}, 'hj_comp_raw', {}, 'sampen_raw', {}, ...
                     'masd_env', {}, 'coh_env_1e', {}, 'coh_env_05', {}, ...
                     'mcr_env', {}, 'hj_act_env', {}, 'hj_mob_env', {}, 'hj_comp_env', {}, 'sampen_env', {});
                 
    acf_raw_avg_all = [];
    acf_env_avg_all = [];
    
    for d = 1:length(datasets)
        ds = datasets{d};
        fprintf('Processing dataset: %s...\n', ds.name);
        
        blocks = cell(target_blocks, 1);
        blocks_found = 0;
        
        if ds.isFile
            if ~exist(ds.path, 'file')
                fprintf('  Warning: File not found %s. Skipping.\n', ds.path);
                continue;
            end
            info = audioinfo(ds.path);
            fs = info.SampleRate;
            block_samples = block_len_sec * fs;
            num_blocks = floor(info.TotalSamples / block_samples);
            blocks_to_read = min(target_blocks, num_blocks);
            
            total_samples_to_read = blocks_to_read * block_samples;
            y_full = audioread(ds.path, [1, total_samples_to_read]);
            if size(y_full, 2) > 1, y_full = mean(y_full, 2); end
            
            for b = 1:blocks_to_read
                start_sample = (b - 1) * block_samples + 1;
                end_sample = b * block_samples;
                y = y_full(start_sample:end_sample);
                blocks_found = blocks_found + 1;
                blocks{blocks_found} = y;
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
            
            file_idx = 1;
            while blocks_found < target_blocks && file_idx <= length(files)
                filepath = fullfile(files(file_idx).folder, files(file_idx).name);
                info = audioinfo(filepath);
                fs = info.SampleRate;
                block_samples = block_len_sec * fs;
                
                if info.TotalSamples >= block_samples
                    start_sample = max(1, round(info.TotalSamples/2 - block_samples/2));
                    end_sample = start_sample + block_samples - 1;
                    y = audioread(filepath, [start_sample, end_sample]);
                    if size(y, 2) > 1, y = mean(y, 2); end
                    
                    blocks_found = blocks_found + 1;
                    blocks{blocks_found} = y;
                end
                file_idx = file_idx + 1;
            end
        end
        
        if blocks_found == 0
            continue;
        end
        
        masd_raw_vals = zeros(blocks_found, 1);
        coh_raw_1e_vals = zeros(blocks_found, 1);
        coh_raw_05_vals = zeros(blocks_found, 1);
        mcr_raw_vals = zeros(blocks_found, 1);
        hj_act_raw_vals = zeros(blocks_found, 1);
        hj_mob_raw_vals = zeros(blocks_found, 1);
        hj_comp_raw_vals = zeros(blocks_found, 1);
        sampen_raw_vals = zeros(blocks_found, 1);
        
        masd_env_vals = zeros(blocks_found, 1);
        coh_env_1e_vals = zeros(blocks_found, 1);
        coh_env_05_vals = zeros(blocks_found, 1);
        mcr_env_vals = zeros(blocks_found, 1);
        hj_act_env_vals = zeros(blocks_found, 1);
        hj_mob_env_vals = zeros(blocks_found, 1);
        hj_comp_env_vals = zeros(blocks_found, 1);
        sampen_env_vals = zeros(blocks_found, 1);
        
        acf_raw_sum = zeros(max_lag_raw + 1, 1);
        acf_env_sum = zeros(max_lag_env + 1, 1);
        
        for b = 1:blocks_found
            y = blocks{b};
            
            % --- Raw Signal ---
            masd_raw_vals(b) = mean(abs(diff(y)));
            
            y_detrend = y - mean(y);
            [acf_raw, ~] = xcorr(y_detrend, max_lag_raw, 'coeff');
            acf_raw_pos = acf_raw(max_lag_raw + 1:end);
            acf_raw_sum = acf_raw_sum + acf_raw_pos;
            
            idx_1e = find(acf_raw_pos <= exp(-1), 1, 'first');
            if ~isempty(idx_1e)
                coh_raw_1e_vals(b) = (idx_1e - 1) / fs;
            else
                coh_raw_1e_vals(b) = max_lag_raw / fs;
            end
            
            idx_05 = find(acf_raw_pos <= 0.5, 1, 'first');
            if ~isempty(idx_05)
                coh_raw_05_vals(b) = (idx_05 - 1) / fs;
            else
                coh_raw_05_vals(b) = max_lag_raw / fs;
            end
            
            mcr_raw_vals(b) = calculate_mcr(y, fs);
            [act_r, mob_r, comp_r] = calculate_hjorth(y);
            hj_act_raw_vals(b) = act_r;
            hj_mob_raw_vals(b) = mob_r;
            hj_comp_raw_vals(b) = comp_r;
            sampen_raw_vals(b) = calculate_sampen(y, 2, 0.2);
            
            % --- Envelope ---
            env = abs(hilbert(y));
            env_ds = resample(env, fs_env, fs);
            masd_env_vals(b) = mean(abs(diff(env_ds)));
            
            env_detrend = env_ds - mean(env_ds);
            [acf_env, ~] = xcorr(env_detrend, max_lag_env, 'coeff');
            acf_env_pos = acf_env(max_lag_env + 1:end);
            acf_env_sum = acf_env_sum + acf_env_pos;
            
            idx_env_1e = find(acf_env_pos <= exp(-1), 1, 'first');
            if ~isempty(idx_env_1e)
                coh_env_1e_vals(b) = (idx_env_1e - 1) / fs_env;
            else
                coh_env_1e_vals(b) = max_lag_env / fs_env;
            end
            
            idx_env_05 = find(acf_env_pos <= 0.5, 1, 'first');
            if ~isempty(idx_env_05)
                coh_env_05_vals(b) = (idx_env_05 - 1) / fs_env;
            else
                coh_env_05_vals(b) = max_lag_env / fs_env;
            end
            
            mcr_env_vals(b) = calculate_mcr(env_ds, fs_env);
            [act_e, mob_e, comp_e] = calculate_hjorth(env_ds);
            hj_act_env_vals(b) = act_e;
            hj_mob_env_vals(b) = mob_e;
            hj_comp_env_vals(b) = comp_e;
            sampen_env_vals(b) = calculate_sampen(env_ds, 2, 0.2);
        end
        
        new_result = struct( ...
            'name', ds.name, ...
            'masd_raw', mean(masd_raw_vals), ...
            'coh_raw_1e', mean(coh_raw_1e_vals), ...
            'coh_raw_05', mean(coh_raw_05_vals), ...
            'mcr_raw', mean(mcr_raw_vals), ...
            'hj_act_raw', mean(hj_act_raw_vals), ...
            'hj_mob_raw', mean(hj_mob_raw_vals), ...
            'hj_comp_raw', mean(hj_comp_raw_vals), ...
            'sampen_raw', mean(sampen_raw_vals), ...
            'masd_env', mean(masd_env_vals), ...
            'coh_env_1e', mean(coh_env_1e_vals), ...
            'coh_env_05', mean(coh_env_05_vals), ...
            'mcr_env', mean(mcr_env_vals), ...
            'hj_act_env', mean(hj_act_env_vals), ...
            'hj_mob_env', mean(hj_mob_env_vals), ...
            'hj_comp_env', mean(hj_comp_env_vals), ...
            'sampen_env', mean(sampen_env_vals) ...
        );
        results = [results; new_result];
        
        acf_raw_avg_all = [acf_raw_avg_all, acf_raw_sum / blocks_found];
        acf_env_avg_all = [acf_env_avg_all, acf_env_sum / blocks_found];
    end
    
    % Print comparative table for Raw Signals
    fprintf('\n====================================================== RAW ACOUSTIC SIGNAL METRICS ======================================================\n');
    fprintf('%-40s | %-10s | %-12s | %-12s | %-10s | %-12s | %-12s | %-10s\n', ...
            'Dataset Name', 'Raw MASD', 'Coh (1/e)  ', 'Coh (0.5)  ', 'MCR (Hz)  ', 'Hjorth Mob  ', 'Hjorth Comp ', 'SampEn    ');
    fprintf('%s\n', repmat('-', 1, 140));
    for i = 1:length(results)
        fprintf('%-40s | %-10.6f | %-9.2f ms | %-9.2f ms | %-10.2f | %-12.6f | %-12.6f | %-10.4f\n', ...
                results(i).name, results(i).masd_raw, results(i).coh_raw_1e*1000, results(i).coh_raw_05*1000, ...
                results(i).mcr_raw, results(i).hj_mob_raw, results(i).hj_comp_raw, results(i).sampen_raw);
    end
    
    % Print comparative table for Envelopes
    fprintf('\n======================================================= AMPLITUDE ENVELOPE METRICS =======================================================\n');
    fprintf('%-40s | %-10s | %-12s | %-12s | %-10s | %-12s | %-12s | %-10s\n', ...
            'Dataset Name', 'Env MASD ', 'Coh (1/e)  ', 'Coh (0.5)  ', 'MCR (Hz)  ', 'Hjorth Mob  ', 'Hjorth Comp ', 'SampEn    ');
    fprintf('%s\n', repmat('-', 1, 140));
    for i = 1:length(results)
        fprintf('%-40s | %-10.6f | %-9.2f ms | %-9.2f ms | %-10.2f | %-12.6f | %-12.6f | %-10.4f\n', ...
                results(i).name, results(i).masd_env, results(i).coh_env_1e*1000, results(i).coh_env_05*1000, ...
                results(i).mcr_env, results(i).hj_mob_env, results(i).hj_comp_env, results(i).sampen_env);
    end
    fprintf('==========================================================================================================================================\n');
    
    % Plot Comparison (2x2 grid for Croatia Raw, Garda Raw)
    t_raw = (0:max_lag_raw) / fs_expected * 1000;
    t_env = (0:max_lag_env) / fs_env * 1000;
    
    croatia_idx = 1:5;
    garda_idx = 6:9;
    
    colors_croatia = hsv(length(croatia_idx));
    colors_garda = [
        0,      0.4470, 0.7410;
        0.8500, 0.3250, 0.0980;
        0.9290, 0.6940, 0.1250;
        0.4940, 0.1840, 0.5560
    ];
    
    fig = figure('Visible', 'off', 'Position', [100, 100, 1600, 1000]);
    
    % 1. Croatia Raw Signal
    subplot(2, 2, 1);
    hold on;
    for i = 1:length(croatia_idx)
        idx = croatia_idx(i);
        plot(t_raw, acf_raw_avg_all(:, idx), 'LineWidth', 1.8, 'Color', colors_croatia(i, :), 'DisplayName', results(idx).name);
    end
    yline(exp(-1), '--r', '1/e', 'HandleVisibility', 'off');
    grid on;
    title('Croatia Raw Signal Autocorrelation');
    xlabel('Lag (ms)');
    ylabel('Normalized Autocorrelation');
    xlim([0, t_raw(end)]);
    legend('Location', 'best', 'FontSize', 8);
    
    % 2. Garda Raw Signal
    subplot(2, 2, 2);
    hold on;
    for i = 1:length(garda_idx)
        idx = garda_idx(i);
        plot(t_raw, acf_raw_avg_all(:, idx), 'LineWidth', 1.8, 'Color', colors_garda(i, :), 'DisplayName', results(idx).name);
    end
    yline(exp(-1), '--r', '1/e', 'HandleVisibility', 'off');
    grid on;
    title('Garda Raw Signal Autocorrelation');
    xlabel('Lag (ms)');
    ylabel('Normalized Autocorrelation');
    xlim([0, t_raw(end)]);
    legend('Location', 'best', 'FontSize', 8);
    
    % 3. Croatia Envelope
    subplot(2, 2, 3);
    hold on;
    for i = 1:length(croatia_idx)
        idx = croatia_idx(i);
        plot(t_env, acf_env_avg_all(:, idx), 'LineWidth', 1.8, 'Color', colors_croatia(i, :), 'DisplayName', results(idx).name);
    end
    yline(exp(-1), '--r', '1/e', 'HandleVisibility', 'off');
    grid on;
    title('Croatia Envelope Autocorrelation');
    xlabel('Lag (ms)');
    ylabel('Normalized Autocorrelation');
    xlim([0, t_env(end)]);
    legend('Location', 'best', 'FontSize', 8);
    
    % 4. Garda Envelope
    subplot(2, 2, 4);
    hold on;
    for i = 1:length(garda_idx)
        idx = garda_idx(i);
        plot(t_env, acf_env_avg_all(:, idx), 'LineWidth', 1.8, 'Color', colors_garda(i, :), 'DisplayName', results(idx).name);
    end
    yline(exp(-1), '--r', '1/e', 'HandleVisibility', 'off');
    grid on;
    title('Garda Envelope Autocorrelation');
    xlabel('Lag (ms)');
    ylabel('Normalized Autocorrelation');
    xlim([0, t_env(end)]);
    legend('Location', 'best', 'FontSize', 8);
    
    saveas(fig, output_img);
    close(fig);
    fprintf('Autocorrelation comparison plot saved to: %s\n', output_img);
end

% --- Helper Functions ---

function y_filt = apply_bandpass(y, fs, f_low, f_high)
    [sos, g] = butter(4, [f_low, f_high] / (fs / 2), 'bandpass');
    y_filt = filtfilt(sos, g, y);
end

function mcr = calculate_mcr(x, fs)
    x_centered = x - mean(x);
    zero_crossings = sum(x_centered(1:end-1) .* x_centered(2:end) < 0);
    mcr = zero_crossings / (length(x) / fs);
end

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
    target_len = 1000;
    
    if N > target_len
        x = resample(x, target_len, N);
        N = target_len;
    end
    
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
