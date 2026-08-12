function plot_coh_time_series()
    rec_path = get_recordings_path();
    
    % Pick a representative scooter run and boat run
    croatia_file = fullfile(rec_path, 'Croatia\Ocean Sonics\2407_1_600m\RBW6737_20250724_091500.wav');
    garda_file = fullfile(rec_path, 'Garda_2_26\1_Shallow Water\Electric\0946.wav');
    
    % Analyze 5 minutes of data in 5-second consecutive blocks
    block_sec = 5;
    total_min = 5;
    num_blocks = (total_min * 60) / block_sec;
    
    coh_c = zeros(num_blocks, 1);
    coh_g = zeros(num_blocks, 1);
    
    info_c = audioinfo(croatia_file);
    info_g = audioinfo(garda_file);
    fs_c_native = info_c.SampleRate;
    fs_g_native = info_g.SampleRate;
    
    % Make sure we don't read past the end of the file
    max_blocks_c = floor(info_c.TotalSamples / (block_sec * fs_c_native));
    max_blocks_g = floor(info_g.TotalSamples / (block_sec * fs_g_native));
    num_blocks = min([num_blocks, max_blocks_c, max_blocks_g]);
    
    coh_c = zeros(num_blocks, 1);
    coh_g = zeros(num_blocks, 1);
    
    fprintf('Extracting Time Series for Croatia (Scooter)...\n');
    for b = 1:num_blocks
        start_samp = (b-1)*block_sec*fs_c_native + 1;
        end_samp = b*block_sec*fs_c_native;
        sig = audioread(croatia_file, [start_samp, end_samp]);
        if size(sig, 2) > 1, sig = mean(sig, 2); end
        coh_c(b) = get_env_coh(sig, fs_c_native);
    end
    
    fprintf('Extracting Time Series for Garda (Boat)...\n');
    for b = 1:num_blocks
        start_samp = (b-1)*block_sec*fs_g_native + 1;
        end_samp = b*block_sec*fs_g_native;
        sig = audioread(garda_file, [start_samp, end_samp]);
        if size(sig, 2) > 1, sig = mean(sig, 2); end
        coh_g(b) = get_env_coh(sig, fs_g_native);
    end
    
    % Smooth the curves slightly for better visualization of the macroscopic trend
    coh_c_smooth = movmean(coh_c, 3);
    coh_g_smooth = movmean(coh_g, 3);
    
    time_axis = (1:num_blocks) * block_sec;
    
    fig = figure('Visible', 'off', 'Position', [100, 100, 1200, 600]);
    
    % Subplot 1: Overlay
    subplot(1, 2, 1);
    plot(time_axis, coh_c_smooth, 'LineWidth', 2, 'Color', [0 0.4470 0.7410], 'DisplayName', 'Croatia (Underwater Scooter)');
    hold on;
    plot(time_axis, coh_g_smooth, 'LineWidth', 2, 'Color', [0.8500 0.3250 0.0980], 'DisplayName', 'Garda (Surface Boat)');
    title('Envelope Coherence Time Over 5-Minute Run', 'FontSize', 14);
    xlabel('Time (seconds)', 'FontSize', 12);
    ylabel('Coherence Time \tau_{1/e} (ms)', 'FontSize', 12);
    legend('Location', 'best');
    grid on;
    ylim([0, max([max(coh_c_smooth), max(coh_g_smooth)]) * 1.1]);
    
    % Subplot 2: Stacked Area (to show dominance)
    subplot(1, 2, 2);
    area(time_axis, coh_g_smooth, 'FaceColor', [0.8500 0.3250 0.0980], 'FaceAlpha', 0.5, 'DisplayName', 'Garda (Boat)');
    hold on;
    area(time_axis, coh_c_smooth, 'FaceColor', [0 0.4470 0.7410], 'FaceAlpha', 0.7, 'DisplayName', 'Croatia (Scooter)');
    title('Coherence Area Comparison', 'FontSize', 14);
    xlabel('Time (seconds)', 'FontSize', 12);
    ylabel('Coherence Time (ms)', 'FontSize', 12);
    legend('Location', 'best');
    grid on;
    ylim([0, max([max(coh_c_smooth), max(coh_g_smooth)]) * 1.1]);
    
    sgtitle('Dynamic Behavior of Envelope Coherence Time', 'FontSize', 16, 'FontWeight', 'bold');
    
    out_dir = 'C:\Users\Roy\dev\research\research\images';
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end
    saveas(fig, fullfile(out_dir, 'coh_time_series.png'));
    
    artifact_dir = 'C:\Users\Roy\.gemini\antigravity-ide\brain\ba8fb3cc-11cb-4768-982c-06c5cf44fdb9';
    saveas(fig, fullfile(artifact_dir, 'coh_time_series.png'));
    close(fig);
    fprintf('Saved coh_time_series.png\n');
end

function coh = get_env_coh(y, fs)
    [b_hp, a_hp] = butter(2, 100 / (fs/2), 'high');
    y_filt = filter(b_hp, a_hp, y);
    
    fs_intermediate = 8000;
    y_ds = resample(y_filt, fs_intermediate, fs);
    
    env = abs(hilbert(y_ds));
    
    fs_env = 2000;
    env_ds = resample(env, fs_env, fs_intermediate);
    
    max_lag_env = round(0.5 * fs_env);
    env_det = env_ds - mean(env_ds);
    [acf, ~] = xcorr(env_det, max_lag_env, 'coeff');
    acf_pos = acf(max_lag_env + 1:end);
    idx = find(acf_pos <= exp(-1), 1, 'first');
    if ~isempty(idx)
        coh = (idx - 1) / fs_env * 1000;
    else
        coh = max_lag_env / fs_env * 1000;
    end
end
