function plot_coherence_comparison()
    rec_path = get_recordings_path();
    datasets = {
        struct('name', 'Croatia 2307 Free', 'path', fullfile(rec_path, 'Croatia\Ocean Sonics\2307_free'), 'isFile', false), ...
        struct('name', 'Croatia 2407_1 600m', 'path', fullfile(rec_path, 'Croatia\Ocean Sonics\2407_1_600m'), 'isFile', false), ...
        struct('name', 'Croatia 2407_2 Snake', 'path', fullfile(rec_path, 'Croatia\Ocean Sonics\2407_2_snake'), 'isFile', false), ...
        struct('name', 'Croatia 2507_1 1k', 'path', fullfile(rec_path, 'Croatia\Ocean Sonics\2507_1_1k'), 'isFile', false), ...
        struct('name', 'Croatia 2507_2 Joint', 'path', fullfile(rec_path, 'Croatia\Ocean Sonics\2507_2_joint'), 'isFile', false), ...
        struct('name', 'Garda Shallow Elec', 'path', fullfile(rec_path, 'Garda_2_26\1_Shallow Water\Electric'), 'isFile', false), ...
        struct('name', 'Garda Shallow Pet', 'path', fullfile(rec_path, 'Garda_2_26\1_Shallow Water\Petrol'), 'isFile', false), ...
        struct('name', 'Garda Deep Elec', 'path', fullfile(rec_path, 'Garda_2_26\2_Deep Water\Electric'), 'isFile', false), ...
        struct('name', 'Garda Deep Pet', 'path', fullfile(rec_path, 'Garda_2_26\2_Deep Water\Petrol'), 'isFile', false)
    };
    
    block_len_sec = 30;
    num_ds = length(datasets);
    coh_1e = NaN(num_ds, 1);
    coh_05 = NaN(num_ds, 1);
    ds_names = cell(num_ds, 1);
    
    fprintf('Starting Coherence Plot Script...\n');
    
    for d = 1:num_ds
        ds = datasets{d};
        ds_names{d} = ds.name;
        fprintf('Processing %s...\n', ds.name);
        
        temp_coh_1e = [];
        temp_coh_05 = [];
        temp_rms = [];
        
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
                        
                        [c1, c2] = extract_coherence(sig_filt, fs);
                        temp_coh_1e(end+1) = c1;
                        temp_coh_05(end+1) = c2;
                        temp_rms(end+1) = rms(sig_filt);
                    end
                end
            end
        end
        
        if ~isempty(temp_coh_1e)
            local_noise_floor = percentile(temp_rms, 15);
            keep_idx = find(temp_rms > 1.8 * local_noise_floor);
            if ~isempty(keep_idx)
                coh_1e(d) = mean(temp_coh_1e(keep_idx));
                coh_05(d) = mean(temp_coh_05(keep_idx));
                fprintf('  -> 1/e: %.4f, 0.5: %.4f\n', coh_1e(d), coh_05(d));
            else
                fprintf('  -> Skipped due to noise floor\n');
            end
        else
            fprintf('  -> No files found\n');
        end
    end
    
    fprintf('Generating plot...\n');
    fig = figure('Visible', 'off', 'Position', [100, 100, 1000, 600]);
    bar_data = [coh_1e, coh_05];
    b = bar(bar_data);
    b(1).FaceColor = '#0072BD';
    b(2).FaceColor = '#D95319';
    
    set(gca, 'XTickLabel', ds_names, 'XTick', 1:num_ds);
    xtickangle(45);
    title('Coherence Time Comparison: 1/e vs 0.5 Threshold');
    ylabel('Coherence Time (ms)');
    legend({'Threshold: 1/e (~0.368)', 'Threshold: 0.5'}, 'Location', 'best');
    grid on;
    
    out_dir = 'C:\Users\Roy\dev\research\research\images';
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end
    saveas(fig, fullfile(out_dir, 'coherence_threshold_comparison.png'));
    close(fig);
    
    fprintf('Plot saved to images/coherence_threshold_comparison.png\n');
end

function [c_1e, c_05] = extract_coherence(y_filt, fs)
    fs_intermediate = 8000;
    y_ds = resample(y_filt, fs_intermediate, fs);
    env = abs(hilbert(y_ds));
    
    fs_env = 2000;
    env_ds = resample(env, fs_env, fs_intermediate);
    
    max_lag_env = round(0.5 * fs_env);
    env_det = env_ds - mean(env_ds);
    [acf, ~] = xcorr(env_det, max_lag_env, 'coeff');
    acf_pos = acf(max_lag_env + 1:end);
    
    idx_1e = find(acf_pos <= exp(-1), 1, 'first');
    if ~isempty(idx_1e)
        c_1e = (idx_1e - 1) / fs_env * 1000;
    else
        c_1e = max_lag_env / fs_env * 1000;
    end
    
    idx_05 = find(acf_pos <= 0.5, 1, 'first');
    if ~isempty(idx_05)
        c_05 = (idx_05 - 1) / fs_env * 1000;
    else
        c_05 = max_lag_env / fs_env * 1000;
    end
end

function val = percentile(x, p)
    x_sorted = sort(x);
    n = length(x);
    idx = max(1, round(n * p / 100));
    val = x_sorted(idx);
end
