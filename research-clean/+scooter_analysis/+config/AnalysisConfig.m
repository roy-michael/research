classdef AnalysisConfig
    % AnalysisConfig - Centralised configuration for acoustic analysis pipelines.
    %
    % Usage:
    %   cfg = scooter_analysis.config.AnalysisConfig();            % default config
    %   cfg = scooter_analysis.config.AnalysisConfig.haifaBay();   % Haifa Bay preset
    %   cfg = scooter_analysis.config.AnalysisConfig.croatia();    % Croatia scooter preset
    %   cfg.f_low = 100;                                           % override any field

    properties
        % Audio Loading
        target_fs       (1,1) double = 8000      % Target sampling rate (Hz)

        % Spectrogram Parameters
        window_dur_sec  (1,1) double = 1.00      % STFT window duration (s)
        overlap_ratio   (1,1) double = 0.90      % STFT overlap ratio [0,1)
        nfft            (1,1) double = 0         % Custom NFFT (0 = auto)
        remove_transients (1,1) logical = true   % Median-filter broadband clicks
        transient_filter_width (1,1) double = 10 % Median filter width (time-pixels)
        prctile_clip    (1,1) double = 99.5      % Upper percentile for colour clipping

        % Frequency Band
        f_low           (1,1) double = 20        % Lower analysis bound (Hz)
        f_high          (1,1) double = 1000      % Upper analysis bound (Hz)

        % Welch / Lobe Tracking
        segment_duration (1,1) double = 60       % Duration of each Welch segment (s)
        step_duration    (1,1) double = 60       % Sliding window step size (s)
        twin_welch       (1,1) double = 0.050    % Welch sub-window size (s)
        df_eval          (1,1) double = 0.50     % Frequency grid spacing (Hz)
        prom_split_db    (1,1) double = 3.0      % Prominence for lobe splitting (dB)

        % Notch Filter (interference removal)
        enable_notch     (1,1) logical = false   % Enable notch suppression band
        notch_low        (1,1) double = 300      % Notch band lower edge (Hz)
        notch_high       (1,1) double = 360      % Notch band upper edge (Hz)

        % Bandwidth Tracker
        bw_slice_dur_sec   (1,1) double = 0.500
        bw_watershed_prom_max_db  (1,1) double = 8.0
        bw_watershed_prom_min_db  (1,1) double = 3.0
        bw_watershed_prom_ratio   (1,1) double = 0.40
        bw_watershed_rebound_ratio (1,1) double = 0.50   % Relative rebound ratio (rise / drop >= 0.50)
        bw_watershed_min_dip_db    (1,1) double = 1.50   % Minimum valley dip from peak to trigger rebound (dB)
        bw_watershed_noise_fallback_margin (1,1) double = 0.90
        bw_smooth_method  (1,:) char = 'welch'
        bw_smooth_window  (1,1) double = 5
        bw_tib_tolerance_hz (1,1) double = 10

        % High-Pass Filter
        hp_cutoff        (1,1) double = 0        % High-pass filter cutoff (0 = auto, uses f_low)
        hp_order         (1,1) double = 4        % Butterworth filter order

        % Video Export
        enable_video     (1,1) logical = false   % Generate Welch diagram video
        video_frame_rate (1,1) double = 4        % Video frame rate

        % Spectrogram Export
        enable_spectrogram (1,1) logical = true  % Generate high-res spectrogram
    end

    methods
        function cfg_bw = toBandwidthConfig(obj)
            % Converts to the struct expected by BandwidthTracker
            cfg_bw = struct();
            cfg_bw.f_low = obj.f_low;
            cfg_bw.f_high = obj.f_high;
            cfg_bw.slice_dur_sec = obj.bw_slice_dur_sec;
            cfg_bw.watershed_prom_max_db = obj.bw_watershed_prom_max_db;
            cfg_bw.watershed_prom_min_db = obj.bw_watershed_prom_min_db;
            cfg_bw.watershed_prom_ratio = obj.bw_watershed_prom_ratio;
            cfg_bw.watershed_rebound_ratio = obj.bw_watershed_rebound_ratio;
            cfg_bw.watershed_min_dip_db = obj.bw_watershed_min_dip_db;
            cfg_bw.watershed_noise_fallback_margin = obj.bw_watershed_noise_fallback_margin;
            cfg_bw.bw_smooth_method = obj.bw_smooth_method;
            cfg_bw.bw_smooth_window = obj.bw_smooth_window;
            cfg_bw.twin_welch = obj.twin_welch;
            cfg_bw.tib_tolerance_hz = obj.bw_tib_tolerance_hz;
        end
    end

    methods (Static)
        function cfg = haifaBay()
            % Preset for Haifa Bay ambient noise monitoring
            cfg = scooter_analysis.config.AnalysisConfig();
            cfg.f_low = 20;
            cfg.f_high = 1000;
            cfg.segment_duration = 30;
            cfg.step_duration = 30;
        end

        function cfg = croatia()
            % Preset for Croatia scooter per-file batch recordings
            cfg = scooter_analysis.config.AnalysisConfig();
            cfg.f_low = 400;
            cfg.f_high = 1600;
            cfg.enable_notch = true;
        end

        function cfg = croatiaDatasets()
            % Preset for Croatia multi-dataset continuous analysis
            cfg = scooter_analysis.config.AnalysisConfig();
            cfg.f_low = 400;
            cfg.f_high = 2000;
            cfg.enable_notch = true;
            cfg.transient_filter_width = 20;
            cfg.enable_video = true;
        end

        function cfg = singleFileDetailed()
            % Preset for single-file deep analysis with finer time resolution
            cfg = scooter_analysis.config.AnalysisConfig();
            cfg.f_low = 400;
            cfg.f_high = 1400;
            cfg.segment_duration = 120;
            cfg.step_duration = 15;
            cfg.prom_split_db = 5.0;
            cfg.transient_filter_width = 30;
            cfg.enable_video = true;
        end

        function cfg = cruise()
            % Preset for Departmental Cruise continuous recording
            cfg = scooter_analysis.config.AnalysisConfig();
            cfg.f_low = 200;
            cfg.f_high = 2000;
            cfg.step_duration = 15;
            cfg.prom_split_db = 5.0;
        end

        function cfg = directory()
            % Preset for generic directory batch analysis
            cfg = scooter_analysis.config.AnalysisConfig();
            cfg.f_low = 100;
            cfg.f_high = 2000;
            cfg.step_duration = 15;
            cfg.prom_split_db = 5.0;
        end

        function cfg = dominantFreq()
            % Preset for dominant frequency tracking (original Ashdod scooter)
            cfg = scooter_analysis.config.AnalysisConfig();
            cfg.f_low = 100;
            cfg.f_high = 2000;
            cfg.step_duration = 15;
            cfg.prom_split_db = 5.0;
        end

        function cfg = auv()
            % Preset for AUV
            cfg = scooter_analysis.config.AnalysisConfig();
            cfg.f_low = 300;
            cfg.f_high = 1400;
            cfg.segment_duration = 60;
            cfg.step_duration = 60;
        end
    end
end
