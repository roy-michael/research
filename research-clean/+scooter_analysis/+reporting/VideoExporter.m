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
            
            % Dark theme colors
            c_bg   = [0.082 0.133 0.263];
            c_ax   = [0.050 0.080 0.160];
            c_text = [0.918 0.941 0.965];
            c_grid = [0.325 0.467 0.569];
            
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
                    'GridColor', c_grid, 'GridAlpha', 0.5, 'LineWidth', 1.0);
                hold(ax, 'on'); grid(ax, 'on');
                
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
                                [0.30 0.65 0.95], 'FaceAlpha', 0.18, 'EdgeColor', 'none', ...
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
                            [0.90 0.25 0.35], 'FaceAlpha', 0.35, 'EdgeColor', 'none', ...
                            'DisplayName', sprintf('Dominant Lobe [%0.1f-%0.1f Hz | %0.1f%%]', ...
                            sr.dom_lobe.f_start, sr.dom_lobe.f_end, sr.dom_lobe.pct_energy));
                    end
                end
                
                % Plot Ambient Baseline
                if ~isempty(sr.ocean_floor)
                    plot(ax, f_grid, sr.ocean_floor, 'Color', [0.961 0.690 0.255], ...
                        'LineStyle', ':', 'LineWidth', 1.5, ...
                        'DisplayName', sprintf('Ambient Baseline (%.1f dB)', sr.ocean_ambient_db));
                end
                
                % Plot PSD
                plot(ax, f_grid, psd_db, 'Color', [0.220 0.659 0.631], ...
                    'LineWidth', 1.5, 'DisplayName', 'Welch PSD');
                
                xlim(ax, [cfg.f_low, cfg.f_high]);
                ylim(ax, [y_floor, max(psd_db) + 5]);
                xlabel(ax, 'Frequency (Hz)', 'FontSize', 12);
                ylabel(ax, 'PSD (dB)', 'FontSize', 12);
                title(ax, sprintf('Segment %d: %.1fs - %.1fs', i, sr.start_time, sr.end_time), ...
                    'FontSize', 14, 'Color', c_text);
                legend(ax, 'Location', 'northeast', 'TextColor', c_text, 'Color', c_bg);
                
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
