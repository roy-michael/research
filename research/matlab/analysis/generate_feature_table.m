function generate_feature_table()
    rec_path = get_recordings_path();
    datasets = {
        struct('name', 'Croatia 2307 Free', 'path', fullfile(rec_path, 'Croatia\Ocean Sonics\2307_free'), 'isFile', false, 'label', 0), ... % 0 = Underwater
        struct('name', 'Croatia 2407_1 600m', 'path', fullfile(rec_path, 'Croatia\Ocean Sonics\2407_1_600m'), 'isFile', false, 'label', 0), ...
        struct('name', 'Croatia 2407_2 Snake', 'path', fullfile(rec_path, 'Croatia\Ocean Sonics\2407_2_snake'), 'isFile', false, 'label', 0), ...
        struct('name', 'Croatia 2507_1 1k', 'path', fullfile(rec_path, 'Croatia\Ocean Sonics\2507_1_1k'), 'isFile', false, 'label', 0), ...
        struct('name', 'Croatia 2507_2 Joint', 'path', fullfile(rec_path, 'Croatia\Ocean Sonics\2507_2_joint'), 'isFile', false, 'label', 0), ...
        struct('name', 'Garda Shallow Electric', 'path', fullfile(rec_path, 'Garda_2_26\1_Shallow Water\Electric'), 'isFile', false, 'label', 1), ... % 1 = Surface
        struct('name', 'Garda Shallow Petrol', 'path', fullfile(rec_path, 'Garda_2_26\1_Shallow Water\Petrol'), 'isFile', false, 'label', 1), ...
        struct('name', 'Garda Deep Electric', 'path', fullfile(rec_path, 'Garda_2_26\2_Deep Water\Electric'), 'isFile', false, 'label', 1), ...
        struct('name', 'Garda Deep Petrol', 'path', fullfile(rec_path, 'Garda_2_26\2_Deep Water\Petrol'), 'isFile', false, 'label', 1)
    };

    block_len_sec = 30;
    
    fprintf('## Feature Values by Dataset\n\n');
    fprintf('| Dataset | Raw Centroid $f_c$ (kHz) | Raw Entropy $H$ | $SampEn$ | $\\tau_{1/e}$ (ms) | $\\tau_{0.5}$ (ms) |\n');
    fprintf('| :--- | :--- | :--- | :--- | :--- | :--- |\n');
    
    for d = 1:length(datasets)
        ds = datasets{d};
        temp_X = [];
        temp_rms = [];
        
        if ds.isFile
            if exist(ds.path, 'file')
                info = audioinfo(ds.path);
                fs = info.SampleRate;
                total_samples = info.TotalSamples;
                block_samples = block_len_sec * fs;
                num_blocks = floor(total_samples / block_samples);
                
                for b = 1:num_blocks
                    start_sample = (b - 1) * block_samples + 1;
                    end_sample = b * block_samples;
                    sig = audioread(ds.path, [start_sample, end_sample]);
                    if size(sig, 2) > 1, sig = mean(sig, 2); end
                    
                    [b_hp, a_hp] = butter(2, 100 / (fs/2), 'high');
                    sig_filt = filter(b_hp, a_hp, sig);
                    
                    feat = extract_features_block(sig_filt, fs);
                    temp_X = [temp_X; feat];
                    temp_rms = [temp_rms; rms(sig_filt)];
                end
            end
        else
            if exist(ds.path, 'dir')
                files = dir(fullfile(ds.path, '**', '*.wav'));
                if ~isempty(files)
                    for f_idx = 1:length(files)
                        filepath = fullfile(files(f_idx).folder, files(f_idx).name);
                        info = audioinfo(filepath);
                        fs = info.SampleRate;
                        block_samples = block_len_sec * fs;
                        
                        num_file_blocks = floor(info.TotalSamples / block_samples);
                        for b = 1:num_file_blocks
                            start_sample = (b - 1) * block_samples + 1;
                            end_sample = b * block_samples;
                            sig = audioread(filepath, [start_sample, end_sample]);
                            if size(sig, 2) > 1, sig = mean(sig, 2); end
                            
                            [b_hp, a_hp] = butter(2, 100 / (fs/2), 'high');
                            sig_filt = filter(b_hp, a_hp, sig);
                            
                            feat = extract_features_block(sig_filt, fs);
                            temp_X = [temp_X; feat];
                            temp_rms = [temp_rms; rms(sig_filt)];
                        end
                    end
                end
            end
        end
        
        if ~isempty(temp_X)
            local_noise_floor = percentile(temp_rms, 15);
            keep_idx = find(temp_rms > 1.8 * local_noise_floor);
            if ~isempty(keep_idx)
                avg_feat = mean(temp_X(keep_idx, :), 1);
                fprintf('| %s | %.4f | %.4f | %.4f | %.4f | %.4f |\n', ds.name, avg_feat(1), avg_feat(2), avg_feat(3), avg_feat(4), avg_feat(5));
            else
                fprintf('| %s | N/A | N/A | N/A | N/A | N/A |\n', ds.name);
            end
        else
            fprintf('| %s | N/A (File not found) | N/A | N/A | N/A | N/A |\n', ds.name);
        end
    end
end

function feat = extract_features_block(y, fs)
    [b_hp, a_hp] = butter(2, 100 / (fs/2), 'high');
    y_filt = filter(b_hp, a_hp, y);
    
    [pxx, f] = periodogram(y_filt, [], [], fs);
    p = pxx / (sum(pxx) + eps);
    raw_ent = -sum(p .* log(p + eps)) / log(length(p));
    raw_centroid = sum(f .* p);
    
    fs_intermediate = 8000;
    y_ds = resample(y_filt, fs_intermediate, fs);
    
    env = abs(hilbert(y_ds));
    
    fs_env = 2000;
    env_ds = resample(env, fs_env, fs_intermediate);
    
    env_sub = env_ds(1:min(fs_env, length(env_ds)));
    env_ds_se = resample(env_sub, 1000, fs_env);
    env_sampen = calculate_sampen(env_ds_se, 2, 0.2);
    
    max_lag_env = round(0.5 * fs_env);
    env_det = env_ds - mean(env_ds);
    [acf, ~] = xcorr(env_det, max_lag_env, 'coeff');
    acf_pos = acf(max_lag_env + 1:end);
    idx_1e = find(acf_pos <= exp(-1), 1, 'first');
    if ~isempty(idx_1e)
        env_cohtime_1e = (idx_1e - 1) / fs_env;
    else
        env_cohtime_1e = max_lag_env / fs_env;
    end
    
    idx_05 = find(acf_pos <= 0.5, 1, 'first');
    if ~isempty(idx_05)
        env_cohtime_05 = (idx_05 - 1) / fs_env;
    else
        env_cohtime_05 = max_lag_env / fs_env;
    end
    
    feat = [raw_centroid / 1000, raw_ent, env_sampen, env_cohtime_1e * 1000, env_cohtime_05 * 1000];
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

function val = percentile(x, p)
    x_sorted = sort(x);
    n = length(x);
    idx = max(1, round(n * p / 100));
    val = x_sorted(idx);
end
