function audio_inspector_gui()
    % Create UI Figure
    fig = uifigure('Name', 'Audio Inspector', 'Position', [100 100 800 800]);
    
    % Add Load Button
    btn = uibutton(fig, 'Position', [20, 750, 100, 30], 'Text', 'Load WAV File', ...
        'ButtonPushedFcn', @(btn,event) loadAudioFile(fig));
    
    % Status Label
    statusLbl = uilabel(fig, 'Position', [130, 750, 600, 30], 'Text', 'No file loaded.');
    
    % Add Axes for Envelope
    axEnv = uiaxes(fig, 'Position', [50, 500, 650, 200]);
    title(axEnv, 'Time-Domain Envelope (Downsampled Absolute Max)');
    xlabel(axEnv, 'Time (s)');
    ylabel(axEnv, 'Amplitude');
    grid(axEnv, 'on');
    
    % Add Axes for Spectrogram
    axSpec = uiaxes(fig, 'Position', [50, 275, 650, 200]);
    title(axSpec, 'Spectrogram');
    xlabel(axSpec, 'Time (s)');
    ylabel(axSpec, 'Frequency (Hz)');
    
    % Add Axes for PSD
    axPSD = uiaxes(fig, 'Position', [50, 50, 650, 200]);
    title(axPSD, 'Welch Power Spectral Density (PSD)');
    xlabel(axPSD, 'Frequency (Hz)');
    ylabel(axPSD, 'Power/Frequency (dB/Hz)');
    grid(axPSD, 'on');
    
    % Store components in UserData for callback access
    fig.UserData = struct('axEnv', axEnv, 'axSpec', axSpec, 'axPSD', axPSD, 'statusLbl', statusLbl);
end

function loadAudioFile(fig)
    [file, path] = uigetfile('*.wav', 'Select WAV File');
    if isequal(file, 0)
        return;
    end
    
    filepath = fullfile(path, file);
    fig.UserData.statusLbl.Text = ['Loading: ', file, '...'];
    drawnow;
    
    try
        [data, fs] = audioread(filepath);
        
        % Convert to mono if stereo
        if size(data, 2) > 1
            data = mean(data, 2);
        end
        
        % Calculate Fast Envelope (Downsampled Rolling Max)
        chunk_size = floor(fs / 100); % 100 points per second
        num_chunks = floor(length(data) / chunk_size);
        
        if num_chunks > 0
            truncated_data = data(1:(num_chunks * chunk_size));
            reshaped_data = reshape(truncated_data, chunk_size, num_chunks);
            env = max(abs(reshaped_data), [], 1);
            time_env = (0:(num_chunks-1)) * (chunk_size / fs);
        else
            env = abs(data);
            time_env = (0:(length(data)-1)) / fs;
        end
        
        % Plot Envelope
        plot(fig.UserData.axEnv, time_env, env, 'b');
        title(fig.UserData.axEnv, 'Time-Domain Envelope (Downsampled Absolute Max)');
        
        % Calculate and Plot Spectrogram
        nfft = min(8192, length(data)); % Increased for higher frequency resolution
        noverlap = round(nfft * 0.875); % 87.5% overlap for higher time resolution
        [~, f_spec, t_spec, p] = spectrogram(data, nfft, noverlap, nfft, fs);
        p_db = 10 * log10(abs(p) + 1e-12);
        imagesc(fig.UserData.axSpec, t_spec, f_spec, p_db);
        axis(fig.UserData.axSpec, 'xy');
        title(fig.UserData.axSpec, 'Spectrogram');
        xlabel(fig.UserData.axSpec, 'Time (s)');
        ylabel(fig.UserData.axSpec, 'Frequency (Hz)');
        colorbar(fig.UserData.axSpec);
        
        % Calculate Welch PSD
        % Ensure data is a vector
        nperseg = min(4096, length(data));
        [pxx, f] = pwelch(data, nperseg, [], [], fs);
        pxx_db = 10 * log10(pxx + 1e-12);
        
        % Plot PSD
        semilogx(fig.UserData.axPSD, f, pxx_db, 'r');
        title(fig.UserData.axPSD, 'Welch Power Spectral Density (PSD)');
        
        fig.UserData.statusLbl.Text = ['Loaded: ', file];
    catch e
        uialert(fig, ['Error loading file: ', e.message], 'Error');
        fig.UserData.statusLbl.Text = 'Error loading file.';
    end
end
