classdef SegmentResult
    % SegmentResult - Data container for a single analysed time segment.
    %
    % Holds all computed quantities for one Welch window so that downstream
    % code never needs to re-derive them.
    
    properties
        start_time  (1,1) double = 0       % Segment start (seconds from file start)
        end_time    (1,1) double = 0       % Segment end   (seconds from file start)
        dom_freq    (1,1) double = NaN     % Dominant lobe peak frequency (Hz)
        peak_psd    (1,1) double = NaN     % Peak PSD of dominant lobe (dB)
        med_bw      (1,1) double = NaN     % Median bandwidth across slices (Hz)
        psd_db      (:,1) double = []      % Interpolated PSD vector (dB)
        f_grid      (:,1) double = []      % Corresponding frequency grid (Hz)
        
        % Full BandwidthTracker output (preserved for fairness graphs)
        slice_bw    struct = struct()      % Output of BandwidthTracker
        
        % Lobe information
        macro_lobes struct = struct()      % All detected macro lobes
        dom_lobe    struct = struct()      % Dominant lobe struct
        ocean_floor (:,1) double = []      % Ambient baseline
        ocean_ambient_db (1,1) double = NaN
    end
end
