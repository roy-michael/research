function apply_mnf_denoising()
    wav_path = 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\2407_1_600m\merged_2407_1_600m.wav';
    
    % Resolve output directory in artifacts folder
    artifact_dir = 'C:\Users\gorke\.gemini\antigravity-ide\brain\391562fb-52fa-44fb-9f43-9869923afe12';
    output_wav_path = fullfile(artifact_dir, 'denoised_merged_2407_1_600m.wav');
    output_img_before = fullfile(artifact_dir, 'spectrogram_before.png');
    output_img_after = fullfile(artifact_dir, 'spectrogram_after.png');

    % Get info
    info = audioinfo(wav_path);
    fs = info.SampleRate;
    total_samples = info.TotalSamples;
    
    % Parameters for STFT
    win_len = 2048;
    hop = win_len / 4;
    nfft = win_len;
    window = hann(win_len, 'periodic');
    
    % Step 1: Estimate MNF transform matrix V using a 2-minute segment of the audio
    % 2 minutes = 120 seconds.
    est_samples = min(total_samples, 120 * fs);
    fprintf('Loading representative segment for MNF estimation (120s)...\n');
    y_sub = audioread(wav_path, [1, est_samples]);
    if size(y_sub, 2) > 1
        y_sub = mean(y_sub, 2);
    end
    
    fprintf('Computing STFT on segment...\n');
    [S_sub, F, T_sub] = stft(y_sub, fs, 'Window', window, 'OverlapLength', win_len - hop, 'FFTLength', nfft);
    
    X_sub = S_sub.'; % [num_frames, num_bins]
    [num_frames_sub, num_bins] = size(X_sub);
    
    % Shift-difference noise covariance
    D_sub = X_sub(2:end, :) - X_sub(1:end-1, :);
    Sigma_N = (D_sub' * D_sub) / (size(D_sub, 1) - 1);
    
    % Data covariance
    X_mean = mean(X_sub, 1);
    X_centered = X_sub - X_mean;
    Sigma_X = (X_centered' * X_centered) / (num_frames_sub - 1);
    
    % Regularization
    Sigma_N = Sigma_N + 1e-8 * eye(num_bins);
    
    % Generalized Eigenvalues
    fprintf('Solving generalized eigenvalue problem...\n');
    [V, D_eig] = eig(Sigma_X, Sigma_N);
    eigenvalues = diag(D_eig);
    [eigenvalues, sort_idx] = sort(real(eigenvalues), 'descend');
    V = V(:, sort_idx);
    
    % Determine components to keep
    threshold = 1.5;
    keep_indices = find(eigenvalues > threshold);
    if isempty(keep_indices) || length(keep_indices) < round(0.05 * num_bins)
        keep_indices = 1:round(0.15 * num_bins); % Fallback to top 15%
    end
    num_keep = length(keep_indices);
    fprintf('Keeping %d components out of %d (eigenvalue threshold: %.2f)\n', num_keep, num_bins, threshold);
    
    % Prepare projection matrix
    V_inv = pinv(V);
    
    % Step 2: Denoise the audio in blocks
    % We will process the audio in 5-minute blocks to be safe and memory-efficient.
    fprintf('Pre-allocating output audio vector...\n');
    y_denoised = zeros(total_samples, 1, 'single');
    
    block_len_sec = 300; % 5 minutes
    block_samples = block_len_sec * fs;
    
    start_idx = 1;
    while start_idx <= total_samples
        end_idx = min(start_idx + block_samples - 1, total_samples);
        fprintf('Processing block %d to %d (of %d)...\n', start_idx, end_idx, total_samples);
        
        % Read block
        y_block = audioread(wav_path, [start_idx, end_idx]);
        if size(y_block, 2) > 1
            y_block = mean(y_block, 2);
        end
        
        % STFT
        [S_block, F_block, T_block] = stft(y_block, fs, 'Window', window, 'OverlapLength', win_len - hop, 'FFTLength', nfft);
        
        % Project block frames to MNF space
        X_block = S_block.';
        X_block_centered = X_block - X_mean;
        Y_block = X_block_centered * V;
        
        % Keep only top components
        Y_block(:, num_keep+1:end) = 0;
        
        % Reconstruct STFT
        X_block_reconstructed = Y_block * V_inv + X_mean;
        S_block_reconstructed = X_block_reconstructed.';
        
        % ISTFT
        y_block_denoised = real(istft(S_block_reconstructed, fs, 'Window', window, 'OverlapLength', win_len - hop, 'FFTLength', nfft));
        
        % Ensure length matches y_block
        len_diff = length(y_block) - length(y_block_denoised);
        if len_diff > 0
            y_block_denoised = [y_block_denoised; zeros(len_diff, 1)];
        elseif len_diff < 0
            y_block_denoised = y_block_denoised(1:length(y_block));
        end
        
        % Store in output
        y_denoised(start_idx:end_idx) = single(y_block_denoised);
        
        start_idx = start_idx + block_samples;
    end
    
    % Write denoised audio
    fprintf('Writing denoised audio to: %s\n', output_wav_path);
    audiowrite(output_wav_path, double(y_denoised), fs);
    
    % Step 3: Generate Spectrograms
    % We will generate spectrograms for a 10-second segment (e.g. from the middle of the audio)
    fprintf('Generating spectrograms for a 10-second segment...\n');
    plot_start = round(total_samples / 2);
    plot_end = plot_start + 10 * fs;
    
    y_plot_orig = audioread(wav_path, [plot_start, plot_end]);
    if size(y_plot_orig, 2) > 1
        y_plot_orig = mean(y_plot_orig, 2);
    end
    
    y_plot_denoised = y_denoised(plot_start:plot_end);
    
    [S_orig, F_plot, T_plot] = stft(y_plot_orig, fs, 'Window', window, 'OverlapLength', win_len - hop, 'FFTLength', nfft);
    [S_den, ~, ~] = stft(double(y_plot_denoised), fs, 'Window', window, 'OverlapLength', win_len - hop, 'FFTLength', nfft);
    
    S_orig_db = 20 * log10(abs(S_orig) + eps);
    S_den_db = 20 * log10(abs(S_den) + eps);
    
    % Find indices for 0-2 kHz range
    idx_2k = find(F_plot <= 2000);
    S_orig_db_sub = S_orig_db(idx_2k, :);
    max_db = max(S_orig_db_sub(:));
    min_db = max_db - 80;
    
    % Original Spectrogram Plot
    fig1 = figure('Visible', 'off', 'Position', [100 100 1200 600]);
    imagesc(T_plot, F_plot/1000, S_orig_db);
    axis xy;
    ylim([0 2]);
    colorbar;
    clim([min_db max_db]);
    colormap('turbo');
    title('Original Spectrogram (Before MNF)');
    xlabel('Time (s)');
    ylabel('Frequency (kHz)');
    saveas(fig1, output_img_before);
    close(fig1);
    
    % Denoised Spectrogram Plot
    fig2 = figure('Visible', 'off', 'Position', [100 100 1200 600]);
    imagesc(T_plot, F_plot/1000, S_den_db);
    axis xy;
    ylim([0 2]);
    colorbar;
    clim([min_db max_db]);
    colormap('turbo');
    title('Denoised Spectrogram (After MNF)');
    xlabel('Time (s)');
    ylabel('Frequency (kHz)');
    saveas(fig2, output_img_after);
    close(fig2);
    
    fprintf('Successfully completed MNF noise reduction and saved spectrograms.\n');
end
