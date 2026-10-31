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
        mean_bw     (1,1) double = NaN     % Mean bandwidth across slices (Hz)
        sem_bw      (1,1) double = NaN     % Standard error of bandwidth across slices (Hz)
        std_bw      (1,1) double = NaN     % Standard deviation of bandwidth across slices (Hz)
        psd_db      (:,1) double = []      % Interpolated PSD vector (dB)
        f_grid      (:,1) double = []      % Corresponding frequency grid (Hz)
        
        % Full BandwidthTracker output (preserved for fairness graphs)
        slice_bw    struct = struct()      % Output of BandwidthTracker

        % Phase Lock (Digital PLL) & Instantaneous Frequency Verification output
        pll_mean_plv      (1,1) double = NaN   % Mean Phase Locking Value (Circular Sync R in [0,1])
        pll_global_r      (1,1) double = NaN   % Global segment circular resultant length R
        pll_phase_std     (1,1) double = NaN   % Mean slice wrapped phase error SD (rad)
        pll_freq_mean     (1,1) double = NaN   % Mean PLL tracked instantaneous frequency (Hz)
        pll_freq_std      (1,1) double = NaN   % Mean slice PLL instantaneous frequency spread SD (Hz)
        pll_freq_dev      (1,1) double = NaN   % Mean slice PLL frequency drift from carrier (Hz)
        pll_freq_verif_err (1,1) double = NaN  % Mean |f_PLL - f_FFT| instantaneous frequency error (Hz)
        pll_lock_ratio    (1,1) double = NaN   % Fraction of slices locked within pll_freq_lock_tol_hz
        pll_result        struct = struct()    % Full output of BandwidthTracker.compute_pll_phase_lock

        % Lobe information
        macro_lobes struct = struct()      % All detected macro lobes
        dom_lobe    struct = struct()      % Dominant lobe struct
        ocean_floor (:,1) double = []      % Ambient baseline
        ocean_ambient_db (1,1) double = NaN
    end
end
