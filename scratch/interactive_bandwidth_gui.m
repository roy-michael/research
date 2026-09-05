function interactive_bandwidth_gui()
    % INTERACTIVE_BANDWIDTH_GUI Creates a MATLAB UI to load an audio file,
    % calculate the Diamant et al. bandwidth, and allow interactive zooming.

    % Create UI Figure
    fig = uifigure('Name', 'Interactive Bandwidth Calculator (Diamant)', 'Position', [100, 100, 1000, 850]);
    
    % Create axes for Time Domain
    ax_time = uiaxes(fig, 'Position', [50, 480, 900, 300]);
    title(ax_time, 'Time Domain (Transient Isolation)');
    xlabel(ax_time, 'Time (s)');
    ylabel(ax_time, 'Amplitude');
    grid(ax_time, 'on');
    
    % Create axes for Frequency Domain
    ax_freq = uiaxes(fig, 'Position', [50, 120, 900, 300]);
    title(ax_freq, 'Frequency Domain (PSD & Bandwidth)');
    xlabel(ax_freq, 'Frequency (Hz)');
    ylabel(ax_freq, 'PSD');
    grid(ax_freq, 'on');
    
    % Enable built-in interactive zooming and panning for uiaxes
    % This provides the zoom/pan toolbar at the top right of each axes
    enableDefaultInteractivity(ax_time);
    enableDefaultInteractivity(ax_freq);
    
    % Create Load Button
    uibutton(fig, 'Position', [50, 800, 150, 35], 'Text', 'Load Audio File', ...
        'ButtonPushedFcn', @(btn,event) load_and_analyze(ax_time, ax_freq, fig));
        
    % Create Filter UI Elements
    uilabel(fig, 'Position', [50, 765, 100, 22], 'Text', 'Filter Range (Hz):', 'FontWeight', 'bold');
    edit_fmin = uieditfield(fig, 'numeric', 'Position', [160, 765, 60, 22], 'Value', 400);
    uilabel(fig, 'Position', [225, 765, 20, 22], 'Text', '-');
    edit_fmax = uieditfield(fig, 'numeric', 'Position', [240, 765, 60, 22], 'Value', 1200);
    cb_filter = uicheckbox(fig, 'Position', [310, 765, 100, 22], 'Text', 'Apply Filter', 'Value', true, 'FontWeight', 'bold');
    
    setappdata(fig, 'edit_fmin', edit_fmin);
    setappdata(fig, 'edit_fmax', edit_fmax);
    setappdata(fig, 'cb_filter', cb_filter);
        
    % Create Label for results
    lbl_result = uilabel(fig, 'Position', [220, 800, 700, 35], ...
        'Text', 'Click "Load Audio File" to begin...', ...
        'FontSize', 14, 'FontWeight', 'bold');
    
    % Store the label in figure appdata so the callback can access it
    setappdata(fig, 'lbl_result', lbl_result);
end

function load_and_analyze(ax_time, ax_freq, fig)
    % Get last used path
    last_path = getappdata(fig, 'last_path');
    if isempty(last_path)
        last_path = pwd;
    end
    
    % Prompt user to select file
    [file, path] = uigetfile({'*.wav', 'Audio Files (*.wav)'}, 'Select Audio File', last_path);
    if isequal(file, 0)
        return; % User canceled
    end
    
    % Save the path for next time
    setappdata(fig, 'last_path', path);
    
    lbl_result = getappdata(fig, 'lbl_result');
    lbl_result.Text = 'Processing... Please wait.';
    drawnow;
    
    try
        % Read audio
        [data, fs] = audioread(fullfile(path, file));
        if size(data, 2) > 1
            data = data(:, 1); % Convert stereo to mono
        end
        
        % Apply Bandpass Filter if checked
        cb_filter = getappdata(fig, 'cb_filter');
        if cb_filter.Value
            edit_fmin = getappdata(fig, 'edit_fmin');
            edit_fmax = getappdata(fig, 'edit_fmax');
            f1 = edit_fmin.Value;
            f2 = edit_fmax.Value;
            
            if f1 >= f2
                error('Min frequency must be less than Max frequency.');
            end
            
            if fs > 2 * f2 % Nyquist requirement
                lbl_result.Text = sprintf('Filtering signal (%.0f-%.0f Hz)...', f1, f2);
                drawnow;
                data = bandpass(data, [f1 f2], fs);
            else
                error('Sample rate (%.0f Hz) is too low to apply a %.0f Hz filter.', fs, f2);
            end
        end
        
        time_vec = (0:length(data)-1) / fs;
        
        % Reset axes modes in case user interactively zoomed in the previous file
        ax_time.XLimMode = 'auto';
        ax_time.YLimMode = 'auto';
        
        % Compute time-domain envelope
        data_env = abs(hilbert(data));
        
        % Plot full time domain with envelopes
        cla(ax_time);
        plot(ax_time, time_vec, data, 'b-', 'LineWidth', 0.5);
        hold(ax_time, 'on');
        plot(ax_time, time_vec, data_env, 'r--', 'LineWidth', 1.0);
        plot(ax_time, time_vec, -data_env, 'r--', 'LineWidth', 1.0);
        hold(ax_time, 'off');
        
        xlim(ax_time, [0, time_vec(end)]);
        title(ax_time, 'Time Domain (Full File) with Envelopes');
        legend(ax_time, {'Signal', 'Upper/Lower Envelope'}, 'Location', 'northeast');
        
        % Compute the overall PSD using pwelch with averaging
        nfft = 8192; 
        window_length = 8192;
        overlap = round(window_length * 0.5);
        [pxx, f] = pwelch(data, hanning(window_length), overlap, nfft, fs);
        
        % Limit frequency view based on filter or default to 4000
        if cb_filter.Value
            max_plot_f = min(fs/2, getappdata(fig, 'edit_fmax').Value * 2);
        else
            max_plot_f = min(fs/2, 4000);
        end
        
        mask = f >= 0 & f <= max_plot_f;
        f_zoom = f(mask);
        v = pxx(mask);
        
        % 1. Noise Floor Normalization
        % Estimate ambient noise using median (ignores dominant peaks) and subtract
        noise_floor = median(v);
        
        v_norm = v - noise_floor;
        v_norm(v_norm < 0) = 0; % Ensure non-negative power for RMS calculation
        
        % 2. Isolate the Dominant Lobe (Robust 10% Power Threshold)
        % To prevent the centroid from being pulled between two disconnected peaks
        % (e.g., a peak at 400Hz and a peak at 850Hz), we isolate the main lobe 
        % around the absolute maximum peak. We define the lobe as the contiguous 
        % region where power remains above 10% of the peak maximum.
        [max_val, f_hat_idx] = max(v_norm);
        thresh = 0.1 * max_val;
        
        left_idx = f_hat_idx;
        while left_idx > 1 && v_norm(left_idx-1) > thresh
            left_idx = left_idx - 1;
        end
        
        right_idx = f_hat_idx;
        while right_idx < length(v_norm) && v_norm(right_idx+1) > thresh
            right_idx = right_idx + 1;
        end
        
        % Extract just the dominant lobe for RMS
        f_lobe = f_zoom(left_idx:right_idx);
        v_lobe = v_norm(left_idx:right_idx);
        
        % 3. Root-Mean-Square (RMS) Bandwidth Calculation
        % Treat the isolated lobe as a probability distribution
        total_power = sum(v_lobe);
        if total_power > 0
            f_centroid = sum(f_lobe .* v_lobe) / total_power;
            % RMS Bandwidth (standard deviation around centroid)
            bw_rms = sqrt(sum(((f_lobe - f_centroid).^2) .* v_lobe) / total_power);
        else
            f_centroid = f_zoom(f_hat_idx);
            bw_rms = 0;
        end
        
        % Define edges for visualization (Centroid +/- 1 RMS bandwidth)
        f_left = f_centroid - bw_rms;
        f_right = f_centroid + bw_rms;
        
        % Plot frequency domain
        ax_freq.XLimMode = 'auto';
        ax_freq.YLimMode = 'auto';
        cla(ax_freq);
        
        % Plot ORIGINAL PSD so no frequencies are visually hidden!
        p_psd = plot(ax_freq, f_zoom, v, 'b-', 'LineWidth', 1.5);
        hold(ax_freq, 'on');
        
        % Plot the noise floor threshold
        p_noise = plot(ax_freq, [f_zoom(1) f_zoom(end)], [noise_floor noise_floor], 'r:', 'LineWidth', 1.5);
        
        % Force UI update so ylim gets the correct data bounds for the green patch
        drawnow; 
        y_lims = ylim(ax_freq);
        
        % Shaded bandwidth region (+/- 1 RMS bandwidth)
        p_patch = patch(ax_freq, [f_left f_right f_right f_left], [y_lims(1) y_lims(1) y_lims(2) y_lims(2)], 'g', 'FaceAlpha', 0.2, 'EdgeColor', 'none');
        
        % Plot markers and edges (plotted on the original PSD curve)
        [~, c_idx] = min(abs(f_zoom - f_centroid));
        p_centroid = plot(ax_freq, f_centroid, v(c_idx), 'ro', 'MarkerSize', 8, 'LineWidth', 2);
        p_edges = plot(ax_freq, [f_left f_left], y_lims, 'k--', 'LineWidth', 1.5);
        plot(ax_freq, [f_right f_right], y_lims, 'k--', 'LineWidth', 1.5);
        
        hold(ax_freq, 'off');
        
        % Show the full requested spectrum so the user has context (they can interactively zoom)
        xlim(ax_freq, [0, max_plot_f]);
        ylim(ax_freq, 'auto');
        
        legend(ax_freq, [p_psd, p_patch, p_centroid, p_edges, p_noise], ...
            {'Original PSD', 'RMS Bandwidth (+/- 1 \sigma)', 'Lobe Centroid', 'Bandwidth Edges', 'Median Noise Floor'}, 'Location', 'northeast');
        title(ax_freq, 'Frequency Domain (RMS Bandwidth)');
        
        % Update label
        lbl_result.Text = sprintf('Loaded: %s | Centroid Freq: %.1f Hz | RMS Bandwidth (\\sigma): %.1f Hz', file, f_centroid, bw_rms);
        
    catch ME
        lbl_result.Text = ['Error: ' ME.message];
    end
end
