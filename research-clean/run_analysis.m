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

% base_dir = 'C:\Users\Roy\Recordings';
base_dir = 'D:\RoyStudies\Recordings';

%% =====================================================================
%  WORKFLOW 1: Haifa Bay - Batch Per-File Analysis
%  (Replaces: batch_analyze_haifa_bay.m)
% ======================================================================
cfg = AnalysisConfig.haifaBay();
ba = BatchAnalyzer( ...
    fullfile(base_dir, '20250805_Haifa_bay_LME/extracted-2'), cfg, ...
    'Name', 'HaifaBay', 'Mode', 'concatenated');
ba.run();

out_base = fullfile(fileparts(mfilename('fullpath')), 'scooter_analysis', 'output');
% 1. Dominant Frequency & Bandwidth Normalised Histograms (Leg1 vs Leg2)
PlotGenerator.comparison(ba, ...
    fullfile(out_base, 'haifa_bay_histograms.png'));

% 2. Overall Dominant Frequency & Bandwidth Histograms
PlotGenerator.overallHistograms(ba, ...
    fullfile(out_base, 'haifa_bay_overall_histograms.png'));

% 3. 4-Panel Bandwidth & Fairness Stability Comparison (Leg1 vs Leg2)
%    (Figure 4: Distribution, TiB Stability, Entropy Stability, Jain's Fairness Index)
PlotGenerator.fairnessComparison(ba, ...
    fullfile(out_base, 'haifa_bay_fairness'));

% 4. Jain's Fairness Index Distribution Histogram (5s Rolling Window)
PlotGenerator.fairnessHistograms(ba, ...
    fullfile(out_base, 'haifa_bay_fairness_histograms.png'), 5);

% 5. Dominant Frequency Peak Plot (Figure 6: Welch PSD & Dominant Frequency)
PlotGenerator.dominantFrequency({ba}, ...
    fullfile(out_base, 'haifa_bay_dominant_frequency'));

% 6. Dominant Frequency Watershed Bandwidth (Figure 2: 250ms Center Slice)
PlotGenerator.dominantWatershed({ba}, ...
    fullfile(out_base, 'haifa_bay_watershed_bandwidth'));

% 7. Macro-Lobe Watershed Segmentation (Figure 1: Macro-Lobes & Noise Floor)
PlotGenerator.macroLobeWatershed({ba}, ...
    fullfile(out_base, 'haifa_bay_macro_lobes'));


return

%% =====================================================================
%  WORKFLOW 2: Croatia - Batch Per-File Analysis
%  (Replaces: batch_analyze_croatia.m)
% ======================================================================
% cfg = AnalysisConfig.croatia();
% ba = BatchAnalyzer( ...
%     fullfile(base_dir, 'Croatia\wav'), cfg, ...
%     'Name', 'Croatia', 'Mode', 'per_file', 'Recursive', true);
% ba.run();


%% =====================================================================
%  WORKFLOW 3: Generic Directory - Batch Per-File Analysis
%  (Replaces: batch_analyze_directory.m)
% ======================================================================
% cfg = AnalysisConfig.directory();
% ba = BatchAnalyzer( ...
%     fullfile(base_dir, 'DepartmentalCruise-2025-06-12\icListen\wav'), cfg, ...
%     'Name', 'DirectoryBatch', 'Mode', 'per_file', 'Recursive', true);
% ba.run();


%% =====================================================================
%  WORKFLOW 4: Single File Deep Analysis
%  (Replaces: analyze_single_file.m)
% ======================================================================
% cfg = AnalysisConfig.singleFileDetailed();
% cfg.enable_video = true;
% ba = BatchAnalyzer( ...
%     fullfile(base_dir, 'Croatia\wav\merged\merged_2207_colmar.wav'), cfg, ...
%     'Name', 'SingleFile', 'Mode', 'single_file');
% ba.run();


%% =====================================================================
%  WORKFLOW 5: Departmental Cruise - Concatenated Continuous Analysis
%  (Replaces: analyze_continuous_cruise.m)
% ======================================================================
% cfg = AnalysisConfig.cruise();
% ba = BatchAnalyzer( ...
%     fullfile(base_dir, 'DepartmentalCruise-2025-06-12\icListen\wav'), cfg, ...
%     'Name', 'Cruise', 'Mode', 'concatenated');
% ba.run();


%% =====================================================================
%  WORKFLOW 6: Croatia Multi-Dataset - Each Subdirectory Concatenated
%  (Replaces: analyze_croatia_datasets.m)
% ======================================================================
% cfg = AnalysisConfig.croatiaDatasets();
% ba = BatchAnalyzer( ...
%     fullfile(base_dir, 'Croatia\wav\merged'), cfg, ...
%     'Name', 'Croatia', 'Mode', 'per_file', ...
%     'Subdatasets', {'merged_2207_colmar.wav', 'merged_2307_free.wav', 'merged_2407_1_600m.wav', 'merged_2407_2_snake.wav', 'merged_2507_1_1k.wav', 'merged_2507_2_joint.wav'});
% ba.run();

%% =====================================================================
%  WORKFLOW 6: AUV
% ======================================================================
cfg = AnalysisConfig.auv();
ba_auv = BatchAnalyzer( ...
    fullfile(base_dir, 'AUVExp_1_26'), cfg, ...
    'Name', 'AUV', 'Mode', 'concatenated', 'Recursive', true);
ba_auv.run();

out_base = fullfile(fileparts(mfilename('fullpath')), 'scooter_analysis', 'output');
% 1. Dominant Frequency & Bandwidth Normalised Histograms (Leg1 vs Leg2)
PlotGenerator.comparison(ba_auv, ...
    fullfile(out_base, 'comparison_histograms.png'));

% 2. Overall Dominant Frequency & Bandwidth Histograms
PlotGenerator.overallHistograms(ba_auv, ...
    fullfile(out_base, 'AUV', 'overall_histograms.png'));

% 3. 4-Panel Bandwidth & Fairness Stability Comparison (Leg1 vs Leg2)
%    (Figure 4: Distribution, TiB Stability, Entropy Stability, Jain's Fairness Index)
PlotGenerator.fairnessComparison(ba_auv, ...
    fullfile(out_base, 'comparison_fairness'));

% 4. Jain's Fairness Index Distribution Histogram (5s Rolling Window)
PlotGenerator.fairnessHistograms(ba_auv, ...
    fullfile(out_base, 'comparison_fairness_histograms.png'), 5);

% 5. Dominant Frequency Peak Plot (Figure 6: Welch PSD & Dominant Frequency)
PlotGenerator.dominantFrequency({ba_auv}, ...
    fullfile(out_base, 'comparison_dominant_frequency'));

% 6. Dominant Frequency Watershed Bandwidth (Figure 2: 250ms Center Slice)
PlotGenerator.dominantWatershed({ba_auv}, ...
    fullfile(out_base, 'comparison_watershed_bandwidth'));

% 7. Macro-Lobe Watershed Segmentation (Figure 1: Macro-Lobes & Noise Floor)
PlotGenerator.macroLobeWatershed({ba_auv}, ...
    fullfile(out_base, 'comparison_macro_lobes'));


%% =====================================================================
%  WORKFLOW 7: Dominant Frequency Tracking
%  (Replaces: analyze_dominant_freq.m)
% ======================================================================
% cfg = AnalysisConfig.dominantFreq();
% ba = BatchAnalyzer( ...
%     fullfile(base_dir, 'Ashdod\scooter_exp\combined_scooter_perfect.wav'), cfg, ...
%     'Name', 'DominantFreq', 'Mode', 'single_file');
% ba.run();


%% =====================================================================
%  WORKFLOW 8: Compare Two Datasets: Haifa Bay vs. Croatia
%  (Histograms & Fairness Comparison as in bandwidth_segment_lobe_floor_watershed.m)
% ======================================================================
% cfg_h = AnalysisConfig.haifaBay();
% cfg_h.segment_duration = 30;
% cfg_h.step_duration = 30;
% ba_h = BatchAnalyzer(fullfile(base_dir, '20250805_Haifa_bay_LME'), cfg_h, ...
%     'Name', 'HaifaBay', 'Mode', 'per_file');
% ba_h.run();

% cfg_c = AnalysisConfig.croatia();
% cfg_c.segment_duration = 30;
% cfg_c.step_duration = 30;
% ba_c = BatchAnalyzer(fullfile(base_dir, 'Croatia\wav\merged'), cfg_c, ...
%     'Name', 'Croatia', 'Mode', 'per_file');
% ba_c.run();

% out_base = fullfile(fileparts(mfilename('fullpath')), 'scooter_analysis', 'output');
% % 1. Dominant Frequency & Bandwidth Normalised Histograms
% PlotGenerator.comparison(ba_h, ba_c, ...
%     fullfile(out_base, 'comparison_histograms.png'));

% % 2. 4-Panel Bandwidth & Fairness Stability Comparison (Haifa Bay vs. Croatia)
% %    (Figure 4: Distribution, TiB Stability, Entropy Stability, Jain's Fairness Index)
% PlotGenerator.fairnessComparison({ba_h, ba_c}, ...
%     fullfile(out_base, 'comparison_fairness'));

% % 3. Dominant Frequency Peak Plot (Figure 6: Welch PSD & Dominant Frequency)
% PlotGenerator.dominantFrequency({ba_h, ba_c}, ...
%     fullfile(out_base, 'comparison_dominant_frequency'));

% % 4. Dominant Frequency Watershed Bandwidth (Figure 2: 250ms Center Slice)
% PlotGenerator.dominantWatershed({ba_h, ba_c}, ...
%     fullfile(out_base, 'comparison_watershed_bandwidth'));

% % 5. Macro-Lobe Watershed Segmentation (Figure 1: Macro-Lobes & Noise Floor)
% PlotGenerator.macroLobeWatershed({ba_h, ba_c}, ...
%     fullfile(out_base, 'comparison_macro_lobes'));

% % 6. Generate All Diagnostic Plots & Summary at Once:
% % PlotGenerator.allWatershedPlots({ba_h, ba_c}, fullfile(out_base, 'comparison_all'));

% % 7. 20-Second Window Fairness Comparison (Custom Output)
% res_h_20 = ba_h.getFairnessResult(20);
% res_c_20 = ba_c.getFairnessResult(20);
% PlotGenerator.fairnessComparison({res_h_20, res_c_20}, ...
%     fullfile(out_base, 'comparison_fairness_20s'));


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
%     results{k} = fr.getVisualizerResult(datasets(k).name);
% end
%
% out_plots = fullfile(fileparts(mfilename('fullpath')), 'output_plots');
% % Diagnostic plots matching bandwidth_segment_lobe_floor_watershed.m:
% PlotGenerator.dominantFrequency(results, out_plots);
% PlotGenerator.dominantWatershed(results, out_plots);
% PlotGenerator.macroLobeWatershed(results, out_plots);
% PlotGenerator.fairnessComparison(results, out_plots);
% % Or all at once:
% % PlotGenerator.allWatershedPlots(results, out_plots);


% fprintf('Select a workflow by uncommenting the appropriate section above.\n');
