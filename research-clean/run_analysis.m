% run_analysis.m - Unified entry point for all acoustic analysis workflows.
%
% This script replaces the following 7+ scripts that previously had to be
% maintained independently:
%   analyze_dominant_freq.m, analyze_single_file.m,
%   analyze_continuous_cruise.m, analyze_croatia_datasets.m,
%   batch_analyze_directory.m, batch_analyze_croatia.m,
%   batch_analyze_haifa_bay.m, compare_histograms.m,
%   plot_high_res_spectrograms.m
%
% All functionality is now consolidated in the +scooter_analysis package.
% Select a workflow below by uncommenting the appropriate section.

clear; close all; clc;

import scooter_analysis.config.AnalysisConfig
import scooter_analysis.pipeline.BatchAnalyzer
import scooter_analysis.reporting.PlotGenerator

%% =====================================================================
%  WORKFLOW 1: Haifa Bay - Batch Per-File Analysis
%  (Replaces: batch_analyze_haifa_bay.m)
% ======================================================================
% cfg = AnalysisConfig.haifaBay();
% ba = BatchAnalyzer( ...
%     'D:\RoyStudies\Recordings\20250805_Haifa_bay_LME', cfg, ...
%     'Name', 'HaifaBay', 'Mode', 'per_file');
% ba.run();


%% =====================================================================
%  WORKFLOW 2: Croatia - Batch Per-File Analysis
%  (Replaces: batch_analyze_croatia.m)
% ======================================================================
% cfg = AnalysisConfig.croatia();
% ba = BatchAnalyzer( ...
%     'D:\RoyStudies\Recordings\Croatia\wav', cfg, ...
%     'Name', 'Croatia', 'Mode', 'per_file', 'Recursive', true);
% ba.run();


%% =====================================================================
%  WORKFLOW 3: Generic Directory - Batch Per-File Analysis
%  (Replaces: batch_analyze_directory.m)
% ======================================================================
% cfg = AnalysisConfig.directory();
% ba = BatchAnalyzer( ...
%     'D:\RoyStudies\Recordings\DepartmentalCruise-2025-06-12\icListen\wav', cfg, ...
%     'Name', 'DirectoryBatch', 'Mode', 'per_file', 'Recursive', true);
% ba.run();


%% =====================================================================
%  WORKFLOW 4: Single File Deep Analysis
%  (Replaces: analyze_single_file.m)
% ======================================================================
% cfg = AnalysisConfig.singleFileDetailed();
% cfg.enable_video = true;
% ba = BatchAnalyzer( ...
%     'D:\RoyStudies\Recordings\Croatia\wav\merged\merged_2207_colmar.wav', cfg, ...
%     'Name', 'SingleFile', 'Mode', 'single_file');
% ba.run();


%% =====================================================================
%  WORKFLOW 5: Departmental Cruise - Concatenated Continuous Analysis
%  (Replaces: analyze_continuous_cruise.m)
% ======================================================================
% cfg = AnalysisConfig.cruise();
% ba = BatchAnalyzer( ...
%     'D:\RoyStudies\Recordings\DepartmentalCruise-2025-06-12\icListen\wav', cfg, ...
%     'Name', 'Cruise', 'Mode', 'concatenated');
% ba.run();


%% =====================================================================
%  WORKFLOW 6: Croatia Multi-Dataset - Each Subdirectory Concatenated
%  (Replaces: analyze_croatia_datasets.m)
% ======================================================================
cfg = AnalysisConfig.croatiaDatasets();
ba = BatchAnalyzer( ...
    'D:\RoyStudies\Recordings\Croatia\wav\merged', cfg, ...
    'Name', 'Croatia', 'Mode', 'per_file', ...
    'Subdatasets', {'merged_2207_colmar.wav', 'merged_2307_free.wav', 'merged_2407_1_600m.wav', 'merged_2407_2_snake.wav', 'merged_2507_1_1k.wav', 'merged_2507_2_joint.wav'});
ba.run();


%% =====================================================================
%  WORKFLOW 7: Dominant Frequency Tracking
%  (Replaces: analyze_dominant_freq.m)
% ======================================================================
% cfg = AnalysisConfig.dominantFreq();
% ba = BatchAnalyzer( ...
%     'D:\RoyStudies\Recordings\Ashdod\scooter_exp\combined_scooter_perfect.wav', cfg, ...
%     'Name', 'DominantFreq', 'Mode', 'single_file');
% ba.run();


%% =====================================================================
%  WORKFLOW 8: Compare Two Datasets
%  (Replaces: compare_histograms.m)
% ======================================================================
% cfg_h = AnalysisConfig.haifaBay();
% ba_h = BatchAnalyzer('D:\RoyStudies\Recordings\20250805_Haifa_bay_LME', cfg_h, ...
%     'Name', 'HaifaBay', 'Mode', 'per_file');
% ba_h.run();
%
% cfg_c = AnalysisConfig.croatia();
% ba_c = BatchAnalyzer('D:\RoyStudies\Recordings\Croatia\wav', cfg_c, ...
%     'Name', 'Croatia', 'Mode', 'per_file', 'Recursive', true);
% ba_c.run();
%
% PlotGenerator.comparison(ba_h, ba_c, ...
%     fullfile(fileparts(mfilename('fullpath')), 'scooter_analysis', 'output', 'comparison_histograms.png'));


fprintf('Select a workflow by uncommenting the appropriate section above.\n');
