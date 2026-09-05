% main_3.m

% Load the recordings
[data_scooter, sr_scooter] = audioread("D:\RoyStudies\Recordings\Croatia\Ocean Sonics\2407_1_600m\RBW6737_20250724_093000.wav");
[data_ship, sr_ship] = audioread("D:\RoyStudies\Recordings\hear-my-ship\V1\Motor Boats\Motorboat_08.08.23_142223_20secCPA.wav");

duration = 10;
data_scooter = resample_and_split(data_scooter, sr_scooter, sr_ship, duration);
data_ship = resample_and_split(data_ship, sr_ship, sr_ship, duration);

% Calculate and plot bandwidth
figure('Position', [100, 100, 1000, 800]);
calculate_and_plot_bandwidth(data_scooter, sr_ship, 'Scooter', 1, [400, 1000]);
calculate_and_plot_bandwidth(data_ship, sr_ship, 'Motor Boat', 2, [50, 24000]);

function calculate_and_plot_bandwidth(data, sr, name, subplot_idx, freq_band)
    ax = subplot(2, 1, subplot_idx);
    
    % 1. Compute Raw FFT Magnitude (matching plot_3 exactly)
    data_mag_full = abs(fft(data));
    N = length(data);
    
    % Keep only positive frequencies
    data_mag = data_mag_full(1:floor(N/2));
    Faxis = linspace(0, sr/2, floor(N/2))';
    
    % Ensure column vector
    if size(data_mag, 2) > 1, data_mag = data_mag'; end
    
    % Ignore frequencies outside the specified band
    valid_idx = (Faxis >= freq_band(1)) & (Faxis <= freq_band(2));
    Faxis = Faxis(valid_idx);
    data_mag = data_mag(valid_idx);
    
    % 2. Calculate Upper and Lower Envelopes
    min_dist = 50; 
    
    % UPPER ENVELOPE
    [peaks, locs_max] = findpeaks(data_mag, 'MinPeakDistance', min_dist);
    % Include endpoints for pchip interpolation
    if isempty(locs_max), locs_max = [1; length(data_mag)]; peaks = [data_mag(1); data_mag(end)]; end
    if locs_max(1) > 1, locs_max = [1; locs_max]; peaks = [data_mag(1); peaks]; end
    if locs_max(end) < length(data_mag), locs_max = [locs_max; length(data_mag)]; peaks = [peaks; data_mag(end)]; end
    
    peak_freqs = Faxis(locs_max);
    envelope_upper = interp1(peak_freqs, peaks, Faxis, 'pchip');
    envelope_upper = max(envelope_upper, 0);
    
    % LOWER ENVELOPE
    [~, locs_min] = findpeaks(-data_mag, 'MinPeakDistance', min_dist); 
    valleys = data_mag(locs_min);
    % Include endpoints for pchip interpolation
    if isempty(locs_min), locs_min = [1; length(data_mag)]; valleys = [data_mag(1); data_mag(end)]; end
    if locs_min(1) > 1, locs_min = [1; locs_min]; valleys = [data_mag(1); valleys]; end
    if locs_min(end) < length(data_mag), locs_min = [locs_min; length(data_mag)]; valleys = [valleys; data_mag(end)]; end
    
    valley_freqs = Faxis(locs_min);
    envelope_lower = interp1(valley_freqs, valleys, Faxis, 'pchip');
    envelope_lower = max(envelope_lower, 0);
    
    % 3. Find Bandwidth via Minimal Distance for Top 5 Peaks
    delta = envelope_upper - envelope_lower;
    
    % Find all local minima of the distance between envelopes
    [~, locs_min_delta] = findpeaks(-delta);
    
    % Find the local peaks of the upper envelope
    [env_peaks, env_locs] = findpeaks(envelope_upper);
    if isempty(env_locs) % Fallback if perfectly smooth
        [env_peaks, env_locs] = max(envelope_upper);
    end
    
    % Get the top 1 highest peak
    [~, sort_idx] = sort(env_peaks, 'descend');
    num_peaks = 1;
    top_peak_locs = env_locs(sort_idx(1:num_peaks));
    
    bw_bounds = [];
    for i = 1:num_peaks
        peak_idx = top_peak_locs(i);
        
        if isempty(locs_min_delta)
            flo_idx = 1; fhi_idx = length(Faxis);
        else
            left_mins = locs_min_delta(locs_min_delta <= peak_idx);
            if isempty(left_mins), flo_idx = 1; else, flo_idx = left_mins(end); end
            
            right_mins = locs_min_delta(locs_min_delta > peak_idx);
            if isempty(right_mins), fhi_idx = length(Faxis); else, fhi_idx = right_mins(1); end
        end
        bw_bounds = [bw_bounds; flo_idx, fhi_idx];
    end
    
    % Merge overlapping bandwidths
    bw_bounds = sortrows(bw_bounds, 1);
    merged_bounds = [];
    if ~isempty(bw_bounds)
        curr_bound = bw_bounds(1,:);
        for i = 2:size(bw_bounds,1)
            if bw_bounds(i,1) <= curr_bound(2)
                curr_bound(2) = max(curr_bound(2), bw_bounds(i,2));
            else
                merged_bounds = [merged_bounds; curr_bound];
                curr_bound = bw_bounds(i,:);
            end
        end
        merged_bounds = [merged_bounds; curr_bound];
    end
    
    % Calculate total bandwidth across all distinct regions
    total_bw = 0;
    for i = 1:size(merged_bounds, 1)
        total_bw = total_bw + (Faxis(merged_bounds(i,2)) - Faxis(merged_bounds(i,1)));
    end
    
    % 4. Dark Theme Plotting
    set(gcf, 'Color', [0.12 0.12 0.12]);
    set(ax, 'Color', [0.18 0.18 0.18], 'XColor', [0.8 0.8 0.8], 'YColor', [0.8 0.8 0.8]);
    
    % Raw spectrum in dim cyan
    plot(Faxis, data_mag, 'Color', [0 1 1 0.4], 'LineWidth', 0.5);
    hold on;
    
    % Envelopes
    plot(Faxis, envelope_upper, 'Color', [1 0.8 0], 'LineWidth', 2.0); % Yellow (Upper)
    plot(Faxis, envelope_lower, 'Color', [1 0 1], 'LineWidth', 2.0);   % Magenta (Lower)
    
    % Plot highlights for all merged bandwidth bounds
    y_min = min(envelope_lower);
    y_max = max(envelope_upper);
    max_fhi = 0;
    
    for i = 1:size(merged_bounds, 1)
        flo_idx = merged_bounds(i, 1);
        fhi_idx = merged_bounds(i, 2);
        flo = Faxis(flo_idx);
        fhi = Faxis(fhi_idx);
        max_fhi = max(max_fhi, fhi);
        
        plot([flo, fhi], [y_min, y_min], 'Color', [0 1 0], 'LineWidth', 4); 
        plot([flo, flo], [y_min, y_max], 'Color', [0 1 0], 'LineStyle', '--');
        plot([fhi, fhi], [y_min, y_max], 'Color', [0 1 0], 'LineStyle', '--');
        
        % Pinch points
        plot(flo, envelope_upper(flo_idx), 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 5);
        plot(flo, envelope_lower(flo_idx), 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 5);
        plot(fhi, envelope_upper(fhi_idx), 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 5);
        plot(fhi, envelope_lower(fhi_idx), 'ro', 'MarkerFaceColor', 'r', 'MarkerSize', 5);
        
        % Vertical calipers
        plot([flo, flo], [envelope_lower(flo_idx), envelope_upper(flo_idx)], 'r-', 'LineWidth', 2.5);
        plot([fhi, fhi], [envelope_lower(fhi_idx), envelope_upper(fhi_idx)], 'r-', 'LineWidth', 2.5);
    end
    
    % Mark the top peak
    plot(Faxis(top_peak_locs), envelope_upper(top_peak_locs), 'k^', 'MarkerFaceColor', 'y', 'MarkerSize', 8);
    
    dom_freq = Faxis(top_peak_locs(1));
    title(sprintf('Envelope Bandwidth (%s) - BW: %.0f Hz | Dom Freq: %.0f Hz', name, total_bw, dom_freq), 'Color', 'w');
    xlabel('Frequency (Hz)', 'Color', 'w');
    ylabel('Magnitude', 'Color', 'w');
    
    xlim([0, min(sr/2, max(max_fhi * 1.5, 2000))]); 
    % Filter duplicate legends
    h = findobj(gca, 'Type', 'line');
    legend(h(end:-1:end-4), {'FFT Magnitude', 'Upper Env', 'Lower Env', 'Bandwidth', 'Top Peaks'}, 'TextColor', 'w', 'Color', [0.2 0.2 0.2], 'EdgeColor', 'none', 'Location', 'best');
    grid on;
    ax.GridColor = [0.4 0.4 0.4];
end

function result = resample_and_split(data, sr_orig, sr_target, duration)
    if sr_orig > sr_target
        [P, Q] = rat(sr_target / sr_orig);
        data = resample(data, P, Q);
    end
    num_samples = min(duration * sr_target, size(data, 1));
    result = data(1:num_samples, :);
end
