classdef Visualizer
    % Handles all MATLAB plotting and command-line printing with unified publication aesthetics.
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
            palette = Visualizer.getPalette();
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

        % =================================================================
        % Figure 1: Macro-Lobe Watershed & Ambient Baseline
        % =================================================================

        function render_spectral_and_cfar_figures(results, cfg)
            if nargin < 2
                cfg = struct();
            elseif ischar(cfg) || isstring(cfg)
                cfg = struct('output_dir', char(cfg));
            end
            if isfield(cfg, 'output_dir') && ~isempty(cfg.output_dir) && ~exist(cfg.output_dir, 'dir')
                mkdir(cfg.output_dir);
            end
            num_data = length(results);
            c_psd  = [0.28 0.75 1.00]; % Electric Sky Blue
            c_amb  = [1.00 0.75 0.25]; % Bright Amber
            c_dom  = [1.00 0.42 0.42]; % Neon Coral

            figure('Name', 'Figure 1: Macro-Lobe Watershed & Ambient Baseline', ...
                'Color', [0.08 0.11 0.17], 'Position', [30, 40, 1600, 470]);

            for k = 1:num_data
                r = results{k};

                % PSD with Macro-Lobes and Baselines
                ax_top = subplot(1, num_data, k);
                hold(ax_top, 'on');

                % Fill dominant macro-lobe
                dom = r.dom_lobe;
                idx_dom = (r.f_grid >= dom.f_start) & (r.f_grid <= dom.f_end);
                f_dom   = r.f_grid(idx_dom);
                p_dom   = r.psd_db(idx_dom);
                y_floor = min(r.psd_db) - 3;
                fill(ax_top, [f_dom; flipud(f_dom)], [p_dom; y_floor * ones(size(p_dom))], ...
                    c_dom, 'FaceAlpha', 0.25, 'EdgeColor', 'none', ...
                    'DisplayName', sprintf('Dominant Lobe [%0.1f-%0.1f Hz | %0.1f%%]', ...
                    dom.f_start, dom.f_end, dom.pct_energy));

                % Fill secondary candidate macro-lobes (Up to 4 total lobes including dominant)
                [~, sort_idx] = sort([r.macro_lobes.energy_lin], 'descend');
                sorted_lobes = r.macro_lobes(sort_idx);

                num_plotted = 1; % dom lobe is already plotted
                for m = 1:length(sorted_lobes)
                    lob = sorted_lobes(m);

                    % We already filled the dominant lobe, but we still draw its xlines
                    if lob.f_start == dom.f_start
                        xline(ax_top, lob.f_start, 'Color', [1.00 0.55 0.55], 'LineStyle', ':', 'LineWidth', 1.2, 'HandleVisibility', 'off');
                        xline(ax_top, lob.f_end,   'Color', [1.00 0.55 0.55], 'LineStyle', ':', 'LineWidth', 1.2, 'HandleVisibility', 'off');
                        continue;
                    end

                    if num_plotted >= 3
                        continue;
                    end

                    num_plotted = num_plotted + 1;
                    idx_m = (r.f_grid >= lob.f_start) & (r.f_grid <= lob.f_end);
                    fill(ax_top, [r.f_grid(idx_m); flipud(r.f_grid(idx_m))], ...
                        [r.psd_db(idx_m); y_floor * ones(sum(idx_m), 1)], ...
                        [0.28 0.75 1.00], 'FaceAlpha', 0.18, 'EdgeColor', 'none', ...
                        'DisplayName', sprintf('Lobe [%0.1f-%0.1f Hz | %0.1f%%]', ...
                        lob.f_start, lob.f_end, lob.pct_energy));

                    xline(ax_top, lob.f_start, 'Color', [0.45 0.75 0.95], 'LineStyle', ':', 'LineWidth', 1.0, 'HandleVisibility', 'off');
                    xline(ax_top, lob.f_end,   'Color', [0.45 0.75 0.95], 'LineStyle', ':', 'LineWidth', 1.0, 'HandleVisibility', 'off');
                end

                % Traces: PSD, Ambient Floor
                plot(ax_top, r.f_grid, r.psd_db, 'Color', c_psd, 'LineWidth', 1.3, 'DisplayName', 'Welch PSD (50 ms)');
                plot(ax_top, r.f_grid, r.ocean_floor_smooth, 'Color', c_amb, 'LineWidth', 1.3, 'LineStyle', ':', ...
                    'DisplayName', sprintf('Ambient Baseline (%0.1f dB)', r.ocean_ambient_db));

                xlim(ax_top, [r.meta.f_low, r.meta.f_high]);
                Visualizer.applyAxesStyle(ax_top, sprintf('%s\nMacro-Lobe Segmentation', r.meta.name), ...
                    'Frequency (Hz)', 'PSD (dB)');
                lgd = legend(ax_top, 'Location', 'northeast');
                Visualizer.styleLegend(lgd);
                
                if isfield(cfg, 'output_dir') && ~isempty(cfg.output_dir)
                    safe_name = regexprep(r.meta.name, '[^\w'']', '_');
                    exportgraphics(ax_top, fullfile(cfg.output_dir, sprintf('Fig1_MacroLobe_%s.png', safe_name)), ...
                        'Resolution', 300, 'BackgroundColor', 'current');
                end
            end

            if isfield(cfg, 'output_dir') && ~isempty(cfg.output_dir)
                exportgraphics(gcf, fullfile(cfg.output_dir, 'Fig1_MacroLobe_Watershed.png'), ...
                    'Resolution', 300, 'BackgroundColor', 'current');
            end
        end

        % =================================================================
        % Figure 3: High-Resolution 2D Spectrograms
        % =================================================================

        function render_spectrogram_figures(results, cfg)
            num_data = length(results);

            figure('Name', 'Figure 3: 2D Time-Frequency Spectrograms with Dominant Lobe Boundaries', ...
                'Color', [0.08 0.11 0.17], 'Position', [90, 120, 1500, 600]);

            for k = 1:num_data
                r = results{k};
                ax = subplot(1, num_data, k);

                % Render 2D Raster in kHz
                f_khz = r.f_spec / 1000;
                imagesc(ax, r.t_spec, f_khz, r.p_spec_db);
                set(ax, 'YDir', 'normal');
                colormap(ax, 'turbo');

                % Contrast enhancement
                c_lo = prctile(r.p_spec_db(:), 10);
                c_hi = prctile(r.p_spec_db(:), 99.7);
                if c_hi <= c_lo, c_hi = c_lo + 25; end
                if exist('clim', 'builtin') || exist('clim', 'file')
                    clim(ax, [c_lo, c_hi]);
                else
                    caxis(ax, [c_lo, c_hi]);
                end

                cb = colorbar(ax);
                cb.Color = [0.88 0.91 0.96];
                ylabel(cb, 'PSD (dB/Hz)', 'Color', [0.88 0.91 0.96], 'FontSize', 9);

                % Overlay Dominant Macro-Lobe Boundaries
                dom = r.dom_lobe;
                yline(ax, dom.f_start / 1000, 'Color', [0.96 0.98 1.00], 'LineStyle', '--', 'LineWidth', 1.5, 'DisplayName', 'Lobe Boundary');
                yline(ax, dom.f_end   / 1000, 'Color', [0.96 0.98 1.00], 'LineStyle', '--', 'LineWidth', 1.5, 'HandleVisibility', 'off');

                Visualizer.applyAxesStyle(ax, ...
                    sprintf('%s: Spectrogram [%d-%d Hz]\nDominant Lobe: [%0.1f - %0.1f Hz]', ...
                    r.meta.name, r.meta.f_low, r.meta.f_high, dom.f_start, dom.f_end), ...
                    'Time (s)', 'Frequency (kHz)');
                lgd = legend(ax, 'Location', 'northwest');
                Visualizer.styleLegend(lgd);

                if isfield(cfg, 'output_dir') && ~isempty(cfg.output_dir)
                    safe_name = regexprep(r.meta.name, '[^\w'']', '_');
                    exportgraphics(ax, fullfile(cfg.output_dir, sprintf('Fig3_Spectrogram_%s.png', safe_name)), ...
                        'Resolution', 300, 'BackgroundColor', 'current');
                end
            end

            if isfield(cfg, 'output_dir') && ~isempty(cfg.output_dir)
                exportgraphics(gcf, fullfile(cfg.output_dir, 'Fig3_2D_Spectrograms.png'), ...
                    'Resolution', 300, 'BackgroundColor', 'current');
            end
        end

        % =================================================================
        % Figure 2: Dominant Frequency Watershed Bandwidth (250ms Center Slice)
        % =================================================================

        function render_dominant_watershed_figures(results, cfg)
            if nargin < 2
                cfg = struct();
            elseif ischar(cfg) || isstring(cfg)
                cfg = struct('output_dir', char(cfg));
            end
            if isfield(cfg, 'output_dir') && ~isempty(cfg.output_dir) && ~exist(cfg.output_dir, 'dir')
                mkdir(cfg.output_dir);
            end
            num_data = length(results);

            figure('Name', 'Figure 2: Dominant Frequency Watershed Bandwidth (250ms Center Slice)', ...
                'Color', [0.08 0.11 0.17], 'Position', [60, 80, 1500, 580]);

            for k = 1:num_data
                r = results{k};
                h = r.slice_bw;

                ax = subplot(1, num_data, k);
                hold(ax, 'on');

                if h.found
                    % Signal FFT slice trace: Ice Blue / Light Silver for high dark-theme contrast
                    plot(ax, h.f_segment, 20*log10(h.mag_segment+eps), 'Color', [0.82 0.88 0.96], 'LineWidth', 1.4, ...
                        'DisplayName', 'Signal FFT Slice (Hann @ Midpoint)');

                    % Local Noise Floor: Bright Amber
                    yline(ax, 20*log10(h.noise_floor+eps), 'Color', [1.00 0.75 0.25], 'LineWidth', 1.4, 'LineStyle', ':', ...
                        'DisplayName', 'Local Noise Floor');

                    if isfield(h, 'target_mag') && ~isnan(h.target_mag) && abs(h.target_mag - h.noise_floor) > 1e-3 * h.noise_floor
                        yline(ax, 20*log10(h.target_mag+eps), 'Color', [0.76 0.52 1.00], 'LineWidth', 1.2, 'LineStyle', '--', ...
                            'DisplayName', 'Adaptive Intersection Threshold (Half Prominence)');
                    end

                    lbl = 'Main Peak';

                    [~, l_idx] = min(abs(h.f_segment - h.l_freq));
                    [~, r_idx] = min(abs(h.f_segment - h.r_freq));
                    l_mag_db = 20*log10(h.mag_segment(l_idx) + eps);
                    r_mag_db = 20*log10(h.mag_segment(r_idx) + eps);

                    % Plot Adaptive Base Intersections (Neon Coral diamond)
                    plot(ax, [h.l_freq, h.r_freq], [l_mag_db, r_mag_db], 'd', ...
                        'MarkerEdgeColor', [1.00 0.42 0.42], 'MarkerFaceColor', [1.00 0.42 0.42], 'MarkerSize', 8, ...
                        'DisplayName', sprintf('%s Base BW: %.1f Hz', lbl, h.main_bw));

                    % Plot Peak Marker (Vibrant Mint triangle)
                    plot(ax, h.main_f, 20*log10(h.main_mag+eps), 'v', ...
                        'MarkerFaceColor', [0.22 0.88 0.55], 'MarkerEdgeColor', 'none', 'MarkerSize', 8, ...
                        'HandleVisibility', 'off');

                    title_str = sprintf('%s: Watershed Peak Detection\nMain Peak = %0.1f Hz | Base BW = %0.1f Hz', ...
                        r.meta.name, h.main_f, h.main_bw);
                else
                    title_str = sprintf('%s: Peak Not Found', r.meta.name);
                end

                Visualizer.applyAxesStyle(ax, title_str, 'Frequency (Hz)', 'Magnitude (dB)');
                lgd = legend(ax, 'Location', 'best');
                Visualizer.styleLegend(lgd);

                if isfield(cfg, 'output_dir') && ~isempty(cfg.output_dir)
                    safe_name = regexprep(r.meta.name, '[^\w'']', '_');
                    exportgraphics(ax, fullfile(cfg.output_dir, sprintf('Fig2_Dominant_Watershed_BW_%s.png', safe_name)), ...
                        'Resolution', 300, 'BackgroundColor', 'current');
                end
            end

            if isfield(cfg, 'output_dir') && ~isempty(cfg.output_dir)
                exportgraphics(gcf, fullfile(cfg.output_dir, 'Fig2_Dominant_Watershed_BW.png'), ...
                    'Resolution', 300, 'BackgroundColor', 'current');
            end
        end

        % =================================================================
        % Figure 4: Bandwidth Distribution Histograms & Fairness Stability
        % =================================================================

        function render_bandwidth_distribution(results, cfg)
            if nargin < 2
                cfg = struct();
            elseif ischar(cfg) || isstring(cfg)
                cfg = struct('output_dir', char(cfg));
            end
            num_data = length(results);
            if num_data < 1
                return;
            end
            
            has_data = false;
            for k = 1:num_data
                if isfield(results{k}, 'slice_bw') && isfield(results{k}.slice_bw, 'all_main_bws') && ...
                        ~isempty(results{k}.slice_bw.all_main_bws)
                    has_data = true;
                    break;
                end
            end
            if ~has_data
                fprintf('[Visualizer] No bandwidth tracking data available for Figure 4.\n');
                return;
            end

            figure('Name', 'Figure 4: Watershed Main Peak Base Bandwidth & Fairness Distribution', ...
                'Color', [0.08 0.11 0.17], 'Position', [50, 160, 1800, 500]);

            % --- Subplot 1: Bandwidth Distribution ---
            ax1 = subplot(1, 4, 1);
            hold(ax1, 'on');

            bw_kde = 2.0; % KDE smoothing bandwidth

            for k = 1:num_data
                data = [];
                if isfield(results{k}, 'slice_bw') && isfield(results{k}.slice_bw, 'all_main_bws')
                    data = results{k}.slice_bw.all_main_bws;
                end
                data = data(isfinite(data) & data > 0);
                if ~isempty(data)
                    [f_val, xi_val] = ksdensity(data, 'Bandwidth', bw_kde);
                    [c, ec] = Visualizer.getDatasetColor(results{k}.meta.name, k);
                    fill(ax1, xi_val, f_val, c, 'FaceAlpha', 0.40, ...
                        'EdgeColor', ec, 'LineWidth', 1.8, 'DisplayName', results{k}.meta.name);
                end
            end

            Visualizer.applyAxesStyle(ax1, 'Bandwidth Distribution Comparison', 'Bandwidth (Hz)', 'Probability Density');
            lgd1 = legend(ax1, 'Location', 'best');
            Visualizer.styleLegend(lgd1);

            % --- Subplot 2: TiB Stability ---
            ax2 = subplot(1, 4, 2);
            hold(ax2, 'on');

            line_styles = {'-', '--', '-.', ':'};
            markers = {'o', 's', '^', 'd', 'v', '>', '<', 'p', 'h'};
            for k = 1:num_data
                win_sizes = []; fair = [];
                if isfield(results{k}, 'slice_bw') && isfield(results{k}.slice_bw, 'fairness_window_sec')
                    win_sizes = results{k}.slice_bw.fairness_window_sec;
                end
                if isfield(results{k}, 'slice_bw') && isfield(results{k}.slice_bw, 'all_tib')
                    fair = results{k}.slice_bw.all_tib;
                end
                if ~isempty(win_sizes) && ~isempty(fair)
                    % Add a tiny visual jitter to separate perfectly overlapping lines
                    jitter = (k-1) * 0.003;
                    [c, ~] = Visualizer.getDatasetColor(results{k}.meta.name, k);
                    ls = line_styles{mod(k-1, length(line_styles))+1};
                    mk = markers{mod(k-1, length(markers))+1};
                    lw = max(1.2, 2.5 - 0.3*k);
                    plot(ax2, win_sizes, fair + jitter, 'LineStyle', ls, 'Marker', mk, 'Color', c, 'LineWidth', lw, 'MarkerSize', 5, ...
                        'DisplayName', results{k}.meta.name);
                end
            end
            ylim(ax2, [0, 1.05]);
            Visualizer.applyAxesStyle(ax2, 'Mean Time-in-Band Stability', 'Window Size N (seconds)', 'Mean Time-in-Band (TiB)');
            lgd2 = legend(ax2, 'Location', 'best');
            Visualizer.styleLegend(lgd2);

            % --- Subplot 3: Entropy Stability ---
            ax3 = subplot(1, 4, 3);
            hold(ax3, 'on');

            for k = 1:num_data
                win_sizes = []; ent = [];
                if isfield(results{k}, 'slice_bw') && isfield(results{k}.slice_bw, 'fairness_window_sec')
                    win_sizes = results{k}.slice_bw.fairness_window_sec;
                end
                if isfield(results{k}, 'slice_bw') && isfield(results{k}.slice_bw, 'all_entropy')
                    ent = results{k}.slice_bw.all_entropy;
                end
                if ~isempty(win_sizes) && ~isempty(ent)
                    jitter = (k-1) * 0.003;
                    [c, ~] = Visualizer.getDatasetColor(results{k}.meta.name, k);
                    ls = line_styles{mod(k-1, length(line_styles))+1};
                    mk = markers{mod(k-1, length(markers))+1};
                    lw = max(1.2, 2.5 - 0.3*k);
                    plot(ax3, win_sizes, 1 - ent + jitter, 'LineStyle', ls, 'Marker', mk, 'Color', c, 'LineWidth', lw, 'MarkerSize', 5, ...
                        'DisplayName', results{k}.meta.name);
                end
            end
            ylim(ax3, [0, 1.05]);
            Visualizer.applyAxesStyle(ax3, 'Entropy Stability', 'Window Size N (seconds)', 'Stability (1 - H_{norm})');
            lgd3 = legend(ax3, 'Location', 'best');
            Visualizer.styleLegend(lgd3);

            % --- Subplot 4: Jain's Fairness Index ---
            ax4 = subplot(1, 4, 4);
            hold(ax4, 'on');

            for k = 1:num_data
                win_sizes = []; fair = [];
                if isfield(results{k}, 'slice_bw') && isfield(results{k}.slice_bw, 'fairness_window_sec')
                    win_sizes = results{k}.slice_bw.fairness_window_sec;
                end
                if isfield(results{k}, 'slice_bw') && isfield(results{k}.slice_bw, 'all_fairness')
                    fair = results{k}.slice_bw.all_fairness;
                end
                if ~isempty(win_sizes) && ~isempty(fair)
                    jitter = (k-1) * 0.003;
                    [c, ~] = Visualizer.getDatasetColor(results{k}.meta.name, k);
                    ls = line_styles{mod(k-1, length(line_styles))+1};
                    mk = markers{mod(k-1, length(markers))+1};
                    lw = max(1.2, 2.5 - 0.3*k);
                    plot(ax4, win_sizes, fair + jitter, 'LineStyle', ls, 'Marker', mk, 'Color', c, 'LineWidth', lw, 'MarkerSize', 5, ...
                        'DisplayName', results{k}.meta.name);
                end
            end
            ylim(ax4, [0, 1.05]);
            Visualizer.applyAxesStyle(ax4, 'Jain''s Fairness', 'Window Size N (seconds)', 'Jain''s Fairness Index');
            lgd4 = legend(ax4, 'Location', 'best');
            Visualizer.styleLegend(lgd4);

            if isfield(cfg, 'output_dir') && ~isempty(cfg.output_dir)
                if ~exist(cfg.output_dir, 'dir')
                    mkdir(cfg.output_dir);
                end
                exportgraphics(ax1, fullfile(cfg.output_dir, 'Fig4_Subplot1_Distribution.png'), ...
                    'Resolution', 300, 'BackgroundColor', 'current');
                exportgraphics(ax2, fullfile(cfg.output_dir, 'Fig4_Subplot2_TiB.png'), ...
                    'Resolution', 300, 'BackgroundColor', 'current');
                exportgraphics(ax3, fullfile(cfg.output_dir, 'Fig4_Subplot3_Entropy.png'), ...
                    'Resolution', 300, 'BackgroundColor', 'current');
                exportgraphics(ax4, fullfile(cfg.output_dir, 'Fig4_Subplot4_Fairness.png'), ...
                    'Resolution', 300, 'BackgroundColor', 'current');
                exportgraphics(gcf, fullfile(cfg.output_dir, 'Fig4_BW_Distribution.png'), ...
                    'Resolution', 300, 'BackgroundColor', 'current');
            end
        end

        % =================================================================
        % Figure 4-B: Binned Bandwidth Distribution & Standard Error
        % =================================================================

        function render_binned_bandwidth_distribution(results, cfg, bin_dur_sec)
            if nargin < 2
                cfg = struct();
            elseif ischar(cfg) || isstring(cfg)
                cfg = struct('output_dir', char(cfg));
            end
            if nargin < 3 || isempty(bin_dur_sec)
                bin_dur_sec = 60.0;
            end
            
            num_data = length(results);
            if num_data < 1
                return;
            end

            binned_datasets = {};
            for k = 1:num_data
                r = results{k};
                ds = struct();
                if isfield(r, 'meta') && isfield(r.meta, 'name')
                    ds.name = r.meta.name;
                elseif isfield(r, 'name')
                    ds.name = r.name;
                else
                    ds.name = sprintf('Dataset %d', k);
                end

                if isfield(r, 'slice_means') && isfield(r, 'slice_sems')
                    ds.slice_means = r.slice_means;
                    ds.slice_sems  = r.slice_sems;
                    ds.slice_stds  = r.slice_stds;
                    ds.slice_times = r.slice_times;
                elseif isfield(r, 'slice_bw') && isfield(r.slice_bw, 'all_main_bws')
                    [ds.slice_means, ds.slice_sems, ds.slice_times, ds.slice_stds] = ...
                        BandwidthTracker.compute_binned_bandwidth(r.slice_bw.all_main_bws, 0.500, bin_dur_sec);
                elseif isfield(r, 'all_main_bws')
                    [ds.slice_means, ds.slice_sems, ds.slice_times, ds.slice_stds] = ...
                        BandwidthTracker.compute_binned_bandwidth(r.all_main_bws, 0.500, bin_dur_sec);
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
                fprintf('[Visualizer] No binned bandwidth data available for %ds analysis.\n', round(bin_dur_sec));
                return;
            end

            fig = figure('Name', sprintf('Figure 4-B: %ds Slice Bandwidth Distribution & Std Error', round(bin_dur_sec)), ...
                'Color', [0.08 0.11 0.17], 'Position', [50, 80, 1400, 850]);

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
                [c, ec] = Visualizer.getDatasetColor(ds.name, k);

                b(k).FaceColor = c;
                b(k).EdgeColor = ec;
                b(k).FaceAlpha = 0.50;
                b(k).DisplayName = sprintf('%s (N=%d slices)', ds.name, length(ds.slice_means));

                % Add error bar to show each bar's std
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
                std_val = std(ds.slice_means);
                sem_overall = mean(ds.slice_sems);
                xline(ax1, m_val, '--', 'Color', ec, 'LineWidth', 1.8, ...
                    'DisplayName', sprintf('%s Mean: %.1f ± %.1f Hz (std: %.1f)', ds.name, m_val, sem_overall, std_val));
            end

            max_p_all = max(P_matrix(:));
            if max_p_all <= 0; max_p_all = 0.5; end
            ylim(ax1, [0, min(1.0, max_p_all * 1.15 + 0.05)]);

            Visualizer.applyAxesStyle(ax1, sprintf('%ds Mean Bandwidth Distribution (Normalized)', round(bin_dur_sec)), ...
                'Mean Bandwidth (Hz)', 'Normalized Probability');
            lgd1 = legend(ax1, 'Location', 'best');
            Visualizer.styleLegend(lgd1);

            % --- Subplot 2: Standard Error Distribution Across Slices ---
            ax2 = subplot(2, 2, 2);
            hold(ax2, 'on');

            all_sems_concat = vertcat(binned_datasets{:});
            all_sems_concat = vertcat(all_sems_concat.slice_sems);
            min_sem = max(0, min(all_sems_concat) * 0.8);
            if length(all_sems_concat) >= 10
                p99 = prctile(all_sems_concat, 99);
                max_sem = max(p99 * 1.25, 4.0);
                if max_sem > max(all_sems_concat); max_sem = max(all_sems_concat) * 1.05; end
            else
                max_sem = max(all_sems_concat) * 1.1;
            end
            num_sem_bins = min(20, max(8, round(sqrt(length(all_sems_concat)))));
            sem_edges = linspace(min_sem, max_sem, num_sem_bins + 1);

            for k = 1:num_ds
                ds = binned_datasets{k};
                [c, ec] = Visualizer.getDatasetColor(ds.name, k);

                clamped_sems = min(ds.slice_sems, max_sem);

                histogram(ax2, clamped_sems, sem_edges, 'Normalization', 'probability', ...
                    'FaceColor', c, 'EdgeColor', ec, 'FaceAlpha', 0.50, ...
                    'DisplayName', sprintf('%s (Avg SE: %.2f Hz)', ds.name, mean(ds.slice_sems)));

                mean_se = mean(ds.slice_sems);
                xline(ax2, mean_se, '--', 'Color', ec, 'LineWidth', 1.8, ...
                    'DisplayName', sprintf('%s Avg SE: %.2f Hz', ds.name, mean_se));
            end

            ylim(ax2, [0, 1.05]);

            Visualizer.applyAxesStyle(ax2, sprintf('Std Error Distribution Across %ds Slices (Normalized)', round(bin_dur_sec)), ...
                'Standard Error SE (Hz)', 'Normalized Probability');
            lgd2 = legend(ax2, 'Location', 'best');
            Visualizer.styleLegend(lgd2);

            % --- Subplot 3: Mean Bandwidth with Error Bars (±SE) vs Time ---
            ax3 = subplot(2, 2, 3);
            hold(ax3, 'on');

            for k = 1:num_ds
                ds = binned_datasets{k};
                [c, ~] = Visualizer.getDatasetColor(ds.name, k);
                t_min = ds.slice_times / 60;

                errorbar(ax3, t_min, ds.slice_means, ds.slice_sems, '.-', ...
                    'Color', c, 'MarkerSize', 10, 'LineWidth', 1.2, 'CapSize', 4, ...
                    'DisplayName', sprintf('%s (Mean: %.1f Hz)', ds.name, mean(ds.slice_means)));
            end

            Visualizer.applyAxesStyle(ax3, sprintf('%ds Slice Mean Bandwidth with Error Bars (±SE)', round(bin_dur_sec)), ...
                'Elapsed Time (minutes)', 'Mean Bandwidth ± SE (Hz)');
            lgd3 = legend(ax3, 'Location', 'best');
            Visualizer.styleLegend(lgd3);

            % --- Subplot 4: Standard Error for Each Slice vs Time ---
            ax4 = subplot(2, 2, 4);
            hold(ax4, 'on');

            for k = 1:num_ds
                ds = binned_datasets{k};
                [c, ec] = Visualizer.getDatasetColor(ds.name, k);
                t_min = ds.slice_times / 60;

                plot(ax4, t_min, ds.slice_sems, '.-', 'Color', c, 'LineWidth', 1.2, ...
                    'MarkerSize', 10, 'DisplayName', sprintf('%s (Avg SE: %.2f Hz)', ds.name, mean(ds.slice_sems)));

                yline(ax4, mean(ds.slice_sems), ':', 'Color', ec, 'LineWidth', 1.5, ...
                    'HandleVisibility', 'off');
            end

            Visualizer.applyAxesStyle(ax4, sprintf('Standard Error for Each %ds Slice', round(bin_dur_sec)), ...
                'Elapsed Time (minutes)', 'Std Error SE (Hz)');
            lgd4 = legend(ax4, 'Location', 'best');
            Visualizer.styleLegend(lgd4);

            if isfield(cfg, 'output_dir') && ~isempty(cfg.output_dir)
                if ~exist(cfg.output_dir, 'dir')
                    mkdir(cfg.output_dir);
                end
                exportgraphics(ax1, fullfile(cfg.output_dir, 'Fig4_Binned_BW_Subplot1_Distribution.png'), ...
                    'Resolution', 300, 'BackgroundColor', 'current');
                exportgraphics(ax2, fullfile(cfg.output_dir, 'Fig4_Binned_BW_Subplot2_StdError_Dist.png'), ...
                    'Resolution', 300, 'BackgroundColor', 'current');
                exportgraphics(ax3, fullfile(cfg.output_dir, 'Fig4_Binned_BW_Subplot3_Mean_Errorbar.png'), ...
                    'Resolution', 300, 'BackgroundColor', 'current');
                exportgraphics(ax4, fullfile(cfg.output_dir, 'Fig4_Binned_BW_Subplot4_StdError_Time.png'), ...
                    'Resolution', 300, 'BackgroundColor', 'current');
                exportgraphics(fig, fullfile(cfg.output_dir, 'Fig4_Binned_BW_Summary.png'), ...
                    'Resolution', 300, 'BackgroundColor', 'current');
            end
        end

        % =================================================================
        % Figure 5: Outlier Signal Segments
        % =================================================================

        function render_outlier_figures(results, cfg)
            num_data = length(results);

            figure('Name', 'Figure 5: Outlier Signal Segments (Furthest from Mean BW)', ...
                'Color', [0.08 0.11 0.17], 'Position', [150, 180, 1600, 470]);

            for k = 1:num_data
                r = results{k};
                slices = r.slice_bw.slice_outputs;

                valid_slices = [];
                bws = [];
                for i = 1:length(slices)
                    if ~isempty(slices{i}) && slices{i}.found && isfinite(slices{i}.main_bw)
                        valid_slices = [valid_slices; i];
                        bws = [bws; slices{i}.main_bw];
                    end
                end

                if isempty(valid_slices)
                    continue;
                end

                mean_bw = mean(bws);
                [~, max_dev_idx] = max(abs(bws - mean_bw));
                outlier_slice = slices{valid_slices(max_dev_idx)};

                ax = subplot(1, num_data, k);
                hold(ax, 'on');

                f_seg = outlier_slice.f_segment;
                mag_db = 20 * log10(outlier_slice.mag_segment + eps);
                nf_db = 20 * log10(outlier_slice.noise_floor + eps);
                target_mag_db = 20 * log10(outlier_slice.target_mag + eps);

                % Plot the raw magnitude in Electric Sky Blue
                plot(ax, f_seg, mag_db, 'Color', [0.28 0.75 1.00], 'LineWidth', 1.3, ...
                    'DisplayName', sprintf('Slice %d (BW: %.1f Hz)', outlier_slice.slice_idx, outlier_slice.main_bw));

                % Plot Noise Floor in Bright Amber
                yline(ax, nf_db, 'Color', [1.00 0.75 0.25], 'LineStyle', '--', 'LineWidth', 1.2, ...
                    'DisplayName', 'Ambient Noise Floor');

                % Markers for Watershed BW in Neon Coral
                plot(ax, outlier_slice.l_freq, target_mag_db, 'd', 'MarkerEdgeColor', [1.00 0.42 0.42], ...
                    'MarkerFaceColor', [1.00 0.42 0.42], 'MarkerSize', 6, 'HandleVisibility', 'off');
                plot(ax, outlier_slice.r_freq, target_mag_db, 'd', 'MarkerEdgeColor', [1.00 0.42 0.42], ...
                    'MarkerFaceColor', [1.00 0.42 0.42], 'MarkerSize', 6, 'HandleVisibility', 'off');

                Visualizer.applyAxesStyle(ax, ...
                    sprintf('%s: Outlier Slice (Dev: %.1f Hz from Mean %.1f Hz)', r.meta.name, abs(outlier_slice.main_bw - mean_bw), mean_bw), ...
                    'Frequency (Hz)', 'Magnitude (dB)');
                lgd = legend(ax, 'Location', 'best');
                Visualizer.styleLegend(lgd);

                if isfield(cfg, 'output_dir') && ~isempty(cfg.output_dir)
                    safe_name = regexprep(r.meta.name, '[^\w'']', '_');
                    exportgraphics(ax, fullfile(cfg.output_dir, sprintf('Fig5_Outlier_Segment_%s.png', safe_name)), ...
                        'Resolution', 300, 'BackgroundColor', 'current');
                end
            end

            if isfield(cfg, 'output_dir') && ~isempty(cfg.output_dir)
                exportgraphics(gcf, fullfile(cfg.output_dir, 'Fig5_Outlier_Segments.png'), ...
                    'Resolution', 300, 'BackgroundColor', 'current');
            end
        end

        % =================================================================
        % Figure 6: Welch PSD & Dominant Frequency
        % =================================================================

        function render_welch_dominant_frequency(results, cfg)
            if nargin < 2
                cfg = struct();
            elseif ischar(cfg) || isstring(cfg)
                cfg = struct('output_dir', char(cfg));
            end
            if isfield(cfg, 'output_dir') && ~isempty(cfg.output_dir) && ~exist(cfg.output_dir, 'dir')
                mkdir(cfg.output_dir);
            end
            num_data = length(results);
            c_psd  = [0.28 0.75 1.00]; % Electric Sky Blue
            c_dom  = [1.00 0.42 0.42]; % Neon Coral

            figure('Name', 'Figure 6: Welch PSD and Dominant Frequency', ...
                'Color', [0.08 0.11 0.17], 'Position', [200, 220, 1600, 470]);

            for k = 1:num_data
                r = results{k};

                ax = subplot(1, num_data, k);
                hold(ax, 'on');

                plot(ax, r.f_grid, r.psd_db, 'Color', c_psd, 'LineWidth', 1.3, 'DisplayName', 'Welch PSD');

                dom = r.dom_lobe;
                plot(ax, dom.peak_freq, dom.peak_psd, 'v', ...
                    'MarkerFaceColor', c_dom, 'MarkerEdgeColor', 'none', 'MarkerSize', 10, ...
                    'DisplayName', sprintf('Dominant Freq (%.1f Hz)', dom.peak_freq));
                
                xline(ax, dom.peak_freq, 'Color', c_dom, 'LineStyle', ':', 'LineWidth', 1.2, 'HandleVisibility', 'off');

                xlim(ax, [r.meta.f_low, r.meta.f_high]);
                Visualizer.applyAxesStyle(ax, sprintf('%s\nWelch PSD & Dominant Frequency', r.meta.name), ...
                    'Frequency (Hz)', 'PSD (dB/Hz)');
                lgd = legend(ax, 'Location', 'northeast');
                Visualizer.styleLegend(lgd);

                if isfield(cfg, 'output_dir') && ~isempty(cfg.output_dir)
                    safe_name = regexprep(r.meta.name, '[^\w'']', '_');
                    exportgraphics(ax, fullfile(cfg.output_dir, sprintf('Fig6_Welch_Dominant_Freq_%s.png', safe_name)), ...
                        'Resolution', 300, 'BackgroundColor', 'current');
                end
            end

            if isfield(cfg, 'output_dir') && ~isempty(cfg.output_dir)
                exportgraphics(gcf, fullfile(cfg.output_dir, 'Fig6_Welch_Dominant_Freq.png'), ...
                    'Resolution', 300, 'BackgroundColor', 'current');
            end
        end

        % =================================================================
        % Diagnostic Console Summary
        % =================================================================

        function print_diagnostic_summary(results)
            fprintf('\n============================================================\n');
            fprintf('ACOUSTIC LOBE & NOISE FLOOR ANALYSIS SUMMARY\n');
            fprintf('============================================================\n');

            for k = 1:length(results)
                r = results{k};
                fprintf('\n------------------------------------------------------------\n');
                fprintf('  %s\n', r.meta.name);
                fprintf('  Passband:                     %d - %d Hz\n', r.meta.f_low, r.meta.f_high);
                fprintf('  Ambient Ocean Noise Floor:    %0.1f dB/Hz\n', r.ocean_ambient_db);
                fprintf('  Detected Macro-Lobes:         %d partitioned regions\n', length(r.macro_lobes));
                fprintf('  ----------------------------------------------------------\n');

                for m = 1:length(r.macro_lobes)
                    lob = r.macro_lobes(m);
                    fprintf('    Lobe %d: [%5.1f - %5.1f Hz] (BW: %4.1f Hz) | Summit: %5.1f dB @ %5.1f Hz | Power: %4.1f%%\n', ...
                        m, lob.f_start, lob.f_end, lob.bandwidth, lob.peak_psd, lob.peak_freq, lob.pct_energy);
                end

                dom = r.dom_lobe;
                fprintf('  ----------------------------------------------------------\n');
                fprintf('  DOMINANT ENERGETIC LOBE:      [%0.1f - %0.1f Hz] (BW: %0.1f Hz)\n', ...
                    dom.f_start, dom.f_end, dom.bandwidth);
                fprintf('    Summit Peak:                %0.2f dB/Hz @ %0.1f Hz\n', dom.peak_psd, dom.peak_freq);
                fprintf('    Acoustic Energy Fraction:   %0.2f%% OF TOTAL BAND POWER\n', dom.pct_energy);

                h = r.slice_bw;
                if h.found
                    fprintf('  ----------------------------------------------------------\n');
                    fprintf('  WATERSHED MAIN PEAK BANDWIDTH (250ms SLICES):\n');
                    fprintf('    MAIN PEAK       %0.2f Hz (Mag: %0.2f dB) | Base BW: %0.2f Hz\n', h.main_f, 20*log10(h.main_mag+eps), h.main_bw);
                end

            end
            fprintf('\n============================================================\n\n');
        end

    end
end
