classdef FileAnalyzer
    % FileAnalyzer - Single-file analysis pipeline.
    %
    % Handles the per-file loop: HP filtering, segment extraction,
    % and calling SegmentAnalyzer for each time window.  Supports both
    % preloaded signals and on-disk reading.
    %
    % Usage:
    %   fr = scooter_analysis.pipeline.FileAnalyzer.analyzeSignal( ...
    %       sig, fs, base_time, cfg, 'Name', 'myfile');
    %
    %   fr = scooter_analysis.pipeline.FileAnalyzer.analyzeFile( ...
    %       filepath, cfg);
    
    methods (Static)
        
        function fr = analyzeSignal(sig, fs, base_time, cfg, varargin)
            % Analyse a preloaded signal through the full pipeline.
            %
            % Args:
            %   sig       - Mono, DC-removed, resampled audio signal
            %   fs        - Sampling rate (Hz)
            %   base_time - datetime of recording start
            %   cfg       - scooter_analysis.config.AnalysisConfig
            %   Name-Value:
            %     'Name'     - Human-readable name (default: 'signal')
            %     'FilePath' - Original file path for reporting (default: '')
            %
            % Returns:
            %   fr - scooter_analysis.results.FileResult
            
            p = inputParser;
            addParameter(p, 'Name', 'signal');
            addParameter(p, 'FilePath', '');
            parse(p, varargin{:});
            
            fr = scooter_analysis.results.FileResult();
            fr.filepath = p.Results.FilePath;
            fr.filename = p.Results.Name;
            fr.base_time = base_time;
            fr.fs = fs;
            
            total_duration = length(sig) / fs;
            fr.total_duration = total_duration;
            
            cfg_bw = cfg.toBandwidthConfig();
            
            % High-pass filter the entire signal once
            [b_hp, a_hp] = butter(cfg.hp_order, cfg.hp_cutoff / (fs / 2), 'high');
            sig_filt = filtfilt(b_hp, a_hp, sig);
            
            % Segment timing
            start_times = 0:cfg.step_duration:(total_duration - cfg.segment_duration);
            if isempty(start_times)
                start_times = 0;
            end
            num_segments = length(start_times);
            segments = repmat(scooter_analysis.results.SegmentResult(), num_segments, 1);
            
            for i = 1:num_segments
                t0 = start_times(i);
                t1 = min(total_duration, t0 + cfg.segment_duration);
                
                s0 = max(1, round(t0 * fs) + 1);
                s1 = round(t1 * fs);
                segment_sig = sig_filt(s0:s1);
                
                segments(i) = scooter_analysis.pipeline.SegmentAnalyzer.analyze( ...
                    segment_sig, fs, t0, t1, cfg, cfg_bw);
                
                if mod(i, 50) == 0
                    fprintf('  Processed segment %d/%d (%.1f mins)...\n', ...
                        i, num_segments, t0/60);
                end
            end
            
            fr.segments = segments;
            fr = fr.buildSummaryVectors();
        end
        
        
        function fr = analyzeFile(filepath, cfg)
            % Load a single file from disk and analyse it.
            %
            % Args:
            %   filepath - Path to WAV file
            %   cfg      - scooter_analysis.config.AnalysisConfig
            %
            % Returns:
            %   fr - scooter_analysis.results.FileResult (empty segments on failure)
            
            [sig, fs, base_time, filename] = ...
                scooter_analysis.io.AudioLoader.loadFile(filepath, cfg.target_fs);
            
            if isempty(sig)
                fr = scooter_analysis.results.FileResult();
                return;
            end
            
            fprintf('Loaded %s (%.1f min)\n', filename, (length(sig)/fs)/60);
            
            fr = scooter_analysis.pipeline.FileAnalyzer.analyzeSignal( ...
                sig, fs, base_time, cfg, 'Name', filename, 'FilePath', filepath);
        end
        
    end
end
