classdef DatasetAnalyzer < handle
    % DatasetAnalyzer - Core analysis engine for batch processing audio files.
    %
    % Processes one or many WAV files through the SpectralEngine and
    % BandwidthTracker pipeline, collecting structured results.
    %
    % Usage:
    %   cfg = AnalysisConfig.haifaBay();
    %   analyzer = DatasetAnalyzer('D:\Recordings\HaifaBay', cfg);
    %   analyzer.run();
    %   ReportGenerator.overallHistograms(analyzer, 'output/histograms.png');
    
    properties
        DatasetPath  (1,:) char                 % Root directory of WAV files
        Config       (1,1) AnalysisConfig       % Analysis configuration
        DatasetName  (1,:) char = 'Dataset'     % Human-readable label
        OutputDir    (1,:) char = ''            % Output directory root
        RecursiveSearch (1,1) logical = false   % Search subdirectories for WAVs
        
        FileResults  (:,1) FileResult = FileResult.empty  % Results per file
    end
    
    methods
        function obj = DatasetAnalyzer(dataset_path, config, varargin)
            % Constructor.
            %
            % Args:
            %   dataset_path - Directory containing WAV files
            %   config       - AnalysisConfig object
            %   Name-Value pairs:
            %     'Name'      - Human-readable dataset name (default: dir basename)
            %     'OutputDir' - Output directory (default: scooter_analysis/output/<Name>)
            %     'Recursive' - Search subdirectories (default: false)
            
            obj.DatasetPath = dataset_path;
            obj.Config = config;
            
            p = inputParser;
            addParameter(p, 'Name', '');
            addParameter(p, 'OutputDir', '');
            addParameter(p, 'Recursive', false);
            parse(p, varargin{:});
            
            obj.RecursiveSearch = p.Results.Recursive;
            
            if isempty(p.Results.Name)
                [~, obj.DatasetName] = fileparts(dataset_path);
            else
                obj.DatasetName = p.Results.Name;
            end
            
            if isempty(p.Results.OutputDir)
                script_dir = fileparts(mfilename('fullpath'));
                obj.OutputDir = fullfile(script_dir, 'output', obj.DatasetName);
            else
                obj.OutputDir = p.Results.OutputDir;
            end
        end
        
        
        function run(obj)
            % Run the full batch analysis pipeline.
            
            % Ensure parent classes are on the path
            script_dir = fileparts(mfilename('fullpath'));
            addpath(fullfile(script_dir, '..'));
            
            files = AudioLoader.findFiles(obj.DatasetPath, obj.RecursiveSearch);
            if isempty(files)
                return;
            end
            
            obj.FileResults = FileResult.empty;
            cfg = obj.Config;
            cfg_bw = cfg.toBandwidthConfig();
            
            for f_idx = 1:length(files)
                filepath = fullfile(files(f_idx).folder, files(f_idx).name);
                
                % --- Load ---
                [sig, fs, base_time, filename] = AudioLoader.loadFile(filepath, cfg.target_fs);
                if isempty(sig)
                    continue;
                end
                
                total_duration = length(sig) / fs;
                fprintf('Loaded %s (%.1f min)\n', filename, total_duration / 60);
                
                % --- Per-file output directory ---
                file_out_dir = fullfile(obj.OutputDir, filename);
                if ~exist(file_out_dir, 'dir')
                    mkdir(file_out_dir);
                end
                
                % --- Analyse segments ---
                fr = obj.analyzeFile(sig, fs, base_time, cfg, cfg_bw);
                fr.filepath = filepath;
                fr.filename = filename;
                fr.base_time = base_time;
                fr.fs = fs;
                fr.total_duration = total_duration;
                fr = fr.buildSummaryVectors();
                
                % --- Write per-file report ---
                obj.writeReport(fr, file_out_dir);
                
                % --- Per-file frequency/bandwidth plot ---
                ReportGenerator.freqBandwidthTimeSeries(fr, file_out_dir);
                
                obj.FileResults(end+1, 1) = fr;
                fprintf('Analysis completed for %s!\n', filename);
            end
            
            fprintf('All %d files processed.\n', length(obj.FileResults));
        end
        
        
        function fr = analyzeFile(~, sig, fs, base_time, cfg, cfg_bw)
            % Analyse a single loaded signal through the Welch+Lobe+BW pipeline.
            
            fr = FileResult();
            total_duration = length(sig) / fs;
            
            % High-pass filter
            [b_hp, a_hp] = butter(cfg.hp_order, cfg.hp_cutoff / (fs / 2), 'high');
            sig_filt = filtfilt(b_hp, a_hp, sig);
            
            % Segment timing
            start_times = 0:cfg.step_duration:(total_duration - cfg.segment_duration);
            if isempty(start_times)
                start_times = 0;
            end
            num_segments = length(start_times);
            segments = repmat(SegmentResult(), num_segments, 1);
            
            for i = 1:num_segments
                t0 = start_times(i);
                t1 = min(total_duration, t0 + cfg.segment_duration);
                
                s0 = max(1, round(t0 * fs) + 1);
                s1 = round(t1 * fs);
                segment_sig = sig_filt(s0:s1);
                
                % Welch PSD
                [psd_db, f_grid, df, ~] = SpectralEngine.compute_welch_psd( ...
                    segment_sig, fs, cfg.f_low, cfg.f_high, cfg.twin_welch, cfg.df_eval);
                
                % Notch filter
                psd_db = DatasetAnalyzer.applyNotch(psd_db, f_grid, cfg.notch_low, cfg.notch_high);
                
                % Macro-lobe segmentation
                [macro_lobes, dom_lobe, ocean_floor_smooth, ocean_ambient_db] = ...
                    SpectralEngine.segment_macro_lobes(psd_db, f_grid, df, cfg.prom_split_db);
                
                % Bandwidth tracking
                slice_bw = BandwidthTracker.compute_watershed_slice_bandwidth( ...
                    segment_sig, fs, dom_lobe, cfg_bw);
                med_bw = median(slice_bw.all_main_bws, 'omitnan');
                
                % Store result
                sr = SegmentResult();
                sr.start_time = t0;
                sr.end_time = t1;
                sr.dom_freq = dom_lobe.peak_freq;
                sr.peak_psd = dom_lobe.peak_psd;
                sr.med_bw = med_bw;
                sr.psd_db = psd_db;
                sr.f_grid = f_grid;
                sr.slice_bw = slice_bw;
                sr.macro_lobes = macro_lobes;
                sr.dom_lobe = dom_lobe;
                sr.ocean_floor = ocean_floor_smooth;
                sr.ocean_ambient_db = ocean_ambient_db;
                
                segments(i) = sr;
            end
            
            fr.segments = segments;
        end
        
        
        function writeReport(~, fr, out_dir)
            % Write the per-file dominant_frequencies_report.txt
            
            report_path = fullfile(out_dir, 'dominant_frequencies_report.txt');
            fid = fopen(report_path, 'w');
            fprintf(fid, 'Analysis of: %s\n', fr.filepath);
            fprintf(fid, 'Total Duration: %.2f seconds (%.2f minutes)\n', ...
                fr.total_duration, fr.total_duration / 60);
            fprintf(fid, '======================================================\n');
            fprintf(fid, 'Segment Index | Start Time (m) | End Time (m) | Dominant Freq (Hz) | Peak PSD (dB) | Bandwidth (Hz)\n');
            
            for i = 1:length(fr.segments)
                sr = fr.segments(i);
                fprintf(fid, '  %4d       | %12.2f | %10.2f | %18.2f | %12.2f | %14.2f\n', ...
                    i, sr.start_time/60, sr.end_time/60, sr.dom_freq, sr.peak_psd, sr.med_bw);
            end
            fclose(fid);
        end
        
        
        % --- Convenience accessors ---
        
        function freqs = getAllDomFreqs(obj)
            % Concatenate dominant frequencies across all files.
            freqs = vertcat(obj.FileResults.dom_freqs);
        end
        
        function bws = getAllBandwidths(obj)
            % Concatenate bandwidths across all files.
            bws = vertcat(obj.FileResults.bw_vals);
        end
        
        function [psd_matrix, times, f_grid] = getLTSAData(obj)
            % Build the full LTSA matrix across all files.
            psd_cells = {obj.FileResults.psd_matrix};
            time_cells = {obj.FileResults.time_centers_abs};
            psd_matrix = cat(2, psd_cells{:});
            times = cat(1, time_cells{:});
            
            % Use f_grid from first file with data
            f_grid = [];
            for i = 1:length(obj.FileResults)
                if ~isempty(obj.FileResults(i).f_grid)
                    f_grid = obj.FileResults(i).f_grid;
                    break;
                end
            end
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
