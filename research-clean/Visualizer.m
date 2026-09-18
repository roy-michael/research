classdef Visualizer
    % Handles all MATLAB plotting and command-line printing.
    methods (Static)

        function render_spectral_and_cfar_figures(results, cfg)
            num_data = length(results);
            c_bg   = [0.07 0.09 0.13];
            c_ax   = [0.10 0.12 0.18];
            c_text = [0.92 0.94 0.97];
            c_grid = [0.20 0.24 0.32];
            c_psd  = [0.20 0.82 1.00];  % Cyan
            c_amb  = [0.50 0.55 0.65];  % Steel Gray

            figure('Name', 'Figure 1: Macro-Lobe Watershed & Ambient Baseline', ...
                'Color', c_bg, 'Position', [30, 40, 1600, 470]);

            for k = 1:num_data
                r = results{k};

                % Top Row: PSD with Macro-Lobes and Baselines
                ax_top = subplot(1, num_data, k);
                set(ax_top, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, ...
                    'GridColor', c_grid, 'GridAlpha', 0.5, 'LineWidth', 1.0);
                hold(ax_top, 'on'); grid(ax_top, 'on');

                % Fill dominant macro-lobe
                dom = r.dom_lobe;
                idx_dom = (r.f_grid >= dom.f_start) & (r.f_grid <= dom.f_end);
                f_dom   = r.f_grid(idx_dom);
                p_dom   = r.psd_db(idx_dom);
                y_floor = min(r.psd_db) - 4;
                fill(ax_top, [f_dom; flipud(f_dom)], [p_dom; y_floor * ones(size(p_dom))], ...
                    [0.90 0.25 0.35], 'FaceAlpha', 0.35, 'EdgeColor', 'none', ...
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
                        xline(ax_top, lob.f_start, 'Color', [0.80 0.40 0.50], 'LineStyle', ':', 'LineWidth', 1.0, 'HandleVisibility', 'off');
                        xline(ax_top, lob.f_end,   'Color', [0.80 0.40 0.50], 'LineStyle', ':', 'LineWidth', 1.0, 'HandleVisibility', 'off');
                        continue;
                    end

                    if num_plotted >= 4
                        continue;
                    end

                    num_plotted = num_plotted + 1;
                    idx_m = (r.f_grid >= lob.f_start) & (r.f_grid <= lob.f_end);
                    fill(ax_top, [r.f_grid(idx_m); flipud(r.f_grid(idx_m))], ...
                        [r.psd_db(idx_m); y_floor * ones(sum(idx_m), 1)], ...
                        [0.30 0.65 0.95], 'FaceAlpha', 0.18, 'EdgeColor', 'none', ...
                        'DisplayName', sprintf('Lobe [%0.1f-%0.1f Hz | %0.1f%%]', ...
                        lob.f_start, lob.f_end, lob.pct_energy));

                    xline(ax_top, lob.f_start, 'Color', [0.80 0.40 0.50], 'LineStyle', ':', 'LineWidth', 1.0, 'HandleVisibility', 'off');
                    xline(ax_top, lob.f_end,   'Color', [0.80 0.40 0.50], 'LineStyle', ':', 'LineWidth', 1.0, 'HandleVisibility', 'off');
                end

                % Traces: PSD, Ambient Floor
                plot(ax_top, r.f_grid, r.psd_db, 'Color', c_psd, 'LineWidth', 1.2, 'DisplayName', 'Welch PSD (50 ms)');
                plot(ax_top, r.f_grid, r.ocean_floor_smooth, 'Color', c_amb, 'LineWidth', 1.2, 'LineStyle', ':', ...
                    'DisplayName', sprintf('Ambient Baseline (%0.1f dB)', r.ocean_ambient_db));

                xlim(ax_top, [r.meta.f_low, r.meta.f_high]);
                ylabel(ax_top, 'PSD (dB/Hz)', 'FontSize', 9, 'FontWeight', 'bold', 'Color', c_text);
                title(ax_top, sprintf('%s\nMacro-Lobe Segmentation', r.meta.name), ...
                    'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
                legend(ax_top, 'Location', 'northeast', 'TextColor', c_text, 'Color', [0.08 0.10 0.15], ...
                    'EdgeColor', c_grid, 'FontSize', 7.5);
            end
        end


        % MODULE 9C: FIGURE 3 - HIGH-RESOLUTION 2D SPECTROGRAMS


        function render_spectrogram_figures(results, cfg)
            num_data = length(results);
            c_bg   = [0.07 0.09 0.13];
            c_ax   = [0.10 0.12 0.18];
            c_text = [0.92 0.94 0.97];
            c_grid = [0.20 0.24 0.32];

            figure('Name', 'Figure 3: 2D Time-Frequency Spectrograms with Dominant Lobe Boundaries', ...
                'Color', c_bg, 'Position', [90, 120, 1500, 600]);

            for k = 1:num_data
                r = results{k};
                ax = subplot(1, num_data, k);
                set(ax, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, ...
                    'GridColor', c_grid, 'LineWidth', 1.0);

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
                cb.Color = c_text;
                ylabel(cb, 'PSD (dB/Hz)', 'Color', c_text, 'FontSize', 9);

                % Overlay Dominant Macro-Lobe Boundaries
                dom = r.dom_lobe;
                yline(ax, dom.f_start / 1000, 'Color', [1.0 1.0 1.0], 'LineStyle', '--', 'LineWidth', 1.4);
                yline(ax, dom.f_end   / 1000, 'Color', [1.0 1.0 1.0], 'LineStyle', '--', 'LineWidth', 1.4);

                xlabel(ax, 'Time (s)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
                ylabel(ax, 'Frequency (kHz)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
                title(ax, sprintf('%s: Spectrogram [%d-%d Hz]\nDominant Lobe: [%0.1f - %0.1f Hz]', ...
                    r.meta.name, r.meta.f_low, r.meta.f_high, dom.f_start, dom.f_end), ...
                    'FontSize', 10.5, 'FontWeight', 'bold', 'Color', c_text);


            end
        end

        % MODULE 10: DIAGNOSTIC REPORTING & CONSOLE OUTPUT


        function render_dominant_watershed_figures(results, cfg)
            num_data = length(results);
            c_bg   = [0.07 0.09 0.13];
            c_ax   = [0.10 0.12 0.18];
            c_text = [0.92 0.94 0.97];
            c_grid = [0.20 0.24 0.32];

            figure('Name', 'Figure 2: Dominant Frequency Watershed Bandwidth (250ms Center Slice)', ...
                'Color', c_bg, 'Position', [60, 80, 1500, 580]);

            for k = 1:num_data
                r = results{k};
                h = r.slice_bw;

                ax = subplot(1, num_data, k);
                set(ax, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, ...
                    'GridColor', c_grid, 'GridAlpha', 0.5, 'LineWidth', 1.0);
                hold(ax, 'on'); grid(ax, 'on');

                if h.found
                    plot(ax, h.f_segment, 20*log10(h.mag_segment+eps), 'Color', [0.75 0.80 0.88], 'LineWidth', 1.4, ...
                        'DisplayName', 'Signal FFT Slice (0.25 s Hann @ Midpoint)');

                    yline(ax, 20*log10(h.noise_floor+eps), 'Color', [1.00 0.78 0.25], 'LineWidth', 1.4, 'LineStyle', ':', ...
                        'DisplayName', 'Local Noise Floor');

                    yline(ax, 20*log10(h.target_mag+eps), 'Color', [1.0 0.4 0.6], 'LineWidth', 1.2, 'LineStyle', '--', ...
                        'DisplayName', 'Adaptive Intersection Threshold (Half Prominence)');

                    lbl = 'Main Peak';

                    l_mag_db = 20*log10(h.mag_segment(h.f_segment == h.l_freq) + eps);
                    r_mag_db = 20*log10(h.mag_segment(h.f_segment == h.r_freq) + eps);

                    % Plot Adaptive Base Intersections
                    plot(ax, [h.l_freq, h.r_freq], [l_mag_db, r_mag_db], 'd', ...
                        'MarkerEdgeColor', [1.0 0.2 0.2], 'MarkerFaceColor', [1.0 0.2 0.2], 'MarkerSize', 8, ...
                        'DisplayName', sprintf('%s Base BW: %.1f Hz', lbl, h.main_bw));

                    % Plot Peak Marker
                    plot(ax, h.main_f, 20*log10(h.main_mag+eps), 'v', ...
                        'MarkerFaceColor', [0.20 0.90 0.55], 'MarkerEdgeColor', 'none', 'MarkerSize', 8, ...
                        'HandleVisibility', 'off');

                    title(ax, sprintf('%s: Watershed Peak Detection\nMain Peak = %0.1f Hz | Base BW = %0.1f Hz', ...
                        r.meta.name, h.main_f, h.main_bw), ...
                        'FontSize', 10.5, 'FontWeight', 'bold', 'Color', c_text);
                else
                    title(ax, sprintf('%s: Peak Not Found', r.meta.name), ...
                        'FontSize', 10.5, 'FontWeight', 'bold', 'Color', c_text);
                end

                xlabel(ax, 'Frequency (Hz)', 'FontSize', 9.5, 'FontWeight', 'bold', 'Color', c_text);
                ylabel(ax, 'Magnitude (dB)', 'FontSize', 9.5, 'FontWeight', 'bold', 'Color', c_text);
                legend(ax, 'Location', 'best', 'TextColor', c_text, 'Color', [0.08 0.10 0.15], ...
                    'EdgeColor', c_grid, 'FontSize', 8);

            end
        end

        % MODULE 9D: FIGURE 4 - BANDWIDTH DISTRIBUTION HISTOGRAMS


        function render_bandwidth_distribution(results, cfg)
            num_data = length(results);
            if num_data < 2
                return;
            end

            c_bg   = [0.07 0.09 0.13];
            c_ax   = [0.10 0.12 0.18];
            c_text = [0.92 0.94 0.97];
            c_grid = [0.20 0.24 0.32];

            figure('Name', 'Figure 4: Watershed Main Peak Base Bandwidth & Fairness Distribution', ...
                'Color', c_bg, 'Position', [120, 160, 1500, 500]);

            % --- Subplot 1: Bandwidth Distribution ---
            ax1 = subplot(1, 3, 1);
            set(ax1, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, ...
                'GridColor', c_grid, 'LineWidth', 1.0);
            hold(ax1, 'on'); grid(ax1, 'on');

            colors = [
                0.8 0.3 0.3; % Red
                0.2 0.6 0.8; % Blue
                0.3 0.8 0.4; % Green
                0.8 0.6 0.2; % Orange
                0.6 0.3 0.8  % Purple
                ];
            edge_colors = colors * 0.7;

            bw_kde = 2.0; % KDE smoothing bandwidth

            for k = 1:num_data
                % Watershed Main Peak BW
                data = results{k}.slice_bw.all_main_bws;
                data = data(isfinite(data) & data > 0);
                if ~isempty(data)
                    [f_val, xi_val] = ksdensity(data, 'Bandwidth', bw_kde);
                    c = colors(mod(k-1, size(colors,1))+1, :);
                    ec = edge_colors(mod(k-1, size(edge_colors,1))+1, :);
                    fill(ax1, xi_val, f_val, c, 'FaceAlpha', 0.5, ...
                        'EdgeColor', ec, 'LineWidth', 2, 'DisplayName', [results{k}.meta.name ' (Watershed)']);
                end

                % (Envelope plotting removed)
            end

            title(ax1, 'Bandwidth Distribution Comparison', ...
                'FontSize', 11, 'FontWeight', 'bold', 'Color', c_text);
            xlabel(ax1, 'Bandwidth (Hz)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
            ylabel(ax1, 'Probability Density', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
            legend(ax1, 'Location', 'best', 'TextColor', c_text, 'Color', [0.08 0.10 0.15], 'EdgeColor', c_grid);

            % --- Subplot 2: TiB Stability ---
            ax2 = subplot(1, 3, 2);
            set(ax2, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, ...
                'GridColor', c_grid, 'LineWidth', 1.0);
            hold(ax2, 'on'); grid(ax2, 'on');

            for k = 1:num_data
                win_sizes = results{k}.slice_bw.fairness_window_sec;
                fair = results{k}.slice_bw.all_tib;
                if ~isempty(win_sizes) && ~isempty(fair)
                    c = colors(mod(k-1, size(colors,1))+1, :);
                    plot(ax2, win_sizes, fair, '-o', 'Color', c, 'LineWidth', 2, 'MarkerSize', 5, ...
                        'DisplayName', [results{k}.meta.name ' (TiB Watershed)']);
                end
                % (Envelope TiB plotting removed)
            end
            ylabel(ax2, 'Mean Time-in-Band (TiB)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
            ylim(ax2, [0, 1.05]);
            title(ax2, 'TiB Stability vs. Window Size N', ...
                'FontSize', 11, 'FontWeight', 'bold', 'Color', c_text);
            xlabel(ax2, 'Window Size N (seconds)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
            legend(ax2, 'Location', 'best', 'TextColor', c_text, 'Color', [0.08 0.10 0.15], 'EdgeColor', c_grid);

            % --- Subplot 3: Entropy Stability ---
            ax3 = subplot(1, 3, 3);
            set(ax3, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, ...
                'GridColor', c_grid, 'LineWidth', 1.0);
            hold(ax3, 'on'); grid(ax3, 'on');

            for k = 1:num_data
                win_sizes = results{k}.slice_bw.fairness_window_sec;
                ent = results{k}.slice_bw.all_entropy;
                if ~isempty(win_sizes) && ~isempty(ent)
                    c = colors(mod(k-1, size(colors,1))+1, :);
                    plot(ax3, win_sizes, 1 - ent, '-s', 'Color', c, 'LineWidth', 2, 'MarkerSize', 5, ...
                        'DisplayName', [results{k}.meta.name ' (Entropy Watershed)']);
                end
            end
            ylabel(ax3, 'Stability (1 - H_{norm})', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
            ylim(ax3, [0, 1.05]);

            title(ax3, 'Entropy Stability vs. Window Size N', ...
                'FontSize', 11, 'FontWeight', 'bold', 'Color', c_text);
            xlabel(ax3, 'Window Size N (seconds)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
            legend(ax3, 'Location', 'best', 'TextColor', c_text, 'Color', [0.08 0.10 0.15], 'EdgeColor', c_grid);

        end

        % MODULE 9E: FIGURE 5 - OUTLIER SIGNAL SEGMENTS


        function render_outlier_figures(results, cfg)
            num_data = length(results);
            c_bg   = [0.07 0.09 0.13];
            c_ax   = [0.10 0.12 0.18];
            c_text = [0.92 0.94 0.97];
            c_grid = [0.20 0.24 0.32];

            figure('Name', 'Figure 5: Outlier Signal Segments (Furthest from Mean BW)', ...
                'Color', c_bg, 'Position', [150, 180, 1600, 470]);

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
                set(ax, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, ...
                    'GridColor', c_grid, 'LineWidth', 1.0);
                hold(ax, 'on'); grid(ax, 'on');

                f_seg = outlier_slice.f_segment;
                mag_db = 20 * log10(outlier_slice.mag_segment + eps);
                nf_db = 20 * log10(outlier_slice.noise_floor + eps);
                target_mag_db = 20 * log10(outlier_slice.target_mag + eps);

                % Plot the raw magnitude
                plot(ax, f_seg, mag_db, 'Color', [0.20 0.82 1.00], 'LineWidth', 1.2, ...
                    'DisplayName', sprintf('Slice %d (BW: %.1f Hz)', outlier_slice.slice_idx, outlier_slice.main_bw));

                % (Lower Envelope trace removed)

                % Plot Noise Floor
                yline(ax, nf_db, 'Color', [0.8 0.4 0.4], 'LineStyle', '--', 'LineWidth', 1.2, ...
                    'DisplayName', 'Ambient Noise Floor');

                % Markers for Watershed BW
                plot(ax, outlier_slice.l_freq, target_mag_db, 'd', 'MarkerEdgeColor', [1.0 0.2 0.2], ...
                    'MarkerFaceColor', [1.0 0.2 0.2], 'MarkerSize', 6, 'HandleVisibility', 'off');
                plot(ax, outlier_slice.r_freq, target_mag_db, 'd', 'MarkerEdgeColor', [1.0 0.2 0.2], ...
                    'MarkerFaceColor', [1.0 0.2 0.2], 'MarkerSize', 6, 'HandleVisibility', 'off');

                % (Envelope Markers removed)

                title(ax, sprintf('%s: Outlier Slice (Dev: %.1f Hz from Mean %.1f Hz)', r.meta.name, abs(outlier_slice.main_bw - mean_bw), mean_bw), ...
                    'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
                xlabel(ax, 'Frequency (Hz)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
                ylabel(ax, 'Magnitude (dB)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
                legend(ax, 'Location', 'best', 'TextColor', c_text, 'Color', [0.08 0.10 0.15], 'EdgeColor', c_grid);
            end
        end


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

        % MODULE 9B: FIGURE 2 - DOMINANT FREQUENCY BANDWIDTH (WATERSHED)

    end
end



