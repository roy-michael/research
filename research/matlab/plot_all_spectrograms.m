% plot_all_spectrograms.m
% Computes and plots high-resolution LOFAR grams (0-4 kHz) for each of the 5 datasets.
% Uses a large NFFT (16,384) for sharp tonal resolution, combined with moving time-averaging
% (LOFAR integration) to suppress random ambient noise and highlight narrow-band tonals.

% Resolve output directory relative to script folder
script_dir = fileparts(mfilename('fullpath'));
output_dir = fullfile(script_dir, '..', 'output');

DATASETS = {
    'D:\RoyStudies\Recordings\Garda_2_26\2_Deep Water\Electric', 'Garda_Electric_DWL_Spectrogram', 'Garda Electric (DWL, 16 kts, away)';
    'D:\RoyStudies\Recordings\Garda_2_26\2_Deep Water\Petrol', 'Garda_Petrol_DWL_Spectrogram', 'Garda Petrol (DWL, 4 kts, away)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692\leg1_straight_line_2_8m_s_6922_827-837.wav', 'AUV_Leg1_DWL_Spectrogram', 'AUV Leg 1 (5.4 kts, straight)';
    'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\2407_2_snake', 'Croatia_2407_2_DWL_Spectrogram', 'Croatia 2407_2 (snake route)';
    'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\2307_free', 'Croatia_2307_free_DWL_Spectrogram', 'Croatia 2307 (freediving Suex VR, 2.1 kts)'
};

% Calibration factor (conversion to micro-Pascals)
calibFactor = 1e6;

for d = 1:size(DATASETS, 1)
    PATH_OR_DIR = DATASETS{d, 1};
    FILE_NAME_OUT = DATASETS{d, 2};
    DISPLAY_NAME = DATASETS{d, 3};
    
    fprintf('Processing LOFAR Gram for %s...\n', DISPLAY_NAME);
    
    % Concatenate all files for the entire run
    if exist(PATH_OR_DIR, 'dir')
        files = dir(fullfile(PATH_OR_DIR, '*.wav'));
        [~, sortIdx] = sort({files.name});
        files = files(sortIdx);
        
        % Calculate total samples
        total_samples = 0;
        sample_rate = [];
        for i = 1:length(files)
            info = audioinfo(fullfile(files(i).folder, files(i).name));
            total_samples = total_samples + info.TotalSamples;
            if i == 1, sample_rate = info.SampleRate; end
        end
        
        y_all = zeros(total_samples, 1);
        current_idx = 1;
        for i = 1:length(files)
            file_path = fullfile(files(i).folder, files(i).name);
            [y, ~] = audioread(file_path);
            if size(y, 2) > 1, y = mean(y, 2); end
            num_s = length(y);
            y_all(current_idx : current_idx + num_s - 1) = y;
            current_idx = current_idx + num_s;
        end
        fs = sample_rate;
    else
        % Single file
        [y_all, fs] = audioread(PATH_OR_DIR);
        if size(y_all, 2) > 1, y_all = mean(y_all, 2); end
    end
    
    % Calibration
    y_cal = y_all * calibFactor;
    clear y_all; % Free memory
    
    % -------------------------------------------------------------
    % LOFAR Gram Computation (Spectrogram + Time Integration)
    % -------------------------------------------------------------
    fprintf('  Calculating LOFAR spectrogram...\n');
    nfft = 16384; % Large NFFT for high frequency resolution
    noverlap = round(nfft * 0.90); % 90% overlap
    step_size = nfft - noverlap;
    window = hann(nfft);
    
    total_len = length(y_cal);
    total_cols = fix((total_len - noverlap) / step_size);
    
    % Time and Frequency vectors
    T = ((0:total_cols-1) * step_size + nfft/2) / fs;
    [~, F, ~, ~] = spectrogram(y_cal(1:nfft), window, noverlap, nfft, fs);
    
    % OpenGL safe compression target shape
    target_shape = [8000, 8000];
    step_y = max(1, floor(length(F) / target_shape(1)));
    step_x = max(1, floor(total_cols / target_shape(2)));
    
    pad_y = mod(-length(F), step_y);
    num_y_bins = (length(F) + pad_y) / step_y;
    
    if step_y > 1
        F_padded = [F; F(end) * ones(pad_y, 1)];
        F = mean(reshape(F_padded, step_y, num_y_bins), 1)';
    end
    
    Sxx_dB = zeros(num_y_bins, total_cols, 'single');
    cols_per_chunk = 500;
    col_idx = 1;
    
    while col_idx <= total_cols
        cols_to_do = min(cols_per_chunk, total_cols - col_idx + 1);
        start_sample = (col_idx - 1) * step_size + 1;
        end_sample = start_sample + nfft - 1 + (cols_to_do - 1) * step_size;
        
        chunk_data = y_cal(start_sample:end_sample);
        [~, ~, ~, P_chunk] = spectrogram(chunk_data, window, noverlap, nfft, fs);
        S_chunk_dB = 10 * log10(P_chunk + eps);
        
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
    end
    
    % --- LOFAR Time-Integration (Averaging along time axis to suppress noise) ---
    fprintf('  Applying LOFAR time integration...\n');
    Sxx_dB = movmean(Sxx_dB, 12, 2); % 12-frame moving average along the time dimension
    
    % Downsample time axis if needed
    if step_x > 1
        display_data = Sxx_dB(:, 1:step_x:end);
        T_display = T(1:step_x:end);
    else
        display_data = Sxx_dB;
        T_display = T;
    end
    
    % Contrast range
    sub_Sxx = display_data(1:10:end, 1:10:end);
    sorted_Sxx = sort(sub_Sxx(:));
    len = length(sorted_Sxx);
    min_dB = sorted_Sxx(max(1, round(len * 0.15)));
    max_dB = sorted_Sxx(max(1, round(len * 0.999)));
    
    % --- Plotting ---
    fig = figure('Name', DISPLAY_NAME, 'Position', [100, 100, 1200, 700], 'Visible', 'off');
    ax = axes(fig);
    imagesc(ax, [T_display(1), T_display(end)], [F(1)/1000, F(end)/1000], display_data);
    axis(ax, 'xy');
    axis(ax, 'tight');
    ylim(ax, [0, 4]); % Focus on 0 to 4 kHz range
    
    try colormap(ax, 'viridis'); catch, colormap(ax, 'parula'); end
    try clim(ax, double([min_dB, max_dB])); catch, caxis(ax, double([min_dB, max_dB])); end
    
    ylabel(ax, 'Frequency [kHz]');
    xlabel(ax, 'Time [sec]');
    title(ax, sprintf('%s LOFAR Gram (0-4 kHz, NFFT=16384, Integrated)', DISPLAY_NAME));
    cb = colorbar(ax);
    cb.Label.String = 'Power/Frequency (dB re 1\muPa^2/Hz)';
    
    % Save image
    saveas(fig, fullfile(output_dir, [FILE_NAME_OUT, '.png']));
    fprintf('  Saved %s.png to output directory\n', FILE_NAME_OUT);
    close(fig);
    clear y_cal display_data Sxx_dB;
end
fprintf('All LOFAR grams generated successfully!\n');
