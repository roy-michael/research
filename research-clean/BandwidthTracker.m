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
            max_bins = 20;
            if isfield(cfg, 'entropy_max_bins') && ~isempty(cfg.entropy_max_bins)
                max_bins = cfg.entropy_max_bins;
            elseif isprop(cfg, 'bw_entropy_max_bins')
                max_bins = cfg.bw_entropy_max_bins;
            end
            [win_sizes, all_tib, all_entropy, all_fairness] = ...
                BandwidthTracker.compute_stability_vs_window(...
                    all_main_bws, slice_dur_sec, total_time_sec, cfg.tib_tolerance_hz, max_bins);

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
                compute_stability_vs_window(bw_array, slice_dur_sec, total_time_sec, tol_hz, max_bins)
            % COMPUTE_STABILITY_VS_WINDOW Evaluates fairness/stability across window sizes.
            %
            % Sweeps window duration W from 2 seconds to total_time_sec in 2-second increments.
            % Partitions the signal into non-overlapping blocks of size W, computes stability
            % metrics per block, and averages them to quantify stability vs aggregation scale.
            %
            % Syntax:
            %   [win_sizes, tib, entropy, fairness] = BandwidthTracker.compute_stability_vs_window(...
            %       bw_array, slice_dur_sec, total_time_sec, tol_hz, max_bins)
            %
            % Inputs:
            %   bw_array       - Vector of instantaneous bandwidth values (Hz)
            %   slice_dur_sec  - Duration per slice in seconds (e.g. 0.5 s)
            %   total_time_sec - Total duration of the recording in seconds
            %   tol_hz         - Tolerance band for Time-in-Band calculation (default: 10 Hz)
            %   max_bins       - Maximum histogram bins for adaptive Shannon entropy (default: 20)
            %
            % Outputs:
            %   window_sizes_sec - Vector of tested window durations (s)
            %   mean_tib         - Average Time-in-Band ratio vs window size
            %   mean_entropy     - Average Normalized Shannon Entropy vs window size
            %   mean_fairness    - Average Jain's Fairness Index vs window size

            if nargin < 4 || isempty(tol_hz); tol_hz = 10; end
            if nargin < 5 || isempty(max_bins); max_bins = 20; end

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

                    % 2. Normalized Shannon Entropy (H_norm) with adaptive binning
                    % Adaptive bin count scales dynamically with sample count M:
                    %   k = min([max_bins, M, max(2, round(sqrt(M) * 1.8))])
                    % Eliminates finite-sample distortion for short windows (e.g. M < 20),
                    % while smoothly matching max_bins (20) for standard 60-second windows (M = 120).
                    if M < 2
                        ent_blocks(b) = 0; % Single sample has zero dispersion
                    else
                        num_bins    = min([max_bins, M, max(2, round(sqrt(M) * 1.8))]);
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
                compute_rolling_stability(bw_array, slice_dur_sec, window_sec, tol_hz, stride_sec, max_bins)
            % COMPUTE_ROLLING_STABILITY Computes temporal stability metrics over time windows.
            %
            % Slides a window of duration window_sec across the bandwidth time series.
            % By default, slides by the full window size (stride_sec = window_sec) to produce
            % contiguous non-overlapping window blocks across time.
            %
            % Syntax:
            %   [t_centers, tib, ent, fair, m_bw, s_bw] = BandwidthTracker.compute_rolling_stability(...
            %       bw_array, slice_dur_sec, window_sec, tol_hz, stride_sec, max_bins)
            %
            % Inputs:
            %   bw_array      - Vector of instantaneous bandwidth values (Hz)
            %   slice_dur_sec - Duration per slice in seconds (e.g. 0.5 s)
            %   window_sec    - Window duration in seconds (e.g. 60 s)
            %   tol_hz        - Time-in-Band tolerance in Hz (default: 10 Hz)
            %   stride_sec    - Stride interval in seconds (default: window_sec -> full window step)
            %   max_bins      - Maximum histogram bins for adaptive Shannon entropy (default: 20)
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
            if nargin < 6 || isempty(max_bins); max_bins = 20; end

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

                % 2. Normalized Shannon Entropy (H_norm): Frequency dispersion with adaptive binning
                % Adaptive bin count scales dynamically with sample count M:
                %   k = min([max_bins, M, max(2, round(sqrt(M) * 1.8))])
                % Eliminates finite-sample distortion for short windows (e.g. M < 20),
                % while smoothly matching max_bins (20) for standard 60-second windows (M = 120).
                if M < 2
                    ent_series(b) = 0; % Single sample has zero dispersion
                else
                    num_bins    = min([max_bins, M, max(2, round(sqrt(M) * 1.8))]);
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


        % =================================================================
        % SECTION 3: Digital Phase-Locked Loop (PLL) & Instantaneous Frequency Verification
        % =================================================================

        function out = compute_pll_phase_lock(signal, fs, dom_lobe, cfg, slice_bw)
            % COMPUTE_PLL_PHASE_LOCK Tracks carrier phase and instantaneous frequency via 2nd-order Digital PLL.
            %
            % Verifies instantaneous frequency stability, FM spread, and phase coherence (Phase Locking
            % Value / Circular Mean Resultant Length R) across uniform time slices.
            %
            % Syntax:
            %   out = BandwidthTracker.compute_pll_phase_lock(signal, fs, dom_lobe, cfg, slice_bw)
            %
            % Inputs:
            %   signal   - 1D time-domain acoustic signal vector
            %   fs       - Sampling frequency (Hz)
            %   dom_lobe - Struct defining dominant macro-lobe (.peak_freq, .f_start, .f_end)
            %   cfg      - Configuration struct (from AnalysisConfig.toBandwidthConfig)
            %   slice_bw - Optional output struct from compute_watershed_slice_bandwidth for FFT comparison
            %
            % Outputs:
            %   out      - Struct containing slice-level and segment-level phase lock & inst. freq metrics.

            out = struct( ...
                'found', false, ...
                'f_center', NaN, ...
                'mean_plv', NaN, ...
                'global_r', NaN, ...
                'phase_std_rad', NaN, ...
                'inst_freq_mean_hz', NaN, ...
                'inst_freq_std_hz', NaN, ...
                'inst_freq_dev_hz', NaN, ...
                'freq_verif_err_hz', NaN, ...
                'lock_ratio', NaN, ...
                'all_plvs', [], ...
                'all_mean_phases', [], ...
                'all_phase_stds', [], ...
                'all_inst_freqs', [], ...
                'all_inst_freq_stds', [], ...
                'all_inst_freq_devs', [], ...
                'all_freq_verif_errs', [], ...
                'phase_samples', [], ...
                'fairness_window_sec', [], ...
                'all_plv_vs_win', [], ...
                'all_phase_ent_vs_win', [], ...
                'all_freq_lock_vs_win', []);

            if isempty(signal) || length(signal) < 64 || ~isstruct(dom_lobe) || ~isfield(dom_lobe, 'peak_freq') || isnan(dom_lobe.peak_freq)
                return;
            end

            sig = double(signal(:));
            N   = length(sig);
            f_center = double(dom_lobe.peak_freq);

            % Extract configuration parameters with defaults
            bp_margin_hz = 80.0;
            if isfield(cfg, 'pll_bandpass_margin_hz') && ~isempty(cfg.pll_bandpass_margin_hz)
                bp_margin_hz = cfg.pll_bandpass_margin_hz;
            end
            loop_bw_hz = 18.0;
            if isfield(cfg, 'pll_loop_bw_hz') && ~isempty(cfg.pll_loop_bw_hz)
                loop_bw_hz = cfg.pll_loop_bw_hz;
            end
            zeta = 0.707;
            if isfield(cfg, 'pll_damping_zeta') && ~isempty(cfg.pll_damping_zeta)
                zeta = cfg.pll_damping_zeta;
            end
            max_freq_dev_hz = 60.0;
            if isfield(cfg, 'pll_max_freq_dev_hz') && ~isempty(cfg.pll_max_freq_dev_hz)
                max_freq_dev_hz = cfg.pll_max_freq_dev_hz;
            end
            freq_lock_tol_hz = 5.0;
            if isfield(cfg, 'pll_freq_lock_tol_hz') && ~isempty(cfg.pll_freq_lock_tol_hz)
                freq_lock_tol_hz = cfg.pll_freq_lock_tol_hz;
            end
            slice_dur_sec = 0.500;
            if isfield(cfg, 'slice_dur_sec') && ~isempty(cfg.slice_dur_sec)
                slice_dur_sec = cfg.slice_dur_sec;
            end
            max_bins = 20;
            if isfield(cfg, 'entropy_max_bins') && ~isempty(cfg.entropy_max_bins)
                max_bins = cfg.entropy_max_bins;
            end

            % --- Step 1 & 2: Per-0.5s-Slice Dominant Frequency Bandpass & 2nd-Order Digital PLL ---
            nyq = 0.5 * fs;
            f_low_lim = 5.0;
            if isfield(cfg, 'f_low') && ~isempty(cfg.f_low)
                f_low_lim = max(5.0, cfg.f_low);
            end
            f_high_lim = nyq - 10.0;
            if isfield(cfg, 'f_high') && ~isempty(cfg.f_high)
                f_high_lim = min(nyq - 5.0, cfg.f_high);
            end

            seg_bw_est = 40.0;
            if (nargin >= 5) && isstruct(slice_bw) && isfield(slice_bw, 'all_main_bws') && ~isempty(slice_bw.all_main_bws)
                valid_bws = slice_bw.all_main_bws(isfinite(slice_bw.all_main_bws) & slice_bw.all_main_bws > 0);
                if ~isempty(valid_bws)
                    seg_bw_est = median(valid_bws);
                end
            elseif isstruct(dom_lobe) && isfield(dom_lobe, 'bandwidth') && isfinite(dom_lobe.bandwidth) && dom_lobe.bandwidth > 0
                seg_bw_est = dom_lobe.bandwidth;
            end

            slice_len  = floor(fs * slice_dur_sec);
            num_slices = floor(N / max(1, slice_len));
            if num_slices < 1
                return;
            end

            wn = 2.0 * pi * loop_bw_hz / (zeta + 1.0 / (4.0 * zeta));
            kp = (2.0 * zeta * wn) / fs;
            ki = (wn * wn) / (fs * fs);

            max_dev_rad = 2.0 * pi * max_freq_dev_hz / fs;
            two_pi      = 2.0 * pi;
            fs_over_2pi = fs / two_pi;

            all_plvs            = zeros(num_slices, 1);
            all_mean_phases     = zeros(num_slices, 1);
            all_phase_stds      = zeros(num_slices, 1);
            all_inst_freqs      = zeros(num_slices, 1);
            all_inst_freq_stds  = zeros(num_slices, 1);
            all_inst_freq_devs  = zeros(num_slices, 1);
            all_freq_verif_errs = nan(num_slices, 1);
            phase_error         = zeros(num_slices * slice_len, 1);
            local_t_idx         = (0 : slice_len - 1)';
            hann_win            = 0.5 * (1 - cos(two_pi * local_t_idx / max(1, slice_len - 1)));
            pad_len             = min(round(0.05 * fs), floor(slice_len / 4));
            env_win             = max(16, round(0.08 * fs));

            has_fft_slices = (nargin >= 5) && isstruct(slice_bw) && ...
                isfield(slice_bw, 'slice_outputs') && length(slice_bw.slice_outputs) >= num_slices;

            for m = 1:num_slices
                idx = (m - 1) * slice_len + (1 : slice_len);

                % 1. Identify the dominant frequency and bandwidth of this 0.5s slice
                f_dom_m = NaN;
                bw_m    = seg_bw_est;
                if has_fft_slices && ~isempty(slice_bw.slice_outputs{m}) && ...
                        isfield(slice_bw.slice_outputs{m}, 'found') && slice_bw.slice_outputs{m}.found
                    if isfield(slice_bw.slice_outputs{m}, 'main_f') && isfinite(slice_bw.slice_outputs{m}.main_f) && slice_bw.slice_outputs{m}.main_f > 0
                        f_dom_m = double(slice_bw.slice_outputs{m}.main_f);
                    end
                    if isfield(slice_bw.slice_outputs{m}, 'main_bw') && isfinite(slice_bw.slice_outputs{m}.main_bw) && slice_bw.slice_outputs{m}.main_bw > 0
                        bw_m = double(slice_bw.slice_outputs{m}.main_bw);
                    end
                end

                % Fallback to local 0.5s Hann-windowed FFT peak if slice_bw was not provided
                if ~isfinite(f_dom_m) || f_dom_m <= 0
                    sig_sl = sig(idx) .* hann_win;
                    Y_sl   = abs(fft(sig_sl));
                    n_half = floor(slice_len / 2) + 1;
                    f_sl   = (0 : n_half - 1)' * (fs / slice_len);
                    Y_half = Y_sl(1:n_half);
                    valid_f = (f_sl >= f_low_lim) & (f_sl <= f_high_lim);
                    if any(valid_f)
                        Y_sub = Y_half;
                        Y_sub(~valid_f) = -Inf;
                        [~, pk_bin] = max(Y_sub);
                        if pk_bin > 1 && pk_bin < n_half
                            y1 = log(max(Y_half(pk_bin - 1), eps));
                            y2 = log(max(Y_half(pk_bin), eps));
                            y3 = log(max(Y_half(pk_bin + 1), eps));
                            denom = 2 * (2 * y2 - y1 - y3);
                            delta = 0;
                            if abs(denom) > 1e-12
                                delta = max(-0.5, min(0.5, (y1 - y3) / denom));
                            end
                            f_dom_m = f_sl(pk_bin) + delta * (fs / slice_len);
                        else
                            f_dom_m = f_sl(pk_bin);
                        end
                    else
                        f_dom_m = f_center;
                    end
                end

                % 2. Extract padded 0.5s segment and bandpass-filter around its dominant frequency f_dom_m
                i_pad1  = max(1, idx(1) - pad_len);
                i_pad2  = min(N, idx(end) + pad_len);
                sig_pad = sig(i_pad1 : i_pad2);

                eff_margin     = min(bp_margin_hz, max(16.0, 0.70 * bw_m));
                max_sym_margin = min(max(12.0, f_dom_m - f_low_lim), max(12.0, f_high_lim - f_dom_m));
                eff_margin     = min(eff_margin, max_sym_margin);

                bp_low  = max(f_low_lim, f_dom_m - eff_margin);
                bp_high = min(f_high_lim, f_dom_m + eff_margin);
                if bp_low >= bp_high - 2.0
                    bp_low  = max(5.0, f_dom_m - 25.0);
                    bp_high = min(nyq - 5.0, f_dom_m + 25.0);
                end

                filt_pad = sig_pad;
                if bp_low > 0 && bp_high < nyq && bp_low < bp_high
                    try
                        [b_bp, a_bp] = butter(2, [bp_low, bp_high] / nyq, 'bandpass');
                        filt_pad = filtfilt(b_bp, a_bp, sig_pad);
                    catch
                        filt_pad = sig_pad;
                    end
                end

                % Analytic signal & AGC normalization on padded slice, then trim guard pad
                z_pad     = hilbert(filt_pad);
                local_env = movmean(abs(z_pad), env_win);
                rms_floor = 0.20 * median(abs(z_pad)) + eps;
                z_norm    = z_pad ./ max(local_env, rms_floor);

                trim_start = (idx(1) - i_pad1) + 1;
                trim_range = trim_start : (trim_start + slice_len - 1);
                real_sig   = max(-1.5, min(1.5, real(z_norm(trim_range))));
                imag_sig   = max(-1.5, min(1.5, imag(z_norm(trim_range))));

                % 3. Run 2nd-Order Digital PLL locked to this 0.5s slice's dominant frequency f_dom_m
                w_center_m  = two_pi * f_dom_m / fs;
                phase_raw_m = zeros(slice_len, 1);
                pe_track_m  = zeros(slice_len, 1);
                freq_out_m  = zeros(slice_len, 1);

                phase           = atan2(imag_sig(1), real_sig(1));
                freq_integrator = 0.0;

                for i = 1:slice_len
                    c_p = cos(phase);
                    s_p = sin(phase);
                    err_sin = imag_sig(i) * c_p - real_sig(i) * s_p;
                    err_cos = real_sig(i) * c_p + imag_sig(i) * s_p;
                    pe = err_sin;
                    pe_track_m(i) = atan2(err_sin, err_cos);

                    freq_integrator = freq_integrator + ki * pe;
                    if freq_integrator > max_dev_rad
                        freq_integrator = max_dev_rad;
                    elseif freq_integrator < -max_dev_rad
                        freq_integrator = -max_dev_rad;
                    end

                    freq_ctrl = kp * pe + freq_integrator;
                    if freq_ctrl > max_dev_rad
                        freq_ctrl = max_dev_rad;
                    elseif freq_ctrl < -max_dev_rad
                        freq_ctrl = -max_dev_rad;
                    end

                    phase          = phase + w_center_m + freq_ctrl;
                    phase_raw_m(i) = phase;
                    freq_out_m(i)  = (w_center_m + freq_ctrl) * fs_over_2pi;
                end

                % 4. Slice-level phase lock & instantaneous frequency statistics
                f_mean_slice          = mean(freq_out_m);
                f_std_slice           = std(freq_out_m);
                all_inst_freqs(m)     = f_mean_slice;
                all_inst_freq_stds(m) = f_std_slice;
                all_inst_freq_devs(m) = abs(f_mean_slice - f_dom_m);
                all_freq_verif_errs(m) = abs(f_mean_slice - f_dom_m);

                % Phase trajectory relative to the 0.5s dominant frequency carrier
                w_slice     = two_pi * f_mean_slice / fs;
                phi_nco_dev = (phase_raw_m - phase_raw_m(1)) - w_slice * local_t_idx;
                phi_seg     = mod(phi_nco_dev + pe_track_m + pi, two_pi) - pi;

                % Circular Mean Resultant Length R (Phase Locking Value) in [0, 1]
                mc       = mean(cos(phi_seg));
                ms       = mean(sin(phi_seg));
                R_val    = hypot(mc, ms);
                phi_mean = atan2(ms, mc);

                % Mean phase offset of this 0.5s segment relative to its FFT dominant frequency f_dom_m
                phi_dom_rel = mod((phase_raw_m - phase_raw_m(1)) - w_center_m * local_t_idx + pe_track_m + pi, two_pi) - pi;
                phi_dom_mean = atan2(mean(sin(phi_dom_rel)), mean(cos(phi_dom_rel)));

                % Centered slice phase error & circular standard deviation
                phi_centered       = mod(phi_seg - phi_mean + pi, two_pi) - pi;
                phase_error(idx)   = phi_centered;
                all_plvs(m)        = R_val;
                all_mean_phases(m) = phi_dom_mean;
                all_phase_stds(m)  = std(phi_centered);
            end

            % Store representative downsampled phase error samples (~600 per segment) for PDF/KDE
            N_valid = num_slices * slice_len;
            ds_step = max(1, floor(N_valid / 600));
            phase_samples = phase_error(1:ds_step:N_valid);

            % --- Step 4: Multiscale Phase & Instantaneous Frequency Stability vs Window Size ---
            total_time_sec = num_slices * slice_dur_sec;
            [win_sizes, all_plv_vs_win, all_phase_ent_vs_win, all_freq_lock_vs_win] = ...
                BandwidthTracker.compute_phase_stability_vs_window( ...
                    all_plvs, all_mean_phases, all_inst_freq_stds, slice_dur_sec, total_time_sec, freq_lock_tol_hz, max_bins);

            % Populate summary metrics
            out.found               = true;
            out.f_center            = f_center;
            out.mean_plv            = mean(all_plvs, 'omitnan');
            out.global_r            = hypot(mean(cos(phase_error)), mean(sin(phase_error)));
            out.phase_std_rad       = mean(all_phase_stds, 'omitnan');
            out.inst_freq_mean_hz   = mean(all_inst_freqs, 'omitnan');
            out.inst_freq_std_hz    = mean(all_inst_freq_stds, 'omitnan');
            out.inst_freq_dev_hz    = mean(all_inst_freq_devs, 'omitnan');
            out.freq_verif_err_hz   = mean(all_freq_verif_errs, 'omitnan');
            out.lock_ratio          = mean(all_inst_freq_stds <= freq_lock_tol_hz, 'omitnan');
            out.all_plvs            = all_plvs;
            out.all_mean_phases     = all_mean_phases;
            out.all_phase_stds      = all_phase_stds;
            out.all_inst_freqs      = all_inst_freqs;
            out.all_inst_freq_stds  = all_inst_freq_stds;
            out.all_inst_freq_devs  = all_inst_freq_devs;
            out.all_freq_verif_errs = all_freq_verif_errs;
            out.phase_samples       = phase_samples;
            out.fairness_window_sec = win_sizes;
            out.all_plv_vs_win      = all_plv_vs_win;
            out.all_phase_ent_vs_win = all_phase_ent_vs_win;
            out.all_freq_lock_vs_win = all_freq_lock_vs_win;
        end

        function [window_sizes_sec, mean_plv, mean_phase_entropy, mean_freq_lock] = ...
                compute_phase_stability_vs_window(plv_array, mean_phases_array, freq_std_array, slice_dur_sec, total_time_sec, freq_tol_hz, max_bins)
            % COMPUTE_PHASE_STABILITY_VS_WINDOW Evaluates PLL phase lock & inst. freq stability vs window scale.
            %
            % Sweeps window duration W from 2 seconds to total_time_sec in 2-second increments.
            % Applies a 5-second median pre-filter (matching compute_stability_vs_window) and computes:
            %   1. Multiscale Phase Locking Value R(W) (vector resultant coherence across window W)
            %   2. Normalized Circular Phase Shannon Entropy (H_phi_norm)
            %   3. Instantaneous Frequency Lock Fairness Index (Jain's Fairness of PLL freq spread)

            if nargin < 6 || isempty(freq_tol_hz); freq_tol_hz = 5.0; end
            if nargin < 7 || isempty(max_bins); max_bins = 20; end

            min_window_sec = 2;
            max_window_sec = floor(total_time_sec);
            if max_window_sec < min_window_sec || isempty(plv_array)
                window_sizes_sec = [];
                mean_plv = [];
                mean_phase_entropy = [];
                mean_freq_lock = [];
                return;
            end

            % 5-second median pre-filter to eliminate single-slice impulse noise (consistent with bandwidth stability)
            med_win = max(3, round(5 / slice_dur_sec));
            plv_filt = medfilt1(double(plv_array(:)), med_win);
            if ~isempty(mean_phases_array)
                phi_filt = medfilt1(double(mean_phases_array(:)), med_win);
            else
                phi_filt = [];
            end
            if ~isempty(freq_std_array)
                fstd_filt = medfilt1(double(freq_std_array(:)), med_win);
            else
                fstd_filt = [];
            end

            window_sizes_sec   = min_window_sec : 2 : max_window_sec;
            mean_plv           = zeros(size(window_sizes_sec));
            mean_phase_entropy = zeros(size(window_sizes_sec));
            mean_freq_lock     = zeros(size(window_sizes_sec));

            fs_samples = 1 / slice_dur_sec;
            T          = length(plv_filt);

            for idx = 1:length(window_sizes_sec)
                win_sec = window_sizes_sec(idx);
                N       = max(1, round(win_sec * fs_samples));

                num_blocks = floor(T / N);
                if num_blocks < 1
                    mean_plv(idx)           = NaN;
                    mean_phase_entropy(idx) = NaN;
                    mean_freq_lock(idx)     = NaN;
                    continue;
                end

                plv_blocks  = zeros(1, num_blocks);
                ent_blocks  = zeros(1, num_blocks);
                lock_blocks = zeros(1, num_blocks);

                for b = 1:num_blocks
                    range_idx = (b - 1) * N + 1 : b * N;
                    blk_plv   = plv_filt(range_idx);
                    valid_p   = isfinite(blk_plv);

                    if ~any(valid_p)
                        plv_blocks(b)  = NaN;
                        ent_blocks(b)  = NaN;
                        lock_blocks(b) = NaN;
                        continue;
                    end

                    % 1. Multiscale Phase Lock Coherence R(W) across window N
                    if ~isempty(phi_filt) && length(phi_filt) >= max(range_idx)
                        blk_phi_raw = phi_filt(range_idx);
                        valid_both  = valid_p & isfinite(blk_phi_raw);
                        if any(valid_both)
                            r_sub   = blk_plv(valid_both);
                            phi_sub = blk_phi_raw(valid_both);
                            plv_blocks(b) = hypot(mean(r_sub .* cos(phi_sub)), mean(r_sub .* sin(phi_sub)));
                        else
                            plv_blocks(b) = mean(blk_plv(valid_p));
                        end
                    else
                        plv_blocks(b) = mean(blk_plv(valid_p));
                    end

                    % 2. Normalized Phase Shannon Entropy across [-pi, pi]
                    if ~isempty(phi_filt) && length(phi_filt) >= max(range_idx)
                        blk_phi = phi_filt(range_idx);
                        blk_phi = blk_phi(isfinite(blk_phi));
                    else
                        blk_phi = [];
                    end
                    M_phi = length(blk_phi);
                    if M_phi < 2
                        ent_blocks(b) = 0;
                    else
                        num_bins = min([max_bins, M_phi, max(2, round(sqrt(M_phi) * 1.8))]);
                        edges = linspace(-pi, pi, num_bins + 1);
                        counts = histcounts(blk_phi, edges);
                        p = counts / max(1, sum(counts));
                        p = p(p > 0);
                        if isempty(p) || isscalar(p)
                            ent_blocks(b) = 0;
                        else
                            H = -sum(p .* log2(p));
                            H_max = log2(num_bins);
                            ent_blocks(b) = H / H_max;
                        end
                    end

                    % 3. Instantaneous Frequency Lock Stability (Jain's Fairness of PLL freq spread)
                    if ~isempty(fstd_filt) && length(fstd_filt) >= max(range_idx)
                        blk_fstd = fstd_filt(range_idx);
                        blk_fstd = blk_fstd(isfinite(blk_fstd) & blk_fstd >= 0);
                    else
                        blk_fstd = [];
                    end
                    if ~isempty(blk_fstd)
                        M_f = length(blk_fstd);
                        s_val = sum(blk_fstd);
                        s_sq  = sum(blk_fstd.^2);
                        if s_sq > 0
                            lock_blocks(b) = (s_val^2) / (M_f * s_sq);
                        else
                            lock_blocks(b) = 1.0;
                        end
                    else
                        lock_blocks(b) = NaN;
                    end
                end

                mean_plv(idx)           = mean(plv_blocks, 'omitnan');
                mean_phase_entropy(idx) = mean(ent_blocks, 'omitnan');
                mean_freq_lock(idx)     = mean(lock_blocks, 'omitnan');
            end
        end

        function [t_centers, plv_series, phase_ent_series, freq_lock_series, mean_freq_std, std_freq_std] = ...
                compute_rolling_phase_stability(plv_array, mean_phases_array, freq_std_array, slice_dur_sec, window_sec, freq_tol_hz, stride_sec, max_bins)
            % COMPUTE_ROLLING_PHASE_STABILITY Computes temporal trajectories of PLL phase lock & inst. freq metrics.
            %
            % Slides a window of duration window_sec (default: 60s non-overlapping stride) across the
            % slice-level PLL time series and computes:
            %   - plv_series:       Mean Phase Locking Value R(t) in [0, 1]
            %   - phase_ent_series: Normalized Phase Shannon Entropy H_phi(t) in [0, 1]
            %   - freq_lock_series: Instantaneous Frequency Stability Fairness Index in [0, 1]
            %   - mean_freq_std:    Mean PLL Instantaneous Frequency Spread sigma_f(t) per window (Hz)
            %   - std_freq_std:     SD of PLL Instantaneous Frequency Spread per window (Hz)

            if nargin < 4 || isempty(slice_dur_sec); slice_dur_sec = 0.500; end
            if nargin < 5 || isempty(window_sec);    window_sec    = 60.0;  end
            if nargin < 6 || isempty(freq_tol_hz);   freq_tol_hz   = 5.0;   end
            if nargin < 7 || isempty(stride_sec);    stride_sec    = window_sec; end
            if nargin < 8 || isempty(max_bins);      max_bins      = 20;    end

            % 5-second median pre-filter to smooth single-slice impulse noise (consistent with compute_rolling_stability)
            med_win = max(3, round(5 / slice_dur_sec));
            plv_filt = medfilt1(double(plv_array(:)), med_win);
            if ~isempty(mean_phases_array)
                phi_filt = medfilt1(double(mean_phases_array(:)), med_win);
            else
                phi_filt = [];
            end
            if ~isempty(freq_std_array)
                fstd_filt = medfilt1(double(freq_std_array(:)), med_win);
            else
                fstd_filt = [];
            end

            N            = max(1, round(window_sec / slice_dur_sec));
            step_samples = max(1, round(stride_sec / slice_dur_sec));
            T            = length(plv_filt);

            if T < N
                t_centers = []; plv_series = []; phase_ent_series = []; freq_lock_series = [];
                mean_freq_std = []; std_freq_std = [];
                return;
            end

            num_windows = floor((T - N) / step_samples) + 1;
            t_centers        = zeros(1, num_windows);
            plv_series       = zeros(1, num_windows);
            phase_ent_series = zeros(1, num_windows);
            freq_lock_series = zeros(1, num_windows);
            mean_freq_std    = zeros(1, num_windows);
            std_freq_std     = zeros(1, num_windows);

            for b = 1:num_windows
                start_idx = (b - 1) * step_samples + 1;
                end_idx   = start_idx + N - 1;
                t_centers(b) = (start_idx - 1 + N / 2) * slice_dur_sec;

                blk_plv = plv_filt(start_idx : end_idx);
                blk_plv = blk_plv(isfinite(blk_plv));
                if isempty(blk_plv)
                    plv_series(b) = NaN;
                else
                    plv_series(b) = mean(blk_plv);
                end

                % Phase Shannon Entropy (Normalized)
                if ~isempty(phi_filt) && length(phi_filt) >= end_idx
                    blk_phi = phi_filt(start_idx : end_idx);
                    blk_phi = blk_phi(isfinite(blk_phi));
                else
                    blk_phi = [];
                end
                M_phi = length(blk_phi);
                if M_phi < 2
                    phase_ent_series(b) = 0;
                else
                    num_bins = min([max_bins, M_phi, max(2, round(sqrt(M_phi) * 1.8))]);
                    edges = linspace(-pi, pi, num_bins + 1);
                    counts = histcounts(blk_phi, edges);
                    p = counts / max(1, sum(counts));
                    p = p(p > 0);
                    if isempty(p) || isscalar(p)
                        phase_ent_series(b) = 0;
                    else
                        H = -sum(p .* log2(p));
                        H_max = log2(num_bins);
                        phase_ent_series(b) = H / H_max;
                    end
                end

                % Instantaneous Frequency Spread & Lock Fairness
                if ~isempty(fstd_filt) && length(fstd_filt) >= end_idx
                    blk_fstd = fstd_filt(start_idx : end_idx);
                    blk_fstd = blk_fstd(isfinite(blk_fstd) & blk_fstd >= 0);
                else
                    blk_fstd = [];
                end
                if ~isempty(blk_fstd)
                    mean_freq_std(b) = mean(blk_fstd);
                    std_freq_std(b)  = std(blk_fstd);
                    M_f   = length(blk_fstd);
                    s_val = sum(blk_fstd);
                    s_sq  = sum(blk_fstd.^2);
                    if s_sq > 0
                        freq_lock_series(b) = (s_val^2) / (M_f * s_sq);
                    else
                        freq_lock_series(b) = 1.0;
                    end
                else
                    mean_freq_std(b)    = NaN;
                    std_freq_std(b)     = NaN;
                    freq_lock_series(b) = NaN;
                end
            end
        end

        function out = compute_binned_phase_lock(plv_array, freq_std_array, phase_std_array, freq_verif_err_array, slice_dur_sec, bin_dur_sec)
            % COMPUTE_BINNED_PHASE_LOCK Aggregates PLL phase lock & inst. freq verification into fixed bins (e.g. 60s).
            %
            % Syntax:
            %   out = BandwidthTracker.compute_binned_phase_lock( ...
            %       plv_array, freq_std_array, phase_std_array, freq_verif_err_array, slice_dur_sec, bin_dur_sec)

            if nargin < 5 || isempty(slice_dur_sec); slice_dur_sec = 0.500; end
            if nargin < 6 || isempty(bin_dur_sec);   bin_dur_sec   = 60.0;  end

            plv_array = plv_array(:);
            out = struct( ...
                'bin_dur_sec', bin_dur_sec, ...
                'slice_times', [], ...
                'plv_means', [], 'plv_stds', [], 'plv_sems', [], ...
                'freq_std_means', [], 'freq_std_stds', [], 'freq_std_sems', [], ...
                'phase_std_means', [], 'phase_std_stds', [], 'phase_std_sems', [], ...
                'verif_err_means', [], 'verif_err_stds', [], 'verif_err_sems', []);

            if isempty(plv_array)
                return;
            end

            N_bin    = max(1, round(bin_dur_sec / slice_dur_sec));
            num_bins = floor(length(plv_array) / N_bin);
            if num_bins < 1
                num_bins = 1;
                N_bin = length(plv_array);
            end

            out.slice_times     = zeros(num_bins, 1);
            out.plv_means       = nan(num_bins, 1);
            out.plv_stds        = nan(num_bins, 1);
            out.plv_sems        = nan(num_bins, 1);
            out.freq_std_means  = nan(num_bins, 1);
            out.freq_std_stds   = nan(num_bins, 1);
            out.freq_std_sems   = nan(num_bins, 1);
            out.phase_std_means = nan(num_bins, 1);
            out.phase_std_stds  = nan(num_bins, 1);
            out.phase_std_sems  = nan(num_bins, 1);
            out.verif_err_means = nan(num_bins, 1);
            out.verif_err_stds  = nan(num_bins, 1);
            out.verif_err_sems  = nan(num_bins, 1);

            for b = 1:num_bins
                idx = (b - 1) * N_bin + 1 : min(length(plv_array), b * N_bin);
                out.slice_times(b) = (b - 0.5) * bin_dur_sec;

                % 1. Phase Locking Value (R)
                blk_p = plv_array(idx);
                blk_p = blk_p(isfinite(blk_p));
                if ~isempty(blk_p)
                    out.plv_means(b) = mean(blk_p);
                    out.plv_stds(b)  = std(blk_p);
                    out.plv_sems(b)  = out.plv_stds(b) / sqrt(length(blk_p));
                end

                % 2. PLL Instantaneous Frequency Spread (sigma_f in Hz)
                if ~isempty(freq_std_array) && length(freq_std_array) >= max(idx)
                    blk_f = freq_std_array(idx);
                    blk_f = blk_f(isfinite(blk_f));
                    if ~isempty(blk_f)
                        out.freq_std_means(b) = mean(blk_f);
                        out.freq_std_stds(b)  = std(blk_f);
                        out.freq_std_sems(b)  = out.freq_std_stds(b) / sqrt(length(blk_f));
                    end
                end

                % 3. Wrapped Phase Error Standard Deviation (sigma_phi in rad)
                if ~isempty(phase_std_array) && length(phase_std_array) >= max(idx)
                    blk_ph = phase_std_array(idx);
                    blk_ph = blk_ph(isfinite(blk_ph));
                    if ~isempty(blk_ph)
                        out.phase_std_means(b) = mean(blk_ph);
                        out.phase_std_stds(b)  = std(blk_ph);
                        out.phase_std_sems(b)  = out.phase_std_stds(b) / sqrt(length(blk_ph));
                    end
                end

                % 4. Instantaneous Frequency Verification Error |f_PLL - f_FFT| (Hz)
                if ~isempty(freq_verif_err_array) && length(freq_verif_err_array) >= max(idx)
                    blk_ve = freq_verif_err_array(idx);
                    blk_ve = blk_ve(isfinite(blk_ve));
                    if ~isempty(blk_ve)
                        out.verif_err_means(b) = mean(blk_ve);
                        out.verif_err_stds(b)  = std(blk_ve);
                        out.verif_err_sems(b)  = out.verif_err_stds(b) / sqrt(length(blk_ve));
                    end
                end
            end
        end

    end
end
