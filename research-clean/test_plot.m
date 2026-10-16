import scooter_analysis.reporting.PlotGenerator

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
