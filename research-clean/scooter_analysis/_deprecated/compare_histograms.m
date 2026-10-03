% compare_histograms.m
clear; close all; clc;

script_dir = fileparts(mfilename('fullpath'));
haifa_dir = fullfile(script_dir, 'output', 'HaifaBay');
croatia_dir = fullfile(script_dir, 'output', 'Croatia');

fprintf('Parsing Haifa Bay data...\n');
[h_freqs, h_bws] = load_results_from_reports(haifa_dir);

fprintf('Parsing Croatia data...\n');
[c_freqs, c_bws] = load_results_from_reports(croatia_dir);

fig = figure('Name', 'Haifa vs Croatia Comparison', 'Position', [100, 100, 1200, 500], 'Color', 'w');

% Dominant Frequency Comparison
subplot(1, 2, 1);
hold on;
% Need to normalize because counts might differ between datasets
histogram(h_freqs, 'BinWidth', 50, 'Normalization', 'probability', 'FaceColor', [0.2 0.6 0.8], 'EdgeColor', 'none', 'FaceAlpha', 0.6);
histogram(c_freqs, 'BinWidth', 50, 'Normalization', 'probability', 'FaceColor', [0.8 0.3 0.3], 'EdgeColor', 'none', 'FaceAlpha', 0.6);
title('Dominant Frequency Distribution (Normalized)');
xlabel('Dominant Frequency (Hz)');
ylabel('Probability');
legend('Haifa Bay', 'Croatia');
grid on;

% Bandwidth Comparison
subplot(1, 2, 2);
hold on;
% Calculate reasonable bin edges for bandwidths
bw_edges = 0:2:max(max(h_bws), max(c_bws));
if isempty(bw_edges), bw_edges = 0:2:100; end

histogram(h_bws, bw_edges, 'Normalization', 'probability', 'FaceColor', [0.2 0.6 0.8], 'EdgeColor', 'none', 'FaceAlpha', 0.6);
histogram(c_bws, bw_edges, 'Normalization', 'probability', 'FaceColor', [0.8 0.3 0.3], 'EdgeColor', 'none', 'FaceAlpha', 0.6);
title('Bandwidth Distribution (Normalized)');
xlabel('Bandwidth (Hz)');
ylabel('Probability');
legend('Haifa Bay', 'Croatia');
grid on;

out_path = fullfile(script_dir, 'output', 'comparison_histograms.png');
exportgraphics(fig, out_path, 'Resolution', 300);
fprintf('Comparison plot saved to %s\n', out_path);

function [dom_freqs, bws] = load_results_from_reports(base_dir)
    reports = dir(fullfile(base_dir, '**', 'dominant_frequencies_report.txt'));
    dom_freqs = [];
    bws = [];
    for i = 1:length(reports)
        filepath = fullfile(reports(i).folder, reports(i).name);
        fid = fopen(filepath, 'r');
        if fid == -1
            continue;
        end
        % Skip 4 header lines then read data
        C = textscan(fid, '%f | %f | %f | %f | %f | %f', 'HeaderLines', 4);
        fclose(fid);
        if ~isempty(C) && ~isempty(C{1}) && length(C) >= 6
            dom_freqs = [dom_freqs; C{4}];
            bws = [bws; C{6}];
        end
    end
end
