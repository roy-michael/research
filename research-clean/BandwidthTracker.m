classdef BandwidthTracker
    % Handles dynamic time-domain tracking and Jain's fairness metrics.
    methods (Static)

        function out = compute_watershed_slice_bandwidth(signal, fs, dom_lobe, slice_dur_sec, fairness_win, smooth_method, smooth_window, tol_hz)
        if isempty(signal)
            out = struct('found', false, 'all_main_bws', [], 'all_fairness', []);
            return;
        end
        
        slice_len = floor(fs * slice_dur_sec);
        total_samples = length(signal);
        num_slices = floor(total_samples / slice_len);
        
        all_main_bws = [];
        all_env_bws = [];
        slice_outputs = cell(num_slices, 1);
        for i = 1:num_slices
            idx = (i-1)*slice_len + (1:slice_len);
            sig_slice = signal(idx);
            slice_out = BandwidthTracker.compute_single_slice_Watershed_bandwidth(sig_slice, fs, dom_lobe, smooth_method, smooth_window);
            slice_out.slice_idx = i;
            slice_outputs{i} = slice_out;
            if slice_out.found && isfinite(slice_out.main_bw)
                all_main_bws = [all_main_bws; slice_out.main_bw];
                all_env_bws = [all_env_bws; slice_out.env_bw];
            end
        end
        
        total_time_sec = num_slices * slice_dur_sec;
        [win_sizes, all_tib, all_entropy] = BandwidthTracker.compute_stability_vs_window(all_main_bws, slice_dur_sec, total_time_sec, tol_hz);
        [~, all_env_tib, all_env_entropy] = BandwidthTracker.compute_stability_vs_window(all_env_bws, slice_dur_sec, total_time_sec, tol_hz);
        
        % Extract Time-Domain Slice Centered on Midpoint for detailed visualization
        center_idx = round(total_samples / 2);
        start_idx  = max(1, center_idx - floor(slice_len / 2));
        end_idx    = min(total_samples, start_idx + slice_len - 1);
        
        sig_slice_center = signal(start_idx:end_idx);
        if length(sig_slice_center) < slice_len
            sig_slice_center = [sig_slice_center; zeros(slice_len - length(sig_slice_center), 1)];
        end
        
        out = BandwidthTracker.compute_single_slice_Watershed_bandwidth(sig_slice_center, fs, dom_lobe, smooth_method, smooth_window);
        out.all_main_bws = all_main_bws;
        out.all_env_bws = all_env_bws;
        out.fairness_window_sec = win_sizes;
        out.all_tib = all_tib;
        out.all_entropy = all_entropy;
        out.all_env_tib = all_env_tib;
        out.all_env_entropy = all_env_entropy;
        out.slice_outputs = slice_outputs;
        end


        function out = compute_single_slice_Watershed_bandwidth(sig_slice, fs, dom_lobe, smooth_method, smooth_window)
        out = struct('found', false, 'main_bw', NaN, 'f_segment', [], 'mag_segment', [], ...
            'noise_floor', NaN, 'main_f', NaN, 'main_mag', NaN, ...
            'l_freq', NaN, 'r_freq', NaN);
        
        slice_len = length(sig_slice);
        win = hann(slice_len);
        sig_win = sig_slice .* win;
        
        sig_fft = fft(sig_win);
        f_axis = (0 : slice_len - 1)' * (fs / slice_len);
        pos_mask = (f_axis >= 0) & (f_axis <= fs / 2);
        f_pos = f_axis(pos_mask);
        mag_pos = abs(sig_fft(pos_mask));
        
        % Focus on the dominant macro-lobe frequency bounds + 50 Hz padding
        f_start = max(0, dom_lobe.f_start - 50);
        f_end   = min(fs/2, dom_lobe.f_end + 50);
        
        idx_mask = (f_pos >= f_start) & (f_pos <= f_end);
        f_segment = f_pos(idx_mask);
        mag_segment = mag_pos(idx_mask);
        
        if numel(mag_segment) < 10
            return;
        end
        
        % Smooth the raw segmented signal before bandwidth detection
        if strcmpi(smooth_method, 'welch')
            N = smooth_window;
            if mod(N, 2) == 0; N = N + 1; end % Ensure odd length for symmetry
            n = (-(N-1)/2 : (N-1)/2)';
            w = 1 - (n / ((N-1)/2)).^2;
            w = w / sum(w); % normalize to preserve energy
            mag_segment = conv(mag_segment, w, 'same');
        else
            mag_segment = smoothdata(mag_segment, smooth_method, smooth_window);
        end
        
        % Smooth linear magnitude for peak/valley detection stability (redundant now, kept for variable compatibility)
        mag_smooth = mag_segment;
        
        % Estimate local noise floor from the outer 15% of the segment
        n_seg = numel(mag_smooth);
        edge_count = max(2, round(0.15 * n_seg));
        edge_values = [mag_smooth(1:edge_count); mag_smooth(end-edge_count+1:end)];
        noise_floor = median(edge_values);
        
        % Find the single dominant peak in the segment (using smoothed for Watershed localization)
        [pk_mag_smooth, pk_idx] = max(mag_smooth);
        pk_f = f_segment(pk_idx);
        pk_mag = mag_segment(pk_idx);
        
        excess_peak = pk_mag_smooth - noise_floor;
        if excess_peak <= 0
            return;
        end
        
        out.found = true;
        out.f_segment = f_segment;
        out.mag_segment = mag_segment;
        out.noise_floor = noise_floor;
        out.main_f = pk_f;
        out.main_mag = pk_mag;
        % 4. Topographic Watershed Expansion (Water Drop Algorithm)
        % We expand outwards from the peak. The boundary is reached when the "water"
        % settles into a basin. A basin is defined by either:
        %   a) Hitting the local noise floor.
        %   b) Reaching a valley minimum and then the signal rises again by a prominence.
        
        % Robust Heuristic: Dynamic prominence threshold based on peak's elevation above noise floor
        peak_elevation_db = 20*log10(pk_mag_smooth+eps) - 20*log10(noise_floor+eps);
        dynamic_prom_db = max(5.0, 0.40 * peak_elevation_db); % At least 5 dB, or 40% of elevation
        prominence_threshold = pk_mag_smooth * (1 - 10^(-dynamic_prom_db/20));
        
        % Right side expansion
        r_idx = pk_idx;
        min_seen_right = mag_smooth(pk_idx);
        for i = pk_idx+1 : length(mag_smooth)
            val = mag_smooth(i);
            if val < min_seen_right
                min_seen_right = val;
                r_idx = i;
            elseif min_seen_right <= noise_floor * 1.05
                % Hit the noise floor basin and started rising: we are at the bottom of the valley.
                break;
            elseif (val - min_seen_right) > prominence_threshold
                % Hit a valley above noise floor and rose by prominence.
                break;
            end
        end
        
        % Left side expansion
        l_idx = pk_idx;
        min_seen_left = mag_smooth(pk_idx);
        for i = pk_idx-1 : -1 : 1
            val = mag_smooth(i);
            if val < min_seen_left
                min_seen_left = val;
                l_idx = i;
            elseif min_seen_left <= noise_floor * 1.05
                % Hit the noise floor basin and started rising: we are at the bottom of the valley.
                break;
            elseif (val - min_seen_left) > prominence_threshold
                % Hit a valley above noise floor and rose by prominence.
                break;
            end
        end
        
        out.l_freq = f_segment(l_idx);
        out.r_freq = f_segment(r_idx);
        out.main_bw = out.r_freq - out.l_freq;
        out.target_mag = noise_floor;
        
        % 5. Lower Envelope Zerocrossing Detection
        % Compute the envelope from the RAW magnitude so it hugs the true signal valleys
        valleys_idx = find(islocalmin(mag_segment));
        if isempty(valleys_idx) || valleys_idx(1) > 1
            valleys_idx = [1; valleys_idx];
        end
        if valleys_idx(end) < length(mag_segment)
            valleys_idx = [valleys_idx; length(mag_segment)];
        end
        lower_env = interp1(valleys_idx, mag_segment(valleys_idx), 1:length(mag_segment), 'linear')';
        
        % Smooth the envelope slightly to prevent extreme micro-jaggedness from raw noise
        lower_env = smoothdata(lower_env, 'gaussian', 5);
        
        % Find intersection of lower envelope and NOISE FLOOR around the peak
        % Right side
        r_env_idx = length(mag_segment);
        for i = pk_idx+1:length(mag_segment)
            if lower_env(i) <= noise_floor * 1.05
                r_env_idx = i;
                break;
            end
        end
        % Left side
        l_env_idx = 1;
        for i = pk_idx-1:-1:1
            if lower_env(i) <= noise_floor * 1.05
                l_env_idx = i;
                break;
            end
        end
        
        out.l_env_freq = f_segment(l_env_idx);
        out.r_env_freq = f_segment(r_env_idx);
        out.env_bw = out.r_env_freq - out.l_env_freq;
        out.lower_env = lower_env;
        end

        function [window_sizes_sec, mean_tib, mean_entropy] = compute_stability_vs_window(bw_array, slice_dur_sec, total_time_sec, tol_hz)
        bw_array = medfilt1(bw_array, max(3, round(5 / slice_dur_sec)));
        
        min_window_sec = 2;
        max_window_sec = floor(total_time_sec);
        if max_window_sec < min_window_sec
            window_sizes_sec = [];
            mean_tib = [];
            mean_entropy = [];
            return;
        end
        
        window_sizes_sec = min_window_sec:2:max_window_sec;
        mean_tib = zeros(size(window_sizes_sec));
        mean_entropy = zeros(size(window_sizes_sec));
        
        fs_samples = 1 / slice_dur_sec;
        T = length(bw_array);
        
        % Pre-calculate histogram bins for entropy calculation
        num_bins = 20;
        
        for idx = 1:length(window_sizes_sec)
            win_sec = window_sizes_sec(idx);
            N = max(1, round(win_sec * fs_samples));
            
            num_blocks = floor(T / N);
            if num_blocks < 1
                mean_tib(idx) = NaN;
                mean_entropy(idx) = NaN;
                continue;
            end
            
            tib_blocks = zeros(1, num_blocks);
            ent_blocks = zeros(1, num_blocks);
            
            for b = 1:num_blocks
                block_data = bw_array((b - 1) * N + 1 : b * N);
                
                % Handle NaNs
                block_data = block_data(isfinite(block_data) & block_data > 0);
                if isempty(block_data)
                    tib_blocks(b) = NaN;
                    ent_blocks(b) = NaN;
                    continue;
                end
                
                % 1. Time-in-Band (TiB)
                med_val = median(block_data);
                tib_blocks(b) = sum(abs(block_data - med_val) <= tol_hz) / length(block_data);
                
                % 2. Shannon Entropy (H_norm)
                [counts, ~] = histcounts(block_data, num_bins);
                p = counts / sum(counts);
                p = p(p > 0);
                if isempty(p) || length(p) == 1
                    ent_blocks(b) = 0; % Perfectly stable
                else
                    H = -sum(p .* log2(p));
                    H_max = log2(length(counts));
                    ent_blocks(b) = H / H_max;
                end
            end
            
            mean_tib(idx) = mean(tib_blocks, 'omitnan');
            mean_entropy(idx) = mean(ent_blocks, 'omitnan');
        end
        end

        function crossing_frequency = interpolate_crossing(f, y, i1, i2, level, side)
        if i1 < 1 || i2 > numel(y) || y(i2) == y(i1)
            if strcmp(side, 'left')
                crossing_frequency = f(max(1, min(numel(f), i1)));
            else
                crossing_frequency = f(max(1, min(numel(f), i2)));
            end
            return;
        end
        crossing_frequency = f(i1) + (level-y(i1)) * (f(i2)-f(i1))/(y(i2)-y(i1));
        end

    end
end
