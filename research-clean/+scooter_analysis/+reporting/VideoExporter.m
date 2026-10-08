classdef VideoExporter
    % VideoExporter - Welch diagram video sequence export.
    %
    % Isolated video-writing logic extracted from the original scripts.
    % Generates an MP4 video animating the Welch PSD with macro-lobe
    % segmentation across all segments of a file.
    %
    % Usage:
    %   scooter_analysis.reporting.VideoExporter.welchDiagramSeries( ...
    %       fr, cfg, vid_path);
    
    methods (Static)
        
        function welchDiagramSeries(fr, cfg, vid_path)
            % Generate an animated MP4 of Welch PSD diagrams across segments.
            %
            % Args:
            %   fr       - scooter_analysis.results.FileResult
            %   cfg      - scooter_analysis.config.AnalysisConfig
            %   vid_path - Output video file path
            
            if isempty(fr.segments)
                return;
            end
            
            % Ensure output directory exists
            vid_dir = fileparts(vid_path);
            if ~exist(vid_dir, 'dir')
                mkdir(vid_dir);
            end
            
            % Setup VideoWriter
            vid_obj = VideoWriter(vid_path, 'MPEG-4');
            vid_obj.FrameRate = cfg.video_frame_rate;
            open(vid_obj);
            
            % Unified publication dark-theme colors
            c_bg   = [0.08 0.11 0.17];
            c_ax   = [0.10 0.13 0.20];
            c_text = [0.88 0.91 0.96];
            c_grid = [0.22 0.27 0.36];
            c_psd  = [0.28 0.75 1.00]; % Electric Sky Blue
            c_dom  = [1.00 0.42 0.42]; % Neon Coral
            c_amb  = [1.00 0.75 0.25]; % Bright Amber
            
            h_fig = figure('Name', 'Welch Diagrams Series', ...
                'Position', [100, 100, 1000, 600], 'Color', c_bg, 'Visible', 'off');
            % Force exact pixel dimensions (both even) for H.264 codec
            set(h_fig, 'Units', 'pixels', 'Position', [100, 100, 1000, 600]);
            set(h_fig, 'Renderer', 'opengl');
            
            for i = 1:length(fr.segments)
                sr = fr.segments(i);
                
                clf(h_fig);
                ax = axes(h_fig);
                set(ax, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, ...
                    'GridColor', c_grid, 'GridAlpha', 0.50, 'LineWidth', 1.0);
                hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');
                
                psd_db = sr.psd_db;
                f_grid = sr.f_grid;
                y_floor = min(psd_db) - 3;
                
                % Plot Secondary Lobes
                if isstruct(sr.macro_lobes) && ~isempty(fieldnames(sr.macro_lobes))
                    for k_l = 1:length(sr.macro_lobes)
                        lob = sr.macro_lobes(k_l);
                        if isstruct(sr.dom_lobe) && isfield(sr.dom_lobe, 'f_start') && ...
                                lob.f_start == sr.dom_lobe.f_start
                            continue;
                        end
                        idx_m = (f_grid >= lob.f_start) & (f_grid <= lob.f_end);
                        if any(idx_m)
                            fill(ax, [f_grid(idx_m); flipud(f_grid(idx_m))], ...
                                [psd_db(idx_m); y_floor * ones(sum(idx_m), 1)], ...
                                [0.28 0.75 1.00], 'FaceAlpha', 0.18, 'EdgeColor', 'none', ...
                                'HandleVisibility', 'off');
                        end
                    end
                end
                
                % Plot Dominant Lobe
                if isstruct(sr.dom_lobe) && isfield(sr.dom_lobe, 'f_start')
                    idx_dom = (f_grid >= sr.dom_lobe.f_start) & (f_grid <= sr.dom_lobe.f_end);
                    f_dom = f_grid(idx_dom);
                    p_dom = psd_db(idx_dom);
                    if ~isempty(f_dom)
                        fill(ax, [f_dom; flipud(f_dom)], [p_dom; y_floor * ones(size(p_dom))], ...
                            c_dom, 'FaceAlpha', 0.25, 'EdgeColor', 'none', ...
                            'DisplayName', sprintf('Dominant Lobe [%0.1f-%0.1f Hz | %0.1f%%]', ...
                            sr.dom_lobe.f_start, sr.dom_lobe.f_end, sr.dom_lobe.pct_energy));
                    end
                end
                
                % Plot Ambient Baseline
                if ~isempty(sr.ocean_floor)
                    plot(ax, f_grid, sr.ocean_floor, 'Color', c_amb, ...
                        'LineStyle', ':', 'LineWidth', 1.5, ...
                        'DisplayName', sprintf('Ambient Baseline (%.1f dB)', sr.ocean_ambient_db));
                end
                
                % Plot PSD
                plot(ax, f_grid, psd_db, 'Color', c_psd, ...
                    'LineWidth', 1.4, 'DisplayName', 'Welch PSD');
                
                xlim(ax, [cfg.f_low, cfg.f_high]);
                ylim(ax, [y_floor, max(psd_db) + 5]);
                xlabel(ax, 'Frequency (Hz)', 'FontSize', 11, 'FontWeight', 'bold', 'Color', c_text);
                ylabel(ax, 'PSD (dB)', 'FontSize', 11, 'FontWeight', 'bold', 'Color', c_text);
                title(ax, sprintf('Segment %d: %.1fs - %.1fs', i, sr.start_time, sr.end_time), ...
                    'FontSize', 12, 'FontWeight', 'bold', 'Color', [0.96 0.98 1.00]);
                lgd = legend(ax, 'Location', 'northeast', 'TextColor', [0.92 0.94 0.98], ...
                    'Color', [0.12 0.16 0.24], 'EdgeColor', [0.26 0.32 0.42], 'Interpreter', 'none');
                
                frame = getframe(h_fig);
                % Ensure frame dimensions are even for H.264 codec
                [fh, fw, ~] = size(frame.cdata);
                if mod(fw, 2) ~= 0
                    frame.cdata = frame.cdata(:, 1:end-1, :);
                end
                if mod(fh, 2) ~= 0
                    frame.cdata = frame.cdata(1:end-1, :, :);
                end
                writeVideo(vid_obj, frame);
            end
            
            close(vid_obj);
            close(h_fig);
            
            fprintf('[VideoExporter] Video saved: %s\n', vid_path);
        end
        
    end
end
