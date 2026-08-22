motorboat_dir = 'D:\RoyStudies\Recordings\hear-my-ship\V1\Motor Boats';
wav_files = dir(fullfile(motorboat_dir, '*.wav'));

bandwidths = zeros(length(wav_files), 1);

for i = 1:length(wav_files)
    wav_path = fullfile(motorboat_dir, wav_files(i).name);
    try
        [data, fs] = audioread(wav_path);
        
        if size(data, 2) > 1
            data = data(:, 1);
        end
        
        % Compute PSD
        nfft = min(2048, length(data));
        [pxx, f] = pwelch(data, rectwin(nfft), 0, nfft, fs);
        
        % Limit to 0-4000 Hz
        mask = f >= 0 & f <= 4000;
        f_zoom = f(mask);
        pxx_zoom = pxx(mask);
        
        % Find dominant freq
        [max_pwr, max_idx] = max(pxx_zoom);
        
        % Find -3dB bandwidth (half power in linear scale)
        threshold = max_pwr / 2;
        
        % Left edge
        idx_low = max_idx;
        while idx_low > 1 && pxx_zoom(idx_low) >= threshold
            idx_low = idx_low - 1;
        end
        
        % Right edge
        idx_high = max_idx;
        while idx_high < length(pxx_zoom) && pxx_zoom(idx_high) >= threshold
            idx_high = idx_high + 1;
        end
        
        bandwidths(i) = f_zoom(idx_high) - f_zoom(idx_low);
        
    catch
        bandwidths(i) = NaN;
    end
    
    if mod(i, 50) == 0
        fprintf('Processed %d/%d\n', i, length(wav_files));
    end
end

% Remove NaNs and extremely large bandwidths (likely noise)
bandwidths = bandwidths(~isnan(bandwidths));

% Plot histogram
fig = figure('Visible', 'off');
histogram(bandwidths, 50, 'FaceColor', '#FF7F50');
title('Histogram of -3dB Bandwidth for Motor Boats (Hear My Ship)');
xlabel('Bandwidth (Hz)');
ylabel('Count');
grid on;

output_img = 'C:\Users\gorke\.gemini\antigravity-ide\brain\e1650f41-21c9-4f66-bd63-a6f32140d912\motorboat_bandwidth_histogram.png';
saveas(fig, output_img);
fprintf('Histogram saved to %s\n', output_img);
