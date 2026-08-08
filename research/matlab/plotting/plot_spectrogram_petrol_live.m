% MAIN_LIVE_SPECTROGRAM_PETROL
% Reads all audio files in both Petrol datasets (Deep and Shallow) and plots 
% full-resolution live spectrograms for comparison.

% Define paths for both datasets
DATASETS = {
    'C:\Users\Roy\Recordings\Garda_2_26\2_Deep Water\Petrol', 'Deep Water';
    'C:\Users\Roy\Recordings\Garda_2_26\1_Shallow Water\Petrol', 'Shallow Water'
};

for d = 1:size(DATASETS, 1)
    DIR_PATH = DATASETS{d, 1};
    DATASET_NAME = DATASETS{d, 2};
    
    fprintf('\n======================================================\n');
    fprintf('Processing Dataset: Petrol (%s)\n', DATASET_NAME);
    fprintf('======================================================\n');
    
    try
        % Get list of all .wav files in the directory
        files = dir(fullfile(DIR_PATH, '*.wav'));
        if isempty(files)
            error('No .wav files found in %s', DIR_PATH);
        end
        
        % Sort files alphabetically by name to ensure sequential order
        [~, sortIdx] = sort({files.name});
        files = files(sortIdx);
        
        fprintf('Selected all %d .wav files in the %s dataset.\n', length(files), DATASET_NAME);
        
        % Pre-allocate array for memory efficiency and speed
        total_samples = 0;
        sample_rate = [];
        for i = 1:length(files)
            info = audioinfo(fullfile(files(i).folder, files(i).name));
            total_samples = total_samples + info.TotalSamples;
            if i == 1
                sample_rate = info.SampleRate;
            end
        end
        
        fprintf('Total samples to load: %d. Allocating memory...\n', total_samples);
        continuous_data = zeros(total_samples, 1);
        
        % Read and concatenate sequentially
        current_idx = 1;
        for i = 1:length(files)
            file_path = fullfile(files(i).folder, files(i).name);
            fprintf('Reading [%d/%d]: %s\n', i, length(files), files(i).name);
            
            [y, fs] = audioread(file_path);
            
            if fs ~= sample_rate
                warning('Sample rate mismatch in %s. Expected %d Hz, got %d Hz.', files(i).name, sample_rate, fs);
            end
            
            % Convert to mono if it happens to be multi-channel
            if size(y, 2) > 1
                y = mean(y, 2);
            end
            
            num_samples = length(y);
            continuous_data(current_idx : current_idx + num_samples - 1) = y;
            current_idx = current_idx + num_samples;
        end
        
        fprintf('Successfully loaded data. Total Shape: [%d, 1], Sample Rate: %d Hz\n', ...
            length(continuous_data), sample_rate);
        
        % Remove NaNs and Infs
        clean_data = continuous_data(isfinite(continuous_data));
        
        % Call the plotting routine
        plot_spectrogram(sample_rate, clean_data, DATASET_NAME, d);
        
    catch e
        fprintf('An error occurred while processing %s: %s\n', DATASET_NAME, e.message);
        disp(e.getReport());
    end
end

fprintf('\nAll processing complete!\n');


%% Local Functions

function plot_spectrogram(samplerate, data, dataset_name, window_offset)
    % 16k FFT for an excellent balance of crisp time and frequency resolution!
    nfft = 16384;
    % 90% overlap for very smooth time transitions (pixel every ~12 milliseconds)
    noverlap = round(nfft * 0.90); 
    step_size = nfft - noverlap;
    
    window = hann(nfft);
    
    fprintf('Computing spectrogram parameters with nfft=%d, noverlap=%d...\n', nfft, noverlap);
    
    total_samples = length(data);
    if total_samples < nfft
        error('Data length (%d) is shorter than the FFT window size (%d).', total_samples, nfft);
    end
    
    % Calculate exact output dimensions
    total_cols = fix((total_samples - noverlap) / step_size);
    
    % Generate Time vector
    T = ((0:total_cols-1) * step_size + nfft/2) / samplerate;
    
    % Dummy run to get F vector
    [~, F, ~, ~] = spectrogram(data(1:nfft), window, noverlap, nfft, samplerate);
    
    % The Petrol dataset creates a massive matrix which can crash MATLAB's renderer.
    % We safely downsample it to fit within OpenGL limits (max ~8000x8000).
    target_render_shape = [8000, 8000];
    
    step_y = max(1, floor(length(F) / target_render_shape(1)));
    step_x = max(1, floor(total_cols / target_render_shape(2)));
    
    % Calculate padded dimensions for immediate Y-downsampling
    pad_y = mod(-length(F), step_y);
    num_y_bins = (length(F) + pad_y) / step_y;
    
    % Downsample F vector to match the compressed Y-axis
    if step_y > 1
        F_padded = [F; F(end) * ones(pad_y, 1)];
        F = mean(reshape(F_padded, step_y, num_y_bins), 1)';
    end
    
    % Pre-allocate the master array
    Sxx_dB = zeros(num_y_bins, total_cols, 'single');
    
    % To prevent RAM overflow, we process in chunks of 500 time-bins
    cols_per_chunk = 500; 
    
    fprintf('Computing massive spectrogram in chunks to prevent memory overload (Total time bins: %d)...\n', total_cols);
    col_idx = 1;
    while col_idx <= total_cols
        cols_to_do = min(cols_per_chunk, total_cols - col_idx + 1);
        
        start_sample = (col_idx - 1) * step_size + 1;
        end_sample = start_sample + nfft - 1 + (cols_to_do - 1) * step_size;
        
        chunk_data = data(start_sample:end_sample);
        
        % Compute spectrogram for just this chunk
        [~, ~, ~, P_chunk] = spectrogram(chunk_data, window, noverlap, nfft, samplerate);
        
        S_chunk_dB = 10 * log10(P_chunk + eps);
        
        % Compress Y-axis on the fly BEFORE appending to main matrix
        if step_y > 1
            if pad_y > 0
                pad_val = min(S_chunk_dB(:));
                S_chunk_dB = [S_chunk_dB; pad_val * ones(pad_y, size(S_chunk_dB, 2), 'single')];
            end
            S_chunk_dB = reshape(S_chunk_dB, step_y, num_y_bins, cols_to_do);
            S_chunk_dB = reshape(max(S_chunk_dB, [], 1), num_y_bins, cols_to_do);
        end
        
        Sxx_dB(:, col_idx : col_idx + cols_to_do - 1) = single(S_chunk_dB);
        
        col_idx = col_idx + cols_to_do;
        if mod(col_idx - 1, cols_per_chunk * 4) == 0 || col_idx > total_cols
            fprintf('  Progress: %d / %d time bins (%.1f%%)\n', col_idx - 1, total_cols, 100*(col_idx-1)/total_cols);
        end
    end
    
    fprintf('Spectrogram computed successfully. Setting up live plot...\n');
    
    % Compress time axis if needed
    if step_x > 1
        fprintf('Downsampling time axis (%dx%d) for safe MATLAB rendering...\n', size(Sxx_dB,1), size(Sxx_dB,2));
        display_data = max_downsample(Sxx_dB, 1, step_x);
    else
        display_data = Sxx_dB;
    end
    
    % Calculate sensible dynamic color limits to massively increase signal power
    fprintf('Calculating optimal color contrast...\n');
    sub_Sxx = display_data(1:10:end, 1:10:end);
    sorted_Sxx = sort(sub_Sxx(:));
    len = length(sorted_Sxx);
    
    % 99.9th percentile (ignores sudden extreme clicks that squash the dynamic range)
    max_dB = sorted_Sxx(max(1, round(len * 0.999))); 
    % 10th percentile (raises the noise floor visually, making signals pop)
    min_dB = sorted_Sxx(max(1, round(len * 0.10))); 
    
    if max_dB <= min_dB
        max_dB = min_dB + 1; % Failsafe for purely silent signals
    end
    
    % Create Figure and Axes (offset slightly so they don't completely overlap)
    fig = figure('Name', sprintf('Live Spectrogram of Petrol (%s)', dataset_name), ...
                 'Position', [100 + (window_offset-1)*50, 100 + (window_offset-1)*50, 1200, 800]);
    ax = axes(fig);
    
    % Plot using the full resolution array
    fprintf('Rendering matrix to figure (this might take a few seconds)...\n');
    imagesc(ax, [T(1), T(end)], [F(1), F(end)], display_data);
    axis(ax, 'xy');    % Set origin to lower-left (equivalent to origin='lower')
    axis(ax, 'tight'); % Fit axes tightly to data limits
    
    % Apply colormap (viridis available in newer MATLAB versions, fallback to parula)
    try colormap(ax, 'viridis'); catch, colormap(ax, 'parula'); end
    
    % Lock color limits so the signal is visible and powerful
    try clim(ax, double([min_dB, max_dB])); catch, caxis(ax, double([min_dB, max_dB])); end
    
    ylabel(ax, 'Frequency [Hz]');
    xlabel(ax, 'Time [sec]');
    title(ax, sprintf('High-Resolution Spectrogram of Petrol (%s)', dataset_name));
    
    cb = colorbar(ax);
    cb.Label.String = 'Power/Frequency (dB/Hz)';
    
    % Enable zoom mode automatically
    zoom(fig, 'on');
    
    fprintf('Plot is live for %s!\n', dataset_name);
    
    % Calculate and plot the median spectrum across time
    fprintf('Calculating median spectrum across time...\n');
    % Sxx_dB is size [num_y_bins, total_cols]. Median across dim 2 (time).
    median_spectrum = median(Sxx_dB, 2);
    
    fig_med = figure('Name', sprintf('Median Spectrum of Petrol (%s)', dataset_name), ...
                     'Position', [700 + (window_offset-1)*50, 100 + (window_offset-1)*50, 800, 600]);
    ax_med = axes(fig_med);
    
    % F matches the rows of Sxx_dB since it was identically downsampled/padded above.
    plot(ax_med, F, median_spectrum, 'k', 'LineWidth', 1.5);
    xlabel(ax_med, 'Frequency [Hz]');
    ylabel(ax_med, 'Median Power/Frequency (dB/Hz)');
    title(ax_med, sprintf('Median Spectrum across Time - Petrol (%s)', dataset_name));
    grid(ax_med, 'on');
    
    % Enable zoom on this figure as well
    zoom(fig_med, 'on');
end

function out = max_downsample(data, step_y, step_x)
    % 2D Max Pooling ensures we don't skip narrow-band signals when scaling down
    if step_y == 1 && step_x == 1
        out = data;
        return;
    end
    
    [H, W] = size(data);
    pad_y = mod(-H, step_y);
    pad_x = mod(-W, step_x);
    
    % Pad array with the minimum value to ensure complete block shapes
    if pad_y > 0 || pad_x > 0
        pad_val = min(data(:));
        data = padarray(data, [pad_y, pad_x], pad_val, 'post');
    end
    
    [H_pad, W_pad] = size(data);
    
    % Apply max across columns (Time axis)
    if step_x > 1
        data = reshape(data, H_pad, step_x, W_pad / step_x);
        data = max(data, [], 2);
        data = reshape(data, H_pad, W_pad / step_x);
        W_pad = W_pad / step_x;
    end
    
    % Apply max across rows (Frequency axis)
    if step_y > 1
        data = reshape(data, step_y, H_pad / step_y, W_pad);
        data = max(data, [], 1);
        data = reshape(data, H_pad / step_y, W_pad);
    end
    
    out = data;
end
