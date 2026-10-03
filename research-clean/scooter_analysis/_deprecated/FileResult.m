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
        
        segments    (:,1) SegmentResult = SegmentResult.empty  % Per-segment results
        
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
    end
end
