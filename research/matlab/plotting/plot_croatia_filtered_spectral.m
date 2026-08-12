function plot_croatia_filtered_spectral()
    % Define the 5 Croatia datasets
    croatia_datasets = {
        struct('name', 'Croatia 2307 Free', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2307_free.wav', 'filename_out', 'croatia_2307_free_filtered.png'), ...
        struct('name', 'Croatia 2407_1 600m', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2407_1_600m.wav', 'filename_out', 'croatia_2407_1_600m_filtered.png'), ...
        struct('name', 'Croatia 2407_2 Snake', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2407_2_snake.wav', 'filename_out', 'croatia_2407_2_snake_filtered.png'), ...
        struct('name', 'Croatia 2507_1 1k', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2507_1_1k.wav', 'filename_out', 'croatia_2507_1_1k_filtered.png'), ...
        struct('name', 'Croatia 2507_2 Joint', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2507_2_joint.wav', 'filename_out', 'croatia_2507_2_joint_filtered.png')
    };
    
    artifact_dir = 'C:\Users\gorke\.gemini\antigravity-ide\brain\a09a1b5f-d3a3-40cf-b59b-54d19ca16f61';
    if ~exist(artifact_dir, 'dir')
        mkdir(artifact_dir);
    end
    
    segment_len_sec = 10; % Use 10-second segment
    
    % STFT/Welch parameters
    win_len = 2048;
    overlap = 1536;
    nfft = 2048;
    window = hann(win_len, 'periodic');
    
    for d = 1:length(croatia_datasets)
        ds = croatia_datasets{d};
        fprintf('Plotting: %s...\n', ds.name);
        
        if ~exist(ds.path, 'file')
            fprintf('  Warning: File %s not found. Skipping.\n', ds.path);
            continue;
        end
        
        % Load info & 10s segment from the middle
        info = audioinfo(ds.path);
        fs = info.SampleRate;
        block_samples = segment_len_sec * fs;
        start_sample = max(1, round(info.TotalSamples / 2 - block_samples / 2));
        end_sample = start_sample + block_samples - 1;
        
        y = audioread(ds.path, [start_sample, end_sample]);
        if size(y, 2) > 1, y = mean(y, 2); end
        
        % Apply 400 - 1200 Hz bandpass filter
        [b, a] = butter(4, [400, 1200] / (fs / 2), 'bandpass');
        y_filt = filter(b, a, y);
        
        % 1. Compute Spectrogram (using stft)
        [S, F, T] = stft(y_filt, fs, 'Window', window, 'OverlapLength', overlap, 'FFTLength', nfft);
        S_db = 20 * log10(abs(S) + eps);
        
        % 2. Compute Welch PSD
        [pxx, f_welch] = pwelch(y_filt, window, overlap, nfft, fs);
        pxx_db = 10 * log10(pxx + eps);
        
        % Create figure
        fig = figure('Visible', 'off', 'Position', [100, 100, 1400, 550]);
        
        % Subplot 1: Spectrogram (400-1200 Hz range focus)
        subplot(1, 2, 1);
        imagesc(T, F, S_db);
        axis xy;
        ylim([300, 1300]);
        colorbar;
        colormap('turbo');
        clim([max(S_db(:)) - 60, max(S_db(:))]);
        title(sprintf('Spectrogram (BP 400-1200 Hz)\n%s', ds.name));
        xlabel('Time (s)');
        ylabel('Frequency (Hz)');
        
        % Subplot 2: Welch PSD
        subplot(1, 2, 2);
        plot(f_welch, pxx_db, 'LineWidth', 2, 'Color', '#0072BD');
        grid on;
        xlim([300, 1300]);
        title(sprintf('Welch Power Spectral Density\n%s', ds.name));
        xlabel('Frequency (Hz)');
        ylabel('Power/Frequency (dB/Hz)');
        
        % Save image
        out_path = fullfile(artifact_dir, ds.filename_out);
        saveas(fig, out_path);
        close(fig);
        
        fprintf('  Saved plot to %s\n', out_path);
    end
    fprintf('All filtered spectral plots generated successfully.\n');
end
