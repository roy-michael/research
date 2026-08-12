function test_coherence()
    rec_path = get_recordings_path();
    
    croatia_file = fullfile(rec_path, 'Croatia\Ocean Sonics\2407_1_600m\RBW6737_20250724_091500.wav');
    garda_file = fullfile(rec_path, 'Garda_2_26\1_Shallow Water\Electric\0928.wav');
    
    fs = 48000; % Will be overridden by audioinfo, just a placeholder
    info_c = audioinfo(croatia_file);
    info_g = audioinfo(garda_file);
    
    % Read 10 seconds from each
    sig_c = audioread(croatia_file, [1, 10 * info_c.SampleRate]);
    if size(sig_c, 2) > 1, sig_c = mean(sig_c, 2); end
    
    sig_g = audioread(garda_file, [1, 10 * info_g.SampleRate]);
    if size(sig_g, 2) > 1, sig_g = mean(sig_g, 2); end
    
    fs_c = info_c.SampleRate;
    fs_g = info_g.SampleRate;
    
    [b_c, a_c] = butter(2, 100 / (fs_c/2), 'high');
    sig_c = filter(b_c, a_c, sig_c);
    
    [b_g, a_g] = butter(2, 100 / (fs_g/2), 'high');
    sig_g = filter(b_g, a_g, sig_g);
    
    figure('Position', [100, 100, 1200, 800]);
    
    subplot(2, 1, 1);
    plot_acf(sig_c, fs_c, 'Croatia (Underwater Scooter)');
    
    subplot(2, 1, 2);
    plot_acf(sig_g, fs_g, 'Garda (Surface Boat)');
    
    out_dir = 'C:\Users\Roy\dev\research\research\images';
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end
    saveas(gcf, fullfile(out_dir, 'acf_comparison.png'));
    
    % copy to artifacts
    artifact_dir = 'C:\Users\Roy\.gemini\antigravity-ide\brain\ba8fb3cc-11cb-4768-982c-06c5cf44fdb9';
    saveas(gcf, fullfile(artifact_dir, 'acf_comparison.png'));
    fprintf('ACF comparison saved to acf_comparison.png\n');
end

function plot_acf(y, fs, title_str)
    fs_intermediate = 8000;
    y_ds = resample(y, fs_intermediate, fs);
    env = abs(hilbert(y_ds));
    
    fs_env = 2000;
    env_ds = resample(env, fs_env, fs_intermediate);
    
    max_lag_env = round(0.5 * fs_env);
    env_det = env_ds - mean(env_ds);
    [acf, lags] = xcorr(env_det, max_lag_env, 'coeff');
    acf_pos = acf(max_lag_env + 1:end);
    lags_pos = lags(max_lag_env + 1:end) / fs_env * 1000; % in ms
    
    % Method 1: First crossing of 1/e
    idx_1e = find(acf_pos <= exp(-1), 1, 'first');
    coh_1e = (idx_1e - 1) / fs_env * 1000;
    
    % Method 2: Integral of squared ACF
    coh_int = sum(acf_pos.^2) / fs_env * 1000;
    
    % Method 3: Integral of absolute ACF
    coh_abs = sum(abs(acf_pos)) / fs_env * 1000;
    
    % Method 4: Last peak above 1/e
    [pks, locs] = findpeaks(acf_pos);
    valid_locs = locs(pks > exp(-1));
    if ~isempty(valid_locs)
        coh_peak = valid_locs(end) / fs_env * 1000;
    else
        coh_peak = coh_1e;
    end
    
    fprintf('%s -> 1/e: %.1f | Int(ACF^2): %.1f | Int(|ACF|): %.1f | LastPeak: %.1f\n', ...
        title_str, coh_1e, coh_int, coh_abs, coh_peak);
    
    % Plot
    plot(lags_pos, acf_pos, 'k', 'LineWidth', 1.5);
    hold on;
    yline(exp(-1), 'r--', '1/e threshold');
    plot(coh_1e, exp(-1), 'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
    
    title(sprintf('%s\n1/e Cross: %.1f ms | Int(ACF^2): %.1f ms | Int(|ACF|): %.1f ms', ...
        title_str, coh_1e, coh_int, coh_abs));
    xlabel('Lag (ms)');
    ylabel('Autocorrelation');
    grid on;
end
