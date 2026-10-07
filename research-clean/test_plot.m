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
