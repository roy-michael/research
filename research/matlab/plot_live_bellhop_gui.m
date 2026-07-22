% plot_live_bellhop_gui.m
% Interactive Live BELLHOP Acoustic Ray-Tracing & Multipath Simulator in MATLAB.
% Drag the Red Source Star (Vessel) or Green Receiver Circle anywhere in the water/air
% to update acoustic rays and multipath channel impulse response in real time!
% Supports above-water vessel engine noise (air-to-water transmission loss) and
% underwater propeller noise. Displays discrete arrivals, convolved received waveform,
% and convolved continuous Welch Power Spectral Density (PSD) spectrum.

function plot_live_bellhop_gui()
    % Resolve paths
    script_dir = fileparts(mfilename('fullpath'));
    workspace_dir = fullfile(script_dir, '..', '..');
    bin_path = fullfile(workspace_dir, 'bellhopcuda', 'bellhopcxx.exe');
    if ~exist(bin_path, 'file')
        bin_path = 'bellhop.exe';
    end
    
    file_root = fullfile(script_dir, 'live_sim_matlab');
    env_file = [file_root '.env'];
    ray_file = [file_root '.ray'];
    arr_file = [file_root '.arr'];
    
    % Ocean Parameters
    water_depth = 50.0; % meters
    max_range = 1000.0; % meters
    freq_hz = 500.0;
    salinity = 38.0;   % PSU (Salt sea - e.g., Mediterranean/Croatia)
    
    % Wave parameters (Interactive)
    wave_height_m = 0.8; % Peak-to-peak wave height
    wave_period_s = 4.0; % Wave period
    
    % Initial Positions & States
    src_range = 0.0;
    src_depth = 10.0;
    rcv_range = 600.0;
    rcv_depth = 25.0;
    src_vel = 0.0;     % Source horizontal velocity (m/s) towards receiver
    engine_noise_db = -70.0; % Decibel noise floor
    
    % Constant Vessel Source Intensity (Reference pressure amplitude at 1m)
    vessel_src_amp = 0.001; 
    
    active_drag = '';
    
    % Create Figure
    fig = figure('Name', 'Live Interactive BELLHOP Acoustic Simulator (MATLAB GUI)', ...
                 'Position', [100, 100, 1400, 950], 'Color', [0.06, 0.09, 0.16]);
    
    % Subplots: Ray tracing takes upper half, lower split into 3 panels
    ax_rays = subplot(4, 3, [1, 2, 3, 4, 5, 6], 'Parent', fig);
    ax_arr  = subplot(4, 3, [7, 10], 'Parent', fig);
    ax_sig  = subplot(4, 3, [8, 11], 'Parent', fig);
    ax_dop  = subplot(4, 3, [9, 12], 'Parent', fig);
    
    % Adjust margins for controls
    set(ax_rays, 'Position', [0.08, 0.48, 0.85, 0.45]);
    set(ax_arr, 'Position', [0.08, 0.14, 0.25, 0.26]);
    set(ax_sig, 'Position', [0.38, 0.14, 0.25, 0.26]);
    set(ax_dop, 'Position', [0.68, 0.14, 0.25, 0.26]);
    
    % --- Add Speed Slider UI Controls ---
    lbl_speed = uicontrol('Style', 'text', 'Parent', fig, ...
                          'String', 'Source Velocity: 0.0 m/s', ...
                          'Units', 'normalized', 'Position', [0.08, 0.06, 0.22, 0.025], ...
                          'BackgroundColor', [0.06, 0.09, 0.16], 'ForegroundColor', 'w', ...
                          'FontSize', 10, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
                      
    slider_speed = uicontrol('Style', 'slider', 'Parent', fig, ...
                             'Min', -10, 'Max', 10, 'Value', 0, ...
                             'Units', 'normalized', 'Position', [0.08, 0.02, 0.22, 0.03], ...
                             'Callback', @on_speed_change);
                         
    % --- Add Wave Height Slider UI Controls ---
    lbl_wave = uicontrol('Style', 'text', 'Parent', fig, ...
                          'String', 'Boat Wave Height: 0.8 m', ...
                          'Units', 'normalized', 'Position', [0.38, 0.06, 0.22, 0.025], ...
                          'BackgroundColor', [0.06, 0.09, 0.16], 'ForegroundColor', 'w', ...
                          'FontSize', 10, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
                      
    slider_wave = uicontrol('Style', 'slider', 'Parent', fig, ...
                             'Min', 0, 'Max', 3.0, 'Value', 0.8, ...
                             'Units', 'normalized', 'Position', [0.38, 0.02, 0.22, 0.03], ...
                             'Callback', @on_wave_change);
                         
    % --- Add Ambient Noise Slider UI Controls ---
    lbl_noise = uicontrol('Style', 'text', 'Parent', fig, ...
                          'String', 'Ambient Noise Floor: -70 dB (Moderate)', ...
                          'Units', 'normalized', 'Position', [0.68, 0.06, 0.22, 0.025], ...
                          'BackgroundColor', [0.06, 0.09, 0.16], 'ForegroundColor', 'w', ...
                          'FontSize', 10, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
                      
    slider_noise = uicontrol('Style', 'slider', 'Parent', fig, ...
                             'Min', -95, 'Max', -45, 'Value', -70, ...
                             'Units', 'normalized', 'Position', [0.68, 0.02, 0.22, 0.03], ...
                             'Callback', @on_noise_change);
    
    % Set Mouse Callbacks
    set(fig, 'WindowButtonDownFcn', @on_press);
    set(fig, 'WindowButtonMotionFcn', @on_motion);
    set(fig, 'WindowButtonUpFcn', @on_release);
    
    % Run Initial Simulation
    update_sim();
    
    % --- Callbacks ---
    function on_speed_change(hObject, ~)
        src_vel = get(hObject, 'Value');
        set(lbl_speed, 'String', sprintf('Source Velocity: %.1f m/s', src_vel));
        update_sim();
    end

    function on_wave_change(hObject, ~)
        wave_height_m = get(hObject, 'Value');
        set(lbl_wave, 'String', sprintf('Boat Wave Height: %.1f m', wave_height_m));
        update_sim();
    end

    function on_noise_change(hObject, ~)
        engine_noise_db = get(hObject, 'Value');
        if engine_noise_db < -80
            desc = 'Very Quiet';
        elseif engine_noise_db < -65
            desc = 'Moderate';
        elseif engine_noise_db < -55
            desc = 'Loud';
        else
            desc = 'Extreme';
        end
        set(lbl_noise, 'String', sprintf('Ambient Noise Floor: %.0f dB (%s)', engine_noise_db, desc));
        update_sim();
    end
    
    % --- Main Update Function ---
    function update_sim()
        persistent is_running needs_update
        if isempty(is_running), is_running = false; end
        if isempty(needs_update), needs_update = false; end
        
        if is_running
            needs_update = true;
            return;
        end
        
        is_running = true;
        
        while true
            needs_update = false;
            
            % Delete stale files to guarantee clean updates
            if exist(ray_file, 'file'), delete(ray_file); end
            if exist(arr_file, 'file'), delete(arr_file); end
            
            try
                % Determine if source is above water (airborne noise)
                is_airborne = (src_depth < 0);
                
                % 1. Write and run standard Ray Tracing ('R')
                write_env('R');
                [~, ~] = system(sprintf('"%s" "%s"', bin_path, file_root));
                all_rays = read_rays(ray_file);
                if exist(ray_file, 'file'), delete(ray_file); end
                
                % 2. Write and run Arrivals ('A')
                write_env('A');
                [~, ~] = system(sprintf('"%s" "%s"', bin_path, file_root));
                arrivals = read_arrivals(arr_file);
                if exist(arr_file, 'file'), delete(arr_file); end
                
                % 3. Write and run Eigenray Tracing ('E') - finds specific arriving rays
                write_env('E');
                [~, ~] = system(sprintf('"%s" "%s"', bin_path, file_root));
                eigen_rays = read_rays(ray_file);
                
                % Sound speed at surface and source depth (for Doppler calculation)
                T_surf = 20.0;
                c_surf = 1449.05 + 4.57 * T_surf - 5.21e-2 * T_surf^2 + 2.3e-4 * T_surf^3 ...
                       + (1.333 - 1.26e-2 * T_surf + 9.0e-5 * T_surf^2) * (salinity - 35);
                
                % Sound speed at source (clamped to surface speed if in air)
                if is_airborne
                    c_s = 340.0; % Sound speed in air (m/s)
                else
                    T_s = 20.0 - 8.0 * (src_depth / water_depth);
                    c_s = 1449.05 + 4.57 * T_s - 5.21e-2 * T_s^2 + 2.3e-4 * T_s^3 ...
                        + (1.333 - 1.26e-2 * T_s + 9.0e-5 * T_s^2) * (salinity - 35) ...
                        + 1.63e-2 * src_depth + 1.8e-7 * src_depth^2;
                end
                
                % Apply Seawater Absorption Attenuation (Francois-Garrison Model)
                % and calculate Doppler shifts
                f_khz = freq_hz / 1000;
                alpha_db_km = (0.11 * f_khz^2 / (1 + f_khz^2)) + (44.0 * f_khz^2 / (4100 + f_khz^2)) + (0.0003 * f_khz^2);
                
                % Peak surface wave vertical velocity
                wave_amp = wave_height_m / 2;
                wave_freq = 1 / wave_period_s;
                v_wave_max = 2 * pi * wave_amp * wave_freq;
                
                % Airborne parameters
                air_trans_loss = 10^(-30/20); % -30 dB transmission loss crossing air-water interface
                
                valid_indices = [];
                for k = 1:length(arrivals)
                    path_dist_m = arrivals(k).delay * 1500;
                    loss_factor = 10^(-(alpha_db_km * (path_dist_m / 1000)) / 20);
                    arrivals(k).amp = arrivals(k).amp * loss_factor;
                    
                    % Mean Doppler frequency shift due to source motion
                    theta_deg = arrivals(k).src_angle;
                    f_mean = freq_hz * (1 + (src_vel * cosd(theta_deg)) / c_s);
                    arrivals(k).freq = f_mean;
                    
                    % Dynamic Doppler spread due to surface wave vertical motion
                    if arrivals(k).surf > 0
                        df_wave = freq_hz * arrivals(k).surf * (2 * v_wave_max * abs(sind(theta_deg))) / c_surf;
                    else
                        df_wave = 0;
                    end
                    arrivals(k).df_wave = df_wave;
                    
                    if is_airborne
                        arrivals(k).amp = arrivals(k).amp * air_trans_loss;
                        % Critical angle refraction filter: Only vertical cone reaches water.
                        if abs(arrivals(k).src_angle) >= 77.0
                            valid_indices = [valid_indices, k];
                        end
                    else
                        valid_indices = [valid_indices, k];
                    end
                end
                arrivals = arrivals(valid_indices);
                
                % 4. Plot Ray Trace Panel
                delete(allchild(ax_rays));
                set(ax_rays, 'Color', [0.06, 0.09, 0.16]);
                hold(ax_rays, 'on');
                
                % Shaded air region above water (sky-gray)
                fill(ax_rays, [0, max_range, max_range, 0], [-6, -6, 0, 0], [0.18, 0.22, 0.29], 'EdgeColor', 'none', 'DisplayName', 'Air');
                
                % Sea Surface & Seabed
                plot(ax_rays, [0, max_range], [0, 0], 'Color', [0.22, 0.74, 0.97], 'LineWidth', 2.5, 'DisplayName', 'Sea Surface (Air-Water Boundary)');
                plot(ax_rays, [0, max_range], [water_depth, water_depth], 'Color', [0.71, 0.33, 0.04], 'LineWidth', 3, 'DisplayName', 'Seabed (1600 m/s)');
                
                % Plot background propagation rays
                for k = 1:length(all_rays)
                    plot(ax_rays, all_rays{k}.r, all_rays{k}.z, 'Color', [0.22, 0.74, 0.97, 0.08], 'LineWidth', 0.5, 'HandleVisibility', 'off');
                end
                
                % Plot highlighted eigenrays
                if ~isempty(arrivals) && ~isempty(eigen_rays)
                    max_amp = max([arrivals.amp]);
                    if max_amp == 0, max_amp = 1; end
                    
                    num_eigen = min(length(eigen_rays), length(arrivals));
                    for k = 1:num_eigen
                        norm_amp = arrivals(k).amp / max_amp;
                        lw = 0.5 + 2.5 * norm_amp;
                        alpha_val = 0.15 + 0.85 * norm_amp;
                        col = [0.22, 0.44, 0.65] * (1 - norm_amp) + [0.96, 0.62, 0.04] * norm_amp;
                        
                        % Draw airborne ray segment if source is above water
                        if is_airborne
                            plot(ax_rays, [src_range, eigen_rays{k}.r(1)], [src_depth, 0], 'Color', [0.71, 0.75, 0.81, alpha_val], 'LineWidth', lw, 'HandleVisibility', 'off');
                        end
                        
                        if k == 1
                            plot(ax_rays, eigen_rays{k}.r, eigen_rays{k}.z, 'Color', [col, alpha_val], 'LineWidth', lw, 'DisplayName', 'Arriving Ray (Eigenray)');
                        else
                            plot(ax_rays, eigen_rays{k}.r, eigen_rays{k}.z, 'Color', [col, alpha_val], 'LineWidth', lw, 'HandleVisibility', 'off');
                        end
                    end
                end
                
                % Direct connection reference line
                plot(ax_rays, [src_range, rcv_range], [src_depth, rcv_depth], 'w:', 'LineWidth', 1, 'HandleVisibility', 'off');
                
                % Source & Receiver Handles
                plot(ax_rays, src_range, src_depth, 'r*', 'MarkerSize', 16, 'LineWidth', 2, 'DisplayName', sprintf('Source (%.1fm)', src_depth));
                plot(ax_rays, rcv_range, rcv_depth, 'go', 'MarkerSize', 12, 'MarkerFaceColor', 'g', 'DisplayName', sprintf('Receiver (%.0fm, %.1fm)', rcv_range, rcv_depth));
                
                hold(ax_rays, 'off');
                grid(ax_rays, 'on');
                set(ax_rays, 'GridColor', [0.58, 0.64, 0.72], 'GridAlpha', 0.3);
                axis(ax_rays, [0, max_range, -6, water_depth + 2]);
                set(ax_rays, 'YDir', 'reverse');
                xlabel(ax_rays, 'Range [m]', 'Color', 'w', 'FontWeight', 'bold');
                ylabel(ax_rays, 'Depth [m]', 'Color', 'w', 'FontWeight', 'bold');
                
                if is_airborne
                    title(ax_rays, 'Live Ray Tracing | Airborne Engine Noise (Refracted at Sea Surface, -30dB loss)', ...
                          'Color', 'w', 'FontSize', 12, 'FontWeight', 'bold');
                else
                    title(ax_rays, 'Live Ray Tracing | Underwater Propeller Noise (Direct Acoustic Propagation)', ...
                          'Color', 'w', 'FontSize', 12, 'FontWeight', 'bold');
                end
                legend(ax_rays, 'TextColor', 'w', 'Color', [0.12, 0.16, 0.23], 'EdgeColor', 'w', 'Location', 'southeast');
                
                % 5. Plot Channel Impulse Response Panel with Noise Floor
                delete(allchild(ax_arr));
                set(ax_arr, 'Color', [0.06, 0.09, 0.16]);
                hold(ax_arr, 'on');
                
                % Ambient noise floor level (raw scale)
                noise_std = 10^(engine_noise_db / 20);
                
                if ~isempty(arrivals)
                    delays_ms = [arrivals.delay] * 1000;
                    amps = [arrivals.amp];
                    
                    % Background Noise
                    t_noise = linspace(min(delays_ms) - 20, max(delays_ms) + 50, 150);
                    val_noise = abs(randn(size(t_noise)) * noise_std);
                    stem(ax_arr, t_noise, val_noise, 'Color', [0.45, 0.52, 0.61, 0.4], 'LineWidth', 0.8, 'Marker', 'none', 'HandleVisibility', 'off');
                    
                    % Arrivals
                    stem(ax_arr, delays_ms, amps, 'Color', [0.22, 0.74, 0.97], 'LineWidth', 2.0, 'Marker', 'none', 'DisplayName', 'Arrivals');
                    
                    for m = 1:length(arrivals)
                        if arrivals(m).surf == 0 && arrivals(m).bot == 0
                            col = [0.13, 0.77, 0.37];
                        else
                            col = [0.96, 0.62, 0.04];
                        end
                        plot(ax_arr, delays_ms(m), amps(m), 'o', 'MarkerFaceColor', col, 'MarkerEdgeColor', 'w', 'MarkerSize', 8, 'HandleVisibility', 'off');
                        text(ax_arr, delays_ms(m), amps(m) + max(amps)*0.05, sprintf('S%d/B%d', arrivals(m).surf, arrivals(m).bot), ...
                             'Color', 'w', 'FontSize', 8, 'HorizontalAlignment', 'center');
                    end
                    
                    yline(ax_arr, noise_std * 3, 'r--', 'Ambient Noise Floor', 'Color', [0.94, 0.27, 0.24], 'LabelHorizontalAlignment', 'right');
                    title(ax_arr, 'Channel Impulse Response', 'Color', 'w', 'FontSize', 11, 'FontWeight', 'bold');
                    ylim(ax_arr, [0, max(noise_std * 5, max(amps)*1.2)]);
                else
                    t_noise = linspace(100, 900, 150);
                    val_noise = abs(randn(size(t_noise)) * noise_std);
                    stem(ax_arr, t_noise, val_noise, 'Color', [0.45, 0.52, 0.61, 0.4], 'LineWidth', 0.8, 'Marker', 'none', 'HandleVisibility', 'off');
                    title(ax_arr, 'Channel Impulse Response (Noise Only)', 'Color', 'w', 'FontSize', 11, 'FontWeight', 'bold');
                    ylim(ax_arr, [0, noise_std * 5]);
                end
                hold(ax_arr, 'off');
                grid(ax_arr, 'on');
                set(ax_arr, 'GridColor', [0.58, 0.64, 0.72], 'GridAlpha', 0.3);
                xlabel(ax_arr, 'Travel Time Delay [ms]', 'Color', 'w', 'FontWeight', 'bold');
                ylabel(ax_arr, 'Absolute Amplitude |P/P0|', 'Color', 'w', 'FontWeight', 'bold');
                
                % 6. Plot Continuous Received Waveform y(t)
                delete(allchild(ax_sig));
                set(ax_sig, 'Color', [0.06, 0.09, 0.16]);
                hold(ax_sig, 'on');
                
                % Synthesize continuous signal
                t_sig_dur_s = 1.0;
                Fs = 5000.0; % 5 kHz sample rate
                t_grid_s = (0 : 1/Fs : t_sig_dur_s)';
                y_sig_raw = zeros(size(t_grid_s));
                
                % Constant Vessel Source Signal Waveform
                y_src = sin(2 * pi * freq_hz * t_grid_s) * vessel_src_amp;
                
                if ~isempty(arrivals)
                    for m = 1:length(arrivals)
                        f_m = arrivals(m).freq;
                        delay_m_s = arrivals(m).delay;
                        
                        phase_pert = 0;
                        if arrivals(m).df_wave > 0
                            phase_pert = (arrivals(m).df_wave / wave_freq) * sin(2 * pi * wave_freq * (t_grid_s - delay_m_s));
                        end
                        
                        y_path = arrivals(m).amp * sin(2 * pi * f_m * (t_grid_s - delay_m_s) + phase_pert);
                        y_sig_raw = y_sig_raw + y_path;
                    end
                    
                    % Calculate peak received amplitude and transmission loss in dB
                    max_rcv_raw = max(abs(y_sig_raw));
                    if max_rcv_raw == 0, max_rcv_raw = 1e-6; end
                    tl_db = -20 * log10(max_rcv_raw);
                    
                    % Scale the received signal dynamically to 40% of the source amplitude for visualization
                    gain_factor = (0.4 * vessel_src_amp) / max_rcv_raw;
                    y_sig_plot = y_sig_raw * gain_factor;
                    
                    % Add random ambient noise (scaled by gain_factor to match waveform plot level and show noise slider effects)
                    y_sig_plot = y_sig_plot + randn(size(t_grid_s)) * noise_std * gain_factor * 0.7;
                    
                    t_zoom_ms = 100.0;
                    n_zoom = round(t_zoom_ms / 1000 * Fs);
                    
                    % Plot CONSTANT Source Waveform (Dashed Red Line)
                    plot(ax_sig, t_grid_s(1:n_zoom) * 1000, y_src(1:n_zoom), 'r--', 'LineWidth', 1.2, 'DisplayName', 'Source (Constant)');
                    
                    % Plot Received Target Signal Waveform (Solid Green Line - scaled to 40% of Src)
                    plot(ax_sig, t_grid_s(1:n_zoom) * 1000, y_sig_plot(1:n_zoom), 'Color', [0.13, 0.77, 0.37], 'LineWidth', 1.2, ...
                         'DisplayName', 'Received (Scaled 40%)');
                    
                    title(ax_sig, 'Waveform y(t) (Zoomed 100ms)', 'Color', 'w', 'FontSize', 11, 'FontWeight', 'bold');
                    xlim(ax_sig, [0, t_zoom_ms]);
                    ylim(ax_sig, [-vessel_src_amp * 1.5, vessel_src_amp * 1.5]);
                    
                    % Display exact Transmission Loss
                    text(ax_sig, 5, -vessel_src_amp * 1.2, sprintf('Acoustic Loss: -%.1f dB', tl_db), ...
                         'Color', 'w', 'FontSize', 9, 'FontWeight', 'bold', ...
                         'BackgroundColor', [0.12, 0.16, 0.23], 'EdgeColor', 'w');
                     
                    legend(ax_sig, 'TextColor', 'w', 'Color', [0.12, 0.16, 0.23], 'EdgeColor', 'w', 'Location', 'southwest');
                else
                    y_sig_plot = randn(size(t_grid_s)) * noise_std * (0.4 * vessel_src_amp / 1e-6) * 0.7;
                    t_zoom_ms = 100.0;
                    plot(ax_sig, t_grid_s(1:round(t_zoom_ms/1000*Fs))*1000, y_sig_plot(1:round(t_zoom_ms/1000*Fs)), 'Color', [0.13, 0.77, 0.37], 'LineWidth', 1.0);
                    title(ax_sig, 'Received Waveform (Noise Only)', 'Color', 'w', 'FontSize', 11, 'FontWeight', 'bold');
                    xlim(ax_sig, [0, t_zoom_ms]);
                    ylim(ax_sig, [-vessel_src_amp * 1.5, vessel_src_amp * 1.5]);
                end
                hold(ax_sig, 'off');
                grid(ax_sig, 'on');
                set(ax_sig, 'GridColor', [0.58, 0.64, 0.72], 'GridAlpha', 0.3);
                xlabel(ax_sig, 'Time [ms]', 'Color', 'w', 'FontWeight', 'bold');
                ylabel(ax_sig, 'Pressure P(t)', 'Color', 'w', 'FontWeight', 'bold');
                
                % 7. Plot Continuous Welch PSD Diagram (High-Resolution frequency domain)
                delete(allchild(ax_dop));
                set(ax_dop, 'Color', [0.06, 0.09, 0.16]);
                hold(ax_dop, 'on');
                
                nfft = 8192; % Fine frequency bins
                
                % Synthesize received signal at true physical scale relative to source reference 1.0
                y_sig_physical = y_sig_raw + randn(size(t_grid_s)) * noise_std * 0.7;
                
                % Calculate PSD of Received Signal (Target)
                [psd_val, f_axis] = periodogram(y_sig_physical, hamming(length(y_sig_physical)), nfft, Fs);
                psd_db = 10 * log10(psd_val + 1e-15);
                
                % Plot Received Target Signal PSD (Solid Orange Line)
                plot(ax_dop, f_axis, psd_db, 'Color', [0.96, 0.62, 0.04], 'LineWidth', 1.8, 'DisplayName', 'Received Target');
                
                % Calculate plot frequency axis limits
                if ~isempty(arrivals)
                    freqs = [arrivals.freq];
                    f_min = min(freqs - [arrivals.df_wave]) - 3;
                    f_max = max(freqs + [arrivals.df_wave]) + 3;
                else
                    f_min = freq_hz - 6; f_max = freq_hz + 6;
                end
                if f_max - f_min < 12
                    f_min = freq_hz - 6; f_max = freq_hz + 6;
                end
                
                xlim(ax_dop, [f_min, f_max]);
                % Fixed decibel Y-limit adjusted to the physical scale [-120 to -30] dB
                ylim(ax_dop, [-120, -30]);
                
                title(ax_dop, 'Received Signal Welch PSD', 'Color', 'w', 'FontSize', 11, 'FontWeight', 'bold');
                
                hold(ax_dop, 'off');
                grid(ax_dop, 'on');
                set(ax_dop, 'GridColor', [0.58, 0.64, 0.72], 'GridAlpha', 0.3);
                xlabel(ax_dop, 'Frequency [Hz]', 'Color', 'w', 'FontWeight', 'bold');
                ylabel(ax_dop, 'Power Spectral Density [dB/Hz]', 'Color', 'w', 'FontWeight', 'bold');
                
                set(ax_arr, 'XColor', 'w', 'YColor', 'w');
                set(ax_sig, 'XColor', 'w', 'YColor', 'w');
                set(ax_dop, 'XColor', 'w', 'YColor', 'w');
                set(ax_rays, 'XColor', 'w', 'YColor', 'w');
                
                drawnow;
                
            catch err
                warning('Error updating simulation: %s', err.message);
            end
            
            if ~needs_update
                break;
            end
        end
        is_running = false;
    end

    % (write_env, read_rays, read_arrivals, mouse callbacks remain unchanged...)
    function write_env(run_type)
        z_ssp = [0.0, 10.0, 20.0, 30.0, 40.0, water_depth];
        c_ssp = zeros(size(z_ssp));
        
        for idx_z = 1:length(z_ssp)
            z = z_ssp(idx_z);
            T = 20.0 - 8.0 * (z / water_depth);
            
            c_val = 1449.05 + 4.57 * T - 5.21e-2 * T^2 + 2.3e-4 * T^3 ...
                  + (1.333 - 1.26e-2 * T + 9.0e-5 * T^2) * (salinity - 35) ...
                  + 1.63e-2 * z + 1.8e-7 * z^2;
            c_ssp(idx_z) = c_val;
        end
        
        bellhop_src_depth = max(0.05, src_depth);
        
        fid = fopen(env_file, 'w');
        if fid == -1, return; end
        fprintf(fid, '''Live BELLHOP Simulation (%s)''\n', run_type);
        fprintf(fid, '%.1f\n1\n''SVF''\n', freq_hz);
        fprintf(fid, '%d %.1f %.1f\n', length(z_ssp), z_ssp(1), z_ssp(end));
        for i = 1:length(z_ssp)
            fprintf(fid, '%.2f %.2f /\n', z_ssp(i), c_ssp(i));
        end
        fprintf(fid, '''A'' 0.0\n%.1f 1600.0 0.0 1.5 0.2 /\n', water_depth);
        fprintf(fid, '1\n%.2f /\n1\n%.2f /\n1\n%.3f /\n', bellhop_src_depth, rcv_depth, rcv_range / 1000.0);
        fprintf(fid, '''%s''\n801\n-80.0 80.0 /\n0.0 60.0 1.2\n', run_type);
        fclose(fid);
    end

    function rays = read_rays(fname)
        rays = {};
        if ~exist(fname, 'file'), return; end
        fid = fopen(fname, 'r');
        if fid == -1, return; end
        
        cleanUp = onCleanup(@() fclose(fid));
        
        for l = 1:7, fgets(fid); end
        while ~feof(fid)
            line = fgets(fid);
            if ischar(line)
                line = strtrim(line);
                if ~isempty(line)
                    tokens = sscanf(line, '%f');
                    if length(tokens) >= 2
                        nsteps = round(tokens(1));
                        if nsteps > 0
                            r_c = zeros(nsteps, 1);
                            z_c = zeros(nsteps, 1);
                            valid_s = 0;
                            for s = 1:nsteps
                                if feof(fid), break; end
                                step_line = fgets(fid);
                                if ischar(step_line)
                                    st = sscanf(step_line, '%f');
                                    if length(st) >= 2
                                        valid_s = valid_s + 1;
                                        r_c(valid_s) = st(1);
                                        z_c(valid_s) = st(2);
                                    end
                                end
                            end
                            if valid_s > 0
                                rays{end+1} = struct('r', r_c(1:valid_s), 'z', z_c(1:valid_s));
                            end
                        end
                    end
                end
            end
        end
    end

    function arrivals = read_arrivals(fname)
        arrivals = [];
        if ~exist(fname, 'file'), return; end
        fid = fopen(fname, 'r');
        if fid == -1, return; end
        
        cleanUp = onCleanup(@() fclose(fid));
        
        for l = 1:5, fgets(fid); end
        narr_line = fgets(fid);
        narr = sscanf(narr_line, '%d');
        fgets(fid);
        
        if isempty(narr) || narr == 0
            return;
        end
        
        for k = 1:narr
            line = fgets(fid);
            if ischar(line)
                tok = sscanf(line, '%f');
                if length(tok) >= 8
                    arrivals(end+1).amp = tok(1);
                    arrivals(end).phase = tok(2);
                    arrivals(end).delay = tok(3);
                    arrivals(end).src_angle = tok(5);
                    arrivals(end).rcv_angle = tok(6);
                    arrivals(end).bot = tok(7);
                    arrivals(end).surf = tok(8);
                end
            end
        end
    end

    function on_press(~, ~)
        cp = get(ax_rays, 'CurrentPoint');
        click_r = cp(1, 1);
        click_z = cp(1, 2);
        
        d_src = hypot(click_r - src_range, (click_z - src_depth) * 10);
        d_rcv = hypot(click_r - rcv_range, (click_z - rcv_depth) * 10);
        
        if d_src < 80 && d_src <= d_rcv
            active_drag = 'source';
        elseif d_rcv < 80
            active_drag = 'receiver';
        else
            active_drag = '';
        end
    end

    function on_motion(~, ~)
        if isempty(active_drag), return; end
        cp = get(ax_rays, 'CurrentPoint');
        new_r = min(max(cp(1, 1), 0), max_range);
        
        if strcmp(active_drag, 'source')
            new_z = min(max(cp(1, 2), -5.0), water_depth - 1);
            src_range = new_r;
            src_depth = new_z;
        elseif strcmp(active_drag, 'receiver')
            new_z = min(max(cp(1, 2), 1.0), water_depth - 1);
            rcv_range = new_r;
            rcv_depth = new_z;
        end
        update_sim();
    end

    function on_release(~, ~)
        active_drag = '';
        update_sim();
    end
end
