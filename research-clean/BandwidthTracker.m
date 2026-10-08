classdef BandwidthTracker
    % BANDWIDTHTRACKER Time-domain slicing, watershed bandwidth estimation, and fairness analysis.
    %
    % This class provides a suite of static methods for acoustic signal bandwidth
    % analysis, dynamic feature extraction, and temporal stability evaluation:
    %
    % 1. Dynamic Time-Domain Slicing & Watershed Bandwidth Estimation:
    %    - compute_watershed_slice_bandwidth: Slices an audio signal into uniform
    %      time windows and tracks instantaneous bandwidth across time.
    %    - compute_single_slice_Watershed_bandwidth: Core spectral engine applying
    %      windowed FFT, adaptive macro-lobe filtering, noise floor estimation,
    %      and topographic watershed boundary expansion.
    %    - interpolate_crossing: Sub-bin linear interpolation for threshold crossings.
    %
    % 2. Multi-Scale Stability & Fairness Analysis:
    %    - compute_stability_vs_window: Evaluates stability metrics (Time-in-Band,
    %      Normalized Shannon Entropy, and Jain's Fairness Index) as a function of
    %      window size W in [min_window_sec, max_window_sec].
    %    - compute_rolling_stability: Computes temporal trajectories of fairness
    %      and stability using sliding or non-overlapping windows (default: full window stride).
    %    - compute_binned_bandwidth: Chunks instantaneous bandwidth into fixed-duration
    %      bins (e.g. 60 seconds) to calculate bin means, standard deviations, and SEM.

    methods (Static)

        % =================================================================
        % SECTION 1: Dynamic Slice-by-Slice Watershed Bandwidth Estimation
        % =================================================================

        function out = compute_watershed_slice_bandwidth(signal, fs, dom_lobe, cfg)
            % COMPUTE_WATERSHED_SLICE_BANDWIDTH Slices a signal into time blocks and tracks bandwidth.
            %
            % Syntax:
            %   out = BandwidthTracker.compute_watershed_slice_bandwidth(signal, fs, dom_lobe, cfg)
            %
            % Inputs:
            %   signal   - 1D time-domain acoustic signal vector
            %   fs       - Sampling frequency (Hz)
            %   dom_lobe - Struct defining dominant macro-lobe bounds (.f_start, .f_end, .peak_freq)
            %   cfg      - Configuration struct (AnalysisConfig or equivalent)
            %
            % Outputs:
            %   out      - Struct containing:
            %              .found               - Logical indicating if valid peak was found
            %              .all_main_bws        - Column vector of valid slice bandwidths (Hz)
            %              .fairness_window_sec - Vector of evaluated window sizes (s)
            %              .all_tib             - Time-in-Band curve vs window size
            %              .all_entropy         - Shannon entropy curve vs window size
            %              .all_fairness        - Jain's fairness curve vs window size
            %              .slice_outputs       - Cell array of detailed per-slice diagnostic structs
            %              .main_bw             - Bandwidth of the midpoint representative slice (Hz)
            %              .f_segment           - Frequency axis of the midpoint slice (Hz)
            %              .mag_segment         - Magnitude spectrum of the midpoint slice

            if isempty(signal)
                out = struct('found', false, 'all_main_bws', [], 'all_fairness', []);
                return;
            end

            % --- Step 1: Discretize signal into uniform non-overlapping time slices ---
            slice_dur_sec = cfg.slice_dur_sec;
            slice_len     = floor(fs * slice_dur_sec);
            total_samples = length(signal);
            num_slices    = floor(total_samples / slice_len);

            all_main_bws  = zeros(num_slices, 1);
            valid_count   = 0;
            slice_outputs = cell(num_slices, 1);

            % --- Step 2: Process each slice through the Watershed bandwidth engine ---
            for i = 1:num_slices
                idx       = (i - 1) * slice_len + (1 : slice_len);
                sig_slice = signal(idx);

                slice_out = BandwidthTracker.compute_single_slice_Watershed_bandwidth(...
                    sig_slice, fs, dom_lobe, cfg);
                slice_out.slice_idx = i;
                slice_outputs{i}    = slice_out;

                if slice_out.found && isfinite(slice_out.main_bw)
                    valid_count = valid_count + 1;
                    all_main_bws(valid_count) = slice_out.main_bw;
                end
            end
            all_main_bws = all_main_bws(1 : valid_count);

            % --- Step 3: Compute multiscale stability vs window size curves ---
            total_time_sec = num_slices * slice_dur_sec;
            [win_sizes, all_tib, all_entropy, all_fairness] = ...
                BandwidthTracker.compute_stability_vs_window(...
                    all_main_bws, slice_dur_sec, total_time_sec, cfg.tib_tolerance_hz);

            % --- Step 4: Extract midpoint representative slice for detailed diagnostics ---
            center_idx = round(total_samples / 2);
            start_idx  = max(1, center_idx - floor(slice_len / 2));
            end_idx    = min(total_samples, start_idx + slice_len - 1);

            sig_slice_center = signal(start_idx:end_idx);
            if length(sig_slice_center) < slice_len
                % Zero-pad if edge boundary truncated
                sig_slice_center = [sig_slice_center; zeros(slice_len - length(sig_slice_center), 1)];
            end

            out = BandwidthTracker.compute_single_slice_Watershed_bandwidth(...
                sig_slice_center, fs, dom_lobe, cfg);

            % Attach summary results across all slices
            out.all_main_bws        = all_main_bws;
            out.fairness_window_sec = win_sizes;
            out.all_tib             = all_tib;
            out.all_entropy         = all_entropy;
            out.all_fairness        = all_fairness;
            out.slice_outputs       = slice_outputs;
        end

        function out = compute_single_slice_Watershed_bandwidth(sig_slice, fs, dom_lobe, cfg)
            % COMPUTE_SINGLE_SLICE_WATERSHED_BANDWIDTH Core spectral watershed boundary detector.
            %
            % Implements topographic watershed flood-fill expansion around the dominant spectral
            % peak within a macro-lobe ROI. Detects boundaries where valleys reach a relative
            % rebound or drop to the ambient noise floor.
            %
            % Syntax:
            %   out = BandwidthTracker.compute_single_slice_Watershed_bandwidth(sig_slice, fs, dom_lobe, cfg)

            out = struct('found', false, 'main_bw', NaN, 'f_segment', [], 'mag_segment', [], ...
                         'noise_floor', NaN, 'main_f', NaN, 'main_mag', NaN, ...
                         'l_freq', NaN, 'r_freq', NaN);

            % --- Phase 1: Windowed Fast Fourier Transform (FFT) ---
            slice_len = length(sig_slice);
            win       = hann(slice_len);              % Smooth edges to suppress spectral leakage
            sig_win   = sig_slice .* win;

            sig_fft   = fft(sig_win);
            f_axis    = (0 : slice_len - 1)' * (fs / slice_len);

            % Retain positive frequencies up to Nyquist limit
            pos_mask  = (f_axis >= 0) & (f_axis <= fs / 2);
            f_pos     = f_axis(pos_mask);
            mag_pos   = abs(sig_fft(pos_mask));

            % --- Phase 2: Region of Interest (ROI) & Adaptive Padding ---
            % Clamp analysis band strictly between configured f_low and f_high
            f_min_bound = 0;
            if isfield(cfg, 'f_low') && ~isempty(cfg.f_low)
                f_min_bound = cfg.f_low;
            end

            f_max_bound = fs / 2;
            if isfield(cfg, 'f_high') && ~isempty(cfg.f_high)
                f_max_bound = min(fs / 2, cfg.f_high);
            end

            macro_bw  = dom_lobe.f_end - dom_lobe.f_start;
            rel_width = macro_bw / max(10.0, dom_lobe.peak_freq);

            % Adapt width factor based on spectral characteristics:
            % - Low-frequency shipping bands (<=250 Hz): multi-harmonic line structure
            % - High-frequency tonal bands (DPVs, AUVs): narrow fractional line width
            if dom_lobe.peak_freq <= 250
                width_factor = min(1.0, max(0.0, (macro_bw - 30) / 70));
            else
                width_factor = min(1.0, max(0.0, (rel_width - 0.35) / 0.40));
            end

            % Adaptive frequency padding around the macro-lobe
            pad_hz   = min(50, max(20, macro_bw * 0.4));
            f_start  = max(f_min_bound, dom_lobe.f_start - pad_hz);
            f_end    = min(f_max_bound, dom_lobe.f_end + pad_hz);

            idx_mask    = (f_pos >= f_start) & (f_pos <= f_end);
            f_segment   = f_pos(idx_mask);
            mag_segment = mag_pos(idx_mask);

            if numel(mag_segment) < 10
                return;
            end

            % --- Phase 3: Spectral Smoothing & Background Noise Floor ---
            % Filter window length scales with width_factor (wider lobes receive stronger smoothing)
            N_smooth = round(cfg.bw_smooth_window + width_factor * 10);
            if mod(N_smooth, 2) == 0; N_smooth = N_smooth + 1; end % Enforce odd symmetry

            if strcmpi(cfg.bw_smooth_method, 'welch')
                n = (-(N_smooth - 1) / 2 : (N_smooth - 1) / 2)';
                w = 1 - (n / ((N_smooth - 1) / 2)).^2;
                w = w / sum(w); % Energy-normalized parabolic window
                mag_segment = conv(mag_segment, w, 'same');
            else
                mag_segment = smoothdata(mag_segment, cfg.bw_smooth_method, N_smooth);
            end

            mag_smooth = mag_segment;

            % Estimate ambient noise floor using the outer 15% edges of the segment
            n_seg       = numel(mag_smooth);
            edge_count  = max(2, round(0.15 * n_seg));
            edge_values = [mag_smooth(1:edge_count); mag_smooth(end - edge_count + 1 : end)];
            noise_floor = median(edge_values);

            % --- Phase 4: Dominant Peak Localization ---
            [pk_mag_smooth, pk_idx] = max(mag_smooth);
            pk_f   = f_segment(pk_idx);
            pk_mag = mag_segment(pk_idx);

            % Require positive elevation above estimated noise floor
            excess_peak = pk_mag_smooth - noise_floor;
            if excess_peak <= 0
                return;
            end

            out.found       = true;
            out.f_segment   = f_segment;
            out.mag_segment = mag_segment;
            out.noise_floor = noise_floor;
            out.main_f      = pk_f;
            out.main_mag    = pk_mag;

            % --- Phase 5: Topographic Watershed Expansion (Water Drop Algorithm) ---
            % Expand outwards from the peak to both sides. A boundary valley is identified
            % when either:
            %   1. Relative Rebound: The signal climbs out of the valley by >= rebound_ratio of the dip
            %   2. Prominence Cap: The signal climbs out of the valley by dynamic prominence threshold
            %   3. Noise Floor Fallback: The valley has dropped firmly below the ambient noise floor

            adaptive_max_prom_db = 2.5 + width_factor * (cfg.watershed_prom_max_db - 2.5);
            peak_elevation_db    = 20 * log10(pk_mag_smooth + eps) - 20 * log10(noise_floor + eps);

            % Dynamic prominence cap in dB
            dynamic_prom_db = min(adaptive_max_prom_db, ...
                max(cfg.watershed_prom_min_db, cfg.watershed_prom_ratio * peak_elevation_db));
            dynamic_prom_db   = min(dynamic_prom_db, adaptive_max_prom_db);
            prom_linear_ratio = 10^(dynamic_prom_db / 20);

            % Relative Rebound parameters
            rebound_ratio = 0.50;
            if isfield(cfg, 'watershed_rebound_ratio') && ~isempty(cfg.watershed_rebound_ratio)
                rebound_ratio = cfg.watershed_rebound_ratio;
            end
            rebound_ratio = rebound_ratio + width_factor * 0.25;

            min_dip_db = 1.50;
            if isfield(cfg, 'watershed_min_dip_db') && ~isempty(cfg.watershed_min_dip_db)
                min_dip_db = cfg.watershed_min_dip_db;
            end

            % --- Right-side boundary expansion ---
            r_idx          = pk_idx;
            min_seen_right = mag_smooth(pk_idx);

            for i = pk_idx + 1 : length(mag_smooth)
                val = mag_smooth(i);

                if val < min_seen_right
                    min_seen_right = val;
                    r_idx = i;
                end

                if val > min_seen_right
                    drop_db = 20 * log10(pk_mag_smooth + eps) - 20 * log10(min_seen_right + eps);
                    rise_db = 20 * log10(val + eps)           - 20 * log10(min_seen_right + eps);

                    % Criterion 1: Relative Rebound from valley
                    if (drop_db >= min_dip_db) && (rise_db >= rebound_ratio * drop_db)
                        break;
                    end

                    % Criterion 2: Absolute prominence climb
                    if val > min_seen_right * prom_linear_ratio
                        break;
                    end

                    % Criterion 3: Hybrid noise floor fallback past lobe boundary
                    is_past_lobe = (f_segment(i) >= dom_lobe.f_end);
                    if (is_past_lobe || width_factor == 0) && ...
                       (min_seen_right <= noise_floor * cfg.watershed_noise_fallback_margin)
                        break;
                    end
                end
            end

            % --- Left-side boundary expansion ---
            l_idx         = pk_idx;
            min_seen_left = mag_smooth(pk_idx);

            for i = pk_idx - 1 : -1 : 1
                val = mag_smooth(i);

                if val < min_seen_left
                    min_seen_left = val;
                    l_idx = i;
                end

                if val > min_seen_left
                    drop_db = 20 * log10(pk_mag_smooth + eps) - 20 * log10(min_seen_left + eps);
                    rise_db = 20 * log10(val + eps)           - 20 * log10(min_seen_left + eps);

                    % Criterion 1: Relative Rebound from valley
                    if (drop_db >= min_dip_db) && (rise_db >= rebound_ratio * drop_db)
                        break;
                    end

                    % Criterion 2: Absolute prominence climb
                    if val > min_seen_left * prom_linear_ratio
                        break;
                    end

                    % Criterion 3: Hybrid noise floor fallback past lobe boundary
                    is_past_lobe = (f_segment(i) <= dom_lobe.f_start);
                    if (is_past_lobe || width_factor == 0) && ...
                       (min_seen_left <= noise_floor * cfg.watershed_noise_fallback_margin)
                        break;
                    end
                end
            end

            % Assemble final frequencies and bandwidth
            out.l_freq     = f_segment(l_idx);
            out.r_freq     = f_segment(r_idx);
            out.main_bw    = out.r_freq - out.l_freq;
            out.target_mag = noise_floor;
        end


        % =================================================================
        % SECTION 2: Multi-Scale Stability & Fairness Analysis
        % =================================================================

        function [window_sizes_sec, mean_tib, mean_entropy, mean_fairness] = ...
                compute_stability_vs_window(bw_array, slice_dur_sec, total_time_sec, tol_hz)
            % COMPUTE_STABILITY_VS_WINDOW Evaluates fairness/stability across window sizes.
            %
            % Sweeps window duration W from 2 seconds to total_time_sec in 2-second increments.
            % Partitions the signal into non-overlapping blocks of size W, computes stability
            % metrics per block, and averages them to quantify stability vs aggregation scale.
            %
            % Syntax:
            %   [win_sizes, tib, entropy, fairness] = BandwidthTracker.compute_stability_vs_window(...
            %       bw_array, slice_dur_sec, total_time_sec, tol_hz)
            %
            % Inputs:
            %   bw_array       - Vector of instantaneous bandwidth values (Hz)
            %   slice_dur_sec  - Duration per slice in seconds (e.g. 0.5 s)
            %   total_time_sec - Total duration of the recording in seconds
            %   tol_hz         - Tolerance band for Time-in-Band calculation (default: 10 Hz)
            %
            % Outputs:
            %   window_sizes_sec - Vector of tested window durations (s)
            %   mean_tib         - Average Time-in-Band ratio vs window size
            %   mean_entropy     - Average Normalized Shannon Entropy vs window size
            %   mean_fairness    - Average Jain's Fairness Index vs window size

            if nargin < 4 || isempty(tol_hz); tol_hz = 10; end

            % 5-second median pre-filter to eliminate single-sample impulse noise
            bw_array = medfilt1(bw_array, max(3, round(5 / slice_dur_sec)));

            min_window_sec = 2;
            max_window_sec = floor(total_time_sec);
            if max_window_sec < min_window_sec
                window_sizes_sec = []; mean_tib = []; mean_entropy = []; mean_fairness = [];
                return;
            end

            window_sizes_sec = min_window_sec : 2 : max_window_sec;
            mean_tib         = zeros(size(window_sizes_sec));
            mean_entropy     = zeros(size(window_sizes_sec));
            mean_fairness    = zeros(size(window_sizes_sec));

            fs_samples = 1 / slice_dur_sec;
            T          = length(bw_array);
            num_bins   = 20;

            for idx = 1:length(window_sizes_sec)
                win_sec = window_sizes_sec(idx);
                N       = max(1, round(win_sec * fs_samples));

                num_blocks = floor(T / N);
                if num_blocks < 1
                    mean_tib(idx)      = NaN;
                    mean_entropy(idx)  = NaN;
                    mean_fairness(idx) = NaN;
                    continue;
                end

                tib_blocks  = zeros(1, num_blocks);
                ent_blocks  = zeros(1, num_blocks);
                fair_blocks = zeros(1, num_blocks);

                for b = 1:num_blocks
                    block_data = bw_array((b - 1) * N + 1 : b * N);
                    block_data = block_data(isfinite(block_data) & block_data > 0);

                    if isempty(block_data)
                        tib_blocks(b)  = NaN;
                        ent_blocks(b)  = NaN;
                        fair_blocks(b) = NaN;
                        continue;
                    end

                    M = length(block_data);

                    % 1. Time-in-Band (TiB)
                    med_val       = median(block_data);
                    tib_blocks(b) = sum(abs(block_data - med_val) <= tol_hz) / M;

                    % 2. Normalized Shannon Entropy (H_norm)
                    [counts, ~] = histcounts(block_data, num_bins);
                    p           = counts / sum(counts);
                    p           = p(p > 0);
                    if isempty(p) || isscalar(p)
                        ent_blocks(b) = 0; % All values in a single bin = perfectly concentrated
                    else
                        H             = -sum(p .* log2(p));
                        H_max         = log2(length(counts));
                        ent_blocks(b) = H / H_max;
                    end

                    % 3. Jain's Fairness Index
                    sum_val    = sum(block_data);
                    sum_sq_val = sum(block_data.^2);
                    if sum_sq_val > 0
                        fair_blocks(b) = (sum_val^2) / (M * sum_sq_val);
                    else
                        fair_blocks(b) = NaN;
                    end
                end

                mean_tib(idx)      = mean(tib_blocks, 'omitnan');
                mean_entropy(idx)  = mean(ent_blocks, 'omitnan');
                mean_fairness(idx) = mean(fair_blocks, 'omitnan');
            end
        end

        function [t_centers, tib_series, ent_series, fair_series, mean_bw, std_bw] = ...
                compute_rolling_stability(bw_array, slice_dur_sec, window_sec, tol_hz, stride_sec)
            % COMPUTE_ROLLING_STABILITY Computes temporal stability metrics over time windows.
            %
            % Slides a window of duration window_sec across the bandwidth time series.
            % By default, slides by the full window size (stride_sec = window_sec) to produce
            % contiguous non-overlapping window blocks across time.
            %
            % Syntax:
            %   [t_centers, tib, ent, fair, m_bw, s_bw] = BandwidthTracker.compute_rolling_stability(...
            %       bw_array, slice_dur_sec, window_sec, tol_hz, stride_sec)
            %
            % Inputs:
            %   bw_array      - Vector of instantaneous bandwidth values (Hz)
            %   slice_dur_sec - Duration per slice in seconds (e.g. 0.5 s)
            %   window_sec    - Window duration in seconds (e.g. 60 s)
            %   tol_hz        - Time-in-Band tolerance in Hz (default: 10 Hz)
            %   stride_sec    - Stride interval in seconds (default: window_sec -> full window step)
            %
            % Outputs:
            %   t_centers   - Center timestamp of each window in seconds
            %   tib_series  - Time-in-Band ratio time series [0, 1]
            %   ent_series  - Normalized Shannon Entropy time series [0, 1]
            %   fair_series - Jain's Fairness Index time series [0, 1]
            %   mean_bw     - Mean bandwidth per window (Hz)
            %   std_bw      - Standard deviation of bandwidth per window (Hz)

            if nargin < 4 || isempty(tol_hz); tol_hz = 10; end
            if nargin < 5 || isempty(stride_sec); stride_sec = window_sec; end % Default: full window step

            % 5-second median pre-filter to smooth transient noise spikes
            bw_array = medfilt1(bw_array, max(3, round(5 / slice_dur_sec)));

            N            = max(1, round(window_sec / slice_dur_sec));
            step_samples = max(1, round(stride_sec / slice_dur_sec));
            T            = length(bw_array);

            if T < N
                t_centers = []; tib_series = []; ent_series = []; fair_series = []; mean_bw = []; std_bw = [];
                return;
            end

            num_windows = floor((T - N) / step_samples) + 1;
            if num_windows < 1
                t_centers = []; tib_series = []; ent_series = []; fair_series = []; mean_bw = []; std_bw = [];
                return;
            end

            t_centers   = zeros(1, num_windows);
            tib_series  = zeros(1, num_windows);
            ent_series  = zeros(1, num_windows);
            fair_series = zeros(1, num_windows);
            mean_bw     = zeros(1, num_windows);
            std_bw      = zeros(1, num_windows);

            num_bins = 20;

            for b = 1:num_windows
                start_idx  = (b - 1) * step_samples + 1;
                end_idx    = start_idx + N - 1;
                block_data = bw_array(start_idx : end_idx);

                % Window center time in seconds
                t_centers(b) = (start_idx - 1 + N / 2) * slice_dur_sec;

                % Filter out non-finite and non-positive points
                block_data = block_data(isfinite(block_data) & block_data > 0);
                if isempty(block_data)
                    tib_series(b)  = NaN;
                    ent_series(b)  = NaN;
                    fair_series(b) = NaN;
                    mean_bw(b)     = NaN;
                    std_bw(b)      = NaN;
                    continue;
                end

                M = length(block_data);

                % Mean and Standard Deviation of Bandwidth within window
                mean_bw(b) = mean(block_data);
                std_bw(b)  = std(block_data);

                % 1. Time-in-Band (TiB): Fraction within +/- tol_hz of window median
                med_val       = median(block_data);
                tib_series(b) = sum(abs(block_data - med_val) <= tol_hz) / M;

                % 2. Normalized Shannon Entropy (H_norm): Frequency dispersion across 20 bins
                [counts, ~] = histcounts(block_data, num_bins);
                p           = counts / sum(counts);
                p           = p(p > 0);
                if isempty(p) || isscalar(p)
                    ent_series(b) = 0; % Perfectly concentrated in a single bin
                else
                    H             = -sum(p .* log2(p));
                    H_max         = log2(length(counts));
                    ent_series(b) = H / H_max;
                end

                % 3. Jain's Fairness Index: Bandwidth equality (1.0 = zero variance)
                sum_val    = sum(block_data);
                sum_sq_val = sum(block_data.^2);
                if sum_sq_val > 0
                    fair_series(b) = (sum_val^2) / (M * sum_sq_val);
                else
                    fair_series(b) = NaN;
                end
            end
        end

        function [slice_means, slice_sems, slice_times, slice_stds] = ...
                compute_binned_bandwidth(bw_array, slice_dur_sec, bin_dur_sec)
            % COMPUTE_BINNED_BANDWIDTH Aggregates bandwidth into fixed-duration bins.
            %
            % Syntax:
            %   [means, sems, times, stds] = BandwidthTracker.compute_binned_bandwidth(...
            %       bw_array, slice_dur_sec, bin_dur_sec)
            %
            % Inputs:
            %   bw_array      - Vector of instantaneous bandwidth values (Hz)
            %   slice_dur_sec - Duration of each instantaneous slice in seconds (default: 0.5)
            %   bin_dur_sec   - Duration of each aggregated slice/bin in seconds (default: 60)
            %
            % Outputs:
            %   slice_means   - Mean instantaneous bandwidth per bin (Hz)
            %   slice_sems    - Standard error of the mean per bin: std(bw) / sqrt(N) (Hz)
            %   slice_times   - Center timestamp of each bin in seconds
            %   slice_stds    - Standard deviation per bin (Hz)

            if nargin < 2 || isempty(slice_dur_sec); slice_dur_sec = 0.500; end
            if nargin < 3 || isempty(bin_dur_sec);   bin_dur_sec   = 60.0;  end

            bw_array = bw_array(:);
            bw_array = bw_array(isfinite(bw_array) & bw_array > 0);

            if isempty(bw_array)
                slice_means = []; slice_sems = []; slice_times = []; slice_stds = [];
                return;
            end

            N_bin    = max(1, round(bin_dur_sec / slice_dur_sec));
            num_bins = floor(length(bw_array) / N_bin);

            if num_bins < 1
                slice_means = mean(bw_array);
                slice_stds  = std(bw_array);
                slice_sems  = slice_stds / sqrt(length(bw_array));
                slice_times = (length(bw_array) * slice_dur_sec) / 2;
                return;
            end

            slice_means = zeros(num_bins, 1);
            slice_sems  = zeros(num_bins, 1);
            slice_stds  = zeros(num_bins, 1);
            slice_times = zeros(num_bins, 1);

            for b = 1:num_bins
                idx = (b - 1) * N_bin + 1 : b * N_bin;
                blk = bw_array(idx);
                blk = blk(isfinite(blk) & blk > 0);

                slice_times(b) = (b - 0.5) * bin_dur_sec;
                n_pts          = length(blk);

                if n_pts >= 2
                    slice_means(b) = mean(blk);
                    slice_stds(b)  = std(blk);
                    slice_sems(b)  = slice_stds(b) / sqrt(n_pts);
                elseif isscalar(blk)
                    slice_means(b) = blk;
                    slice_stds(b)  = 0;
                    slice_sems(b)  = 0;
                else
                    slice_means(b) = NaN;
                    slice_stds(b)  = NaN;
                    slice_sems(b)  = NaN;
                end
            end
        end

        function crossing_frequency = interpolate_crossing(f, y, i1, i2, level, side)
            % INTERPOLATE_CROSSING Sub-bin linear interpolation for frequency crossing.
            %
            % Computes the precise frequency at which the spectrum crosses a given level
            % between indices i1 and i2.
            %
            % Syntax:
            %   crossing_f = BandwidthTracker.interpolate_crossing(f, y, i1, i2, level, side)

            if i1 < 1 || i2 > numel(y) || y(i2) == y(i1)
                if strcmp(side, 'left')
                    crossing_frequency = f(max(1, min(numel(f), i1)));
                else
                    crossing_frequency = f(max(1, min(numel(f), i2)));
                end
                return;
            end

            % Linear interpolation formula: f = f1 + (level - y1) * (f2 - f1) / (y2 - y1)
            crossing_frequency = f(i1) + (level - y(i1)) * (f(i2) - f(i1)) / (y(i2) - y(i1));
        end

    end
end
