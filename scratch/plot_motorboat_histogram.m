motorboat_dir = 'D:\RoyStudies\Recordings\hear-my-ship\V1\Motor Boats';
wav_files = dir(fullfile(motorboat_dir, '*.wav'));

dominant_freqs = zeros(length(wav_files), 1);

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
        [~, max_idx] = max(pxx_zoom);
        dominant_freqs(i) = f_zoom(max_idx);
        
    catch
        dominant_freqs(i) = NaN;
    end
    
    if mod(i, 50) == 0
        fprintf('Processed %d/%d\n', i, length(wav_files));
    end
end

% Remove NaNs
dominant_freqs = dominant_freqs(~isnan(dominant_freqs));

% Plot histogram
fig = figure('Visible', 'off');
histogram(dominant_freqs, 50, 'FaceColor', '#87CEEB');
title('Histogram of Dominant Frequencies for Motor Boats (Hear My Ship)');
xlabel('Frequency (Hz)');
ylabel('Count');
xlim([0 4000]);
grid on;

output_img = 'd:\dev\research\scratch\motorboat_histogram.png';
saveas(fig, output_img);
fprintf('Histogram saved to %s\n', output_img);
