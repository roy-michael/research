classdef PlotGenerator
    % PlotGenerator - Static plotting and export methods for analysis results.
    %
    % All methods are static so they can be called without instantiation.
    % Every figure is created invisible and closed after export to prevent
    % GUI exhaustion during large batch runs.
    %
    % Usage:
    %   scooter_analysis.reporting.PlotGenerator.freqBandwidthTimeSeries(fr, out_dir);
    %   scooter_analysis.reporting.PlotGenerator.overallHistograms(analyzer, out_path);
    %   scooter_analysis.reporting.PlotGenerator.ltsa(analyzer, out_path);
    %   scooter_analysis.reporting.PlotGenerator.spectrogram(sig, fs, base_time, cfg, out_path);
    %   scooter_analysis.reporting.PlotGenerator.comparison(analyzerA, analyzerB, out_path);
    %   scooter_analysis.reporting.PlotGenerator.fairnessComparison(analyzers, out_dir);
    %   scooter_analysis.reporting.PlotGenerator.fairnessHistograms(analyzers, out_path);
    %   scooter_analysis.reporting.PlotGenerator.dominantFrequency(analyzers, out_dir);
    %   scooter_analysis.reporting.PlotGenerator.dominantWatershed(analyzers, out_dir);
    %   scooter_analysis.reporting.PlotGenerator.macroLobeWatershed(analyzers, out_dir);
    %   scooter_analysis.reporting.PlotGenerator.allWatershedPlots(analyzers, out_dir);

    methods (Static)

        % =================================================================
        % Unified Design System: Palette, Color Assignment & Styling
        % =================================================================

        function colors = getPalette()
            % Canonical High-Contrast Luminous Dark-Theme Palette:
            % 1. Electric Sky Blue: [0.28, 0.75, 1.00] (HaifaBay / Primary)
            % 2. Neon Coral:        [1.00, 0.42, 0.42] (Croatia / Secondary)
            % 3. Vibrant Mint:      [0.22, 0.88, 0.55] (AUV / Tertiary)
            % 4. Bright Amber:      [1.00, 0.75, 0.25] (Cruise / Quaternary)
            % 5. Neon Amethyst:     [0.76, 0.52, 1.00] (Quinary)
            % 6. Aqua Teal:         [0.20, 0.88, 0.88] (Senary)
            colors = [
                0.28 0.75 1.00;
                1.00 0.42 0.42;
                0.22 0.88 0.55;
                1.00 0.75 0.25;
                0.76 0.52 1.00;
                0.20 0.88 0.88
                ];
        end

        function [c, ec] = getDatasetColor(name, index)
            % Resolves a consistent color and edge color for a dataset by name or index.
            palette = scooter_analysis.reporting.PlotGenerator.getPalette();
            if nargin < 2 || isempty(index); index = 1; end

            c = [];
            if nargin >= 1 && ~isempty(name)
                lower_name = lower(string(name));
                if contains(lower_name, "haifa")
                    c = palette(1, :);
                elseif contains(lower_name, "croatia") || contains(lower_name, "suex")
                    c = palette(2, :);
                elseif contains(lower_name, "auv") || contains(lower_name, "seacraft")
                    c = palette(3, :);
                elseif contains(lower_name, "cruise") || contains(lower_name, "motorboat")
                    c = palette(4, :);
                end
            end
            if isempty(c)
                c = palette(mod(index - 1, size(palette, 1)) + 1, :);
            end
            ec = min(1.0, c * 1.15); % Luminous edge highlighting on dark background
        end

        function applyAxesStyle(ax, title_str, x_label, y_label)
            % Applies unified dark-theme styling to an axis.
            c_ax   = [0.10 0.13 0.20];
            c_text = [0.88 0.91 0.96];
            c_grid = [0.22 0.27 0.36];

            set(ax, 'Color', c_ax, ...
                'XColor', c_text, 'YColor', c_text, ...
                'GridColor', c_grid, 'GridAlpha', 0.50, ...
                'LineWidth', 1.0, 'FontSize', 9);
            grid(ax, 'on');
            box(ax, 'on');
            if nargin >= 2 && ~isempty(title_str)
                title(ax, title_str, 'FontSize', 11, 'FontWeight', 'bold', 'Color', [0.96 0.98 1.00]);
            end
            if nargin >= 3 && ~isempty(x_label)
                xlabel(ax, x_label, 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
            end
            if nargin >= 4 && ~isempty(y_label)
                ylabel(ax, y_label, 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
            end
        end

        function styleLegend(lgd)
            % Applies unified dark-theme styling to a legend.
            if isempty(lgd) || ~isvalid(lgd); return; end
            set(lgd, 'Location', 'best', 'FontSize', 8.5, ...
                'TextColor', [0.92 0.94 0.98], 'Color', [0.12 0.16 0.24], ...
                'EdgeColor', [0.26 0.32 0.42], 'Interpreter', 'none');
        end

        function freqBandwidthTimeSeries(fr, out_dir)
            % Plot dominant frequency and bandwidth over time for one file.
            %
            % Args:
            %   fr      - A scooter_analysis.results.FileResult object
            %   out_dir - Directory to save the plot

            if isempty(fr.dom_freqs)
                return;
            end

            palette = scooter_analysis.reporting.PlotGenerator.getPalette();
            fig = figure('Name', 'Freq & BW Over Time', ...
                'Position', [50, 100, 1800, 500], 'Color', [0.08 0.11 0.17], 'Visible', 'off');

            ax = gca;
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax, ...
                sprintf('Signal Tracking – %s', fr.filename), 'Time (UTC)');

            yyaxis left
            plot(fr.time_centers_abs, fr.dom_freqs, '.', 'MarkerSize', 8, 'Color', palette(1, :));
            ylabel('Dominant Frequency (Hz)', 'FontSize', 10, 'FontWeight', 'bold');
            ax.YColor = palette(1, :);

            yyaxis right
            plot(fr.time_centers_abs, fr.bw_vals, '-', 'LineWidth', 1.5, 'Color', palette(4, :));
            ylabel('Bandwidth (Hz)', 'FontSize', 10, 'FontWeight', 'bold');
            ylim([0, max(max(fr.bw_vals)*1.2, 50)]);
            ax.YColor = palette(4, :);

            datetick('x', 'HH:MM', 'keepticks', 'keeplimits');

            plot_path = fullfile(out_dir, 'continuous_freq_bw_plot.png');
            scooter_analysis.reporting.PlotGenerator.safeExport(fig, plot_path);
        end


        function overallHistograms(analyzer, out_path)
            % Plot two side-by-side histograms: dominant frequency and bandwidth.
            %
            % Args:
            %   analyzer - A BatchAnalyzer that has been run()
            %   out_path - Output image path

            all_freqs = analyzer.getAllDomFreqs();
            all_bws = analyzer.getAllBandwidths();

            if isempty(all_freqs) && isempty(all_bws)
                fprintf('[PlotGenerator] No frequency/bandwidth data available for overallHistograms.\n');
                return;
            end

            [c, ec] = scooter_analysis.reporting.PlotGenerator.getDatasetColor(analyzer.DatasetName, 1);

            fig = figure('Name', 'Overall Distributions', ...
                'Position', [100, 100, 1200, 500], 'Color', [0.08 0.11 0.17], 'Visible', 'off');

            ax1 = subplot(1, 2, 1);
            histogram(ax1, all_freqs, 'BinWidth', 50, 'FaceColor', c, 'EdgeColor', ec, 'FaceAlpha', 0.65);
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax1, ...
                sprintf('Dominant Frequency Distribution (%s)', analyzer.DatasetName), ...
                'Dominant Frequency (Hz)', 'Count');

            ax2 = subplot(1, 2, 2);
            histogram(ax2, all_bws, 20, 'FaceColor', c, 'EdgeColor', ec, 'FaceAlpha', 0.65);
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax2, ...
                sprintf('Bandwidth Distribution (%s)', analyzer.DatasetName), ...
                'Bandwidth (Hz)', 'Count');

            scooter_analysis.reporting.PlotGenerator.safeExport(fig, out_path);
        end


        function ltsa(analyzer, out_path)
            % Plot a Long-Term Spectral Average (LTSA / cumulative spectrogram).
            %
            % Args:
            %   analyzer - A BatchAnalyzer that has been run()
            %   out_path - Output image path

            [psd_matrix, times, f_grid] = analyzer.getLTSAData();
            if isempty(psd_matrix)
                fprintf('[PlotGenerator] No PSD data available for LTSA.\n');
                return;
            end

            fig = figure('Name', 'Cumulative Spectrogram', ...
                'Position', [50, 50, 1800, 600], 'Color', [0.08 0.11 0.17], 'Visible', 'off');

            % Median-subtract to highlight transient events
            median_profile = median(psd_matrix, 2);
            ltsa_clean = bsxfun(@minus, psd_matrix, median_profile);
            ltsa_clean(ltsa_clean < 0) = 0;
            p_max = prctile(ltsa_clean(:), 99.5);

            imagesc(times, f_grid, ltsa_clean);
            axis xy;
            if exist('clim', 'builtin') || exist('clim', 'file')
                clim([0, max(p_max, 1)]);
            else
                caxis([0, max(p_max, 1)]);
            end
            colormap turbo;
            c = colorbar;
            c.Color = [0.88 0.91 0.96];
            c.Label.String = 'Relative Power (dB)';
            c.Label.Color = [0.88 0.91 0.96];
            datetick('x', 'mm-dd HH:MM', 'keepticks', 'keeplimits');
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(gca, ...
                sprintf('Long-Term Spectrogram – %s', analyzer.DatasetName), ...
                'Time (UTC)', 'Frequency (Hz)');

            scooter_analysis.reporting.PlotGenerator.safeExport(fig, out_path);
        end


        function spectrogram(sig, fs, base_time, cfg, out_path)
            % Plot a high-resolution spectrogram for a single signal.
            %
            % Args:
            %   sig       - Audio signal vector
            %   fs        - Sampling rate (Hz)
            %   base_time - datetime of recording start
            %   cfg       - scooter_analysis.config.AnalysisConfig
            %   out_path  - Output image path

            % Target max time slices to prevent out-of-memory on multi-hour recordings
            max_time_slices = 3600;

            window_dur = cfg.window_dur_sec;
            overlap_ratio = cfg.overlap_ratio;

            % If the requested window and overlap would produce too many columns,
            % scale window/step appropriately
            est_cols = ceil(length(sig) / (fs * window_dur * max(0.01, 1 - overlap_ratio)));
            if est_cols > max_time_slices
                target_step_sec = (length(sig) / fs) / max_time_slices;
                window_dur = max(cfg.window_dur_sec, target_step_sec);
                overlap_ratio = max(0, 1 - (target_step_sec / window_dur));
            end

            window = round(fs * window_dur);
            noverlap = min(window - 1, round(window * overlap_ratio));

            if cfg.nfft == 0
                nfft = min(4096, 2^nextpow2(window));
            else
                nfft = cfg.nfft;
            end

            [~, f_spec, t_spec, p_spec] = spectrogram(sig, ...
                hamming(window), noverlap, nfft, fs);

            f_mask = (f_spec >= cfg.f_low) & (f_spec <= cfg.f_high);
            f_band = f_spec(f_mask);
            p_band = p_spec(f_mask, :);
            p_db = 10 * log10(p_band + eps);

            % Transient removal
            if cfg.remove_transients
                p_db = medfilt1(p_db, cfg.transient_filter_width, [], 2);
            end

            % Median subtract
            median_profile = median(p_db, 2);
            p_db_clean = bsxfun(@minus, p_db, median_profile);
            p_db_clean(p_db_clean < 0) = 0;

            p_max = prctile(p_db_clean(:), cfg.prctile_clip);
            if p_max <= 0; p_max = 1; end

            t_absolute = datenum(base_time + seconds(t_spec));

            fig = figure('Name', 'Continuous Spectrogram', ...
                'Position', [50, 50, 1800, 600], 'Color', [0.08 0.11 0.17], 'Visible', 'off');
            imagesc(t_absolute, f_band, p_db_clean);
            axis xy;
            if exist('clim', 'builtin') || exist('clim', 'file')
                clim([0, p_max]);
            else
                caxis([0, p_max]);
            end
            colormap turbo;
            ylim([cfg.f_low, cfg.f_high]);
            c = colorbar;
            c.Color = [0.88 0.91 0.96];
            c.Label.String = 'Relative Power (dB above median)';
            c.Label.Color = [0.88 0.91 0.96];
            datetick('x', 'HH:MM', 'keepticks', 'keeplimits');
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(gca, ...
                sprintf('Spectrogram (Start: %s UTC)', datestr(base_time, 'yyyy-mm-dd HH:MM:SS')), ...
                'Time (UTC)', 'Frequency (Hz)');

            scooter_analysis.reporting.PlotGenerator.safeExport(fig, out_path);
        end


        function comparison(varargin)
            % Plot overlaid normalised histograms comparing two datasets or files.
            %
            % Usage:
            %   PlotGenerator.comparison(analyzerA, analyzerB, out_path)
            %   PlotGenerator.comparison(fileResA, fileResB, out_path)
            %   PlotGenerator.comparison(analyzerWithMultipleFiles, out_path)

            if isempty(varargin)
                return;
            end

            out_path = varargin{end};
            items = varargin(1:end-1);

            if length(items) == 1 && iscell(items{1})
                items = items{1};
            end

            if length(items) == 1 && isa(items{1}, 'scooter_analysis.pipeline.BatchAnalyzer') && length(items{1}.FileResults) >= 2
                itemA = items{1}.FileResults(1);
                itemB = items{1}.FileResults(2);
            elseif length(items) >= 2
                itemA = items{1};
                itemB = items{2};
            else
                fprintf('[PlotGenerator] comparison requires 2 datasets or a dataset with >= 2 files.\n');
                return;
            end

            [a_freqs, a_bws, nameA] = scooter_analysis.reporting.PlotGenerator.extractHistogramData(itemA);
            [b_freqs, b_bws, nameB] = scooter_analysis.reporting.PlotGenerator.extractHistogramData(itemB);

            [cA, ecA] = scooter_analysis.reporting.PlotGenerator.getDatasetColor(nameA, 1);
            [cB, ecB] = scooter_analysis.reporting.PlotGenerator.getDatasetColor(nameB, 2);

            fig = figure('Name', 'Dataset Comparison', ...
                'Position', [100, 100, 1200, 500], 'Color', [0.08 0.11 0.17], 'Visible', 'off');

            % Dominant Frequency
            ax1 = subplot(1, 2, 1);
            hold(ax1, 'on');
            histogram(ax1, a_freqs, 'BinWidth', 50, 'Normalization', 'probability', ...
                'FaceColor', cA, 'EdgeColor', ecA, 'FaceAlpha', 0.60, 'LineWidth', 0.8);
            histogram(ax1, b_freqs, 'BinWidth', 50, 'Normalization', 'probability', ...
                'FaceColor', cB, 'EdgeColor', ecB, 'FaceAlpha', 0.60, 'LineWidth', 0.8);
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax1, ...
                'Dominant Frequency (Normalised)', 'Dominant Frequency (Hz)', 'Probability');
            lgd1 = legend(ax1, nameA, nameB);
            scooter_analysis.reporting.PlotGenerator.styleLegend(lgd1);

            % Bandwidth
            ax2 = subplot(1, 2, 2);
            hold(ax2, 'on');
            valid_a_bws = a_bws(isfinite(a_bws) & a_bws > 0);
            valid_b_bws = b_bws(isfinite(b_bws) & b_bws > 0);
            bw_max = max([valid_a_bws(:); valid_b_bws(:); 50]);
            bw_edges = 0:2:bw_max;
            if isempty(bw_edges); bw_edges = 0:2:100; end
            histogram(ax2, valid_a_bws, bw_edges, 'Normalization', 'probability', ...
                'FaceColor', cA, 'EdgeColor', ecA, 'FaceAlpha', 0.60, 'LineWidth', 0.8);
            histogram(ax2, valid_b_bws, bw_edges, 'Normalization', 'probability', ...
                'FaceColor', cB, 'EdgeColor', ecB, 'FaceAlpha', 0.60, 'LineWidth', 0.8);
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax2, ...
                'Bandwidth (Normalised)', 'Bandwidth (Hz)', 'Probability');
            lgd2 = legend(ax2, nameA, nameB);
            scooter_analysis.reporting.PlotGenerator.styleLegend(lgd2);

            scooter_analysis.reporting.PlotGenerator.safeExport(fig, out_path);
        end


        function fairnessComparison(varargin)
            % fairnessComparison - Plot and export 4-panel bandwidth & fairness stability comparison.
            %
            % Generates (Figure 4):
            %   1. Bandwidth Distribution Comparison (KDE)
            %   2. Mean Time-in-Band (TiB) Stability
            %   3. Entropy Stability (1 - H_norm)
            %   4. Jain's Fairness Index vs Window Size
            %
            % Usage:
            %   PlotGenerator.fairnessComparison(analyzer)
            %   PlotGenerator.fairnessComparison(analyzer, out_dir)
            %   PlotGenerator.fairnessComparison(analyzerA, analyzerB, out_dir)
            %   PlotGenerator.fairnessComparison({analyzerA, analyzerB}, out_dir)

            [results, out_dir] = scooter_analysis.reporting.PlotGenerator.parseVisualizerInputs(varargin{:});
            if isempty(results)
                return;
            end

            cfg_vis = struct('output_dir', out_dir);
            Visualizer.render_bandwidth_distribution(results, cfg_vis);
        end

        function fairnessDerivativeVsWindow(varargin)
            % fairnessDerivativeVsWindow - Plot derivative of stability metrics with respect
            % to window size N (d(TiB)/dN, d(1-H)/dN, d(J)/dN).
            [results, out_path] = scooter_analysis.reporting.PlotGenerator.parseVisualizerInputs(varargin{:});
            if isempty(results)
                return;
            end

            fig = figure('Name', 'Fairness Stability Derivative vs Window Size', ...
                'Position', [100, 100, 1200, 420], 'Color', [0.08 0.11 0.17], 'Visible', 'off');

            ax1 = subplot(1, 3, 1);
            ax2 = subplot(1, 3, 2);
            ax3 = subplot(1, 3, 3);
            all_axes = [ax1, ax2, ax3];

            for ax = all_axes
                scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax);
                hold(ax, 'on');
                yline(ax, 0, '--', 'Color', [0.65 0.70 0.80], 'LineWidth', 1.2, 'Alpha', 0.85, ...
                    'DisplayName', 'Zero Drift');
            end

            for k = 1:length(results)
                r = results{k};
                if ~isfield(r, 'slice_bw') || ~isfield(r.slice_bw, 'fairness_window_sec') || isempty(r.slice_bw.fairness_window_sec)
                    continue;
                end
                win_sec = r.slice_bw.fairness_window_sec;
                [c, ~] = scooter_analysis.reporting.PlotGenerator.getDatasetColor(r.meta.name, k);

                if isfield(r.slice_bw, 'all_tib') && ~isempty(r.slice_bw.all_tib)
                    d_tib_dN = scooter_analysis.reporting.PlotGenerator.numericalDerivative(win_sec, r.slice_bw.all_tib);
                    plot(ax1, win_sec, d_tib_dN, '.-', 'Color', c, 'LineWidth', 1.5, 'MarkerSize', 8, 'DisplayName', r.meta.name);
                end

                if isfield(r.slice_bw, 'all_entropy') && ~isempty(r.slice_bw.all_entropy)
                    d_ent_dN = scooter_analysis.reporting.PlotGenerator.numericalDerivative(win_sec, 1 - r.slice_bw.all_entropy);
                    plot(ax2, win_sec, d_ent_dN, '.-', 'Color', c, 'LineWidth', 1.5, 'MarkerSize', 8, 'DisplayName', r.meta.name);
                end

                if isfield(r.slice_bw, 'all_fairness') && ~isempty(r.slice_bw.all_fairness)
                    d_fair_dN = scooter_analysis.reporting.PlotGenerator.numericalDerivative(win_sec, r.slice_bw.all_fairness);
                    plot(ax3, win_sec, d_fair_dN, '.-', 'Color', c, 'LineWidth', 1.5, 'MarkerSize', 8, 'DisplayName', r.meta.name);
                end
            end

            tol_hz = scooter_analysis.reporting.PlotGenerator.extractTibTolerance(results);
            title(ax1, sprintf('d(TiB)/dN vs Window Size (\\pm%g Hz)', tol_hz), 'FontSize', 11, 'FontWeight', 'bold', 'Color', [0.96 0.98 1.00]);
            ylabel(ax1, 'd(TiB)/dN (s^{-1})', 'FontSize', 10, 'FontWeight', 'bold', 'Color', [0.88 0.91 0.96]);
            xlabel(ax1, 'Window Size N (s)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', [0.88 0.91 0.96]);

            title(ax2, 'd(1 - H)/dN vs Window Size', 'FontSize', 11, 'FontWeight', 'bold', 'Color', [0.96 0.98 1.00]);
            ylabel(ax2, 'd(Stability)/dN (s^{-1})', 'FontSize', 10, 'FontWeight', 'bold', 'Color', [0.88 0.91 0.96]);
            xlabel(ax2, 'Window Size N (s)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', [0.88 0.91 0.96]);

            title(ax3, 'd(Fairness)/dN vs Window Size', 'FontSize', 11, 'FontWeight', 'bold', 'Color', [0.96 0.98 1.00]);
            ylabel(ax3, 'd(Fairness)/dN (s^{-1})', 'FontSize', 10, 'FontWeight', 'bold', 'Color', [0.88 0.91 0.96]);
            xlabel(ax3, 'Window Size N (s)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', [0.88 0.91 0.96]);

            for ax = all_axes
                lgd = legend(ax, 'Location', 'best');
                scooter_analysis.reporting.PlotGenerator.styleLegend(lgd);
            end

            scooter_analysis.reporting.PlotGenerator.safeExport(fig, out_path);
        end

        function fairnessHistograms(varargin)
            % fairnessHistograms - Plot normalised histograms of rolling Jain's fairness index.
            %
            % Usage:
            %   PlotGenerator.fairnessHistograms(analyzer, out_path)
            %   PlotGenerator.fairnessHistograms(analyzer, out_path, window_sec)

            if isempty(varargin)
                return;
            end

            win_sec = 5;
            if nargin >= 3 && isnumeric(varargin{end})
                win_sec = varargin{end};
                vis_args = varargin(1:end-1);
            else
                vis_args = varargin;
            end

            [results, out_path] = scooter_analysis.reporting.PlotGenerator.parseVisualizerInputs(vis_args{:});
            if isempty(results)
                return;
            end

            fig = figure('Name', 'Fairness Index Distribution', ...
                'Position', [100, 100, 900, 500], 'Color', [0.08 0.11 0.17], 'Visible', 'off');
            ax = gca;
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax);
            hold(ax, 'on');

            slice_dur = 0.5;
            N = max(1, round(win_sec / slice_dur));
            edges = 0:0.02:1.00;

            legend_entries = {};
            for k = 1:length(results)
                r = results{k};
                if ~isfield(r, 'slice_bw') || ~isfield(r.slice_bw, 'all_main_bws')
                    continue;
                end
                bws = r.slice_bw.all_main_bws;
                bws = bws(isfinite(bws) & bws > 0);

                num_blocks = floor(length(bws) / N);
                if num_blocks < 1
                    continue;
                end

                fair_vals = zeros(num_blocks, 1);
                for b = 1:num_blocks
                    blk = bws((b-1)*N + 1 : b*N);
                    s_val = sum(blk);
                    s_sq = sum(blk.^2);
                    if s_sq > 0
                        fair_vals(b) = (s_val^2) / (length(blk) * s_sq);
                    else
                        fair_vals(b) = NaN;
                    end
                end
                fair_vals = fair_vals(isfinite(fair_vals));
                if isempty(fair_vals)
                    continue;
                end

                [c, ec] = scooter_analysis.reporting.PlotGenerator.getDatasetColor(r.meta.name, k);
                histogram(ax, fair_vals, edges, 'Normalization', 'probability', ...
                    'FaceColor', c, 'EdgeColor', ec, 'FaceAlpha', 0.60, 'LineWidth', 0.8);

                legend_entries{end+1} = sprintf('%s (Mean J=%.3f)', r.meta.name, mean(fair_vals));
            end

            title(ax, sprintf('Jain''s Fairness Index Distribution (%ds Rolling Window)', win_sec), ...
                'FontSize', 11, 'FontWeight', 'bold', 'Color', [0.96 0.98 1.00]);
            xlabel(ax, 'Jain''s Fairness Index', 'FontSize', 10, 'FontWeight', 'bold', 'Color', [0.88 0.91 0.96]);
            ylabel(ax, 'Probability', 'FontSize', 10, 'FontWeight', 'bold', 'Color', [0.88 0.91 0.96]);
            if ~isempty(legend_entries)
                lgd = legend(ax, legend_entries, 'Location', 'northwest');
                scooter_analysis.reporting.PlotGenerator.styleLegend(lgd);
            end
            xlim(ax, [0, 1.02]);

            scooter_analysis.reporting.PlotGenerator.safeExport(fig, out_path);
        end

        function [d_y, dt_vec] = numericalDerivative(t_vec, y_vec)
            % numericalDerivative - Computes central finite difference derivative dy/dt.
            if isempty(t_vec) || isempty(y_vec)
                d_y = [];
                dt_vec = [];
                return;
            end
            is_row = isrow(y_vec);
            t_col  = t_vec(:);
            y_col  = y_vec(:);
            d_y    = nan(size(y_col));
            dt_vec = zeros(size(t_col));
            valid  = isfinite(t_col) & isfinite(y_col);
            if sum(valid) >= 2
                t_sub  = t_col(valid);
                y_sub  = y_col(valid);
                dt_sub = gradient(t_sub);
                dt_sub(dt_sub == 0) = eps;
                d_sub  = gradient(y_sub) ./ dt_sub;
                d_y(valid)    = d_sub;
                dt_vec(valid) = dt_sub;
            elseif sum(valid) == 1
                d_y(valid) = 0;
            end
            if is_row
                d_y    = d_y';
                dt_vec = dt_vec';
            end
        end

        function y_smooth = applySgolayFilter(data, order, framelen)
            % applySgolayFilter - Robust Savitzky-Golay filtering with NaN safety and adaptive frame length.
            if nargin < 2 || isempty(order); order = 2; end
            if nargin < 3 || isempty(framelen); framelen = 5; end

            y_smooth = data;
            if isempty(data)
                return;
            end

            is_row = isrow(data);
            d_vec = data(:)';
            N = length(d_vec);
            if N <= order + 2
                return;
            end

            % Ensure framelen is an odd integer <= N and > order
            framelen = min(framelen, 2 * floor(N / 2) - 1);
            if mod(framelen, 2) == 0
                framelen = framelen - 1;
            end
            if framelen <= order
                framelen = order + 1 + mod(order, 2);
            end
            if framelen > N || framelen <= order
                return;
            end

            nan_mask = isnan(d_vec);
            if all(nan_mask)
                return;
            end

            if any(nan_mask)
                d_filled = fillmissing(d_vec, 'linear', 'EndValues', 'nearest');
            else
                d_filled = d_vec;
            end

            try
                filtered = sgolayfilt(d_filled, order, framelen);
                filtered(nan_mask) = NaN;
                if is_row
                    y_smooth = filtered;
                else
                    y_smooth = filtered';
                end
            catch
                % Fallback: return original data if sgolayfilt is unavailable or fails
                y_smooth = data;
            end
        end

        function renderShadedPatch(ax, t_axis, data, color, clamp_01, alpha_val)
            % renderShadedPatch - Plots a semi-transparent patch for the variance region [mean-std, mean+std].
            if nargin < 5 || isempty(clamp_01); clamp_01 = false; end
            if nargin < 6 || isempty(alpha_val); alpha_val = 0.22; end
            m = mean(data, 'omitnan');
            s = std(data, 'omitnan');
            lb = m - s;
            ub = m + s;
            if clamp_01
                lb = max(0.0, lb);
                ub = min(1.0, ub);
            end
            patch(ax, [t_axis(1), t_axis(end), t_axis(end), t_axis(1)], ...
                [lb, lb, ub, ub], ...
                color, 'FaceAlpha', alpha_val, 'EdgeColor', 'none', 'HandleVisibility', 'off');
        end

        function tol_hz = extractTibTolerance(results)
            % extractTibTolerance - Extracts TiB tolerance band in Hz from results or config.
            tol_hz = 15; % Default fallback matching AnalysisConfig
            if isempty(results); return; end
            if ~iscell(results); results = {results}; end
            for k = 1:length(results)
                r = results{k};
                if isstruct(r)
                    if isfield(r, 'tol_hz') && ~isempty(r.tol_hz)
                        tol_hz = r.tol_hz;
                        return;
                    elseif isfield(r, 'Config') && isprop(r.Config, 'bw_tib_tolerance_hz')
                        tol_hz = r.Config.bw_tib_tolerance_hz;
                        return;
                    elseif isfield(r, 'meta') && isfield(r.meta, 'tol_hz') && ~isempty(r.meta.tol_hz)
                        tol_hz = r.meta.tol_hz;
                        return;
                    end
                elseif isobject(r) && isprop(r, 'Config') && isprop(r.Config, 'bw_tib_tolerance_hz')
                    tol_hz = r.Config.bw_tib_tolerance_hz;
                    return;
                end
            end
        end

        function rollingFairnessComparison(varargin)
            % rollingFairnessComparison - Plot rolling fairness time series paired with
            % their derivatives of change (rate of change dy/dt) in a 3x2 grid.
            %
            % Usage:
            %   PlotGenerator.rollingFairnessComparison(analyzerA, analyzerB, out_path)
            %   PlotGenerator.rollingFairnessComparison({resA, resB}, out_path)

            if isempty(varargin)
                return;
            end

            [results, out_path] = scooter_analysis.reporting.PlotGenerator.parseVisualizerInputs(varargin{:});
            if isempty(results)
                return;
            end

            fig = figure('Name', 'Rolling Fairness & Derivative of Change Comparison', ...
                'Position', [50, 50, 1600, 950], 'Color', [0.08 0.11 0.17], 'Visible', 'off');

            ax1 = subplot(3, 2, 1);
            ax2 = subplot(3, 2, 2);
            ax3 = subplot(3, 2, 3);
            ax4 = subplot(3, 2, 4);
            ax5 = subplot(3, 2, 5);
            ax6 = subplot(3, 2, 6);
            all_axes = [ax1, ax2, ax3, ax4, ax5, ax6];

            for ax = all_axes
                hold(ax, 'on');
            end

            % Zero reference line for all derivative subplots (ax2, ax4, ax6)
            for ax = [ax2, ax4, ax6]
                yline(ax, 0, '--', 'Color', [0.65 0.70 0.80], 'LineWidth', 1.2, 'Alpha', 0.85, ...
                    'DisplayName', 'Zero Drift (Steady State)');
            end

            % Helper function to plot shaded variance region (with optional [0, 1] clamping)
            plotShadedRegion = @(ax, t_axis, data, color, varargin) ...
                scooter_analysis.reporting.PlotGenerator.renderShadedPatch(ax, t_axis, data, color, varargin{:});

            plotMeanLine = @(ax, t_axis, data, color) ...
                plot(ax, [t_axis(1), t_axis(end)], [mean(data,'omitnan'), mean(data,'omitnan')], ...
                '-', 'Color', color, 'LineWidth', 1.8, 'HandleVisibility', 'off');

            max_t = 0;

            for k = 1:length(results)
                r = results{k};
                if ~isfield(r, 'tib_series') || isempty(r.tib_series)
                    continue;
                end

                % Check if data is already sampled at window rate (e.g., 60s) or dense rate
                if length(r.t_centers) > 1
                    dt = median(diff(r.t_centers));
                elseif isfield(r, 'window_sec') && ~isempty(r.window_sec)
                    dt = r.window_sec;
                else
                    dt = 60.0;
                end
                if isnan(dt) || dt <= 0; dt = 60.0; end

                if dt >= 55.0 || length(r.t_centers) <= 5
                    bin_t = r.t_centers;
                    bin_tib_m = r.tib_series;
                    bin_ent_m = r.ent_series;
                    bin_fair_m = r.fair_series;
                else
                    samples_per_bin = max(1, round(60 / dt));
                    num_bins = floor(length(r.t_centers) / samples_per_bin);
                    if num_bins < 1
                        continue;
                    end
                    bin_t = zeros(1, num_bins);
                    bin_tib_m = zeros(1, num_bins);
                    bin_ent_m = zeros(1, num_bins);
                    bin_fair_m = zeros(1, num_bins);
                    for b = 1:num_bins
                        idx = (b-1)*samples_per_bin + 1 : b*samples_per_bin;
                        bin_t(b) = mean(r.t_centers(idx));
                        bin_tib_m(b) = mean(r.tib_series(idx), 'omitnan');
                        bin_ent_m(b) = mean(r.ent_series(idx), 'omitnan');
                        bin_fair_m(b) = mean(r.fair_series(idx), 'omitnan');
                    end
                end

                max_t = max(max_t, max(bin_t));
                [c, ~] = scooter_analysis.reporting.PlotGenerator.getDatasetColor(r.meta.name, k);

                % Compute numerical derivatives dy/dt (s^-1)
                d_tib  = scooter_analysis.reporting.PlotGenerator.numericalDerivative(bin_t, bin_tib_m);
                d_ent  = scooter_analysis.reporting.PlotGenerator.numericalDerivative(bin_t, bin_ent_m);
                d_fair = scooter_analysis.reporting.PlotGenerator.numericalDerivative(bin_t, bin_fair_m);

                % Savitzky-Golay filtered derivatives
                d_tib_sg  = scooter_analysis.reporting.PlotGenerator.applySgolayFilter(d_tib, 2, 15);
                d_ent_sg  = scooter_analysis.reporting.PlotGenerator.applySgolayFilter(d_ent, 2, 15);
                d_fair_sg = scooter_analysis.reporting.PlotGenerator.applySgolayFilter(d_fair, 2, 15);

                % --- Row 1: TiB and d(TiB)/dt ---
                plotShadedRegion(ax1, bin_t, bin_tib_m, c, true);
                plotMeanLine(ax1, bin_t, bin_tib_m, c);
                plot(ax1, bin_t, bin_tib_m, '.-', 'Color', [c, 0.80], 'MarkerSize', 7, 'LineWidth', 1.1, ...
                    'DisplayName', sprintf('%s (Mean: %.2f ± %.2f)', r.meta.name, mean(bin_tib_m,'omitnan'), std(bin_tib_m,'omitnan')));

                plotShadedRegion(ax2, bin_t, d_tib, c);
                plotMeanLine(ax2, bin_t, d_tib, c);
                plot(ax2, bin_t, d_tib, ':', 'Color', [c, 0.35], 'MarkerSize', 4, 'LineWidth', 0.8, ...
                    'DisplayName', sprintf('%s (Raw)', r.meta.name));
                plot(ax2, bin_t, d_tib_sg, '-', 'Color', c, 'LineWidth', 2.0, ...
                    'DisplayName', sprintf('%s (SG-Filtered)', r.meta.name));

                % --- Row 2: Entropy and d(Entropy)/dt ---
                plotShadedRegion(ax3, bin_t, bin_ent_m, c, true);
                plotMeanLine(ax3, bin_t, bin_ent_m, c);
                plot(ax3, bin_t, bin_ent_m, '.-', 'Color', [c, 0.80], 'MarkerSize', 7, 'LineWidth', 1.1, ...
                    'DisplayName', sprintf('%s (Mean: %.2f ± %.2f)', r.meta.name, mean(bin_ent_m,'omitnan'), std(bin_ent_m,'omitnan')));

                plotShadedRegion(ax4, bin_t, d_ent, c);
                plotMeanLine(ax4, bin_t, d_ent, c);
                plot(ax4, bin_t, d_ent, ':', 'Color', [c, 0.35], 'MarkerSize', 4, 'LineWidth', 0.8, ...
                    'DisplayName', sprintf('%s (Raw)', r.meta.name));
                plot(ax4, bin_t, d_ent_sg, '-', 'Color', c, 'LineWidth', 2.0, ...
                    'DisplayName', sprintf('%s (SG-Filtered)', r.meta.name));

                % --- Row 3: Fairness and d(Fairness)/dt ---
                plotShadedRegion(ax5, bin_t, bin_fair_m, c, true);
                plotMeanLine(ax5, bin_t, bin_fair_m, c);
                plot(ax5, bin_t, bin_fair_m, '.-', 'Color', [c, 0.80], 'MarkerSize', 7, 'LineWidth', 1.1, ...
                    'DisplayName', sprintf('%s (Mean: %.2f ± %.2f)', r.meta.name, mean(bin_fair_m,'omitnan'), std(bin_fair_m,'omitnan')));

                plotShadedRegion(ax6, bin_t, d_fair, c);
                plotMeanLine(ax6, bin_t, d_fair, c);
                plot(ax6, bin_t, d_fair, ':', 'Color', [c, 0.35], 'MarkerSize', 4, 'LineWidth', 0.8, ...
                    'DisplayName', sprintf('%s (Raw)', r.meta.name));
                plot(ax6, bin_t, d_fair_sg, '-', 'Color', c, 'LineWidth', 2.0, ...
                    'DisplayName', sprintf('%s (SG-Filtered)', r.meta.name));
            end

            % Clamp bounded metrics to [0, 1.02] so variance bands don't overflow
            ylim(ax1, [0, 1.02]);
            ylim(ax3, [0, 1.02]);
            cur_y5 = ylim(ax5);
            ylim(ax5, [max(0, cur_y5(1)), 1.02]);

            tol_hz = scooter_analysis.reporting.PlotGenerator.extractTibTolerance(results);
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax1, ...
                sprintf('Time-in-Band (TiB, \\pm%g Hz) - 60s Windows', tol_hz), '', 'TiB Ratio');
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax2, ...
                sprintf('TiB Rate of Change (Derivative: d(TiB)/dt, \\pm%g Hz)', tol_hz), '', 'd(TiB)/dt (s^{-1})');
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax3, ...
                'Shannon Entropy (Norm) - 60s Windows', '', 'Entropy (Norm)');
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax4, ...
                'Shannon Entropy Rate of Change (Derivative: d(H)/dt)', '', 'd(Entropy)/dt (s^{-1})');
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax5, ...
                'Jain''s Fairness Index - 60s Windows', 'Time (s)', 'Fairness Index');
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax6, ...
                'Jain''s Fairness Rate of Change (Derivative: d(Fairness)/dt)', 'Time (s)', 'd(Fairness)/dt (s^{-1})');

            for ax = all_axes
                lgd = legend(ax, 'Location', 'best');
                scooter_analysis.reporting.PlotGenerator.styleLegend(lgd);
                if max_t > 0
                    xlim(ax, [0, max_t * 1.02]);
                end
            end

            scooter_analysis.reporting.PlotGenerator.safeExport(fig, out_path);
        end

        function rollingFairnessDerivativeComparison(varargin)
            % rollingFairnessDerivativeComparison - Plot dedicated 3-panel time series of the
            % rate of change (numerical derivative dy/dt) of each fairness measurement.
            %
            % Usage:
            %   PlotGenerator.rollingFairnessDerivativeComparison(analyzerA, analyzerB, out_path)
            %   PlotGenerator.rollingFairnessDerivativeComparison({resA, resB}, out_path)

            if isempty(varargin)
                return;
            end

            [results, out_path] = scooter_analysis.reporting.PlotGenerator.parseVisualizerInputs(varargin{:});
            if isempty(results)
                return;
            end

            fig = figure('Name', 'Rolling Fairness Derivative of Change', ...
                'Position', [100, 100, 1200, 850], 'Color', [0.08 0.11 0.17], 'Visible', 'off');

            ax1 = subplot(3, 1, 1);
            ax2 = subplot(3, 1, 2);
            ax3 = subplot(3, 1, 3);
            all_axes = [ax1, ax2, ax3];

            for ax = all_axes
                hold(ax, 'on');
                yline(ax, 0, '--', 'Color', [0.65 0.70 0.80], 'LineWidth', 1.2, 'Alpha', 0.85, ...
                    'DisplayName', 'Zero Drift (Steady State)');
            end

            plotShadedRegion = @(ax, t_axis, data, color) ...
                patch(ax, [t_axis(1), t_axis(end), t_axis(end), t_axis(1)], ...
                [mean(data,'omitnan') - std(data,'omitnan'), mean(data,'omitnan') - std(data,'omitnan'), ...
                mean(data,'omitnan') + std(data,'omitnan'), mean(data,'omitnan') + std(data,'omitnan')], ...
                color, 'FaceAlpha', 0.20, 'EdgeColor', 'none', 'HandleVisibility', 'off');

            plotMeanLine = @(ax, t_axis, data, color) ...
                plot(ax, [t_axis(1), t_axis(end)], [mean(data,'omitnan'), mean(data,'omitnan')], ...
                '-', 'Color', color, 'LineWidth', 1.8, 'HandleVisibility', 'off');

            max_t = 0;

            for k = 1:length(results)
                r = results{k};
                if ~isfield(r, 'tib_series') || isempty(r.tib_series)
                    continue;
                end

                % Check if data is already sampled at window rate (e.g., 60s) or dense rate
                if length(r.t_centers) > 1
                    dt = median(diff(r.t_centers));
                elseif isfield(r, 'window_sec') && ~isempty(r.window_sec)
                    dt = r.window_sec;
                else
                    dt = 60.0;
                end
                if isnan(dt) || dt <= 0; dt = 60.0; end

                if dt >= 55.0 || length(r.t_centers) <= 5
                    bin_t = r.t_centers;
                    bin_tib_m = r.tib_series;
                    bin_ent_m = r.ent_series;
                    bin_fair_m = r.fair_series;
                else
                    samples_per_bin = max(1, round(60 / dt));
                    num_bins = floor(length(r.t_centers) / samples_per_bin);
                    if num_bins < 1
                        continue;
                    end
                    bin_t = zeros(1, num_bins);
                    bin_tib_m = zeros(1, num_bins);
                    bin_ent_m = zeros(1, num_bins);
                    bin_fair_m = zeros(1, num_bins);
                    for b = 1:num_bins
                        idx = (b-1)*samples_per_bin + 1 : b*samples_per_bin;
                        bin_t(b) = mean(r.t_centers(idx));
                        bin_tib_m(b) = mean(r.tib_series(idx), 'omitnan');
                        bin_ent_m(b) = mean(r.ent_series(idx), 'omitnan');
                        bin_fair_m(b) = mean(r.fair_series(idx), 'omitnan');
                    end
                end

                max_t = max(max_t, max(bin_t));
                [c, ~] = scooter_analysis.reporting.PlotGenerator.getDatasetColor(r.meta.name, k);

                d_tib  = scooter_analysis.reporting.PlotGenerator.numericalDerivative(bin_t, bin_tib_m);
                d_ent  = scooter_analysis.reporting.PlotGenerator.numericalDerivative(bin_t, bin_ent_m);
                d_fair = scooter_analysis.reporting.PlotGenerator.numericalDerivative(bin_t, bin_fair_m);

                % Savitzky-Golay filtered derivatives (order 2, frame length 15)
                d_tib_sg  = scooter_analysis.reporting.PlotGenerator.applySgolayFilter(d_tib, 2, 15);
                d_ent_sg  = scooter_analysis.reporting.PlotGenerator.applySgolayFilter(d_ent, 2, 15);
                d_fair_sg = scooter_analysis.reporting.PlotGenerator.applySgolayFilter(d_fair, 2, 15);

                % Subplot 1: d(TiB)/dt
                plotShadedRegion(ax1, bin_t, d_tib, c);
                plotMeanLine(ax1, bin_t, d_tib, c);
                plot(ax1, bin_t, d_tib, ':', 'Color', [c, 0.35], 'MarkerSize', 4, 'LineWidth', 0.8, ...
                    'DisplayName', sprintf('%s (Raw)', r.meta.name));
                plot(ax1, bin_t, d_tib_sg, '-', 'Color', c, 'LineWidth', 2.0, ...
                    'DisplayName', sprintf('%s (SG-Filtered, μ: %+.1e, σ: %.1e s⁻¹)', r.meta.name, mean(d_tib_sg,'omitnan'), std(d_tib_sg,'omitnan')));

                % Subplot 2: d(Entropy)/dt
                plotShadedRegion(ax2, bin_t, d_ent, c);
                plotMeanLine(ax2, bin_t, d_ent, c);
                plot(ax2, bin_t, d_ent, ':', 'Color', [c, 0.35], 'MarkerSize', 4, 'LineWidth', 0.8, ...
                    'DisplayName', sprintf('%s (Raw)', r.meta.name));
                plot(ax2, bin_t, d_ent_sg, '-', 'Color', c, 'LineWidth', 2.0, ...
                    'DisplayName', sprintf('%s (SG-Filtered, μ: %+.1e, σ: %.1e s⁻¹)', r.meta.name, mean(d_ent_sg,'omitnan'), std(d_ent_sg,'omitnan')));

                % Subplot 3: d(Fairness)/dt
                plotShadedRegion(ax3, bin_t, d_fair, c);
                plotMeanLine(ax3, bin_t, d_fair, c);
                plot(ax3, bin_t, d_fair, ':', 'Color', [c, 0.35], 'MarkerSize', 4, 'LineWidth', 0.8, ...
                    'DisplayName', sprintf('%s (Raw)', r.meta.name));
                plot(ax3, bin_t, d_fair_sg, '-', 'Color', c, 'LineWidth', 2.0, ...
                    'DisplayName', sprintf('%s (SG-Filtered, μ: %+.1e, σ: %.1e s⁻¹)', r.meta.name, mean(d_fair_sg,'omitnan'), std(d_fair_sg,'omitnan')));
            end

            tol_hz = scooter_analysis.reporting.PlotGenerator.extractTibTolerance(results);
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax1, ...
                sprintf('Time-in-Band Rate of Change (Derivative: d(TiB)/dt, \\pm%g Hz)', tol_hz), '', 'd(TiB)/dt (s^{-1})');
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax2, ...
                'Shannon Entropy Rate of Change (Derivative: d(H)/dt)', '', 'd(Entropy)/dt (s^{-1})');
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax3, ...
                'Jain''s Fairness Index Rate of Change (Derivative: d(Fairness)/dt)', 'Time (s)', 'd(Fairness)/dt (s^{-1})');

            for ax = all_axes
                lgd = legend(ax, 'Location', 'best');
                scooter_analysis.reporting.PlotGenerator.styleLegend(lgd);
                if max_t > 0
                    xlim(ax, [0, max_t * 1.02]);
                end
            end

            scooter_analysis.reporting.PlotGenerator.safeExport(fig, out_path);
        end


        function dominantFrequency(varargin)
            % dominantFrequency - Plot and export Figure 6: Welch PSD & Dominant Frequency.
            % (Matches Fig 6 in bandwidth_segment_lobe_floor_watershed.m)
            %
            % Usage:
            %   PlotGenerator.dominantFrequency(analyzer)
            %   PlotGenerator.dominantFrequency(analyzer, out_dir)
            %   PlotGenerator.dominantFrequency(analyzerA, analyzerB, out_dir)
            %   PlotGenerator.dominantFrequency({analyzerA, analyzerB}, out_dir)

            [results, out_dir] = scooter_analysis.reporting.PlotGenerator.parseVisualizerInputs(varargin{:});
            if isempty(results)
                return;
            end
            cfg_vis = struct('output_dir', out_dir);
            Visualizer.render_welch_dominant_frequency(results, cfg_vis);
        end


        function dominantWatershed(varargin)
            % dominantWatershed - Plot and export Figure 2: Dominant Frequency Watershed Bandwidth (250ms Center Slice).
            % (Matches Fig 2 in bandwidth_segment_lobe_floor_watershed.m)
            %
            % Usage:
            %   PlotGenerator.dominantWatershed(analyzer)
            %   PlotGenerator.dominantWatershed(analyzer, out_dir)
            %   PlotGenerator.dominantWatershed(analyzerA, analyzerB, out_dir)
            %   PlotGenerator.dominantWatershed({analyzerA, analyzerB}, out_dir)

            [results, out_dir] = scooter_analysis.reporting.PlotGenerator.parseVisualizerInputs(varargin{:});
            if isempty(results)
                return;
            end
            cfg_vis = struct('output_dir', out_dir);
            Visualizer.render_dominant_watershed_figures(results, cfg_vis);
        end


        function macroLobeWatershed(varargin)
            % macroLobeWatershed - Plot and export Figure 1: Macro-Lobe Watershed & Ambient Baseline.
            % (Matches Fig 1 in bandwidth_segment_lobe_floor_watershed.m)
            %
            % Usage:
            %   PlotGenerator.macroLobeWatershed(analyzer)
            %   PlotGenerator.macroLobeWatershed(analyzer, out_dir)
            %   PlotGenerator.macroLobeWatershed(analyzerA, analyzerB, out_dir)
            %   PlotGenerator.macroLobeWatershed({analyzerA, analyzerB}, out_dir)

            [results, out_dir] = scooter_analysis.reporting.PlotGenerator.parseVisualizerInputs(varargin{:});
            if isempty(results)
                return;
            end
            cfg_vis = struct('output_dir', out_dir);
            Visualizer.render_spectral_and_cfar_figures(results, cfg_vis);
        end


        function allWatershedPlots(varargin)
            % allWatershedPlots - Generate all diagnostic figures from bandwidth_segment_lobe_floor_watershed.m:
            %   1. Macro-Lobe Watershed & Ambient Baseline (Fig 1)
            %   2. Dominant Frequency Watershed Bandwidth (Fig 2)
            %   3. Bandwidth & Fairness Stability Distribution (Fig 4)
            %   4. Welch PSD & Dominant Frequency (Fig 6)
            %   5. Diagnostic report summary

            [results, out_dir] = scooter_analysis.reporting.PlotGenerator.parseVisualizerInputs(varargin{:});
            if isempty(results)
                return;
            end
            cfg_vis = struct('output_dir', out_dir);
            Visualizer.render_spectral_and_cfar_figures(results, cfg_vis);
            Visualizer.render_dominant_watershed_figures(results, cfg_vis);
            if length(results) >= 2
                Visualizer.render_bandwidth_distribution(results, cfg_vis);
            end
            Visualizer.render_welch_dominant_frequency(results, cfg_vis);
            Visualizer.print_diagnostic_summary(results);
        end


        function binnedBandwidthDistribution(varargin)
            % binnedBandwidthDistribution - Plot bandwidth distribution histogram of 60s slice means
            % and plot the standard error (std error = SEM) for each slice.
            %
            % Generates a publication-grade multi-panel figure:
            %   Panel 1: Bandwidth Distribution Histogram (using the mean of each 60s slice)
            %   Panel 2: Standard Error Distribution across slices
            %   Panel 3: Mean Bandwidth with Error Bars (±SE) vs Time for each 60s slice
            %   Panel 4: Standard Error for each 60s slice vs Time
            %
            % Usage:
            %   PlotGenerator.binnedBandwidthDistribution(analyzer, out_path)
            %   PlotGenerator.binnedBandwidthDistribution(analyzerA, analyzerB, out_path)
            %   PlotGenerator.binnedBandwidthDistribution({analyzerA, analyzerB}, out_path)
            %   PlotGenerator.binnedBandwidthDistribution(..., bin_dur_sec, out_path)

            if isempty(varargin)
                return;
            end

            out_path = '';
            last_arg = varargin{end};
            if (ischar(last_arg) && isrow(last_arg)) || (isstring(last_arg) && isscalar(last_arg))
                out_path = char(last_arg);
                items = varargin(1:end-1);
            else
                items = varargin;
            end

            error_type = 'std'; % Default: sample standard deviation (SD)
            if ~isempty(items) && (ischar(items{end}) || isstring(items{end})) && ...
                    ismember(lower(string(items{end})), ["std", "sem"])
                error_type = char(lower(string(items{end})));
                items = items(1:end-1);
            end

            bin_dur_sec = 60.0;
            if ~isempty(items) && isnumeric(items{end}) && isscalar(items{end})
                bin_dur_sec = items{end};
                items = items(1:end-1);
            end

            % Re-check error_type in case order was (..., bin_dur, 'std')
            if ~isempty(items) && (ischar(items{end}) || isstring(items{end})) && ...
                    ismember(lower(string(items{end})), ["std", "sem"])
                error_type = char(lower(string(items{end})));
                items = items(1:end-1);
            end
            use_std = strcmpi(error_type, 'std');

            if length(items) == 1 && iscell(items{1})
                items = items{1};
            end

            binned_datasets = {};
            for i = 1:numel(items)
                item = items{i};
                if isempty(item); continue; end

                ds = struct();
                if isa(item, 'scooter_analysis.pipeline.BatchAnalyzer')
                    ds.name = item.DatasetName;
                    res = item.getBinnedBandwidthResult(bin_dur_sec);
                    ds.slice_means = res.slice_means;
                    ds.slice_sems  = res.slice_sems;
                    ds.slice_stds  = res.slice_stds;
                    ds.slice_times = res.slice_times;
                elseif isa(item, 'scooter_analysis.results.FileResult')
                    ds.name = item.filename;
                    res = item.getBinnedBandwidthResult(bin_dur_sec);
                    ds.slice_means = res.slice_means;
                    ds.slice_sems  = res.slice_sems;
                    ds.slice_stds  = res.slice_stds;
                    ds.slice_times = res.slice_times;
                elseif isstruct(item)
                    if isfield(item, 'meta') && isfield(item.meta, 'name')
                        ds.name = item.meta.name;
                    elseif isfield(item, 'name')
                        ds.name = item.name;
                    else
                        ds.name = sprintf('Dataset %d', i);
                    end

                    if isfield(item, 'slice_means') && isfield(item.slice_sems)
                        ds.slice_means = item.slice_means;
                        ds.slice_sems  = item.slice_sems;
                        ds.slice_stds  = item.slice_stds;
                        ds.slice_times = item.slice_times;
                    elseif isfield(item, 'slice_bw') && isfield(item.slice_bw, 'all_main_bws')
                        [ds.slice_means, ds.slice_sems, ds.slice_times, ds.slice_stds] = ...
                            BandwidthTracker.compute_binned_bandwidth(item.slice_bw.all_main_bws, 0.500, bin_dur_sec);
                    elseif isfield(item, 'all_main_bws')
                        [ds.slice_means, ds.slice_sems, ds.slice_times, ds.slice_stds] = ...
                            BandwidthTracker.compute_binned_bandwidth(item.all_main_bws, 0.500, bin_dur_sec);
                    else
                        continue;
                    end
                else
                    continue;
                end

                valid_mask = isfinite(ds.slice_means) & ds.slice_means > 0;
                ds.slice_means = ds.slice_means(valid_mask);
                ds.slice_sems  = ds.slice_sems(valid_mask);
                ds.slice_stds  = ds.slice_stds(valid_mask);
                ds.slice_times = ds.slice_times(valid_mask);

                if ~isempty(ds.slice_means)
                    binned_datasets{end+1} = ds;
                end
            end

            num_ds = length(binned_datasets);
            if num_ds < 1
                fprintf('[PlotGenerator] No binned bandwidth data available to plot.\n');
                return;
            end

            vis_state = 'off';
            if isempty(out_path)
                vis_state = 'on';
            end

            err_name_str = 'Standard Deviation';
            err_sym_str  = 'SD';
            if ~use_std
                err_name_str = 'Standard Error';
                err_sym_str  = 'SE';
            end

            fig = figure('Name', sprintf('Bandwidth Distribution (%ds Slices) & %s', round(bin_dur_sec), err_name_str), ...
                'Position', [60, 60, 1400, 850], 'Color', [0.08 0.11 0.17], 'Visible', vis_state);

            % --- Subplot 1: 60s Mean Bandwidth Distribution Histogram ---
            ax1 = subplot(2, 2, 1);
            hold(ax1, 'on');

            all_means_concat = vertcat(binned_datasets{:});
            all_means_concat = vertcat(all_means_concat.slice_means);
            min_bw = max(0, min(all_means_concat) - 5);
            max_bw = max(all_means_concat) + 5;
            if max_bw <= min_bw
                max_bw = min_bw + 10;
            end
            num_bins = min(16, max(8, round(sqrt(length(all_means_concat)) / 1.2)));
            bin_edges = linspace(min_bw, max_bw, num_bins + 1);
            bin_centers = (bin_edges(1:end-1) + bin_edges(2:end)) / 2;
            bin_width = bin_edges(2) - bin_edges(1);

            % Build matrices for grouped bars and error bars
            P_matrix = zeros(num_bins, num_ds);
            err_low_matrix = zeros(num_bins, num_ds);
            err_up_matrix  = zeros(num_bins, num_ds);

            for k = 1:num_ds
                ds = binned_datasets{k};
                N_k = length(ds.slice_means);
                counts = histcounts(ds.slice_means, bin_edges);
                probs = counts / max(1, N_k);

                % Each bar's standard deviation (binomial/multinomial proportion std):
                % sigma = sqrt(p * (1 - p) / N)
                sigma_bar = sqrt(probs .* (1 - probs) ./ max(1, N_k));

                P_matrix(:, k) = probs(:);
                err_low_matrix(:, k) = min(probs(:), sigma_bar(:));
                err_up_matrix(:, k)  = sigma_bar(:);
            end

            if num_ds == 1
                b = bar(ax1, bin_centers, P_matrix, 'BarWidth', 0.95);
            else
                b = bar(ax1, bin_centers, P_matrix, 'grouped', 'BarWidth', 0.95);
            end

            for k = 1:num_ds
                ds = binned_datasets{k};
                [c, ec] = scooter_analysis.reporting.PlotGenerator.getDatasetColor(ds.name, k);

                b(k).FaceColor = c;
                b(k).EdgeColor = ec;
                b(k).FaceAlpha = 0.60;
                b(k).DisplayName = sprintf('%s (N=%d slices)', ds.name, length(ds.slice_means));

                % Add error bar to show each bar's std (centered on each grouped bar, only for non-empty bars)
                x_pos = b(k).XEndPoints;
                y_pos = b(k).YData;
                valid_bars = (y_pos > 0);
                if any(valid_bars)
                    errorbar(ax1, x_pos(valid_bars), y_pos(valid_bars), ...
                        err_low_matrix(valid_bars, k)', err_up_matrix(valid_bars, k)', ...
                        'LineStyle', 'none', 'Color', ec, 'LineWidth', 1.3, 'CapSize', 4, ...
                        'HandleVisibility', 'off');
                end

                % Overlay smooth KDE curve normalized to match bar probability height
                if length(ds.slice_means) >= 4
                    try
                        [f_kde, xi_kde] = ksdensity(ds.slice_means);
                        max_p = max(P_matrix(:, k));
                        max_f = max(f_kde);
                        if max_f > 0 && max_p > 0
                            f_kde_norm = f_kde * (max_p / max_f);
                        else
                            f_kde_norm = f_kde;
                        end
                        plot(ax1, xi_kde, f_kde_norm, '-', 'Color', ec, 'LineWidth', 2, ...
                            'HandleVisibility', 'off');
                    catch
                    end
                end

                m_val = mean(ds.slice_means);
                macro_std = std(ds.slice_means);
                if use_std
                    within_slice_err = mean(ds.slice_stds);
                else
                    within_slice_err = mean(ds.slice_sems);
                end
                xline(ax1, m_val, '--', 'Color', ec, 'LineWidth', 1.8, ...
                    'DisplayName', sprintf('%s Mean: %.1f ± %.1f Hz (std: %.1f)', ds.name, m_val, within_slice_err, macro_std));
            end

            max_p_all = max(P_matrix(:));
            if max_p_all <= 0; max_p_all = 0.5; end
            ylim(ax1, [0, min(1.0, max_p_all * 1.15 + 0.05)]);

            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax1, ...
                sprintf('%ds Mean Bandwidth Distribution (Normalized)', round(bin_dur_sec)), ...
                sprintf('Mean Bandwidth per %ds Slice (Hz)', round(bin_dur_sec)), ...
                'Normalized Probability');
            lgd1 = legend(ax1, 'Location', 'best');
            scooter_analysis.reporting.PlotGenerator.styleLegend(lgd1);

            % --- Subplot 2: Standard Deviation / Error Distribution Across Slices ---
            ax2 = subplot(2, 2, 2);
            hold(ax2, 'on');

            if use_std
                all_err_concat = vertcat(binned_datasets{:});
                all_err_concat = vertcat(all_err_concat.slice_stds);
            else
                all_err_concat = vertcat(binned_datasets{:});
                all_err_concat = vertcat(all_err_concat.slice_sems);
            end
            min_err = max(0, min(all_err_concat) * 0.8);
            if length(all_err_concat) >= 10
                p99 = prctile(all_err_concat, 99);
                max_err = max(p99 * 1.25, 4.0);
                if max_err > max(all_err_concat); max_err = max(all_err_concat) * 1.05; end
            else
                max_err = max(all_err_concat) * 1.1;
            end
            num_err_bins = min(20, max(8, round(sqrt(length(all_err_concat)))));
            err_edges = linspace(min_err, max_err, num_err_bins + 1);

            for k = 1:num_ds
                ds = binned_datasets{k};
                [c, ec] = scooter_analysis.reporting.PlotGenerator.getDatasetColor(ds.name, k);

                if use_std
                    slice_err_vec = ds.slice_stds;
                else
                    slice_err_vec = ds.slice_sems;
                end
                % Clip any extreme outlier values to max_err so all data is represented
                clamped_err = min(slice_err_vec, max_err);

                histogram(ax2, clamped_err, err_edges, 'Normalization', 'probability', ...
                    'FaceColor', c, 'EdgeColor', ec, 'FaceAlpha', 0.60, ...
                    'DisplayName', sprintf('%s (Avg %s: %.2f Hz)', ds.name, err_sym_str, mean(slice_err_vec)));

                mean_err = mean(slice_err_vec);
                xline(ax2, mean_err, '--', 'Color', ec, 'LineWidth', 1.8, ...
                    'DisplayName', sprintf('%s Avg %s: %.2f Hz', ds.name, err_sym_str, mean_err));
            end

            ylim(ax2, [0, 1.05]);

            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax2, ...
                sprintf('%s Distribution Across %ds Slices (Normalized)', err_name_str, round(bin_dur_sec)), ...
                sprintf('%s %s (Hz)', err_name_str, err_sym_str), ...
                'Normalized Probability');
            lgd2 = legend(ax2, 'Location', 'best');
            scooter_analysis.reporting.PlotGenerator.styleLegend(lgd2);

            % --- Subplot 3: Mean Bandwidth with Error Bars (±SD or ±SE) vs Time ---
            ax3 = subplot(2, 2, 3);
            hold(ax3, 'on');

            for k = 1:num_ds
                ds = binned_datasets{k};
                [c, ~] = scooter_analysis.reporting.PlotGenerator.getDatasetColor(ds.name, k);
                t_min = ds.slice_times / 60;
                if use_std
                    slice_err_vec = ds.slice_stds;
                else
                    slice_err_vec = ds.slice_sems;
                end

                t_row = t_min(:)';
                y_row = ds.slice_means(:)';
                err_row = slice_err_vec(:)';
                valid_mask = ~isnan(t_row) & ~isnan(y_row) & ~isnan(err_row);
                t_valid = t_row(valid_mask);
                y_valid = y_row(valid_mask);
                err_valid = err_row(valid_mask);

                if ~isempty(t_valid)
                    upper_bound = y_valid + err_valid;
                    lower_bound = max(0, y_valid - err_valid);

                    patch(ax3, [t_valid, fliplr(t_valid)], [upper_bound, fliplr(lower_bound)], ...
                        c, 'FaceAlpha', 0.20, 'EdgeColor', 'none', 'HandleVisibility', 'off');

                    plot(ax3, t_valid, y_valid, '.-', ...
                        'Color', [c, 0.90], 'MarkerSize', 8, 'LineWidth', 1.2, ...
                        'DisplayName', sprintf('%s (Mean: %.1f Hz)', ds.name, mean(y_valid)));
                end
            end

            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax3, ...
                sprintf('%ds Slice Mean Bandwidth with Shaded ±%s', round(bin_dur_sec), err_sym_str), ...
                'Elapsed Time (minutes)', ...
                sprintf('Mean Bandwidth ± %s (Hz)', err_sym_str));
            lgd3 = legend(ax3, 'Location', 'best');
            scooter_analysis.reporting.PlotGenerator.styleLegend(lgd3);

            % --- Subplot 4: Standard Deviation / Error for Each Slice vs Time ---
            ax4 = subplot(2, 2, 4);
            hold(ax4, 'on');

            for k = 1:num_ds
                ds = binned_datasets{k};
                [c, ~] = scooter_analysis.reporting.PlotGenerator.getDatasetColor(ds.name, k);
                t_min = ds.slice_times / 60;
                if use_std
                    slice_err_vec = ds.slice_stds;
                else
                    slice_err_vec = ds.slice_sems;
                end

                plot(ax4, t_min, slice_err_vec, '.-', 'Color', c, 'LineWidth', 1.2, ...
                    'MarkerSize', 10, 'DisplayName', sprintf('%s (Avg %s: %.2f Hz)', ds.name, err_sym_str, mean(slice_err_vec)));

                yline(ax4, mean(slice_err_vec), ':', 'Color', c, 'LineWidth', 1.5, ...
                    'HandleVisibility', 'off');
            end

            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax4, ...
                sprintf('%s for Each %ds Slice', err_name_str, round(bin_dur_sec)), ...
                'Elapsed Time (minutes)', ...
                sprintf('%s %s (Hz)', err_name_str, err_sym_str));
            lgd4 = legend(ax4, 'Location', 'best');
            scooter_analysis.reporting.PlotGenerator.styleLegend(lgd4);

            if ~isempty(out_path)
                scooter_analysis.reporting.PlotGenerator.safeExport(fig, out_path);
            end
        end


        function bandwidthDistribution60s(varargin)
            % Alias for binnedBandwidthDistribution with 60s slices.
            scooter_analysis.reporting.PlotGenerator.binnedBandwidthDistribution(varargin{:});
        end


        % =================================================================
        % Phase Lock (Digital PLL) & Instantaneous Frequency Verification Plots
        % =================================================================

        function phaseLockComparison(varargin)
            % phaseLockComparison - Plot and export 4-panel Phase Lock & Instantaneous Frequency
            % Verification comparison across datasets or files.
            %
            % Generates:
            %   1. Wrapped Phase Error Distribution (PDF in [-pi, pi])
            %   2. Mean Phase Locking Value (Circular Sync R) vs Window Size N
            %   3. Phase Concentration Stability (1 - H_phi_norm) vs Window Size N
            %   4. Instantaneous Frequency Stability Fairness vs Window Size N
            %
            % Usage:
            %   PlotGenerator.phaseLockComparison({ba_h, ba_c, ba_auv}, out_dir)

            [results, out_dir] = scooter_analysis.reporting.PlotGenerator.parseVisualizerInputs(varargin{:});
            if isempty(results)
                return;
            end

            cfg_vis = struct('output_dir', out_dir);
            Visualizer.render_phase_lock_distribution(results, cfg_vis);
        end


        function rollingPhaseLockComparison(varargin)
            % rollingPhaseLockComparison - Plot 60s rolling Phase Lock (R), Phase Entropy (H_phi),
            % and Instantaneous Frequency Lock Fairness paired with their derivatives of change (3x2 grid).
            %
            % Usage:
            %   PlotGenerator.rollingPhaseLockComparison({res_h_pll, res_c_pll, res_auv_pll}, out_path)
            %   PlotGenerator.rollingPhaseLockComparison({ba_h, ba_c, ba_auv}, out_path)

            if isempty(varargin)
                return;
            end

            [results, out_path] = scooter_analysis.reporting.PlotGenerator.parsePhaseLockRollingInputs(varargin{:});
            if isempty(results)
                return;
            end

            fig = figure('Name', 'Rolling Phase Lock & Instantaneous Frequency Stability Comparison', ...
                'Position', [50, 50, 1600, 950], 'Color', [0.08 0.11 0.17], 'Visible', 'off');

            ax1 = subplot(3, 2, 1);
            ax2 = subplot(3, 2, 2);
            ax3 = subplot(3, 2, 3);
            ax4 = subplot(3, 2, 4);
            ax5 = subplot(3, 2, 5);
            ax6 = subplot(3, 2, 6);
            all_axes = [ax1, ax2, ax3, ax4, ax5, ax6];

            for ax = all_axes
                hold(ax, 'on');
            end

            for ax = [ax2, ax4, ax6]
                yline(ax, 0, '--', 'Color', [0.65 0.70 0.80], 'LineWidth', 1.2, 'Alpha', 0.85, ...
                    'DisplayName', 'Zero Drift (Steady State)');
            end

            plotShadedRegion = @(ax, t_axis, data, color, varargin) ...
                scooter_analysis.reporting.PlotGenerator.renderShadedPatch(ax, t_axis, data, color, varargin{:});

            plotMeanLine = @(ax, t_axis, data, color) ...
                plot(ax, [t_axis(1), t_axis(end)], [mean(data,'omitnan'), mean(data,'omitnan')], ...
                '-', 'Color', color, 'LineWidth', 1.8, 'HandleVisibility', 'off');

            max_t = 0;

            for k = 1:length(results)
                r = results{k};
                if ~isfield(r, 'plv_series') || isempty(r.plv_series)
                    continue;
                end

                bin_t    = r.t_centers;
                bin_plv  = r.plv_series;
                bin_pent = r.phase_ent_series;
                bin_flk  = r.freq_lock_series;

                if isempty(bin_t); continue; end
                max_t = max(max_t, max(bin_t));
                [c, ~] = scooter_analysis.reporting.PlotGenerator.getDatasetColor(r.meta.name, k);

                d_plv  = scooter_analysis.reporting.PlotGenerator.numericalDerivative(bin_t, bin_plv);
                d_pent = scooter_analysis.reporting.PlotGenerator.numericalDerivative(bin_t, bin_pent);
                d_flk  = scooter_analysis.reporting.PlotGenerator.numericalDerivative(bin_t, bin_flk);

                d_plv_sg  = scooter_analysis.reporting.PlotGenerator.applySgolayFilter(d_plv, 2, 15);
                d_pent_sg = scooter_analysis.reporting.PlotGenerator.applySgolayFilter(d_pent, 2, 15);
                d_flk_sg  = scooter_analysis.reporting.PlotGenerator.applySgolayFilter(d_flk, 2, 15);

                % --- Row 1: Phase Locking Value R and dR/dt ---
                plotShadedRegion(ax1, bin_t, bin_plv, c, true);
                plotMeanLine(ax1, bin_t, bin_plv, c);
                plot(ax1, bin_t, bin_plv, '.-', 'Color', [c, 0.80], 'MarkerSize', 7, 'LineWidth', 1.1, ...
                    'DisplayName', sprintf('%s (Mean: %.2f ± %.2f)', r.meta.name, mean(bin_plv,'omitnan'), std(bin_plv,'omitnan')));

                plotShadedRegion(ax2, bin_t, d_plv, c);
                plotMeanLine(ax2, bin_t, d_plv, c);
                plot(ax2, bin_t, d_plv, ':', 'Color', [c, 0.35], 'MarkerSize', 4, 'LineWidth', 0.8, ...
                    'DisplayName', sprintf('%s (Raw)', r.meta.name));
                plot(ax2, bin_t, d_plv_sg, '-', 'Color', c, 'LineWidth', 2.0, ...
                    'DisplayName', sprintf('%s (SG-Filtered)', r.meta.name));

                % --- Row 2: Phase Entropy H_phi and d(H_phi)/dt ---
                plotShadedRegion(ax3, bin_t, bin_pent, c, true);
                plotMeanLine(ax3, bin_t, bin_pent, c);
                plot(ax3, bin_t, bin_pent, '.-', 'Color', [c, 0.80], 'MarkerSize', 7, 'LineWidth', 1.1, ...
                    'DisplayName', sprintf('%s (Mean: %.2f ± %.2f)', r.meta.name, mean(bin_pent,'omitnan'), std(bin_pent,'omitnan')));

                plotShadedRegion(ax4, bin_t, d_pent, c);
                plotMeanLine(ax4, bin_t, d_pent, c);
                plot(ax4, bin_t, d_pent, ':', 'Color', [c, 0.35], 'MarkerSize', 4, 'LineWidth', 0.8, ...
                    'DisplayName', sprintf('%s (Raw)', r.meta.name));
                plot(ax4, bin_t, d_pent_sg, '-', 'Color', c, 'LineWidth', 2.0, ...
                    'DisplayName', sprintf('%s (SG-Filtered)', r.meta.name));

                % --- Row 3: Instantaneous Frequency Stability Fairness and Derivative ---
                plotShadedRegion(ax5, bin_t, bin_flk, c, true);
                plotMeanLine(ax5, bin_t, bin_flk, c);
                plot(ax5, bin_t, bin_flk, '.-', 'Color', [c, 0.80], 'MarkerSize', 7, 'LineWidth', 1.1, ...
                    'DisplayName', sprintf('%s (Mean: %.2f ± %.2f)', r.meta.name, mean(bin_flk,'omitnan'), std(bin_flk,'omitnan')));

                plotShadedRegion(ax6, bin_t, d_flk, c);
                plotMeanLine(ax6, bin_t, d_flk, c);
                plot(ax6, bin_t, d_flk, ':', 'Color', [c, 0.35], 'MarkerSize', 4, 'LineWidth', 0.8, ...
                    'DisplayName', sprintf('%s (Raw)', r.meta.name));
                plot(ax6, bin_t, d_flk_sg, '-', 'Color', c, 'LineWidth', 2.0, ...
                    'DisplayName', sprintf('%s (SG-Filtered)', r.meta.name));
            end

            ylim(ax1, [0, 1.02]);
            ylim(ax3, [0, 1.02]);
            cur_y5 = ylim(ax5);
            ylim(ax5, [max(0, cur_y5(1)), 1.02]);

            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax1, ...
                'Phase Locking Value (Circular Sync R) - 60s Windows', '', 'Phase Lock R');
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax2, ...
                'Phase Lock Rate of Change (Derivative: dR/dt)', '', 'dR/dt (s^{-1})');
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax3, ...
                'Phase Shannon Entropy (Norm H_\phi) - 60s Windows', '', 'Phase Entropy (Norm)');
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax4, ...
                'Phase Entropy Rate of Change (Derivative: d(H_\phi)/dt)', '', 'd(H_\phi)/dt (s^{-1})');
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax5, ...
                'Instantaneous Frequency Lock Fairness - 60s Windows', 'Time (s)', 'Freq Lock Fairness');
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax6, ...
                'Inst. Freq Fairness Rate of Change (Derivative: d(Fairness)/dt)', 'Time (s)', 'd(Fairness)/dt (s^{-1})');

            for ax = all_axes
                lgd = legend(ax, 'Location', 'best');
                scooter_analysis.reporting.PlotGenerator.styleLegend(lgd);
                if max_t > 0
                    xlim(ax, [0, max_t * 1.02]);
                end
            end

            scooter_analysis.reporting.PlotGenerator.safeExport(fig, out_path);
        end


        function rollingPhaseLockDerivativeComparison(varargin)
            % rollingPhaseLockDerivativeComparison - Plot dedicated 3-panel time series of the
            % rate of change (dy/dt) of Phase Locking Value R, Phase Entropy H_phi, and Inst. Freq Fairness.

            if isempty(varargin)
                return;
            end

            [results, out_path] = scooter_analysis.reporting.PlotGenerator.parsePhaseLockRollingInputs(varargin{:});
            if isempty(results)
                return;
            end

            fig = figure('Name', 'Rolling Phase Lock Derivative of Change', ...
                'Position', [100, 100, 1200, 850], 'Color', [0.08 0.11 0.17], 'Visible', 'off');

            ax1 = subplot(3, 1, 1);
            ax2 = subplot(3, 1, 2);
            ax3 = subplot(3, 1, 3);
            all_axes = [ax1, ax2, ax3];

            for ax = all_axes
                hold(ax, 'on');
                yline(ax, 0, '--', 'Color', [0.65 0.70 0.80], 'LineWidth', 1.2, 'Alpha', 0.85, ...
                    'DisplayName', 'Zero Drift (Steady State)');
            end

            plotShadedRegion = @(ax, t_axis, data, color) ...
                scooter_analysis.reporting.PlotGenerator.renderShadedPatch(ax, t_axis, data, color, false, 0.20);

            plotMeanLine = @(ax, t_axis, data, color) ...
                plot(ax, [t_axis(1), t_axis(end)], [mean(data,'omitnan'), mean(data,'omitnan')], ...
                '-', 'Color', color, 'LineWidth', 1.8, 'HandleVisibility', 'off');

            max_t = 0;

            for k = 1:length(results)
                r = results{k};
                if ~isfield(r, 'plv_series') || isempty(r.plv_series)
                    continue;
                end

                bin_t    = r.t_centers;
                bin_plv  = r.plv_series;
                bin_pent = r.phase_ent_series;
                bin_flk  = r.freq_lock_series;

                if isempty(bin_t); continue; end
                max_t = max(max_t, max(bin_t));
                [c, ~] = scooter_analysis.reporting.PlotGenerator.getDatasetColor(r.meta.name, k);

                d_plv  = scooter_analysis.reporting.PlotGenerator.numericalDerivative(bin_t, bin_plv);
                d_pent = scooter_analysis.reporting.PlotGenerator.numericalDerivative(bin_t, bin_pent);
                d_flk  = scooter_analysis.reporting.PlotGenerator.numericalDerivative(bin_t, bin_flk);

                d_plv_sg  = scooter_analysis.reporting.PlotGenerator.applySgolayFilter(d_plv, 2, 15);
                d_pent_sg = scooter_analysis.reporting.PlotGenerator.applySgolayFilter(d_pent, 2, 15);
                d_flk_sg  = scooter_analysis.reporting.PlotGenerator.applySgolayFilter(d_flk, 2, 15);

                plotShadedRegion(ax1, bin_t, d_plv, c);
                plotMeanLine(ax1, bin_t, d_plv, c);
                plot(ax1, bin_t, d_plv, ':', 'Color', [c, 0.35], 'MarkerSize', 4, 'LineWidth', 0.8, ...
                    'DisplayName', sprintf('%s (Raw)', r.meta.name));
                plot(ax1, bin_t, d_plv_sg, '-', 'Color', c, 'LineWidth', 2.0, ...
                    'DisplayName', sprintf('%s (SG-Filtered, μ: %+.1e, σ: %.1e s⁻¹)', r.meta.name, mean(d_plv_sg,'omitnan'), std(d_plv_sg,'omitnan')));

                plotShadedRegion(ax2, bin_t, d_pent, c);
                plotMeanLine(ax2, bin_t, d_pent, c);
                plot(ax2, bin_t, d_pent, ':', 'Color', [c, 0.35], 'MarkerSize', 4, 'LineWidth', 0.8, ...
                    'DisplayName', sprintf('%s (Raw)', r.meta.name));
                plot(ax2, bin_t, d_pent_sg, '-', 'Color', c, 'LineWidth', 2.0, ...
                    'DisplayName', sprintf('%s (SG-Filtered, μ: %+.1e, σ: %.1e s⁻¹)', r.meta.name, mean(d_pent_sg,'omitnan'), std(d_pent_sg,'omitnan')));

                plotShadedRegion(ax3, bin_t, d_flk, c);
                plotMeanLine(ax3, bin_t, d_flk, c);
                plot(ax3, bin_t, d_flk, ':', 'Color', [c, 0.35], 'MarkerSize', 4, 'LineWidth', 0.8, ...
                    'DisplayName', sprintf('%s (Raw)', r.meta.name));
                plot(ax3, bin_t, d_flk_sg, '-', 'Color', c, 'LineWidth', 2.0, ...
                    'DisplayName', sprintf('%s (SG-Filtered, μ: %+.1e, σ: %.1e s⁻¹)', r.meta.name, mean(d_flk_sg,'omitnan'), std(d_flk_sg,'omitnan')));
            end

            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax1, ...
                'Phase Locking Value Rate of Change (Derivative: dR/dt)', '', 'dR/dt (s^{-1})');
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax2, ...
                'Phase Shannon Entropy Rate of Change (Derivative: d(H_\phi)/dt)', '', 'd(H_\phi)/dt (s^{-1})');
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax3, ...
                'Instantaneous Frequency Lock Fairness Rate of Change (Derivative: d(Fairness)/dt)', 'Time (s)', 'd(Fairness)/dt (s^{-1})');

            for ax = all_axes
                lgd = legend(ax, 'Location', 'best');
                scooter_analysis.reporting.PlotGenerator.styleLegend(lgd);
                if max_t > 0
                    xlim(ax, [0, max_t * 1.02]);
                end
            end

            scooter_analysis.reporting.PlotGenerator.safeExport(fig, out_path);
        end


        function binnedPhaseLockDistribution(varargin)
            % binnedPhaseLockDistribution - Plot 2x2 publication-grade figure of 60s Slice
            % Phase Locking Value (R) & Instantaneous Frequency Spread (PLL sigma_f in Hz):
            %   Panel 1: 60s Mean Phase Locking Value (R) Distribution (Normalized) with grouped bars, error bars, KDE & mean lines
            %   Panel 2: 60s Mean PLL Instantaneous Frequency Spread (sigma_f in Hz) Distribution (Normalized)
            %   Panel 3: 60s Slice Phase Locking Value (R) with Shaded ±SD vs Elapsed Time (minutes)
            %   Panel 4: 60s Slice PLL Instantaneous Frequency Spread (Hz) with Shaded ±SD vs Elapsed Time (minutes)
            %
            % Usage:
            %   PlotGenerator.binnedPhaseLockDistribution({ba_h, ba_c, ba_auv}, out_path)

            if isempty(varargin)
                return;
            end

            out_path = '';
            last_arg = varargin{end};
            if (ischar(last_arg) && isrow(last_arg)) || (isstring(last_arg) && isscalar(last_arg))
                out_path = char(last_arg);
                items = varargin(1:end-1);
            else
                items = varargin;
            end

            bin_dur_sec = 60.0;
            if ~isempty(items) && isnumeric(items{end}) && isscalar(items{end})
                bin_dur_sec = items{end};
                items = items(1:end-1);
            end

            if length(items) == 1 && iscell(items{1})
                items = items{1};
            end

            binned_datasets = scooter_analysis.reporting.PlotGenerator.extractBinnedPhaseLockDatasets(items, bin_dur_sec);
            num_ds = length(binned_datasets);
            if num_ds < 1
                fprintf('[PlotGenerator] No binned phase lock data available to plot.\n');
                return;
            end

            vis_state = 'off';
            if isempty(out_path)
                vis_state = 'on';
            end

            fig = figure('Name', sprintf('Phase Lock (R) & Instantaneous Frequency Verification (%ds Slices)', round(bin_dur_sec)), ...
                'Position', [60, 60, 1400, 850], 'Color', [0.08 0.11 0.17], 'Visible', vis_state);

            % --- Subplot 1: 60s Mean Phase Locking Value (R) Distribution ---
            ax1 = subplot(2, 2, 1);
            hold(ax1, 'on');

            num_bins_plv = 14;
            plv_edges = linspace(0.0, 1.0, num_bins_plv + 1);
            plv_centers = (plv_edges(1:end-1) + plv_edges(2:end)) / 2;

            P_plv = zeros(num_bins_plv, num_ds);
            err_low_plv = zeros(num_bins_plv, num_ds);
            err_up_plv  = zeros(num_bins_plv, num_ds);

            for k = 1:num_ds
                ds = binned_datasets{k};
                N_k = length(ds.plv_means);
                counts = histcounts(ds.plv_means, plv_edges);
                probs = counts / max(1, N_k);
                sigma_bar = sqrt(probs .* (1 - probs) ./ max(1, N_k));
                P_plv(:, k) = probs(:);
                err_low_plv(:, k) = min(probs(:), sigma_bar(:));
                err_up_plv(:, k)  = sigma_bar(:);
            end

            if num_ds == 1
                b1 = bar(ax1, plv_centers, P_plv, 'BarWidth', 0.95);
            else
                b1 = bar(ax1, plv_centers, P_plv, 'grouped', 'BarWidth', 0.95);
            end

            for k = 1:num_ds
                ds = binned_datasets{k};
                [c, ec] = scooter_analysis.reporting.PlotGenerator.getDatasetColor(ds.name, k);

                b1(k).FaceColor = c;
                b1(k).EdgeColor = ec;
                b1(k).FaceAlpha = 0.60;
                b1(k).DisplayName = sprintf('%s (N=%d slices)', ds.name, length(ds.plv_means));

                x_pos = b1(k).XEndPoints;
                y_pos = b1(k).YData;
                valid_bars = (y_pos > 0);
                if any(valid_bars)
                    errorbar(ax1, x_pos(valid_bars), y_pos(valid_bars), ...
                        err_low_plv(valid_bars, k)', err_up_plv(valid_bars, k)', ...
                        'LineStyle', 'none', 'Color', ec, 'LineWidth', 1.3, 'CapSize', 4, ...
                        'HandleVisibility', 'off');
                end

                if length(ds.plv_means) >= 4
                    try
                        [f_kde, xi_kde] = ksdensity(ds.plv_means, 'Support', [0, 1]);
                        max_p = max(P_plv(:, k));
                        max_f = max(f_kde);
                        if max_f > 0 && max_p > 0
                            f_kde_norm = f_kde * (max_p / max_f);
                        else
                            f_kde_norm = f_kde;
                        end
                        plot(ax1, xi_kde, f_kde_norm, '-', 'Color', ec, 'LineWidth', 2, 'HandleVisibility', 'off');
                    catch
                    end
                end

                m_val = mean(ds.plv_means, 'omitnan');
                within_sd = mean(ds.plv_stds, 'omitnan');
                macro_sd  = std(ds.plv_means, 'omitnan');
                xline(ax1, m_val, '--', 'Color', ec, 'LineWidth', 1.8, ...
                    'DisplayName', sprintf('%s Mean R: %.2f ± %.2f (std: %.2f)', ds.name, m_val, within_sd, macro_sd));
            end

            max_p_plv = max(P_plv(:));
            if max_p_plv <= 0; max_p_plv = 0.5; end
            ylim(ax1, [0, min(1.0, max_p_plv * 1.18 + 0.05)]);
            xlim(ax1, [0, 1.02]);

            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax1, ...
                sprintf('%ds Mean Phase Locking Value (R) Distribution (Normalized)', round(bin_dur_sec)), ...
                sprintf('Mean Phase Locking Value R per %ds Slice', round(bin_dur_sec)), ...
                'Normalized Probability');
            lgd1 = legend(ax1, 'Location', 'best');
            scooter_analysis.reporting.PlotGenerator.styleLegend(lgd1);

            % --- Subplot 2: 60s Mean PLL Instantaneous Frequency Spread Distribution ---
            ax2 = subplot(2, 2, 2);
            hold(ax2, 'on');

            all_fstd_concat = [];
            for k = 1:num_ds
                all_fstd_concat = [all_fstd_concat; binned_datasets{k}.freq_std_means(:)];
            end
            all_fstd_concat = all_fstd_concat(isfinite(all_fstd_concat));
            if isempty(all_fstd_concat); all_fstd_concat = [0; 10]; end

            min_fstd = max(0, min(all_fstd_concat) * 0.85);
            max_fstd = max(all_fstd_concat) * 1.10;
            if max_fstd <= min_fstd; max_fstd = min_fstd + 5.0; end
            num_fstd_bins = min(16, max(8, round(sqrt(length(all_fstd_concat)) / 1.1)));
            fstd_edges = linspace(min_fstd, max_fstd, num_fstd_bins + 1);
            fstd_centers = (fstd_edges(1:end-1) + fstd_edges(2:end)) / 2;

            P_fstd = zeros(num_fstd_bins, num_ds);
            err_low_fstd = zeros(num_fstd_bins, num_ds);
            err_up_fstd  = zeros(num_fstd_bins, num_ds);

            for k = 1:num_ds
                ds = binned_datasets{k};
                N_k = length(ds.freq_std_means);
                counts = histcounts(ds.freq_std_means, fstd_edges);
                probs = counts / max(1, N_k);
                sigma_bar = sqrt(probs .* (1 - probs) ./ max(1, N_k));
                P_fstd(:, k) = probs(:);
                err_low_fstd(:, k) = min(probs(:), sigma_bar(:));
                err_up_fstd(:, k)  = sigma_bar(:);
            end

            if num_ds == 1
                b2 = bar(ax2, fstd_centers, P_fstd, 'BarWidth', 0.95);
            else
                b2 = bar(ax2, fstd_centers, P_fstd, 'grouped', 'BarWidth', 0.95);
            end

            for k = 1:num_ds
                ds = binned_datasets{k};
                [c, ec] = scooter_analysis.reporting.PlotGenerator.getDatasetColor(ds.name, k);

                b2(k).FaceColor = c;
                b2(k).EdgeColor = ec;
                b2(k).FaceAlpha = 0.60;
                b2(k).DisplayName = sprintf('%s (N=%d slices)', ds.name, length(ds.freq_std_means));

                x_pos = b2(k).XEndPoints;
                y_pos = b2(k).YData;
                valid_bars = (y_pos > 0);
                if any(valid_bars)
                    errorbar(ax2, x_pos(valid_bars), y_pos(valid_bars), ...
                        err_low_fstd(valid_bars, k)', err_up_fstd(valid_bars, k)', ...
                        'LineStyle', 'none', 'Color', ec, 'LineWidth', 1.3, 'CapSize', 4, ...
                        'HandleVisibility', 'off');
                end

                if length(ds.freq_std_means) >= 4
                    try
                        [f_kde, xi_kde] = ksdensity(ds.freq_std_means);
                        max_p = max(P_fstd(:, k));
                        max_f = max(f_kde);
                        if max_f > 0 && max_p > 0
                            f_kde_norm = f_kde * (max_p / max_f);
                        else
                            f_kde_norm = f_kde;
                        end
                        plot(ax2, xi_kde, f_kde_norm, '-', 'Color', ec, 'LineWidth', 2, 'HandleVisibility', 'off');
                    catch
                    end
                end

                m_fstd = mean(ds.freq_std_means, 'omitnan');
                within_fstd = mean(ds.freq_std_stds, 'omitnan');
                macro_fstd  = std(ds.freq_std_means, 'omitnan');
                xline(ax2, m_fstd, '--', 'Color', ec, 'LineWidth', 1.8, ...
                    'DisplayName', sprintf('%s Mean σ_f: %.1f ± %.1f Hz (std: %.1f)', ds.name, m_fstd, within_fstd, macro_fstd));
            end

            max_p_fstd = max(P_fstd(:));
            if max_p_fstd <= 0; max_p_fstd = 0.5; end
            ylim(ax2, [0, min(1.0, max_p_fstd * 1.18 + 0.05)]);

            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax2, ...
                sprintf('%ds PLL Instantaneous Frequency Spread (\\sigma_f) Distribution', round(bin_dur_sec)), ...
                sprintf('Mean PLL Inst. Freq Spread \\sigma_f per %ds Slice (Hz)', round(bin_dur_sec)), ...
                'Normalized Probability');
            lgd2 = legend(ax2, 'Location', 'best');
            scooter_analysis.reporting.PlotGenerator.styleLegend(lgd2);

            % --- Subplot 3: 60s Slice Phase Locking Value (R) with Shaded ±SD vs Time ---
            ax3 = subplot(2, 2, 3);
            hold(ax3, 'on');

            for k = 1:num_ds
                ds = binned_datasets{k};
                [c, ~] = scooter_analysis.reporting.PlotGenerator.getDatasetColor(ds.name, k);
                t_min = ds.slice_times(:)' / 60;
                y_row = ds.plv_means(:)';
                err_row = ds.plv_stds(:)';

                valid_mask = isfinite(t_min) & isfinite(y_row) & isfinite(err_row);
                t_v = t_min(valid_mask);
                y_v = y_row(valid_mask);
                e_v = err_row(valid_mask);

                if ~isempty(t_v)
                    upper_b = min(1.0, y_v + e_v);
                    lower_b = max(0.0, y_v - e_v);
                    patch(ax3, [t_v, fliplr(t_v)], [upper_b, fliplr(lower_b)], ...
                        c, 'FaceAlpha', 0.20, 'EdgeColor', 'none', 'HandleVisibility', 'off');
                    plot(ax3, t_v, y_v, '.-', 'Color', [c, 0.90], 'MarkerSize', 8, 'LineWidth', 1.2, ...
                        'DisplayName', sprintf('%s (Mean R: %.2f ± %.2f)', ds.name, mean(y_v), mean(e_v)));
                end
            end
            ylim(ax3, [0, 1.05]);

            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax3, ...
                sprintf('%ds Slice Mean Phase Locking Value (R) with Shaded ±SD', round(bin_dur_sec)), ...
                'Elapsed Time (minutes)', 'Phase Locking Value R ± SD');
            lgd3 = legend(ax3, 'Location', 'best');
            scooter_analysis.reporting.PlotGenerator.styleLegend(lgd3);

            % --- Subplot 4: 60s Slice PLL Instantaneous Frequency Spread with Shaded ±SD vs Time ---
            ax4 = subplot(2, 2, 4);
            hold(ax4, 'on');

            for k = 1:num_ds
                ds = binned_datasets{k};
                [c, ~] = scooter_analysis.reporting.PlotGenerator.getDatasetColor(ds.name, k);
                t_min = ds.slice_times(:)' / 60;
                y_row = ds.freq_std_means(:)';
                err_row = ds.freq_std_stds(:)';

                valid_mask = isfinite(t_min) & isfinite(y_row) & isfinite(err_row);
                t_v = t_min(valid_mask);
                y_v = y_row(valid_mask);
                e_v = err_row(valid_mask);

                if ~isempty(t_v)
                    upper_b = y_v + e_v;
                    lower_b = max(0.0, y_v - e_v);
                    patch(ax4, [t_v, fliplr(t_v)], [upper_b, fliplr(lower_b)], ...
                        c, 'FaceAlpha', 0.20, 'EdgeColor', 'none', 'HandleVisibility', 'off');
                    plot(ax4, t_v, y_v, '.-', 'Color', [c, 0.90], 'MarkerSize', 8, 'LineWidth', 1.2, ...
                        'DisplayName', sprintf('%s (Mean σ_f: %.1f ± %.1f Hz)', ds.name, mean(y_v), mean(e_v)));
                    yline(ax4, mean(y_v), ':', 'Color', c, 'LineWidth', 1.5, 'HandleVisibility', 'off');
                end
            end

            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax4, ...
                sprintf('%ds Slice PLL Instantaneous Frequency Spread (\\sigma_f) with Shaded ±SD', round(bin_dur_sec)), ...
                'Elapsed Time (minutes)', 'PLL Inst. Freq Spread \sigma_f ± SD (Hz)');
            lgd4 = legend(ax4, 'Location', 'best');
            scooter_analysis.reporting.PlotGenerator.styleLegend(lgd4);

            if ~isempty(out_path)
                scooter_analysis.reporting.PlotGenerator.safeExport(fig, out_path);
            end
        end


        function binnedInstFreqVerification(varargin)
            % binnedInstFreqVerification - Plot 2x2 publication-grade figure of 60s Slice
            % PLL Instantaneous Frequency Verification Error |f_PLL - f_FFT| (Hz) & SD across slices.
            % Directly mirrors binnedBandwidthDistribution for instantaneous frequency verification.

            if isempty(varargin)
                return;
            end

            out_path = '';
            last_arg = varargin{end};
            if (ischar(last_arg) && isrow(last_arg)) || (isstring(last_arg) && isscalar(last_arg))
                out_path = char(last_arg);
                items = varargin(1:end-1);
            else
                items = varargin;
            end

            bin_dur_sec = 60.0;
            if ~isempty(items) && isnumeric(items{end}) && isscalar(items{end})
                bin_dur_sec = items{end};
                items = items(1:end-1);
            end

            if length(items) == 1 && iscell(items{1})
                items = items{1};
            end

            binned_datasets = scooter_analysis.reporting.PlotGenerator.extractBinnedPhaseLockDatasets(items, bin_dur_sec);
            num_ds = length(binned_datasets);
            if num_ds < 1
                fprintf('[PlotGenerator] No binned instantaneous frequency verification data available.\n');
                return;
            end

            % Build adapter structs so binnedBandwidthDistribution-style 4-panel layout renders
            % the PLL Instantaneous Frequency Spread (2 * sigma_f in Hz) & its SD across 60s slices
            adapted = cell(1, num_ds);
            for k = 1:num_ds
                ds = binned_datasets{k};
                ad = struct();
                ad.meta.name   = ds.name;
                ad.slice_means = ds.freq_std_means;
                ad.slice_stds  = ds.freq_std_stds;
                ad.slice_sems  = ds.freq_std_sems;
                ad.slice_times = ds.slice_times;
                adapted{k} = ad;
            end

            vis_state = 'off';
            if isempty(out_path); vis_state = 'on'; end

            fig = figure('Name', sprintf('PLL Instantaneous Frequency Spread (%ds Slices) & SD', round(bin_dur_sec)), ...
                'Position', [60, 60, 1400, 850], 'Color', [0.08 0.11 0.17], 'Visible', vis_state);

            ax1 = subplot(2, 2, 1); hold(ax1, 'on');
            ax2 = subplot(2, 2, 2); hold(ax2, 'on');
            ax3 = subplot(2, 2, 3); hold(ax3, 'on');
            ax4 = subplot(2, 2, 4); hold(ax4, 'on');

            all_means_concat = [];
            all_err_concat   = [];
            for k = 1:num_ds
                all_means_concat = [all_means_concat; adapted{k}.slice_means(:)];
                all_err_concat   = [all_err_concat; adapted{k}.slice_stds(:)];
            end
            all_means_concat = all_means_concat(isfinite(all_means_concat));
            all_err_concat   = all_err_concat(isfinite(all_err_concat));

            min_v = max(0, min(all_means_concat) - 1);
            max_v = max(all_means_concat) + 1;
            if max_v <= min_v; max_v = min_v + 5; end
            num_bins = min(16, max(8, round(sqrt(length(all_means_concat)) / 1.2)));
            bin_edges = linspace(min_v, max_v, num_bins + 1);
            bin_centers = (bin_edges(1:end-1) + bin_edges(2:end)) / 2;

            P_mat = zeros(num_bins, num_ds);
            el_mat = zeros(num_bins, num_ds);
            eu_mat = zeros(num_bins, num_ds);
            for k = 1:num_ds
                N_k = length(adapted{k}.slice_means);
                counts = histcounts(adapted{k}.slice_means, bin_edges);
                probs = counts / max(1, N_k);
                sig_b = sqrt(probs .* (1 - probs) ./ max(1, N_k));
                P_mat(:, k)  = probs(:);
                el_mat(:, k) = min(probs(:), sig_b(:));
                eu_mat(:, k) = sig_b(:);
            end

            if num_ds == 1
                b = bar(ax1, bin_centers, P_mat, 'BarWidth', 0.95);
            else
                b = bar(ax1, bin_centers, P_mat, 'grouped', 'BarWidth', 0.95);
            end

            min_err = max(0, min(all_err_concat) * 0.8);
            max_err = max(all_err_concat) * 1.05;
            if max_err <= min_err; max_err = min_err + 2.0; end
            err_edges = linspace(min_err, max_err, min(20, max(8, round(sqrt(length(all_err_concat))))) + 1);

            for k = 1:num_ds
                ds = adapted{k};
                [c, ec] = scooter_analysis.reporting.PlotGenerator.getDatasetColor(ds.meta.name, k);

                b(k).FaceColor = c;
                b(k).EdgeColor = ec;
                b(k).FaceAlpha = 0.60;
                b(k).DisplayName = sprintf('%s (N=%d slices)', ds.meta.name, length(ds.slice_means));

                x_pos = b(k).XEndPoints;
                y_pos = b(k).YData;
                vb = (y_pos > 0);
                if any(vb)
                    errorbar(ax1, x_pos(vb), y_pos(vb), el_mat(vb, k)', eu_mat(vb, k)', ...
                        'LineStyle', 'none', 'Color', ec, 'LineWidth', 1.3, 'CapSize', 4, 'HandleVisibility', 'off');
                end

                if length(ds.slice_means) >= 4
                    try
                        [f_kde, xi_kde] = ksdensity(ds.slice_means);
                        max_p = max(P_mat(:, k));
                        max_f = max(f_kde);
                        if max_f > 0 && max_p > 0
                            plot(ax1, xi_kde, f_kde * (max_p / max_f), '-', 'Color', ec, 'LineWidth', 2, 'HandleVisibility', 'off');
                        end
                    catch
                    end
                end

                m_val = mean(ds.slice_means, 'omitnan');
                within_sd = mean(ds.slice_stds, 'omitnan');
                macro_sd  = std(ds.slice_means, 'omitnan');
                xline(ax1, m_val, '--', 'Color', ec, 'LineWidth', 1.8, ...
                    'DisplayName', sprintf('%s Mean: %.1f ± %.1f Hz (std: %.1f)', ds.meta.name, m_val, within_sd, macro_sd));

                % Subplot 2: SD histogram
                histogram(ax2, min(ds.slice_stds, max_err), err_edges, 'Normalization', 'probability', ...
                    'FaceColor', c, 'EdgeColor', ec, 'FaceAlpha', 0.60, ...
                    'DisplayName', sprintf('%s (Avg SD: %.2f Hz)', ds.meta.name, within_sd));
                xline(ax2, within_sd, '--', 'Color', ec, 'LineWidth', 1.8, ...
                    'DisplayName', sprintf('%s Avg SD: %.2f Hz', ds.meta.name, within_sd));

                % Subplot 3: Mean ± SD vs Time
                t_min = ds.slice_times(:)' / 60;
                y_row = ds.slice_means(:)';
                e_row = ds.slice_stds(:)';
                vm = isfinite(t_min) & isfinite(y_row) & isfinite(e_row);
                if any(vm)
                    tv = t_min(vm); yv = y_row(vm); ev = e_row(vm);
                    patch(ax3, [tv, fliplr(tv)], [yv + ev, fliplr(max(0, yv - ev))], ...
                        c, 'FaceAlpha', 0.20, 'EdgeColor', 'none', 'HandleVisibility', 'off');
                    plot(ax3, tv, yv, '.-', 'Color', [c, 0.90], 'MarkerSize', 8, 'LineWidth', 1.2, ...
                        'DisplayName', sprintf('%s (Mean: %.1f Hz)', ds.meta.name, mean(yv)));
                end

                % Subplot 4: SD vs Time
                plot(ax4, t_min, ds.slice_stds, '.-', 'Color', c, 'LineWidth', 1.2, ...
                    'MarkerSize', 10, 'DisplayName', sprintf('%s (Avg SD: %.2f Hz)', ds.meta.name, within_sd));
                yline(ax4, within_sd, ':', 'Color', c, 'LineWidth', 1.5, 'HandleVisibility', 'off');
            end

            ylim(ax1, [0, min(1.0, max(P_mat(:)) * 1.15 + 0.05)]);
            ylim(ax2, [0, 1.05]);

            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax1, ...
                sprintf('%ds Mean PLL Inst. Frequency Spread Distribution (Normalized)', round(bin_dur_sec)), ...
                sprintf('Mean PLL Inst. Freq Spread \\sigma_f per %ds Slice (Hz)', round(bin_dur_sec)), ...
                'Normalized Probability');
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax2, ...
                sprintf('Standard Deviation Distribution Across %ds Slices (Normalized)', round(bin_dur_sec)), ...
                'Standard Deviation SD (Hz)', 'Normalized Probability');
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax3, ...
                sprintf('%ds Slice Mean PLL Inst. Frequency Spread with Shaded ±SD', round(bin_dur_sec)), ...
                'Elapsed Time (minutes)', 'Mean PLL Freq Spread \sigma_f ± SD (Hz)');
            scooter_analysis.reporting.PlotGenerator.applyAxesStyle(ax4, ...
                sprintf('Standard Deviation for Each %ds Slice', round(bin_dur_sec)), ...
                'Elapsed Time (minutes)', 'Standard Deviation SD (Hz)');

            for ax = [ax1, ax2, ax3, ax4]
                lgd = legend(ax, 'Location', 'best');
                scooter_analysis.reporting.PlotGenerator.styleLegend(lgd);
            end

            if ~isempty(out_path)
                scooter_analysis.reporting.PlotGenerator.safeExport(fig, out_path);
            end
        end
    end


    methods (Static, Access = private)
        function safeExport(fig, out_path)
            % Export figure to file and close it.  Create parent dirs if needed.
            out_dir = fileparts(out_path);
            if ~exist(out_dir, 'dir')
                mkdir(out_dir);
            end
            try
                exportgraphics(fig, out_path, 'Resolution', 300, 'BackgroundColor', 'current');
            catch ME
                fprintf('[PlotGenerator] Export failed for %s: %s\n', out_path, ME.message);
            end
            close(fig);
        end

        function [results, out_dir] = parseVisualizerInputs(varargin)
            % Normalize varied input arguments into a cell array of Visualizer result structs
            % and an output directory string.
            results = {};
            out_dir = '';

            if isempty(varargin)
                return;
            end

            % Check if the last argument is a character vector or string scalar specifying out_dir
            last_arg = varargin{end};
            if (ischar(last_arg) && isrow(last_arg)) || (isstring(last_arg) && isscalar(last_arg))
                out_dir = char(last_arg);
                items = varargin(1:end-1);
            else
                items = varargin;
            end

            % If single cell array was passed (e.g. {ba_auv} or {ba_h, ba_c})
            if length(items) == 1 && iscell(items{1})
                items = items{1};
            end

            if numel(items) == 1 && isa(items{1}, 'scooter_analysis.pipeline.BatchAnalyzer') && length(items{1}.FileResults) > 1
                results = items{1}.getFileVisualizerResults();
            else
                for i = 1:numel(items)
                    results = scooter_analysis.reporting.PlotGenerator.extractVisualizerResults(results, items{i});
                end
            end

            if isempty(out_dir)
                out_dir = fullfile(pwd, 'outputs');
            end
        end

        function [freqs, bws, name] = extractHistogramData(item)
            if isa(item, 'scooter_analysis.pipeline.BatchAnalyzer')
                name = item.DatasetName;
                freqs = item.getAllDomFreqs();
                bws = item.getAllBandwidths();
            elseif isa(item, 'scooter_analysis.results.FileResult')
                name = item.filename;
                freqs = item.dom_freqs;
                bws = item.bw_vals;
            elseif isstruct(item)
                if isfield(item, 'meta') && isfield(item.meta, 'name')
                    name = item.meta.name;
                else
                    name = 'Signal';
                end
                if isfield(item, 'slice_bw') && isfield(item.slice_bw, 'all_main_bws')
                    bws = item.slice_bw.all_main_bws;
                else
                    bws = [];
                end
                if isfield(item, 'dom_lobe') && isfield(item.dom_lobe, 'peak_freq')
                    freqs = item.dom_lobe.peak_freq;
                else
                    freqs = [];
                end
            else
                name = 'Unknown';
                freqs = [];
                bws = [];
            end
        end

        function results = extractVisualizerResults(results, item)
            if isempty(item)
                return;
            elseif iscell(item)
                for k = 1:numel(item)
                    results = scooter_analysis.reporting.PlotGenerator.extractVisualizerResults(results, item{k});
                end
            elseif isa(item, 'scooter_analysis.pipeline.BatchAnalyzer')
                if ~isempty(item.FileResults)
                    results{end+1} = item.getVisualizerResult();
                end
            elseif isa(item, 'scooter_analysis.results.FileResult')
                results{end+1} = item.getVisualizerResult();
            elseif isstruct(item)
                if isfield(item, 'meta') || isfield(item, 'f_grid')
                    results{end+1} = item;
                end
            end
        end

        function [results, out_path] = parsePhaseLockRollingInputs(varargin)
            results = {};
            out_path = '';
            if isempty(varargin)
                return;
            end
            last_arg = varargin{end};
            if (ischar(last_arg) && isrow(last_arg)) || (isstring(last_arg) && isscalar(last_arg))
                out_path = char(last_arg);
                items = varargin(1:end-1);
            else
                items = varargin;
            end
            if length(items) == 1 && iscell(items{1})
                items = items{1};
            end
            for i = 1:numel(items)
                it = items{i};
                if isa(it, 'scooter_analysis.pipeline.BatchAnalyzer')
                    results{end+1} = it.getRollingPhaseLockResult(60.0);
                elseif isa(it, 'scooter_analysis.results.FileResult')
                    results{end+1} = it.getRollingPhaseLockResult(60.0);
                elseif isstruct(it)
                    if isfield(it, 'plv_series')
                        results{end+1} = it;
                    elseif isfield(it, 'pll_result') && isfield(it.pll_result, 'all_slice_plv')
                        [t_c, plv_s, ent_s, fair_s] = BandwidthTracker.compute_rolling_phase_stability( ...
                            it.pll_result.all_slice_plv, it.pll_result.all_slice_mean_phases, ...
                            it.pll_result.all_slice_inst_freq_stds, 0.500, 60.0, 5.0, 0.500);
                        r_s = struct('meta', it.meta, 'window_sec', 60.0, ...
                            't_centers', t_c, 'plv_series', plv_s, ...
                            'phase_ent_series', ent_s, 'freq_fair_series', fair_s);
                        results{end+1} = r_s;
                    end
                end
            end
        end

        function binned_datasets = extractBinnedPhaseLockDatasets(items, bin_dur_sec)
            binned_datasets = {};
            for i = 1:numel(items)
                item = items{i};
                if isempty(item); continue; end
                ds = struct();
                if isa(item, 'scooter_analysis.pipeline.BatchAnalyzer')
                    r = item.getBinnedPhaseLockResult(bin_dur_sec);
                    ds = r;
                    ds.name = item.DatasetName;
                elseif isa(item, 'scooter_analysis.results.FileResult')
                    r = item.getBinnedPhaseLockResult(bin_dur_sec);
                    ds = r;
                    ds.name = item.filename;
                elseif isstruct(item)
                    if isfield(item, 'meta') && isfield(item.meta, 'name')
                        ds.name = item.meta.name;
                    elseif isfield(item, 'name')
                        ds.name = item.name;
                    else
                        ds.name = sprintf('Dataset %d', i);
                    end

                    if isfield(item, 'plv_means') && isfield(item, 'freq_std_means')
                        ds.plv_means      = item.plv_means;
                        ds.plv_stds       = item.plv_stds;
                        ds.plv_sems       = item.plv_sems;
                        ds.freq_std_means = item.freq_std_means;
                        ds.freq_std_stds  = item.freq_std_stds;
                        ds.freq_std_sems  = item.freq_std_sems;
                        ds.verif_means    = item.verif_means;
                        ds.verif_stds     = item.verif_stds;
                        ds.slice_times    = item.slice_times;
                    elseif isfield(item, 'pll_result') && isfield(item.pll_result, 'all_slice_plv')
                        [ds.plv_means, ds.plv_sems, ds.slice_times, ds.plv_stds, ...
                            ds.freq_std_means, ds.freq_std_sems, ds.freq_std_stds, ...
                            ds.verif_means, ds.verif_stds] = ...
                            BandwidthTracker.compute_binned_phase_lock( ...
                            item.pll_result.all_slice_plv, ...
                            item.pll_result.all_slice_inst_freq_stds, ...
                            item.pll_result.all_slice_phase_stds, ...
                            item.pll_result.all_slice_freq_verif_errs, ...
                            0.500, bin_dur_sec);
                    else
                        continue;
                    end
                else
                    continue;
                end

                valid_mask = isfinite(ds.plv_means) & ds.plv_means >= 0;
                ds.plv_means      = ds.plv_means(valid_mask);
                ds.plv_stds       = ds.plv_stds(valid_mask);
                ds.plv_sems       = ds.plv_sems(valid_mask);
                ds.freq_std_means = ds.freq_std_means(valid_mask);
                ds.freq_std_stds  = ds.freq_std_stds(valid_mask);
                ds.freq_std_sems  = ds.freq_std_sems(valid_mask);
                if isfield(ds, 'verif_means') && length(ds.verif_means) == length(valid_mask)
                    ds.verif_means = ds.verif_means(valid_mask);
                    ds.verif_stds  = ds.verif_stds(valid_mask);
                end
                ds.slice_times    = ds.slice_times(valid_mask);

                if ~isempty(ds.plv_means)
                    binned_datasets{end+1} = ds;
                end
            end
        end
    end
end
