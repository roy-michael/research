classdef BandwidthTracker
    % Handles dynamic time-domain tracking and Jain's fairness metrics.
    methods (Static)

        function out = compute_watershed_slice_bandwidth(signal, fs, dom_lobe, cfg)
        if isempty(signal)
            out = struct('found', false, 'all_main_bws', [], 'all_fairness', []);
            return;
        end
        
        slice_dur_sec = cfg.slice_dur_sec;
        slice_len = floor(fs * slice_dur_sec);
        total_samples = length(signal);
        num_slices = floor(total_samples / slice_len);
        
        all_main_bws = [];
        slice_outputs = cell(num_slices, 1);
        for i = 1:num_slices
            idx = (i-1)*slice_len + (1:slice_len);
            sig_slice = signal(idx);
            slice_out = BandwidthTracker.compute_single_slice_Watershed_bandwidth(sig_slice, fs, dom_lobe, cfg);
            slice_out.slice_idx = i;
            slice_outputs{i} = slice_out;
            if slice_out.found && isfinite(slice_out.main_bw)
                all_main_bws = [all_main_bws; slice_out.main_bw];
            end
        end
        
        total_time_sec = num_slices * slice_dur_sec;
        [win_sizes, all_tib, all_entropy, all_fairness] = BandwidthTracker.compute_stability_vs_window(all_main_bws, slice_dur_sec, total_time_sec, cfg.tib_tolerance_hz);
        
        % Extract Time-Domain Slice Centered on Midpoint for detailed visualization
        center_idx = round(total_samples / 2);
        start_idx  = max(1, center_idx - floor(slice_len / 2));
        end_idx    = min(total_samples, start_idx + slice_len - 1);
        
        sig_slice_center = signal(start_idx:end_idx);
        if length(sig_slice_center) < slice_len
            sig_slice_center = [sig_slice_center; zeros(slice_len - length(sig_slice_center), 1)];
        end
        
        out = BandwidthTracker.compute_single_slice_Watershed_bandwidth(sig_slice_center, fs, dom_lobe, cfg);
        out.all_main_bws = all_main_bws;
        out.fairness_window_sec = win_sizes;
        out.all_tib = all_tib;
        out.all_entropy = all_entropy;
        out.all_fairness = all_fairness;
        out.slice_outputs = slice_outputs;
        end


        function out = compute_single_slice_Watershed_bandwidth(sig_slice, fs, dom_lobe, cfg)
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
        
        % Focus on the dominant macro-lobe frequency bounds + 50 Hz padding,
        % strictly clamped to the analysis passband [f_low, f_high]
        f_min_bound = 0;
        if isfield(cfg, 'f_low') && ~isempty(cfg.f_low)
            f_min_bound = cfg.f_low;
        end
        f_max_bound = fs / 2;
        if isfield(cfg, 'f_high') && ~isempty(cfg.f_high)
            f_max_bound = min(fs / 2, cfg.f_high);
        end
        
        macro_bw = dom_lobe.f_end - dom_lobe.f_start;
        rel_width = macro_bw / max(10.0, dom_lobe.peak_freq);
        if dom_lobe.peak_freq <= 250
            % Low-frequency shipping band: multi-harmonic structure
            width_factor = min(1.0, max(0.0, (macro_bw - 30) / 70));
        else
            % High-frequency tonal band (DPV scooters, AUVs: narrow fractional width)
            width_factor = min(1.0, max(0.0, (rel_width - 0.35) / 0.40));
        end
        
        % Adaptive padding around macro lobe
        pad_hz = min(50, max(20, macro_bw * 0.4));
        f_start = max(f_min_bound, dom_lobe.f_start - pad_hz);
        f_end   = min(f_max_bound, dom_lobe.f_end + pad_hz);
        
        idx_mask = (f_pos >= f_start) & (f_pos <= f_end);
        f_segment = f_pos(idx_mask);
        mag_segment = mag_pos(idx_mask);
        
        if numel(mag_segment) < 10
            return;
        end
        
        % Smooth the raw segmented signal before bandwidth detection
        % Adaptive smoothing window: base window for narrow tones, up to 15 for wide multi-harmonic lobes
        N = round(cfg.bw_smooth_window + width_factor * 10);
        if mod(N, 2) == 0; N = N + 1; end % Ensure odd length for symmetry
        if strcmpi(cfg.bw_smooth_method, 'welch')
            n = (-(N-1)/2 : (N-1)/2)';
            w = 1 - (n / ((N-1)/2)).^2;
            w = w / sum(w); % normalize to preserve energy
            mag_segment = conv(mag_segment, w, 'same');
        else
            mag_segment = smoothdata(mag_segment, cfg.bw_smooth_method, N);
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
        % settles into a basin. A basin is defined by a local minimum (valley) where:
        %   a) The signal rises out of the valley by a dynamically tapered prominence
        %   b) OR the valley has dropped below the ambient noise floor
        
        % Scale max prominence smoothly between 2.5 dB and cfg max (8.0 dB)
        adaptive_max_prom_db = 2.5 + width_factor * (cfg.watershed_prom_max_db - 2.5);
        
        % Dynamic prominence threshold based on peak's elevation above noise floor
        peak_elevation_db = 20*log10(pk_mag_smooth+eps) - 20*log10(noise_floor+eps);
        
        % Apply adaptive cap to track wide lobes while aggressively clipping narrow DPV skirts
        dynamic_prom_db = min(adaptive_max_prom_db, max(cfg.watershed_prom_min_db, cfg.watershed_prom_ratio * peak_elevation_db)); 
        % If adaptive max is lower than min (e.g. 2.5 < 3.0), enforce the adaptive max.
        dynamic_prom_db = min(dynamic_prom_db, adaptive_max_prom_db); 
        
        prom_linear_ratio = 10^(dynamic_prom_db/20);
        
        % Relative Rebound parameters (Topological Persistence & Catchment Basin Dynamics)
        rebound_ratio = 0.50;
        if isfield(cfg, 'watershed_rebound_ratio') && ~isempty(cfg.watershed_rebound_ratio)
            rebound_ratio = cfg.watershed_rebound_ratio;
        end
        % Scale rebound ratio for broad multi-harmonic lobes to allow inter-harmonic ripple
        rebound_ratio = rebound_ratio + width_factor * 0.25;

        min_dip_db = 1.50;
        if isfield(cfg, 'watershed_min_dip_db') && ~isempty(cfg.watershed_min_dip_db)
            min_dip_db = cfg.watershed_min_dip_db;
        end

        % Right side expansion
        r_idx = pk_idx;
        min_seen_right = mag_smooth(pk_idx);
        for i = pk_idx+1 : length(mag_smooth)
            val = mag_smooth(i);
            
            % Track the lowest point seen so far
            if val < min_seen_right
                min_seen_right = val;
                r_idx = i;
            end
            
            % Are we currently rising out of the valley located at min_seen_right?
            if val > min_seen_right
                drop_db = 20*log10(pk_mag_smooth+eps) - 20*log10(min_seen_right+eps);
                rise_db = 20*log10(val+eps) - 20*log10(min_seen_right+eps);

                % Formal Relative Rebound Criterion:
                % Stop if the valley is a genuine dip (>= min_dip_db) and rebounds by >= rebound_ratio of the dip
                if (drop_db >= min_dip_db) && (rise_db >= rebound_ratio * drop_db)
                    break; % r_idx remains perfectly at the valley
                end

                % Fallback 1: Stop if it rises by prominence cap
                if val > min_seen_right * prom_linear_ratio
                    break; % r_idx remains perfectly at the valley
                end
                
                % Fallback 2: Hybrid Fallback (Stop at first valley once firmly below noise floor)
                % For wide multi-harmonic lobes, guard against premature stop on internal interference nulls inside dom_lobe:
                is_past_lobe = (f_segment(i) >= dom_lobe.f_end);
                if (is_past_lobe || width_factor == 0) && (min_seen_right <= noise_floor * cfg.watershed_noise_fallback_margin)
                    break;
                end
            end
        end
        
        % Left side expansion
        l_idx = pk_idx;
        min_seen_left = mag_smooth(pk_idx);
        for i = pk_idx-1 : -1 : 1
            val = mag_smooth(i);
            
            % Track the lowest point seen so far
            if val < min_seen_left
                min_seen_left = val;
                l_idx = i;
            end
            
            % Are we currently rising out of the valley located at min_seen_left?
            if val > min_seen_left
                drop_db = 20*log10(pk_mag_smooth+eps) - 20*log10(min_seen_left+eps);
                rise_db = 20*log10(val+eps) - 20*log10(min_seen_left+eps);

                % Formal Relative Rebound Criterion:
                % Stop if the valley is a genuine dip (>= min_dip_db) and rebounds by >= rebound_ratio of the dip
                if (drop_db >= min_dip_db) && (rise_db >= rebound_ratio * drop_db)
                    break; % l_idx remains perfectly at the valley
                end

                % Fallback 1: Stop if it rises by prominence cap
                if val > min_seen_left * prom_linear_ratio
                    break; % l_idx remains perfectly at the valley
                end
                
                % Fallback 2: Hybrid Fallback (Stop at first valley once firmly below noise floor)
                % For wide multi-harmonic lobes, guard against premature stop on internal interference nulls inside dom_lobe:
                is_past_lobe = (f_segment(i) <= dom_lobe.f_start);
                if (is_past_lobe || width_factor == 0) && (min_seen_left <= noise_floor * cfg.watershed_noise_fallback_margin)
                    break;
                end
            end
        end
        
        out.l_freq = f_segment(l_idx);
        out.r_freq = f_segment(r_idx);
        out.main_bw = out.r_freq - out.l_freq;
        out.target_mag = noise_floor;
        end

        function [window_sizes_sec, mean_tib, mean_entropy, mean_fairness] = compute_stability_vs_window(bw_array, slice_dur_sec, total_time_sec, tol_hz)
        bw_array = medfilt1(bw_array, max(3, round(5 / slice_dur_sec)));
        
        min_window_sec = 2;
        max_window_sec = floor(total_time_sec);
        if max_window_sec < min_window_sec
            window_sizes_sec = [];
            mean_tib = [];
            mean_entropy = [];
            mean_fairness = [];
            return;
        end
        
        window_sizes_sec = min_window_sec:2:max_window_sec;
        mean_tib = zeros(size(window_sizes_sec));
        mean_entropy = zeros(size(window_sizes_sec));
        mean_fairness = zeros(size(window_sizes_sec));
        
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
            fair_blocks = zeros(1, num_blocks);
            
            for b = 1:num_blocks
                block_data = bw_array((b - 1) * N + 1 : b * N);
                
                % Handle NaNs
                block_data = block_data(isfinite(block_data) & block_data > 0);
                if isempty(block_data)
                    tib_blocks(b) = NaN;
                    ent_blocks(b) = NaN;
                    fair_blocks(b) = NaN;
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
                
                % 3. Jain's Fairness
                sum_val = sum(block_data);
                sum_sq_val = sum(block_data.^2);
                if sum_sq_val > 0
                    fair_blocks(b) = (sum_val^2) / (length(block_data) * sum_sq_val);
                else
                    fair_blocks(b) = NaN;
                end
            end
            
            mean_tib(idx) = mean(tib_blocks, 'omitnan');
            mean_entropy(idx) = mean(ent_blocks, 'omitnan');
            mean_fairness(idx) = mean(fair_blocks, 'omitnan');
        end
        end

        function [t_centers, tib_series, ent_series, fair_series, mean_bw, std_bw] = compute_rolling_stability(bw_array, slice_dur_sec, window_sec, tol_hz)
            bw_array = medfilt1(bw_array, max(3, round(5 / slice_dur_sec)));
            
            N = max(1, round(window_sec / slice_dur_sec));
            T = length(bw_array);
            
            num_windows = T - N + 1;
            if num_windows < 1
                t_centers = []; tib_series = []; ent_series = []; fair_series = []; mean_bw = []; std_bw = [];
                return;
            end
            
            t_centers = ((1:num_windows) + N/2 - 0.5) * slice_dur_sec;
            tib_series = zeros(1, num_windows);
            ent_series = zeros(1, num_windows);
            fair_series = zeros(1, num_windows);
            mean_bw = zeros(1, num_windows);
            std_bw = zeros(1, num_windows);
            
            num_bins = 20;
            
            for b = 1:num_windows
                block_data = bw_array(b : b + N - 1);
                
                % Handle NaNs
                block_data = block_data(isfinite(block_data) & block_data > 0);
                if isempty(block_data)
                    tib_series(b) = NaN;
                    ent_series(b) = NaN;
                    fair_series(b) = NaN;
                    mean_bw(b) = NaN;
                    std_bw(b) = NaN;
                    continue;
                end
                
                % Mean and Std of Bandwidth
                mean_bw(b) = mean(block_data);
                std_bw(b) = std(block_data);
                
                % 1. Time-in-Band (TiB)
                med_val = median(block_data);
                tib_series(b) = sum(abs(block_data - med_val) <= tol_hz) / length(block_data);
                
                % 2. Shannon Entropy (H_norm)
                [counts, ~] = histcounts(block_data, num_bins);
                p = counts / sum(counts);
                p = p(p > 0);
                if isempty(p) || length(p) == 1
                    ent_series(b) = 0; % Perfectly stable
                else
                    H = -sum(p .* log2(p));
                    H_max = log2(length(counts));
                    ent_series(b) = H / H_max;
                end
                
                % 3. Jain's Fairness
                sum_val = sum(block_data);
                sum_sq_val = sum(block_data.^2);
                if sum_sq_val > 0
                    fair_series(b) = (sum_val^2) / (length(block_data) * sum_sq_val);
                else
                    fair_series(b) = NaN;
                end
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
