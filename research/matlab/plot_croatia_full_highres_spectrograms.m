function plot_croatia_full_highres_spectrograms()
    % Define the 5 Croatia datasets
    croatia_datasets = {
        struct('name', 'Croatia 2307 Free', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2307_free.wav', 'filename_out', 'croatia_2307_free_full_highres.png'), ...
        struct('name', 'Croatia 2407_1 600m', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2407_1_600m.wav', 'filename_out', 'croatia_2407_1_600m_full_highres.png'), ...
        struct('name', 'Croatia 2407_2 Snake', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2407_2_snake.wav', 'filename_out', 'croatia_2407_2_snake_full_highres.png'), ...
        struct('name', 'Croatia 2507_1 1k', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2507_1_1k.wav', 'filename_out', 'croatia_2507_1_1k_full_highres.png'), ...
        struct('name', 'Croatia 2507_2 Joint', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2507_2_joint.wav', 'filename_out', 'croatia_2507_2_joint_full_highres.png')
    };
    
    artifact_dir = 'C:\Users\gorke\.gemini\antigravity-ide\brain\a09a1b5f-d3a3-40cf-b59b-54d19ca16f61';
    if ~exist(artifact_dir, 'dir')
        mkdir(artifact_dir);
    end
    
    fs_new = 4000; % Downsample to 4 kHz (covers 0 - 2000 Hz, well above 1200 Hz BP limit)
    
    % STFT Parameters for High Resolution at 4 kHz
    win_len = 512;     % 512 FFT size -> 7.8 Hz frequency bins
    hop = 128;         % 75% overlap -> 32 ms temporal frames
    nfft = 512;
    window = hann(win_len, 'periodic');
    
    for d = 1:length(croatia_datasets)
        ds = croatia_datasets{d};
        fprintf('Processing full timeline spectrogram for: %s...\n', ds.name);
        
        if ~exist(ds.path, 'file')
            fprintf('  Warning: File %s not found. Skipping.\n', ds.path);
            continue;
        end
        
        % 1. Read the ENTIRE 1-hour audio file
        info = audioinfo(ds.path);
        fs = info.SampleRate;
        y = audioread(ds.path);
        if size(y, 2) > 1, y = mean(y, 2); end
        
        % 2. Apply stable continuous bandpass filter (400 - 1200 Hz) using filtfilt
        [sos, g] = butter(4, [400, 1200] / (fs / 2), 'bandpass');
        y_filt = filtfilt(sos, g, y);
        
        % Clear original y to free memory
        clear y;
        
        % 3. Downsample to 4 kHz
        y_ds = resample(y_filt, fs_new, fs);
        clear y_filt;
        
        % 4. Compute STFT on downsampled signal
        [S, F, T] = stft(y_ds, fs_new, 'Window', window, 'OverlapLength', win_len - hop, 'FFTLength', nfft);
        clear y_ds;
        
        % Keep only frequencies of interest (300 - 1300 Hz)
        idx_range = find(F >= 300 & F <= 1300);
        F_sub = F(idx_range);
        S_sub = abs(S(idx_range, :));
        clear S;
        
        % Convert to dB
        S_db = 20 * log10(double(S_sub) + eps);
        clear S_sub;
        
        % Time in minutes
        t_minutes = T / 60;
        
        % Plotting
        fig = figure('Visible', 'off', 'Position', [100, 100, 1800, 600]);
        imagesc(t_minutes, F_sub, S_db);
        axis xy;
        ylim([300, 1300]);
        xlim([0, t_minutes(end)]);
        colorbar;
        colormap('turbo');
        
        % Set dynamic range based on actual content
        clim([max(S_db(:)) - 50, max(S_db(:))]);
        
        title(sprintf('Full 1-Hour High-Resolution Spectrogram (BP 400-1200 Hz)\n%s', ds.name), 'FontSize', 14);
        xlabel('Time (minutes)', 'FontSize', 12);
        ylabel('Frequency (Hz)', 'FontSize', 12);
        
        out_path = fullfile(artifact_dir, ds.filename_out);
        saveas(fig, out_path);
        close(fig);
        
        fprintf('  Saved full timeline high-res spectrogram to %s\n', out_path);
    end
    fprintf('All full timeline high-res spectrograms generated successfully.\n');
end
