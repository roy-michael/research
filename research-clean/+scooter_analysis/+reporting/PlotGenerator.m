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
            
            window = round(fs * cfg.window_dur_sec);
            noverlap = round(window * cfg.overlap_ratio);
            
            if cfg.nfft == 0
                nfft = 2^nextpow2(window * 2);
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
        
        
        function comparison(analyzerA, analyzerB, out_path)
            % Plot overlaid normalised histograms comparing two datasets.
            %
            % Args:
            %   analyzerA - First BatchAnalyzer (run)
            %   analyzerB - Second BatchAnalyzer (run)
            %   out_path  - Output image path
            
            a_freqs = analyzerA.getAllDomFreqs();
            b_freqs = analyzerB.getAllDomFreqs();
            a_bws = analyzerA.getAllBandwidths();
            b_bws = analyzerB.getAllBandwidths();
            
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
            legend(analyzerA.DatasetName, analyzerB.DatasetName);
            grid on;
            
            % Bandwidth
            subplot(1, 2, 2);
            hold on;
            bw_max = max(max(a_bws), max(b_bws));
            bw_edges = 0:2:bw_max;
            if isempty(bw_edges); bw_edges = 0:2:100; end
            histogram(a_bws, bw_edges, 'Normalization', 'probability', ...
                'FaceColor', [0.2 0.6 0.8], 'EdgeColor', 'none', 'FaceAlpha', 0.6);
            histogram(b_bws, bw_edges, 'Normalization', 'probability', ...
                'FaceColor', [0.8 0.3 0.3], 'EdgeColor', 'none', 'FaceAlpha', 0.6);
            title('Bandwidth (Normalised)');
            xlabel('Bandwidth (Hz)');
            ylabel('Probability');
            legend(analyzerA.DatasetName, analyzerB.DatasetName);
            grid on;
            
            scooter_analysis.reporting.PlotGenerator.safeExport(fig, out_path);
        end
        
        
        function fairnessComparison(varargin)
            % fairnessComparison - Plot and export 4-panel bandwidth & fairness stability comparison.
            %
            % Generates:
            %   1. Bandwidth Distribution Comparison (KDE)
            %   2. Mean Time-in-Band (TiB) Stability
            %   3. Entropy Stability (1 - H_norm)
            %   4. Jain's Fairness Index vs Window Size
            %
            % Exactly as done in bandwidth_segment_lobe_floor_watershed.m.
            %
            % Usage:
            %   PlotGenerator.fairnessComparison(analyzer)
            %   PlotGenerator.fairnessComparison(analyzer, out_dir)
            %   PlotGenerator.fairnessComparison(analyzerA, analyzerB, out_dir)
            %   PlotGenerator.fairnessComparison({analyzerA, analyzerB}, out_dir)
            %   PlotGenerator.fairnessComparison(results_cell, out_dir)
            
            if nargin == 0
                return;
            end
            
            firstArg = varargin{1};
            out_dir = '';
            results = {};
            
            if nargin >= 2 && isa(varargin{2}, 'scooter_analysis.pipeline.BatchAnalyzer')
                % Two analyzers passed as (baA, baB, [out_dir])
                analyzers = {varargin{1}, varargin{2}};
                if nargin >= 3 && (ischar(varargin{3}) || isstring(varargin{3}))
                    out_dir = char(varargin{3});
                end
                results = cell(length(analyzers), 1);
                for k = 1:length(analyzers)
                    results{k} = analyzers{k}.getFairnessResult();
                end
            elseif iscell(firstArg)
                % Cell array passed: could be cell of BatchAnalyzers, FileResults, or result structs
                if nargin >= 2 && (ischar(varargin{2}) || isstring(varargin{2}))
                    out_dir = char(varargin{2});
                end
                results = cell(length(firstArg), 1);
                for k = 1:length(firstArg)
                    item = firstArg{k};
                    if isa(item, 'scooter_analysis.pipeline.BatchAnalyzer')
                        results{k} = item.getFairnessResult();
                    elseif isa(item, 'scooter_analysis.results.FileResult')
                        results{k} = item.getFairnessResult();
                    elseif isstruct(item)
                        results{k} = item;
                    end
                end
            elseif isa(firstArg, 'scooter_analysis.pipeline.BatchAnalyzer')
                if nargin >= 2 && (ischar(varargin{2}) || isstring(varargin{2}))
                    out_dir = char(varargin{2});
                else
                    out_dir = fullfile(firstArg.OutputDir, 'fairness_comparison');
                end
                if length(firstArg.FileResults) > 1
                    results = firstArg.getFileFairnessResults();
                else
                    results = {firstArg.getFairnessResult()};
                end
            elseif isa(firstArg, 'scooter_analysis.results.FileResult')
                if nargin >= 2 && (ischar(varargin{2}) || isstring(varargin{2}))
                    out_dir = char(varargin{2});
                end
                results = {firstArg.getFairnessResult()};
            elseif isstruct(firstArg)
                if nargin >= 2 && (ischar(varargin{2}) || isstring(varargin{2}))
                    out_dir = char(varargin{2});
                end
                results = num2cell(firstArg);
            end
            
            if length(results) < 2
                fprintf('[PlotGenerator] fairnessComparison requires at least 2 datasets or files to compare.\n');
                return;
            end
            
            cfg_vis = struct();
            cfg_vis.output_dir = out_dir;
            Visualizer.render_bandwidth_distribution(results, cfg_vis);
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
    end
end
