% Script to estimate "target size" (time duration) using the method from Diamant et al. 2019
% Method: target size estimation via zero-crossings of the time-domain signal and its envelope

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
    
    % We work directly with the time domain signal, v
    v = data;
    time_vec = (0:length(v)-1) / fs;
    
    % Compute envelope using Hilbert transform magnitude
    v_tilde = abs(hilbert(v));
    
    % Find dominant peak in time domain (target position t_hat)
    [~, t_hat] = max(abs(v)); % using max absolute value to find the strongest transient
    
    % Force v to be positive for the crossing detection, or just use absolute difference
    % The paper method uses v and its envelope. 
    % We use abs(v) so it matches the positive envelope.
    v_abs = abs(v);
    diff_v = abs(v_abs - v_tilde);
    
    if t_hat < length(v_abs)
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
    
    duration = time_vec(l1) - time_vec(l2);
    
    % Plotting
    subplot(num_files, 1, i);
    plot(time_vec, v, 'b-', 'LineWidth', 1.0); hold on;
    plot(time_vec, v_tilde, 'r--', 'LineWidth', 1.5);
    
    % Mark peak and edges
    peak_time = time_vec(t_hat);
    plot(peak_time, v(t_hat), 'ko', 'MarkerSize', 8, 'LineWidth', 2);
    plot(time_vec(l1), v(l1), 'kx', 'MarkerSize', 8, 'LineWidth', 2);
    plot(time_vec(l2), v(l2), 'kx', 'MarkerSize', 8, 'LineWidth', 2);
    
    % Focus around the dominant time peak
    zoom_range = 0.5; % 0.5 seconds around the peak
    t_min = max(0, peak_time - zoom_range);
    t_max = min(time_vec(end), peak_time + zoom_range);
    xlim([t_min, t_max]);
    
    title(sprintf('File: %s | Peak: %.2fs | Diamant Duration: %.3f s', wav_files(i).name, peak_time, duration));
    xlabel('Time (s)');
    ylabel('Amplitude');
    legend('Signal', 'Envelope', 'Peak', 'Edges');
    grid on;
end

output_img = 'C:\Users\gorke\.gemini\antigravity-ide\brain\e1650f41-21c9-4f66-bd63-a6f32140d912\diamant_time_plot.png';
saveas(fig, output_img);
fprintf('Plot saved to %s\n', output_img);
