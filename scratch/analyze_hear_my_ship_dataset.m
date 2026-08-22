% analyze_hear_my_ship_dataset.m
dataset_path = 'D:\RoyStudies\Recordings\hear-my-ship\V1';
subdirs = dir(dataset_path);
subdirs = subdirs([subdirs.isdir] & ~startsWith({subdirs.name}, '.'));

results = struct();

for i = 1:length(subdirs)
    class_name = subdirs(i).name;
    class_path = fullfile(dataset_path, class_name);
    
    files = dir(fullfile(class_path, '*.wav'));
    if isempty(files)
        continue;
    end
    
    centroids = zeros(length(files), 1);
    bandwidths = zeros(length(files), 1);
    
    fprintf('Processing %s (%d files)...\n', class_name, length(files));
    
    for j = 1:length(files)
        file_path = fullfile(class_path, files(j).name);
        try
            [data, fs] = audioread(file_path);
            if size(data, 2) > 1
                data = data(:, 1);
            end
            
            % Compute overall PSD
            nfft = 8192;
            window_length = 8192;
            overlap = round(window_length * 0.5);
            [pxx, f] = pwelch(data, hanning(window_length), overlap, nfft, fs);
            
            % Limit to 0-4000 Hz
            max_plot_f = min(fs/2, 4000);
            mask = f >= 0 & f <= max_plot_f;
            f_zoom = f(mask);
            v = pxx(mask);
            
            % 1. Noise Floor Normalization (Moving Median)
            window_size = max(20, round(length(v) / 20));
            noise_floor = movmedian(v, window_size);
            v_norm = v - noise_floor;
            v_norm(v_norm < 0) = 0;
            
            % Zero out ultra-low flow noise (< 20 Hz)
            v_norm(f_zoom < 20) = 0;
            
            % 2. Isolate Dominant Lobe (10% Threshold)
            [max_val, f_hat_idx] = max(v_norm);
            if max_val == 0
                centroids(j) = NaN;
                bandwidths(j) = NaN;
                continue;
            end
            thresh = 0.1 * max_val;
            
            left_idx = f_hat_idx;
            while left_idx > 1 && v_norm(left_idx-1) > thresh
                left_idx = left_idx - 1;
            end
            
            right_idx = f_hat_idx;
            while right_idx < length(v_norm) && v_norm(right_idx+1) > thresh
                right_idx = right_idx + 1;
            end
            
            f_lobe = f_zoom(left_idx:right_idx);
            v_lobe = v_norm(left_idx:right_idx);
            
            % 3. RMS Calculation
            total_power = sum(v_lobe);
            if total_power > 0
                f_centroid = sum(f_lobe .* v_lobe) / total_power;
                bw_rms = sqrt(sum(((f_lobe - f_centroid).^2) .* v_lobe) / total_power);
            else
                f_centroid = f_zoom(f_hat_idx);
                bw_rms = 0;
            end
            
            centroids(j) = f_centroid;
            bandwidths(j) = bw_rms;
        catch ME
            fprintf('  Failed %s: %s\n', files(j).name, ME.message);
            centroids(j) = NaN;
            bandwidths(j) = NaN;
        end
    end
    
    results(i).class_name = class_name;
    results(i).centroids = centroids(~isnan(centroids));
    results(i).bandwidths = bandwidths(~isnan(bandwidths));
end

% Plotting Histograms
num_classes = length(results);
colors = lines(num_classes);

% Figure 1: Centroids
fig1 = figure('Name', 'Dominant Frequency (Centroid) Histograms', 'Position', [100, 100, 1200, 800]);
for i = 1:num_classes
    if isempty(results(i).centroids)
        continue;
    end
    subplot(num_classes, 1, i);
    histogram(results(i).centroids, 'BinWidth', 50, 'FaceColor', colors(i,:), 'EdgeColor', 'black');
    title(results(i).class_name);
    xlim([0, 4000]);
    ylabel('Count');
end
xlabel('Centroid Frequency (Hz)');
sgtitle('Dominant Frequency (Centroid) by Vessel Type');

% Figure 2: Bandwidths
fig2 = figure('Name', 'RMS Bandwidth Histograms', 'Position', [150, 150, 1200, 800]);
for i = 1:num_classes
    if isempty(results(i).bandwidths)
        continue;
    end
    subplot(num_classes, 1, i);
    histogram(results(i).bandwidths, 'BinWidth', 10, 'FaceColor', colors(i,:), 'EdgeColor', 'black');
    title(results(i).class_name);
    xlim([0, 1000]);
    ylabel('Count');
end
xlabel('RMS Bandwidth (Hz)');
sgtitle('RMS Bandwidth by Vessel Type');

% Figure 3: Scatter Plot
fig3 = figure('Name', 'Centroid vs Bandwidth', 'Position', [200, 200, 800, 600]);
hold on;
for i = 1:num_classes
    if isempty(results(i).centroids)
        continue;
    end
    scatter(results(i).centroids, results(i).bandwidths, 36, colors(i,:), 'filled', 'DisplayName', results(i).class_name, 'MarkerFaceAlpha', 0.6);
end
hold off;
xlabel('Centroid Frequency (Hz)');
ylabel('RMS Bandwidth (Hz)');
title('Centroid vs RMS Bandwidth by Vessel Type');
legend('Location', 'best');
grid on;

fprintf('Done.\n');
