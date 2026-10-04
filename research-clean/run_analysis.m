% run_analysis.m - Unified entry point for all acoustic analysis workflows.
%
% This script replaces the following 7+ scripts that previously had to be
% maintained independently:
%   analyze_dominant_freq.m, analyze_single_file.m,
%   analyze_continuous_cruise.m, analyze_croatia_datasets.m,
%   batch_analyze_directory.m, batch_analyze_croatia.m,
%   batch_analyze_haifa_bay.m, compare_histograms.m,
%   plot_high_res_spectrograms.m,
%   bandwidth_segment_lobe_floor_watershed.m
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
% cfg = AnalysisConfig.croatiaDatasets();
% ba = BatchAnalyzer( ...
%     'D:\RoyStudies\Recordings\Croatia\wav\merged', cfg, ...
%     'Name', 'Croatia', 'Mode', 'per_file', ...
%     'Subdatasets', {'merged_2207_colmar.wav', 'merged_2307_free.wav', 'merged_2407_1_600m.wav', 'merged_2407_2_snake.wav', 'merged_2507_1_1k.wav', 'merged_2507_2_joint.wav'});
% ba.run();


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
%  WORKFLOW 8: Compare Two Datasets: Haifa Bay vs. Croatia
%  (Histograms & Fairness Comparison as in bandwidth_segment_lobe_floor_watershed.m)
% ======================================================================
cfg_h = AnalysisConfig.haifaBay();
ba_h = BatchAnalyzer('D:\RoyStudies\Recordings\20250805_Haifa_bay_LME', cfg_h, ...
    'Name', 'HaifaBay', 'Mode', 'per_file');
ba_h.run();

cfg_c = AnalysisConfig.croatia();
ba_c = BatchAnalyzer('D:\RoyStudies\Recordings\Croatia\wav\merged', cfg_c, ...
    'Name', 'Croatia', 'Mode', 'per_file');
ba_c.run();

out_base = fullfile(fileparts(mfilename('fullpath')), 'scooter_analysis', 'output');
% 1. Dominant Frequency & Bandwidth Normalised Histograms
PlotGenerator.comparison(ba_h, ba_c, ...
    fullfile(out_base, 'comparison_histograms.png'));

% 2. 4-Panel Bandwidth & Fairness Stability Comparison (Haifa Bay vs. Croatia)
%    (Figure 4: Distribution, TiB Stability, Entropy Stability, Jain's Fairness Index)
PlotGenerator.fairnessComparison({ba_h, ba_c}, ...
    fullfile(out_base, 'comparison_fairness'));


%% =====================================================================
%  WORKFLOW 9: Multi-Dataset Watershed Bandwidth & Fairness Comparison
%  (Replaces: bandwidth_segment_lobe_floor_watershed.m)
% ======================================================================
% base_dir = 'D:\RoyStudies\Recordings';
% dir_hear_my_ship = fullfile(base_dir, 'hear_my_ship', 'V1', 'Motor Boats');
% dir_haifa        = fullfile(base_dir, '20250805_Haifa_bay_LME', 'extracted');
% dir_croatia      = fullfile(base_dir, 'Croatia', 'wav', '2407_1_600m');
% dir_cruise       = fullfile(base_dir, 'DepartmentalCruise-2025-06-12', 'icListen', 'wav');
%
% datasets = struct(...
%     'name',   {'Motorboat', ...
%                'SUEX VR-X DPV', ...
%                'SEACRAFT GO! DPV'}, ...
%     'path',   {fullfile(dir_haifa, 'channelA_2025-08-07_20-44-20_02.wav'), ...
%                fullfile(dir_croatia, 'RBW6737_20250724_093800.wav'), ...
%                fullfile(dir_cruise, 'RBW6922_20250612_063100.wav')}, ...
%     'f_low',  {0,    400,  400}, ...
%     'f_high', {2000, 2000, 2000} ...
% );
%
% results = cell(length(datasets), 1);
% for k = 1:length(datasets)
%     cfg_k = AnalysisConfig();
%     cfg_k.f_low = datasets(k).f_low;
%     cfg_k.f_high = datasets(k).f_high;
%     cfg_k.segment_duration = 60.0;
%     cfg_k.prom_split_db = 5.0;
%     fr = scooter_analysis.pipeline.FileAnalyzer.analyzeFile(datasets(k).path, cfg_k);
%     results{k} = fr.getFairnessResult(datasets(k).name);
% end
%
% out_fairness = fullfile(fileparts(mfilename('fullpath')), 'output_plots');
% PlotGenerator.fairnessComparison(results, out_fairness);


fprintf('Select a workflow by uncommenting the appropriate section above.\n');
