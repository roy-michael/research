% MAIN_STATIC_SPECTROGRAM
% Optimized for memory by chunking and immediate downsampling
DIR_PATH = 'C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2507_1_1k';
try
    files = dir(fullfile(DIR_PATH, '*.wav'));
    if isempty(files), error('No .wav files found'); end
    [~, sortIdx] = sort({files.name});
    files = files(sortIdx);
    
    total_samples = 0;
    for i = 1:length(files)
        info = audioinfo(fullfile(files(i).folder, files(i).name));
        total_samples = total_samples + info.TotalSamples;
        if i == 1, sample_rate = info.SampleRate; end
    end
    
    continuous_data = zeros(total_samples, 1);
    current_idx = 1;
    for i = 1:length(files)
        [y, ~] = audioread(fullfile(files(i).folder, files(i).name));
        if size(y, 2) > 1, y = mean(y, 2); end
        continuous_data(current_idx : current_idx + length(y) - 1) = y;
        current_idx = current_idx + length(y);
    end
    
    clean_data = continuous_data(isfinite(continuous_data));
    plot_spectrogram(sample_rate, clean_data);
catch e
    fprintf('An error occurred: %s\n', e.message);
end

function plot_spectrogram(samplerate, data)
    nfft = 16 * 1024;
    window_length = nfft;
    noverlap = round(window_length * 0.90); 
    step_size = window_length - noverlap;
    window = hann(window_length);
    
    % Downsampling factor to keep memory within 15.7GB limit
    % Aiming for a final matrix roughly 20000 columns wide
    target_cols = 20000;
    total_samples = length(data);
    total_cols = fix((total_samples - noverlap) / step_size);
    time_downsample = max(1, ceil(total_cols / target_cols));
    final_cols = ceil(total_cols / time_downsample);
    
    % Calculate F vector
    [~, F, ~, ~] = spectrogram(data(1:window_length), window, noverlap, nfft, samplerate);
    
    % Pre-allocate only the downsampled matrix
    Sxx_dB = zeros(length(F), final_cols, 'single');
    
    use_gpu = canUseGPU();
    if use_gpu
        fprintf('GPU detected. Using parallel acceleration...\n');
        data = gpuArray(single(data));
        window = gpuArray(single(window));
    end
    
    fprintf('Computing and downsampling spectrogram (Memory-Safe Mode)...\n');
    chunk_size = 2000; 
    for col_idx = 1:chunk_size:total_cols
        cols_to_do = min(chunk_size, total_cols - col_idx + 1);
        start_sample = (col_idx - 1) * step_size + 1;
        end_sample = start_sample + window_length - 1 + (cols_to_do - 1) * step_size;
        
        [~, ~, ~, P_chunk] = spectrogram(data(start_sample:end_sample), window, noverlap, nfft, samplerate);
        chunk_dB = gather(10 * log10(P_chunk + eps));
        
        % Downsample this chunk in time before placing into Sxx_dB
        start_target = ceil(col_idx / time_downsample);
        end_target = start_target + size(chunk_dB, 2) / time_downsample - 1;
        
        % Simplified downsampling: pick every Nth column
        Sxx_dB(:, start_target:end_target) = chunk_dB(:, 1:time_downsample:end);
        
        fprintf('  Processed %d / %d time columns\n', min(col_idx + chunk_size, total_cols), total_cols);
    end
    
    % Final Plotting
    fig = figure('Position', [100, 100, 1200, 800]);
    imagesc([0 total_cols*step_size/samplerate], [F(1) F(end)], Sxx_dB);
    axis xy; colormap(viridis); clim([-110 -40]);
    ylabel('Frequency [Hz]'); xlabel('Time [sec]');
    colorbar;
    fprintf('Plotting complete!\n');
end

function use_gpu = canUseGPU()
    try use_gpu = gpuDeviceCount > 0; catch, use_gpu = false; end
end