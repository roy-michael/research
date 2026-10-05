classdef BatchAnalyzer < handle
    % BatchAnalyzer - Multi-file / multi-dataset analysis orchestrator.
    %
    % Supports four modes of operation:
    %   'single_file'  - Analyse one WAV file (like analyze_single_file.m)
    %   'per_file'     - Analyse each WAV independently (like batch_analyze_haifa_bay.m)
    %   'concatenated'  - Concatenate all files into one signal (like analyze_continuous_cruise.m)
    %   'multi_dataset' - Loop over named subdirectories, each concatenated
    %                     (like analyze_croatia_datasets.m)
    %
    % Usage:
    %   cfg = scooter_analysis.config.AnalysisConfig.haifaBay();
    %   ba = scooter_analysis.pipeline.BatchAnalyzer( ...
    %       'D:\Recordings\HaifaBay', cfg, ...
    %       'Name', 'HaifaBay', 'Mode', 'per_file');
    %   ba.run();
    
    properties
        DatasetPath   (1,:) char                              % Root directory or single file
        Config        (1,1) scooter_analysis.config.AnalysisConfig
        DatasetName   (1,:) char = 'Dataset'                  % Human-readable label
        OutputDir     (1,:) char = ''                          % Output directory root
        Mode          (1,:) char = 'per_file'                 % 'single_file'|'per_file'|'concatenated'|'multi_dataset'
        RecursiveSearch (1,1) logical = false                  % Search subdirectories for WAVs
        Subdatasets   (1,:) cell = {}                          % Subdirectory names for multi_dataset mode
        
        FileResults   (:,1) scooter_analysis.results.FileResult = ...
            scooter_analysis.results.FileResult.empty         % Results per file/dataset
    end
    
    methods
        function obj = BatchAnalyzer(dataset_path, config, varargin)
            % Constructor.
            %
            % Args:
            %   dataset_path - Directory or single file path
            %   config       - scooter_analysis.config.AnalysisConfig
            %   Name-Value pairs:
            %     'Name'         - Human-readable dataset name
            %     'OutputDir'    - Output directory (default: auto from Name)
            %     'Mode'         - 'single_file'|'per_file'|'concatenated'|'multi_dataset'
            %     'Recursive'    - Search subdirectories (default: false)
            %     'Subdatasets'  - Cell array of subdirectory names for multi_dataset
            
            obj.DatasetPath = dataset_path;
            obj.Config = config;
            
            p = inputParser;
            addParameter(p, 'Name', '');
            addParameter(p, 'OutputDir', '');
            addParameter(p, 'Mode', 'per_file');
            addParameter(p, 'Recursive', false);
            addParameter(p, 'Subdatasets', {});
            parse(p, varargin{:});
            
            obj.Mode = p.Results.Mode;
            obj.RecursiveSearch = p.Results.Recursive;
            obj.Subdatasets = p.Results.Subdatasets;
            
            if isempty(p.Results.Name)
                [~, obj.DatasetName] = fileparts(dataset_path);
            else
                obj.DatasetName = p.Results.Name;
            end
            
            if isempty(p.Results.OutputDir)
                % Go from +pipeline -> +scooter_analysis -> research-clean
                research_clean_dir = fileparts(fileparts(fileparts(mfilename('fullpath'))));
                obj.OutputDir = fullfile(research_clean_dir, 'scooter_analysis', 'output', obj.DatasetName);
            else
                obj.OutputDir = p.Results.OutputDir;
            end
        end
        
        
        function run(obj)
            % Run the full batch analysis pipeline according to the configured mode.
            
            fprintf('\n======================================================\n');
            fprintf('BatchAnalyzer: %s  (mode: %s)\n', obj.DatasetName, obj.Mode);
            fprintf('======================================================\n');
            
            switch obj.Mode
                case 'single_file'
                    obj.runSingleFile();
                case 'per_file'
                    obj.runPerFile();
                case 'concatenated'
                    obj.runConcatenated();
                case 'multi_dataset'
                    obj.runMultiDataset();
                otherwise
                    error('BatchAnalyzer:InvalidMode', ...
                        'Unknown mode "%s". Use single_file|per_file|concatenated|multi_dataset.', obj.Mode);
            end
            
            fprintf('\n======================================================\n');
            fprintf('All analysis completed for %s! (%d results)\n', ...
                obj.DatasetName, length(obj.FileResults));
            fprintf('======================================================\n');
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
        
        function bws = getAllSliceBandwidths(obj)
            % Concatenate all fine-grained slice bandwidths across all segments in all files.
            bws_cells = {};
            for i = 1:length(obj.FileResults)
                fr = obj.FileResults(i);
                bws_cells{end+1} = fr.getAllSliceBandwidths();
            end
            bws = vertcat(bws_cells{:});
        end
        
        function res = getFairnessResult(obj, max_window_sec)
            % Build a result struct representing this entire dataset,
            % compatible with Visualizer.render_bandwidth_distribution.
            if nargin < 2 || isempty(max_window_sec)
                max_window_sec = 60;
            end
            
            bws = obj.getAllSliceBandwidths();
            bws = bws(isfinite(bws) & bws > 0);
            
            slice_dur = obj.Config.bw_slice_dur_sec;
            tol_hz = obj.Config.bw_tib_tolerance_hz;
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
            
            res = struct();
            res.meta.name = obj.DatasetName;
            res.slice_bw.all_main_bws = bws;
            res.slice_bw.fairness_window_sec = win_sizes;
            res.slice_bw.all_tib = all_tib;
            res.slice_bw.all_entropy = all_entropy;
            res.slice_bw.all_fairness = all_fairness;
        end
        
        function results = getFileFairnessResults(obj, max_window_sec)
            % Build cell array of result structs, one per file in this analyzer.
            if nargin < 2 || isempty(max_window_sec)
                max_window_sec = 60;
            end
            num_files = length(obj.FileResults);
            results = cell(num_files, 1);
            for i = 1:num_files
                results{i} = obj.FileResults(i).getFairnessResult(obj.FileResults(i).filename, max_window_sec);
            end
        end
        
        function res = getVisualizerResult(obj)
            % Build a structured container representing this dataset for Visualizer
            % (Fig 1 Macro-Lobe, Fig 2 Watershed BW, Fig 4 Fairness, Fig 6 Dominant Freq)
            res = struct();
            res.meta = struct('name', obj.DatasetName, ...
                'f_low', obj.Config.f_low, 'f_high', obj.Config.f_high);
            
            if isempty(obj.FileResults)
                res.f_grid = [];
                res.psd_db = [];
                res.macro_lobes = struct([]);
                res.dom_lobe = struct('peak_freq', NaN, 'peak_psd', NaN, 'f_start', NaN, 'f_end', NaN, 'pct_energy', 0);
                res.ocean_floor_smooth = [];
                res.ocean_ambient_db = NaN;
                res.slice_bw = struct('found', false, 'all_main_bws', [], ...
                    'fairness_window_sec', [], 'all_tib', [], 'all_entropy', [], 'all_fairness', []);
                return;
            end
            
            % Find file and segment with highest peak PSD across the dataset
            best_fr_idx = 1;
            best_sr_idx = 1;
            best_psd = -Inf;
            
            for fi = 1:length(obj.FileResults)
                fr = obj.FileResults(fi);
                if ~isempty(fr.segments)
                    [max_p, s_idx] = max([fr.segments.peak_psd]);
                    if max_p > best_psd
                        best_psd = max_p;
                        best_fr_idx = fi;
                        best_sr_idx = s_idx;
                    end
                end
            end
            
            if isinf(best_psd)
                res.f_grid = [];
                res.psd_db = [];
                res.macro_lobes = struct([]);
                res.dom_lobe = struct('peak_freq', NaN, 'peak_psd', NaN, 'f_start', NaN, 'f_end', NaN, 'pct_energy', 0);
                res.ocean_floor_smooth = [];
                res.ocean_ambient_db = NaN;
                res.slice_bw = struct('found', false, 'all_main_bws', [], ...
                    'fairness_window_sec', [], 'all_tib', [], 'all_entropy', [], 'all_fairness', []);
                return;
            end
            
            sr = obj.FileResults(best_fr_idx).segments(best_sr_idx);
            
            res.f_grid = sr.f_grid;
            res.psd_db = sr.psd_db;
            res.macro_lobes = sr.macro_lobes;
            res.dom_lobe = sr.dom_lobe;
            res.ocean_floor_smooth = sr.ocean_floor;
            res.ocean_ambient_db = sr.ocean_ambient_db;
            
            % slice_bw containing both single-slice watershed and multi-slice fairness
            res.slice_bw = sr.slice_bw;
            fair_res = obj.getFairnessResult();
            res.slice_bw.all_main_bws = fair_res.slice_bw.all_main_bws;
            res.slice_bw.fairness_window_sec = fair_res.slice_bw.fairness_window_sec;
            res.slice_bw.all_tib = fair_res.slice_bw.all_tib;
            res.slice_bw.all_entropy = fair_res.slice_bw.all_entropy;
            res.slice_bw.all_fairness = fair_res.slice_bw.all_fairness;
        end
        
        function results = getFileVisualizerResults(obj)
            % Build cell array of Visualizer containers, one per file
            num_files = length(obj.FileResults);
            results = cell(num_files, 1);
            for i = 1:num_files
                results{i} = obj.FileResults(i).getVisualizerResult(obj.FileResults(i).filename);
            end
        end
    end
    
    
    methods (Access = private)
        
        function runSingleFile(obj)
            % Analyse a single file.
            
            if ~exist(obj.DatasetPath, 'file')
                fprintf('Error: File not found %s\n', obj.DatasetPath);
                return;
            end
            
            [~, filename, ~] = fileparts(obj.DatasetPath);
            file_out_dir = fullfile(obj.OutputDir, filename);
            if ~exist(file_out_dir, 'dir'); mkdir(file_out_dir); end
            
            fr = scooter_analysis.pipeline.FileAnalyzer.analyzeFile( ...
                obj.DatasetPath, obj.Config);
            
            if isempty(fr.segments); return; end
            
            % Write report
            scooter_analysis.reporting.ReportGenerator.writeFileReport(fr, file_out_dir);
            
            % Plots
            scooter_analysis.reporting.PlotGenerator.freqBandwidthTimeSeries(fr, file_out_dir);
            
            if obj.Config.enable_spectrogram
                try
                    [sig, fs, base_time] = scooter_analysis.io.AudioLoader.loadFile( ...
                        obj.DatasetPath, obj.Config.target_fs);
                    scooter_analysis.reporting.PlotGenerator.spectrogram( ...
                        sig, fs, base_time, obj.Config, ...
                        fullfile(file_out_dir, 'continuous_spectrogram.png'));
                catch ME
                    fprintf('[BatchAnalyzer] Warning: Failed to generate spectrogram for %s: %s\n', filename, ME.message);
                end
            end
            
            if obj.Config.enable_video
                scooter_analysis.reporting.VideoExporter.welchDiagramSeries( ...
                    fr, obj.Config, fullfile(file_out_dir, 'welch_diagrams_series.mp4'));
            end
            
            obj.FileResults = fr;
            fprintf('Analysis completed for %s!\n', filename);
        end
        
        
        function runPerFile(obj)
            % Analyse each WAV file in the directory independently.
            
            files = scooter_analysis.io.AudioLoader.findFiles( ...
                obj.DatasetPath, obj.RecursiveSearch);
            if isempty(files); return; end
            
            obj.FileResults = scooter_analysis.results.FileResult.empty;
            
            for f_idx = 1:length(files)
                filepath = fullfile(files(f_idx).folder, files(f_idx).name);
                [~, filename, ~] = fileparts(filepath);
                
                fprintf('\n=== Processing File %d/%d: %s ===\n', ...
                    f_idx, length(files), filename);
                
                file_out_dir = fullfile(obj.OutputDir, filename);
                if ~exist(file_out_dir, 'dir'); mkdir(file_out_dir); end
                
                fr = scooter_analysis.pipeline.FileAnalyzer.analyzeFile( ...
                    filepath, obj.Config);
                
                if isempty(fr.segments); continue; end
                
                % Write report
                scooter_analysis.reporting.ReportGenerator.writeFileReport(fr, file_out_dir);
                
                % Plots
                scooter_analysis.reporting.PlotGenerator.freqBandwidthTimeSeries(fr, file_out_dir);
                
                if obj.Config.enable_video
                    scooter_analysis.reporting.VideoExporter.welchDiagramSeries( ...
                        fr, obj.Config, fullfile(file_out_dir, 'welch_diagrams_series.mp4'));
                end
                
                obj.FileResults(end+1, 1) = fr;
                fprintf('Analysis completed for %s!\n', filename);
            end
            
            % Overall summaries
            if length(obj.FileResults) > 0
                scooter_analysis.reporting.PlotGenerator.overallHistograms( ...
                    obj, fullfile(obj.OutputDir, 'overall_histograms.png'));
                scooter_analysis.reporting.PlotGenerator.ltsa( ...
                    obj, fullfile(obj.OutputDir, 'cumulative_spectrogram.png'));
            end
            if length(obj.FileResults) > 1
                fairness_dir = fullfile(obj.OutputDir, 'fairness_comparison');
                scooter_analysis.reporting.PlotGenerator.fairnessComparison(obj, fairness_dir);
            end
        end
        
        
        function runConcatenated(obj)
            % Concatenate all files into one continuous signal and analyse.
            
            [sig, fs, base_time] = scooter_analysis.io.AudioLoader.loadAndConcatenate( ...
                obj.DatasetPath, obj.Config.target_fs, obj.RecursiveSearch);
            
            if isempty(sig); return; end
            
            if ~exist(obj.OutputDir, 'dir'); mkdir(obj.OutputDir); end
            
            fr = scooter_analysis.pipeline.FileAnalyzer.analyzeSignal( ...
                sig, fs, base_time, obj.Config, ...
                'Name', obj.DatasetName, 'FilePath', obj.DatasetPath);
            
            % Write report
            scooter_analysis.reporting.ReportGenerator.writeFileReport(fr, obj.OutputDir);
            
            % Plots
            scooter_analysis.reporting.PlotGenerator.freqBandwidthTimeSeries(fr, obj.OutputDir);
            
            if obj.Config.enable_spectrogram
                try
                    scooter_analysis.reporting.PlotGenerator.spectrogram( ...
                        sig, fs, base_time, obj.Config, ...
                        fullfile(obj.OutputDir, 'continuous_spectrogram.png'));
                catch ME
                    fprintf('[BatchAnalyzer] Warning: Failed to generate continuous spectrogram: %s\n', ME.message);
                end
            end
            
            if obj.Config.enable_video
                scooter_analysis.reporting.VideoExporter.welchDiagramSeries( ...
                    fr, obj.Config, fullfile(obj.OutputDir, 'welch_diagrams_series.mp4'));
            end
            
            obj.FileResults = fr;
        end
        
        
        function runMultiDataset(obj)
            % Loop over named subdirectories, each treated as a concatenated dataset.
            
            if isempty(obj.Subdatasets)
                error('BatchAnalyzer:NoSubdatasets', ...
                    'multi_dataset mode requires Subdatasets to be specified.');
            end
            
            obj.FileResults = scooter_analysis.results.FileResult.empty;
            
            for ds_idx = 1:length(obj.Subdatasets)
                ds_name = obj.Subdatasets{ds_idx};
                target_dir = fullfile(obj.DatasetPath, ds_name);
                ds_out_dir = fullfile(obj.OutputDir, ds_name);
                
                fprintf('\n======================================================\n');
                fprintf('ANALYZING DATASET: %s\n', ds_name);
                fprintf('======================================================\n');
                
                if ~exist(ds_out_dir, 'dir'); mkdir(ds_out_dir); end
                
                [sig, fs, base_time] = scooter_analysis.io.AudioLoader.loadAndConcatenate( ...
                    target_dir, obj.Config.target_fs, obj.RecursiveSearch);
                
                if isempty(sig); continue; end
                
                fr = scooter_analysis.pipeline.FileAnalyzer.analyzeSignal( ...
                    sig, fs, base_time, obj.Config, ...
                    'Name', ds_name, 'FilePath', target_dir);
                
                % Write report
                scooter_analysis.reporting.ReportGenerator.writeFileReport(fr, ds_out_dir);
                
                % Plots
                scooter_analysis.reporting.PlotGenerator.freqBandwidthTimeSeries(fr, ds_out_dir);
                
                if obj.Config.enable_spectrogram
                    scooter_analysis.reporting.PlotGenerator.spectrogram( ...
                        sig, fs, base_time, obj.Config, ...
                        fullfile(ds_out_dir, 'continuous_spectrogram.png'));
                end
                
                if obj.Config.enable_video
                    scooter_analysis.reporting.VideoExporter.welchDiagramSeries( ...
                        fr, obj.Config, fullfile(ds_out_dir, 'welch_diagrams_series.mp4'));
                end
                
                obj.FileResults(end+1, 1) = fr;
            end
            
            if length(obj.FileResults) > 1
                fairness_dir = fullfile(obj.OutputDir, 'fairness_comparison');
                scooter_analysis.reporting.PlotGenerator.fairnessComparison(obj, fairness_dir);
            end
        end
        
    end
end
