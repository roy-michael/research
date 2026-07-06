% plot_auv_lofar.m
% Computes and plots high-resolution LOFAR grams (0-4 kHz) for all 10 AUV datasets.
% Uses a large NFFT (16,384) for sharp tonal resolution, combined with moving time-averaging
% (LOFAR integration) to suppress random ambient noise.

% Resolve output directory relative to script folder
script_dir = fileparts(mfilename('fullpath'));
output_dir = fullfile(script_dir, '..', 'output');

DATASETS = {
    % Hydrophone 6922 (30m)
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692\leg1_straight_line_2_8m_s_6922_827-837.wav', 'AUV_H6922_Straight_Leg1_LOFAR', 'AUV Straight Leg 1 (30m, 5.4 kts)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692\leg2_straight_line_1_8m_s_6922_840-857.wav', 'AUV_H6922_Straight_Leg2_LOFAR', 'AUV Straight Leg 2 (30m, 3.5 kts)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692\leg3_straight_line_1_112m_s_6922_900-910.wav', 'AUV_H6922_Straight_Leg3_LOFAR', 'AUV Straight Leg 3 (30m, 2.2 kts)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part2_Poligon\IcListen6692\leg1_Polygon_6922_921-929.wav', 'AUV_H6922_Polygon_Leg1_LOFAR', 'AUV Polygon Leg 1 (30m)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part2_Poligon\IcListen6692\leg2_Polygon_6922_934-955.wav', 'AUV_H6922_Polygon_Leg2_LOFAR', 'AUV Polygon Leg 2 (30m)';
    
    % Hydrophone 6695 (5m)
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6695\leg1_straight_line_2_8m_s_6695_827-837.wav', 'AUV_H6695_Straight_Leg1_LOFAR', 'AUV Straight Leg 1 (5m, 5.4 kts)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6695\leg2_straight_line_1_8m_s_6695_840-857.wav', 'AUV_H6695_Straight_Leg2_LOFAR', 'AUV Straight Leg 2 (5m, 3.5 kts)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6695\leg3_straight_line_1_112m_s_6695_900-910.wav', 'AUV_H6695_Straight_Leg3_LOFAR', 'AUV Straight Leg 3 (5m, 2.2 kts)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part2_Poligon\IcListen6695\leg1_Polygon_6695_921-929.wav', 'AUV_H6695_Polygon_Leg1_LOFAR', 'AUV Polygon Leg 1 (5m)';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part2_Poligon\IcListen6695\leg2_Polygon_6695_934-955.wav', 'AUV_H6695_Polygon_Leg2_LOFAR', 'AUV Polygon Leg 2 (5m)';
};

calibFactor = 1e6;

for d = 1:size(DATASETS, 1)
    file_path = DATASETS{d, 1};
    file_name_out = DATASETS{d, 2};
    display_name = DATASETS{d, 3};
    
    fprintf('Processing LOFAR Gram for %s...\n', display_name);
    [y, fs] = audioread(file_path);
    if size(y, 2) > 1, y = mean(y, 2); end
    
    y_cal = y * calibFactor;
    clear y;
    
    % LOFAR Gram Computation
    nfft = 16384; 
    noverlap = round(nfft * 0.90);
    step_size = nfft - noverlap;
    window = hann(nfft);
    
    total_len = length(y_cal);
    total_cols = fix((total_len - noverlap) / step_size);
    
    T = ((0:total_cols-1) * step_size + nfft/2) / fs;
    [~, F, ~, ~] = spectrogram(y_cal(1:nfft), window, noverlap, nfft, fs);
    
    % Target OpenGL shape size
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
    
    % Time averaging (LOFAR Integration)
    Sxx_dB = movmean(Sxx_dB, 12, 2);
    
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
    
    % Plotting
    fig = figure('Name', display_name, 'Position', [100, 100, 1200, 700], 'Visible', 'off');
    ax = axes(fig);
    imagesc(ax, [T_display(1), T_display(end)], [F(1)/1000, F(end)/1000], display_data);
    axis(ax, 'xy');
    axis(ax, 'tight');
    ylim(ax, [0, 4]); % Focus 0-4 kHz
    
    try colormap(ax, 'viridis'); catch, colormap(ax, 'parula'); end
    try clim(ax, double([min_dB, max_dB])); catch, caxis(ax, double([min_dB, max_dB])); end
    
    ylabel(ax, 'Frequency [kHz]');
    xlabel(ax, 'Time [sec]');
    title(ax, sprintf('%s LOFAR Gram (0-4 kHz, NFFT=16384)', display_name));
    cb = colorbar(ax);
    cb.Label.String = 'Power/Frequency (dB re 1\muPa^2/Hz)';
    
    saveas(fig, fullfile(output_dir, [file_name_out, '.png']));
    fprintf('  Saved %s.png to output directory\n', file_name_out);
    close(fig);
    clear y_cal display_data Sxx_dB;
end
fprintf('All AUV LOFAR grams generated successfully!\n');
