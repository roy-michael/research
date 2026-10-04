classdef FileResult
    % FileResult - Aggregated analysis output for a single audio file.
    %
    % Collects all SegmentResult objects and derived time-series vectors
    % for one recording file.
    
    properties
        filepath    (1,:) char = ''            % Original file path
        filename    (1,:) char = ''            % File basename (no extension)
        base_time   (1,1) datetime = datetime('today')  % Start time extracted from filename
        fs          (1,1) double = 0           % Sampling rate after resampling
        total_duration (1,1) double = 0        % Total duration (seconds)
        
        segments    (:,1) scooter_analysis.results.SegmentResult = ...
            scooter_analysis.results.SegmentResult.empty  % Per-segment results
        
        % Convenience vectors (derived from segments)
        dom_freqs   (:,1) double = []          % [num_segments x 1]
        bw_vals     (:,1) double = []          % [num_segments x 1]
        time_centers_abs (:,1) double = []     % [num_segments x 1] datenum values
        
        % PSD matrix for LTSA
        psd_matrix  (:,:) single = single([])  % [num_freq_bins x num_segments]
        f_grid      (:,1) double = []          % Frequency axis for psd_matrix
    end
    
    methods
        function obj = buildSummaryVectors(obj)
            % Derive the convenience vectors from the segments array.
            if isempty(obj.segments)
                return;
            end
            obj.dom_freqs = [obj.segments.dom_freq]';
            obj.bw_vals   = [obj.segments.med_bw]';
            
            time_centers_sec = ([obj.segments.start_time]' + [obj.segments.end_time]') / 2;
            obj.time_centers_abs = datenum(obj.base_time + seconds(time_centers_sec));
            
            % Build PSD matrix
            psd_cols = {obj.segments.psd_db};
            if ~isempty(psd_cols{1})
                obj.psd_matrix = single(cell2mat(psd_cols));
                obj.f_grid = obj.segments(1).f_grid;
            end
        end
        
        function bws = getAllSliceBandwidths(obj)
            % Concatenate all fine-grained slice bandwidths across segments.
            bws_cells = {};
            for s = 1:length(obj.segments)
                if isfield(obj.segments(s).slice_bw, 'all_main_bws') && ...
                        ~isempty(obj.segments(s).slice_bw.all_main_bws)
                    bws_cells{end+1} = obj.segments(s).slice_bw.all_main_bws(:);
                end
            end
            bws = vertcat(bws_cells{:});
        end
        
        function res = getFairnessResult(obj, custom_name, max_window_sec)
            % Build a result struct compatible with Visualizer.render_bandwidth_distribution
            if nargin < 2 || isempty(custom_name)
                custom_name = obj.filename;
            end
            if nargin < 3 || isempty(max_window_sec)
                max_window_sec = 60;
            end
            
            bws = obj.getAllSliceBandwidths();
            bws = bws(isfinite(bws) & bws > 0);
            
            slice_dur = 0.500;
            tol_hz = 10;
            if ~isempty(obj.segments) && isfield(obj.segments(1).slice_bw, 'fairness_window_sec') && ...
                    ~isempty(obj.segments(1).slice_bw.fairness_window_sec) && length(obj.segments) == 1
                win_sizes = obj.segments(1).slice_bw.fairness_window_sec;
                all_tib = obj.segments(1).slice_bw.all_tib;
                all_entropy = obj.segments(1).slice_bw.all_entropy;
                all_fairness = obj.segments(1).slice_bw.all_fairness;
            else
                total_time = min(length(bws) * slice_dur, max_window_sec);
                if total_time >= 2 && ~isempty(bws)
                    [win_sizes, all_tib, all_entropy, all_fairness] = ...
                        BandwidthTracker.compute_stability_vs_window(bws, slice_dur, total_time, tol_hz);
                else
                    win_sizes = [];
                    all_tib = [];
                    all_entropy = [];
                    all_fairness = [];
                end
            end
            
            res = struct();
            res.meta.name = custom_name;
            res.slice_bw.all_main_bws = bws;
            res.slice_bw.fairness_window_sec = win_sizes;
            res.slice_bw.all_tib = all_tib;
            res.slice_bw.all_entropy = all_entropy;
            res.slice_bw.all_fairness = all_fairness;
        end
    end
end
