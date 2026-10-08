classdef SegmentAnalyzer
    % SegmentAnalyzer - Reusable single-segment analysis core.
    %
    % Extracts the shared inner-loop body (Welch -> Notch -> Lobe -> BW) that
    % was duplicated across all 7 original scripts into one static method.
    %
    % Usage:
    %   sr = scooter_analysis.pipeline.SegmentAnalyzer.analyze( ...
    %       segment_sig, fs, t0, t1, cfg, cfg_bw);
    
    methods (Static)
        
        function sr = analyze(segment_sig, fs, t0, t1, cfg, cfg_bw)
            % Analyse one time segment through the full Welch+Lobe+BW pipeline.
            %
            % Args:
            %   segment_sig - Signal vector for this segment (already HP-filtered)
            %   fs          - Sampling rate (Hz)
            %   t0          - Segment start time (seconds from file start)
            %   t1          - Segment end time (seconds from file start)
            %   cfg         - scooter_analysis.config.AnalysisConfig
            %   cfg_bw      - Bandwidth tracker struct (from cfg.toBandwidthConfig)
            %
            % Returns:
            %   sr - scooter_analysis.results.SegmentResult
            
            sr = scooter_analysis.results.SegmentResult();
            sr.start_time = t0;
            sr.end_time = t1;
            
            % Welch PSD
            [psd_db, f_grid, df, ~] = SpectralEngine.compute_welch_psd( ...
                segment_sig, fs, cfg.f_low, cfg.f_high, cfg.twin_welch, cfg.df_eval);
            
            % Notch filter (interference removal)
            if cfg.enable_notch && cfg.notch_low > 0 && cfg.notch_high > cfg.notch_low
                psd_db = scooter_analysis.pipeline.SegmentAnalyzer.applyNotch( ...
                    psd_db, f_grid, cfg.notch_low, cfg.notch_high);
            end
            
            % Macro-lobe segmentation
            [macro_lobes, dom_lobe, ocean_floor_smooth, ocean_ambient_db] = ...
                SpectralEngine.segment_macro_lobes(psd_db, f_grid, df, cfg.prom_split_db);
            
            % Bandwidth tracking
            slice_bw = BandwidthTracker.compute_watershed_slice_bandwidth( ...
                segment_sig, fs, dom_lobe, cfg_bw);
            bws_valid = slice_bw.all_main_bws(isfinite(slice_bw.all_main_bws) & slice_bw.all_main_bws > 0);
            med_bw = median(bws_valid, 'omitnan');
            mean_bw = mean(bws_valid, 'omitnan');
            std_bw  = std(bws_valid, 'omitnan');
            if ~isempty(bws_valid)
                sem_bw = std_bw / sqrt(length(bws_valid));
            else
                sem_bw = NaN;
            end
            
            % Populate result
            sr.dom_freq = dom_lobe.peak_freq;
            sr.peak_psd = dom_lobe.peak_psd;
            sr.med_bw = med_bw;
            sr.mean_bw = mean_bw;
            sr.sem_bw = sem_bw;
            sr.std_bw = std_bw;
            sr.psd_db = psd_db;
            sr.f_grid = f_grid;
            sr.slice_bw = slice_bw;
            sr.macro_lobes = macro_lobes;
            sr.dom_lobe = dom_lobe;
            sr.ocean_floor = ocean_floor_smooth;
            sr.ocean_ambient_db = ocean_ambient_db;
        end
        
    end
    
    
    methods (Static, Access = private)
        function psd_db = applyNotch(psd_db, f_grid, f_notch_low, f_notch_high)
            % Interpolate across a notch band to suppress known interference.
            mask = (f_grid >= f_notch_low) & (f_grid <= f_notch_high);
            idx_left = find(f_grid < f_notch_low, 1, 'last');
            idx_right = find(f_grid > f_notch_high, 1, 'first');
            if ~isempty(idx_left) && ~isempty(idx_right)
                psd_db(mask) = interp1( ...
                    [f_grid(idx_left), f_grid(idx_right)], ...
                    [psd_db(idx_left), psd_db(idx_right)], ...
                    f_grid(mask), 'linear');
            end
        end
    end
end
