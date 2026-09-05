% Script to calculate bandwidth using the method from Diamant et al. 2019
% Method: target size estimation via zero-crossings of the signal and its envelope

motorboat_dir = 'D:\RoyStudies\Recordings\hear-my-ship\V1\Motor Boats';
wav_files = dir(fullfile(motorboat_dir, '*.wav'));

num_files = min(5, length(wav_files));
fig = figure('Position', [100, 100, 1200, 800], 'Visible', 'off');

for i = 1:num_files
    wav_path = fullfile(motorboat_dir, wav_files(i).name);
    [data, fs] = audioread(wav_path);
    
    if size(data, 2) > 1
        data = data(:, 1);
    end
    
    % Compute PSD
    nfft = min(2048, length(data));
    [pxx, f] = pwelch(data, rectwin(nfft), 0, nfft, fs);
    
    % Limit to 0-1000 Hz for peak finding
    mask = f >= 0 & f <= 1000;
    f_zoom = f(mask);
    v = pxx(mask);
    
    % Compute envelope using Hilbert transform magnitude
    v_tilde = abs(hilbert(v));
    
    % Find dominant freq (target position t_hat)
    [~, t_hat] = max(v);
    
    % Find l1 and l2 according to the paper:
    % l1 = argmin |v(n) - v_tilde(n)| for n > t_hat
    % l2 = argmin |v(n) - v_tilde(n)| for n < t_hat
    diff_v = abs(v - v_tilde);
    
    if t_hat < length(v)
        [~, l1_offset] = min(diff_v(t_hat+1:end));
        l1 = t_hat + l1_offset;
    else
        l1 = t_hat;
    end
    
    if t_hat > 1
        [~, l2] = min(diff_v(1:t_hat-1));
    else
        l2 = t_hat;
    end
    
    bw = f_zoom(l1) - f_zoom(l2);
    
    % Plotting
    subplot(num_files, 1, i);
    plot(f_zoom, v, 'b-', 'LineWidth', 1.5); hold on;
    plot(f_zoom, v_tilde, 'r--', 'LineWidth', 1.5);
    
    % Mark peak and edges
    peak_freq = f_zoom(t_hat);
    plot(peak_freq, v(t_hat), 'ko', 'MarkerSize', 8, 'LineWidth', 2);
    plot(f_zoom(l1), v(l1), 'kx', 'MarkerSize', 8, 'LineWidth', 2);
    plot(f_zoom(l2), v(l2), 'kx', 'MarkerSize', 8, 'LineWidth', 2);
    
    % Focus around the dominant frequency
    zoom_range = 150; % 150 Hz around the peak
    f_min = max(0, peak_freq - zoom_range);
    f_max = peak_freq + zoom_range;
    xlim([f_min, f_max]);
    
    % Add more scales to the frequency ruler
    xticks(f_min:25:f_max);
    
    title(sprintf('File: %s | Peak: %.1f Hz | Diamant Bandwidth: %.1f Hz', wav_files(i).name, peak_freq, bw));
    xlabel('Frequency (Hz)');
    ylabel('PSD');
    legend('v (PSD)', 'v_{tilde} (Envelope)', 'Peak', 'Bandwidth Edges');
    grid on;
end

output_img = 'C:\Users\gorke\.gemini\antigravity-ide\brain\e1650f41-21c9-4f66-bd63-a6f32140d912\diamant_bandwidth_plot.png';
saveas(fig, output_img);
fprintf('Plot saved to %s\n', output_img);
