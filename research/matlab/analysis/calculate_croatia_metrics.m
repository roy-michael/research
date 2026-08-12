function calculate_croatia_metrics()
    wav_path = 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2407_1_600m.wav';
    
    % Check if file exists
    if ~exist(wav_path, 'file')
        error('Audio file not found: %s', wav_path);
    end
    
    % Resolve output directory in artifacts folder
    artifact_dir = 'C:\Users\gorke\.gemini\antigravity-ide\brain\a09a1b5f-d3a3-40cf-b59b-54d19ca16f61';
    if ~exist(artifact_dir, 'dir')
        mkdir(artifact_dir);
    end
    output_img = fullfile(artifact_dir, 'autocorrelation_croatia.png');
    
    % Get audio info
    info = audioinfo(wav_path);
    fs = info.SampleRate;
    total_samples = info.TotalSamples;
    duration = info.Duration;
    
    fprintf('--- Audio File Information ---\n');
    fprintf('Path: %s\n', wav_path);
    fprintf('Sample Rate: %d Hz\n', fs);
    fprintf('Total Samples: %d\n', total_samples);
    fprintf('Duration: %.2f seconds (%.2f minutes)\n\n', duration, duration/60);
    
    % Processing parameters
    block_len_sec = 10; % 10-second blocks
    block_samples = block_len_sec * fs;
    num_blocks = floor(total_samples / block_samples);
    
    % Limit to first 20 blocks (~3.3 minutes) for quick and reliable computation
    blocks_to_process = min(20, num_blocks);
    
    % Preallocate results
    masd_raw_all = zeros(blocks_to_process, 1);
    coherence_time_raw_1e = zeros(blocks_to_process, 1);
    coherence_time_raw_05 = zeros(blocks_to_process, 1);
    
    masd_env_all = zeros(blocks_to_process, 1);
    coherence_time_env_1e = zeros(blocks_to_process, 1);
    coherence_time_env_05 = zeros(blocks_to_process, 1);
    
    % Keep track of ACFs for plotting (average of processed blocks)
    max_lag_raw = round(0.5 * fs); % 500 ms max lag for raw signal
    acf_raw_sum = zeros(max_lag_raw + 1, 1);
    
    % For envelope, we'll downsample to 2000 Hz to calculate coherence time over longer lags
    fs_env = 2000;
    max_lag_env = round(1.0 * fs_env); % 1 second max lag for envelope
    acf_env_sum = zeros(max_lag_env + 1, 1);
    
    fprintf('Processing %d blocks of %d seconds each...\n', blocks_to_process, block_len_sec);
    
    for b = 1:blocks_to_process
        start_sample = (b - 1) * block_samples + 1;
        end_sample = start_sample + block_samples - 1;
        
        % Read block
        y = audioread(wav_path, [start_sample, end_sample]);
        if size(y, 2) > 1
            y = mean(y, 2);
        end
        
        % --- Raw Signal Calculations ---
        % 1. MASD
        masd_raw_all(b) = mean(abs(diff(y)));
        
        % 2. Autocorrelation & Coherence Time
        y_detrend = y - mean(y);
        [acf_raw, lags_raw] = xcorr(y_detrend, max_lag_raw, 'coeff');
        % Keep only positive lags
        acf_raw_pos = acf_raw(max_lag_raw + 1:end);
        acf_raw_sum = acf_raw_sum + acf_raw_pos;
        
        % Find first drop below thresholds
        idx_1e = find(acf_raw_pos <= exp(-1), 1, 'first');
        if ~isempty(idx_1e)
            coherence_time_raw_1e(b) = (idx_1e - 1) / fs;
        else
            coherence_time_raw_1e(b) = max_lag_raw / fs;
        end
        
        idx_05 = find(acf_raw_pos <= 0.5, 1, 'first');
        if ~isempty(idx_05)
            coherence_time_raw_05(b) = (idx_05 - 1) / fs;
        else
            coherence_time_raw_05(b) = max_lag_raw / fs;
        end
        
        % --- Envelope Calculations ---
        % Extract amplitude envelope using absolute value of Hilbert transform
        env = abs(hilbert(y));
        % Downsample envelope for speed and physical relevance (modulation)
        env_ds = resample(env, fs_env, fs);
        
        % 1. MASD of Envelope
        masd_env_all(b) = mean(abs(diff(env_ds)));
        
        % 2. Autocorrelation & Coherence Time of Envelope
        env_detrend = env_ds - mean(env_ds);
        [acf_env, lags_env] = xcorr(env_detrend, max_lag_env, 'coeff');
        acf_env_pos = acf_env(max_lag_env + 1:end);
        acf_env_sum = acf_env_sum + acf_env_pos;
        
        idx_env_1e = find(acf_env_pos <= exp(-1), 1, 'first');
        if ~isempty(idx_env_1e)
            coherence_time_env_1e(b) = (idx_env_1e - 1) / fs_env;
        else
            coherence_time_env_1e(b) = max_lag_env / fs_env;
        end
        
        idx_env_05 = find(acf_env_pos <= 0.5, 1, 'first');
        if ~isempty(idx_env_05)
            coherence_time_env_05(b) = (idx_env_05 - 1) / fs_env;
        else
            coherence_time_env_05(b) = max_lag_env / fs_env;
        end
    end
    
    % Average ACFs
    acf_raw_avg = acf_raw_sum / blocks_to_process;
    acf_env_avg = acf_env_sum / blocks_to_process;
    
    % Display Results
    fprintf('\n================ RESULTS ================\n');
    fprintf('RAW ACOUSTIC SIGNAL METRICS:\n');
    fprintf('  Mean MASD:                  %.6f\n', mean(masd_raw_all));
    fprintf('  Mean Coherence Time (1/e):  %.6f ms (%.2f samples)\n', mean(coherence_time_raw_1e)*1000, mean(coherence_time_raw_1e)*fs);
    fprintf('  Mean Coherence Time (0.5):  %.6f ms (%.2f samples)\n', mean(coherence_time_raw_05)*1000, mean(coherence_time_raw_05)*fs);
    fprintf('\n');
    fprintf('AMPLITUDE ENVELOPE METRICS:\n');
    fprintf('  Mean MASD (Downsampled):    %.6f\n', mean(masd_env_all));
    fprintf('  Mean Coherence Time (1/e):  %.6f ms\n', mean(coherence_time_env_1e)*1000);
    fprintf('  Mean Coherence Time (0.5):  %.6f ms\n', mean(coherence_time_env_05)*1000);
    fprintf('=========================================\n');
    
    % Plot Autocorrelation Functions
    t_raw = (0:max_lag_raw) / fs * 1000; % ms
    t_env = (0:max_lag_env) / fs_env * 1000; % ms
    
    fig = figure('Visible', 'off', 'Position', [100, 100, 1000, 500]);
    
    subplot(1, 2, 1);
    plot(t_raw, acf_raw_avg, 'LineWidth', 2, 'Color', '#0072BD');
    hold on;
    grid on;
    yline(exp(-1), '--r', '1/e Threshold', 'LabelHorizontalAlignment', 'right');
    yline(0.5, '--g', '0.5 Threshold', 'LabelHorizontalAlignment', 'right');
    title('Raw Signal Autocorrelation');
    xlabel('Lag (ms)');
    ylabel('Normalized Autocorrelation');
    xlim([0, t_raw(end)]);
    
    subplot(1, 2, 2);
    plot(t_env, acf_env_avg, 'LineWidth', 2, 'Color', '#D95319');
    hold on;
    grid on;
    yline(exp(-1), '--r', '1/e Threshold', 'LabelHorizontalAlignment', 'right');
    yline(0.5, '--g', '0.5 Threshold', 'LabelHorizontalAlignment', 'right');
    title('Amplitude Envelope Autocorrelation');
    xlabel('Lag (ms)');
    ylabel('Normalized Autocorrelation');
    xlim([0, t_env(end)]);
    
    saveas(fig, output_img);
    close(fig);
    fprintf('Autocorrelation plot saved to: %s\n', output_img);
end
