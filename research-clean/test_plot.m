import scooter_analysis.reporting.PlotGenerator
import scooter_analysis.reporting.ReportGenerator
import scooter_analysis.config.AnalysisConfig
import scooter_analysis.pipeline.SegmentAnalyzer

% Create dummy data for HaifaBay (e.g. 5 hours = 300 minutes)
% With 0.5s steps, 5 hours = 300 * 60 * 2 = 36000 points
N = 36000;
res_h_roll = struct();
res_h_roll.meta.name = 'HaifaBay';
res_h_roll.window_sec = 60;
res_h_roll.t_centers = (1:N) * 0.5;
res_h_roll.tib_series = 0.5 + 0.1 * randn(1, N);
res_h_roll.ent_series = 0.8 + 0.05 * randn(1, N);
res_h_roll.fair_series = 0.9 + 0.02 * randn(1, N);

% Create dummy data for Croatia
res_c_roll = struct();
res_c_roll.meta.name = 'Croatia';
res_c_roll.window_sec = 60;
res_c_roll.t_centers = (1:N) * 0.5;
res_c_roll.tib_series = 0.4 + 0.15 * randn(1, N);
res_c_roll.ent_series = 0.7 + 0.1 * randn(1, N);
res_c_roll.fair_series = 0.85 + 0.05 * randn(1, N);

% Plot
out_base = fullfile(fileparts(mfilename('fullpath')), 'scooter_analysis', 'output');
if ~exist(out_base, 'dir')
    mkdir(out_base);
end
out_file = fullfile(out_base, 'test_rolling_fairness_60s.png');

PlotGenerator.rollingFairnessComparison({res_h_roll, res_c_roll}, out_file);
fprintf('Test plot saved to: %s\n', out_file);

out_file_deriv = fullfile(out_base, 'test_rolling_fairness_derivative_60s.png');
PlotGenerator.rollingFairnessDerivativeComparison({res_h_roll, res_c_roll}, out_file_deriv);
fprintf('Test derivative plot saved to: %s\n', out_file_deriv);

% Create synthetic instantaneous bandwidth data for HaifaBay and Croatia
% E.g., 2 hours = 7200 s = 14400 slices of 0.5s
M = 14400;
% HaifaBay: centered around 80 Hz with slow drift and noise
bws_haifa = 80 + 10 * sin((1:M)' * 2*pi / 2000) + 8 * randn(M, 1);
bws_haifa = max(10, bws_haifa);

% Croatia: centered around 140 Hz with higher variability
bws_croatia = 140 + 15 * cos((1:M)' * 2*pi / 1500) + 18 * randn(M, 1);
bws_croatia = max(10, bws_croatia);

% AUV: centered around 55 Hz
bws_auv = 55 + 8 * sin((1:M)' * 2*pi / 1800) + 12 * randn(M, 1);
bws_auv = max(10, bws_auv);

res_h_bw = struct();
res_h_bw.meta.name = 'HaifaBay';
res_h_bw.slice_bw.all_main_bws = bws_haifa;

res_c_bw = struct();
res_c_bw.meta.name = 'Croatia';
res_c_bw.slice_bw.all_main_bws = bws_croatia;

res_auv_bw = struct();
res_auv_bw.meta.name = 'AUV';
res_auv_bw.slice_bw.all_main_bws = bws_auv;

out_binned = fullfile(out_base, 'test_binned_bandwidth_60s.png');
PlotGenerator.binnedBandwidthDistribution({res_h_bw, res_c_bw, res_auv_bw}, out_binned);
fprintf('Test binned bandwidth plot saved to: %s\n', out_binned);

out_vis_dir = fullfile(out_base, 'test_vis_binned');
Visualizer.render_binned_bandwidth_distribution({res_h_bw, res_c_bw, res_auv_bw}, out_vis_dir);
fprintf('Test Visualizer binned bandwidth plots saved to: %s\n', out_vis_dir);

% =========================================================================
% Test Digital PLL Phase Lock & Instantaneous Frequency Verification Pipeline
% =========================================================================
fprintf('\n--- Running Digital PLL Phase Lock & Inst. Freq Verification Tests ---\n');
rng(42);
fs = 8000;
dur = 10.0;
t_sig = (0:1/fs:dur-1/fs)';

% 1. Test real PLL signal processing via SegmentAnalyzer on a coherent maneuvering underwater tone vs FM-smeared surface tone
f0 = 850.0;
phase_doppler = 2*pi * (740*t_sig + 8.0*sin(2*pi*0.08*t_sig));
sig_coherent = cos(phase_doppler + 0.15*sin(2*pi*1.2*t_sig)) + 0.20*randn(size(t_sig));
sig_smeared  = cos(2*pi*180*t_sig + 4.5*sin(2*pi*2.2*t_sig) + 2.5*cos(2*pi*5.5*t_sig)) .* (1 + 0.5*randn(size(t_sig))) + 0.45*randn(size(t_sig));

cfg_u = AnalysisConfig.croatia();
cfg_s = AnalysisConfig.haifaBay();
seg_coh = SegmentAnalyzer.analyze(sig_coherent, fs, 0.0, dur, cfg_u, cfg_u.toBandwidthConfig());
seg_smr = SegmentAnalyzer.analyze(sig_smeared, fs, 0.0, dur, cfg_s, cfg_s.toBandwidthConfig());

fprintf('Underwater Maneuvering Scooter -> Watershed BW: %.1f Hz | Mean PLV R = %.3f | PLL Freq Spread SD = %.2f Hz | Verif Err = %.2f Hz\n', ...
    seg_coh.mean_bw, seg_coh.pll_mean_plv, seg_coh.pll_freq_std, seg_coh.pll_freq_verif_err);
fprintf('Surface Vessel (Cavitation/FM) -> Watershed BW: %.1f Hz | Mean PLV R = %.3f | PLL Freq Spread SD = %.2f Hz | Verif Err = %.2f Hz\n', ...
    seg_smr.mean_bw, seg_smr.pll_mean_plv, seg_smr.pll_freq_std, seg_smr.pll_freq_verif_err);

% 2. Test multi-hour synthetic PLL slice series for HaifaBay, Croatia, and AUV
res_h_bw.pll_result = struct();
res_h_bw.pll_result.all_slice_plv = min(0.99, max(0.05, 0.78 + 0.06*sin((1:M)'*2*pi/1800) + 0.07*randn(M, 1)));
res_h_bw.pll_result.all_slice_mean_phases = mod(0.25*randn(M, 1) + pi, 2*pi) - pi;
res_h_bw.pll_result.all_slice_phase_stds = max(0.05, 0.65 + 0.12*randn(M, 1));
res_h_bw.pll_result.all_slice_inst_freqs = 780 + 4*sin((1:M)'*2*pi/2400) + 2.5*randn(M, 1);
res_h_bw.pll_result.all_slice_inst_freq_stds = max(0.5, 4.2 + 0.8*sin((1:M)'*2*pi/2000) + 1.1*randn(M, 1));
res_h_bw.pll_result.all_slice_freq_verif_errs = abs(1.8 + 0.9*randn(M, 1));
res_h_bw.pll_result.phase_samples = mod(0.45*randn(20000, 1) + pi, 2*pi) - pi;
[res_h_bw.pll_result.fairness_window_sec, res_h_bw.pll_result.all_plv_stability, ...
 res_h_bw.pll_result.all_phase_entropy, res_h_bw.pll_result.all_freq_lock_fairness] = ...
    BandwidthTracker.compute_phase_stability_vs_window( ...
        res_h_bw.pll_result.all_slice_plv, res_h_bw.pll_result.all_slice_mean_phases, ...
        res_h_bw.pll_result.all_slice_inst_freq_stds, 0.500, M*0.5, 5.0);

res_c_bw.pll_result = struct();
res_c_bw.pll_result.all_slice_plv = min(0.99, max(0.05, 0.46 + 0.09*cos((1:M)'*2*pi/1500) + 0.11*randn(M, 1)));
res_c_bw.pll_result.all_slice_mean_phases = mod(1.15*randn(M, 1) + pi, 2*pi) - pi;
res_c_bw.pll_result.all_slice_phase_stds = max(0.10, 1.25 + 0.20*randn(M, 1));
res_c_bw.pll_result.all_slice_inst_freqs = 920 + 12*cos((1:M)'*2*pi/1500) + 6.5*randn(M, 1);
res_c_bw.pll_result.all_slice_inst_freq_stds = max(1.0, 11.5 + 2.2*cos((1:M)'*2*pi/1500) + 2.6*randn(M, 1));
res_c_bw.pll_result.all_slice_freq_verif_errs = abs(4.9 + 2.1*randn(M, 1));
res_c_bw.pll_result.phase_samples = mod(1.30*randn(20000, 1) + pi, 2*pi) - pi;
[res_c_bw.pll_result.fairness_window_sec, res_c_bw.pll_result.all_plv_stability, ...
 res_c_bw.pll_result.all_phase_entropy, res_c_bw.pll_result.all_freq_lock_fairness] = ...
    BandwidthTracker.compute_phase_stability_vs_window( ...
        res_c_bw.pll_result.all_slice_plv, res_c_bw.pll_result.all_slice_mean_phases, ...
        res_c_bw.pll_result.all_slice_inst_freq_stds, 0.500, M*0.5, 5.0);

res_auv_bw.pll_result = struct();
res_auv_bw.pll_result.all_slice_plv = min(0.99, max(0.05, 0.86 + 0.04*sin((1:M)'*2*pi/2200) + 0.05*randn(M, 1)));
res_auv_bw.pll_result.all_slice_mean_phases = mod(0.18*randn(M, 1) + pi, 2*pi) - pi;
res_auv_bw.pll_result.all_slice_phase_stds = max(0.05, 0.48 + 0.08*randn(M, 1));
res_auv_bw.pll_result.all_slice_inst_freqs = 1150 + 2.5*sin((1:M)'*2*pi/2100) + 1.5*randn(M, 1);
res_auv_bw.pll_result.all_slice_inst_freq_stds = max(0.3, 2.8 + 0.5*sin((1:M)'*2*pi/1800) + 0.7*randn(M, 1));
res_auv_bw.pll_result.all_slice_freq_verif_errs = abs(1.1 + 0.5*randn(M, 1));
res_auv_bw.pll_result.phase_samples = mod(0.30*randn(20000, 1) + pi, 2*pi) - pi;
[res_auv_bw.pll_result.fairness_window_sec, res_auv_bw.pll_result.all_plv_stability, ...
 res_auv_bw.pll_result.all_phase_entropy, res_auv_bw.pll_result.all_freq_lock_fairness] = ...
    BandwidthTracker.compute_phase_stability_vs_window( ...
        res_auv_bw.pll_result.all_slice_plv, res_auv_bw.pll_result.all_slice_mean_phases, ...
        res_auv_bw.pll_result.all_slice_inst_freq_stds, 0.500, M*0.5, 5.0);

out_pll_roll = fullfile(out_base, 'test_rolling_phase_lock_60s.png');
PlotGenerator.rollingPhaseLockComparison({res_h_bw, res_c_bw, res_auv_bw}, out_pll_roll);
fprintf('Test rolling phase lock plot saved to: %s\n', out_pll_roll);

out_pll_deriv = fullfile(out_base, 'test_rolling_phase_lock_derivative_60s.png');
PlotGenerator.rollingPhaseLockDerivativeComparison({res_h_bw, res_c_bw, res_auv_bw}, out_pll_deriv);
fprintf('Test rolling phase lock derivative plot saved to: %s\n', out_pll_deriv);

out_pll_binned = fullfile(out_base, 'test_binned_phase_lock_60s.png');
PlotGenerator.binnedPhaseLockDistribution({res_h_bw, res_c_bw, res_auv_bw}, out_pll_binned);
fprintf('Test binned phase lock plot saved to: %s\n', out_pll_binned);

out_verif_binned = fullfile(out_base, 'test_binned_inst_freq_spread_60s.png');
PlotGenerator.binnedInstFreqVerification({res_h_bw, res_c_bw, res_auv_bw}, out_verif_binned);
fprintf('Test binned inst freq verification plot saved to: %s\n', out_verif_binned);

out_pll_4panel = fullfile(out_base, 'test_phase_lock_4panel');
PlotGenerator.phaseLockComparison({res_h_bw, res_c_bw, res_auv_bw}, out_pll_4panel);
fprintf('Test 4-panel phase lock plot saved to: %s\n', out_pll_4panel);

out_pll_report = fullfile(out_base, 'test_phase_lock_verification_statistics.txt');
ReportGenerator.writePhaseLockComparisonReport({res_h_bw, res_c_bw, res_auv_bw}, out_pll_report, 60);
fprintf('Test phase lock statistical report saved to: %s\n', out_pll_report);
