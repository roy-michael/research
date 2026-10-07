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

        function freqBandwidthTimeSeries(fr, out_dir)
            % Plot dominant frequency and bandwidth over time for one file.
            %
            % Args:
            %   fr      - A scooter_analysis.results.FileResult object
            %   out_dir - Directory to save the plot

            if isempty(fr.dom_freqs)
                return;
            end

            fig = figure('Name', 'Freq & BW Over Time', ...
                'Position', [50, 100, 1800, 500], 'Color', 'w', 'Visible', 'off');

            yyaxis left
            plot(fr.time_centers_abs, fr.dom_freqs, '.', 'MarkerSize', 8, 'Color', [0.2 0.5 0.8]);
            ylabel('Dominant Frequency (Hz)');

            yyaxis right
            plot(fr.time_centers_abs, fr.bw_vals, '-', 'LineWidth', 1.5, 'Color', [0.8 0.2 0.2 0.5]);
            ylabel('Bandwidth (Hz)');
            ylim([0, max(max(fr.bw_vals)*1.2, 50)]);

            grid on;
            datetick('x', 'HH:MM', 'keepticks', 'keeplimits');
            xlabel('Time (UTC)');
            title(sprintf('Signal Tracking – %s', fr.filename));

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

            fig = figure('Name', 'Overall Distributions', ...
                'Position', [100, 100, 1200, 500], 'Color', 'w', 'Visible', 'off');

            subplot(1, 2, 1);
            histogram(all_freqs, 'BinWidth', 50);
            title(sprintf('Dominant Frequency Distribution (%s)', analyzer.DatasetName));
            xlabel('Dominant Frequency (Hz)');
            ylabel('Count');
            grid on;

            subplot(1, 2, 2);
            histogram(all_bws, 20);
            title(sprintf('Bandwidth Distribution (%s)', analyzer.DatasetName));
            xlabel('Bandwidth (Hz)');
            ylabel('Count');
            grid on;

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
                'Position', [50, 50, 1800, 600], 'Color', 'w', 'Visible', 'off');

            % Median-subtract to highlight transient events
            median_profile = median(psd_matrix, 2);
            ltsa_clean = bsxfun(@minus, psd_matrix, median_profile);
            ltsa_clean(ltsa_clean < 0) = 0;
            p_max = prctile(ltsa_clean(:), 99.5);

            imagesc(times, f_grid, ltsa_clean);
            axis xy;
            caxis([0, max(p_max, 1)]);
            colormap jet;
            c = colorbar;
            c.Label.String = 'Relative Power (dB)';
            datetick('x', 'mm-dd HH:MM', 'keepticks', 'keeplimits');
            title(sprintf('Long-Term Spectrogram – %s', analyzer.DatasetName));
            xlabel('Time (UTC)');
            ylabel('Frequency (Hz)');

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
                'Position', [50, 50, 1800, 600], 'Color', 'w', 'Visible', 'off');
            imagesc(t_absolute, f_band, p_db_clean);
            axis xy;
            caxis([0, p_max]);
            colormap jet;
            ylim([cfg.f_low, cfg.f_high]);
            c = colorbar;
            c.Label.String = 'Relative Power (dB above median)';
            datetick('x', 'HH:MM', 'keepticks', 'keeplimits');
            title(sprintf('Spectrogram (Start: %s UTC)', datestr(base_time, 'yyyy-mm-dd HH:MM:SS')));
            xlabel('Time (UTC)');
            ylabel('Frequency (Hz)');

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

            fig = figure('Name', 'Dataset Comparison', ...
                'Position', [100, 100, 1200, 500], 'Color', 'w', 'Visible', 'off');

            % Dominant Frequency
            subplot(1, 2, 1);
            hold on;
            histogram(a_freqs, 'BinWidth', 50, 'Normalization', 'probability', ...
                'FaceColor', [0.2 0.6 0.8], 'EdgeColor', 'none', 'FaceAlpha', 0.6);
            histogram(b_freqs, 'BinWidth', 50, 'Normalization', 'probability', ...
                'FaceColor', [0.8 0.3 0.3], 'EdgeColor', 'none', 'FaceAlpha', 0.6);
            title('Dominant Frequency (Normalised)');
            xlabel('Dominant Frequency (Hz)');
            ylabel('Probability');
            legend(nameA, nameB, 'Interpreter', 'none');
            grid on;

            % Bandwidth
            subplot(1, 2, 2);
            hold on;
            valid_a_bws = a_bws(isfinite(a_bws) & a_bws > 0);
            valid_b_bws = b_bws(isfinite(b_bws) & b_bws > 0);
            bw_max = max([valid_a_bws(:); valid_b_bws(:); 50]);
            bw_edges = 0:2:bw_max;
            if isempty(bw_edges); bw_edges = 0:2:100; end
            histogram(valid_a_bws, bw_edges, 'Normalization', 'probability', ...
                'FaceColor', [0.2 0.6 0.8], 'EdgeColor', 'none', 'FaceAlpha', 0.6);
            histogram(valid_b_bws, bw_edges, 'Normalization', 'probability', ...
                'FaceColor', [0.8 0.3 0.3], 'EdgeColor', 'none', 'FaceAlpha', 0.6);
            title('Bandwidth (Normalised)');
            xlabel('Bandwidth (Hz)');
            ylabel('Probability');
            legend(nameA, nameB, 'Interpreter', 'none');
            grid on;

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
                'Position', [100, 100, 900, 500], 'Color', 'w', 'Visible', 'off');
            hold on; grid on;

            colors = [
                0.2 0.6 0.8;
                0.8 0.3 0.3;
                0.3 0.8 0.4;
                0.8 0.6 0.2;
                0.6 0.3 0.8
                ];

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

                c = colors(mod(k-1, size(colors, 1)) + 1, :);
                histogram(fair_vals, edges, 'Normalization', 'probability', ...
                    'FaceColor', c, 'EdgeColor', 'none', 'FaceAlpha', 0.6);

                legend_entries{end+1} = sprintf('%s (Mean J=%.3f)', r.meta.name, mean(fair_vals));
            end

            title(sprintf('Jain''s Fairness Index Distribution (%ds Rolling Window)', win_sec), ...
                'FontSize', 12, 'FontWeight', 'bold');
            xlabel('Jain''s Fairness Index', 'FontSize', 10, 'FontWeight', 'bold');
            ylabel('Probability', 'FontSize', 10, 'FontWeight', 'bold');
            if ~isempty(legend_entries)
                legend(legend_entries, 'Location', 'northwest', 'Interpreter', 'none');
            end
            xlim([0, 1.02]);

            scooter_analysis.reporting.PlotGenerator.safeExport(fig, out_path);
        end

        function rollingFairnessComparison(varargin)
            % rollingFairnessComparison - Plot rolling fairness time series with mean and variance guides.
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

            fig = figure('Name', 'Rolling Fairness Comparison', ...
                'Position', [100, 100, 1200, 800], 'Color', 'w', 'Visible', 'off');

            colors = [
                0.2 0.6 0.8;
                0.8 0.3 0.3;
                0.3 0.8 0.4;
                0.8 0.6 0.2;
                0.6 0.3 0.8
                ];

            subplot(3,1,1); hold on; grid on; title('Time-in-Band (TiB) - 60s Windows'); ylabel('TiB Ratio');
            subplot(3,1,2); hold on; grid on; title('Shannon Entropy (Norm) - 60s Windows'); ylabel('Entropy');
            subplot(3,1,3); hold on; grid on; title('Jain''s Fairness Index - 60s Windows'); ylabel('Fairness'); xlabel('Time (s)');

            for k = 1:length(results)
                r = results{k};
                if ~isfield(r, 'tib_series') || isempty(r.tib_series)
                    continue;
                end

                % Bin the rolling data into 60-second non-overlapping segments
                dt = median(diff(r.t_centers));
                if isnan(dt) || dt == 0
                    dt = 0.5;
                end
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

                c = colors(mod(k-1, size(colors, 1)) + 1, :);

                % Helper function to plot shaded overall variance region
                plotShadedRegion = @(t_axis, data, color) ...
                    patch([t_axis(1), t_axis(end), t_axis(end), t_axis(1)], ...
                    [mean(data,'omitnan') - std(data,'omitnan'), mean(data,'omitnan') - std(data,'omitnan'), ...
                    mean(data,'omitnan') + std(data,'omitnan'), mean(data,'omitnan') + std(data,'omitnan')], ...
                    color, 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');

                plotMeanLine = @(t_axis, data, color) ...
                    plot([t_axis(1), t_axis(end)], [mean(data,'omitnan'), mean(data,'omitnan')], ...
                    '-', 'Color', color, 'LineWidth', 2, 'HandleVisibility', 'off');

                % Plot TiB
                subplot(3,1,1);
                plotShadedRegion(bin_t, bin_tib_m, c);
                plotMeanLine(bin_t, bin_tib_m, c);
                plot(bin_t, bin_tib_m, '.-', 'Color', [c, 0.4], 'MarkerSize', 8, 'LineWidth', 1, 'DisplayName', r.meta.name);

                % Plot Entropy
                subplot(3,1,2);
                plotShadedRegion(bin_t, bin_ent_m, c);
                plotMeanLine(bin_t, bin_ent_m, c);
                plot(bin_t, bin_ent_m, '.-', 'Color', [c, 0.4], 'MarkerSize', 8, 'LineWidth', 1, 'DisplayName', r.meta.name);

                % Plot Fairness
                subplot(3,1,3);
                plotShadedRegion(bin_t, bin_fair_m, c);
                plotMeanLine(bin_t, bin_fair_m, c);
                plot(bin_t, bin_fair_m, '.-', 'Color', [c, 0.4], 'MarkerSize', 8, 'LineWidth', 1, 'DisplayName', r.meta.name);
            end

            for i = 1:3
                subplot(3,1,i);
                legend('Location', 'best');
                if isfield(results{1}, 't_centers') && ~isempty(results{1}.t_centers)
                    xlim([0, max(results{1}.t_centers) * 1.05]);
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
    end


    methods (Static, Access = private)
        function safeExport(fig, out_path)
            % Export figure to file and close it.  Create parent dirs if needed.
            out_dir = fileparts(out_path);
            if ~exist(out_dir, 'dir')
                mkdir(out_dir);
            end
            try
                exportgraphics(fig, out_path, 'Resolution', 300);
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
    end
end
