function stft_gui_


fig = uifigure('Name', 'LOFAR Spectrogram Viewer', 'Position', [100 100 1400 900]);


ax = uiaxes(fig, 'Position', [50 280 1250 550]);
title(ax, 'LOFAR Spectrogram');
xlabel(ax, 'Time (s)');
ylabel(ax, 'Frequency (kHz)');


uibutton(fig, 'push', 'Text', 'Load WAV File', ...
    'Position', [50 50 120 30], ...
    'ButtonPushedFcn', @(~,~) loadWavFile());

uilabel(fig, 'Position', [200 90 120 22], 'Text', 'Window Length:');
windowField = uieditfield(fig, 'numeric', ...
    'Position', [310 90 80 22], ...
    'Limits', [128 65536*8], ...
    'Value', 1024);


uilabel(fig, 'Position', [200 50 120 22], 'Text', 'FFT Points:');
nfftField = uieditfield(fig, 'numeric', ...
    'Position', [310 50 80 22], ...
    'Limits', [128 65536*16], ...
    'Value', 1024);


uilabel(fig, 'Position', [420 50 80 22], 'Text', 'Overlap (%):');
overlapField = uieditfield(fig, 'numeric', ...
    'Position', [500 50 60 22], ...
    'Limits', [0 99], ...
    'Value', 75);


uilabel(fig, 'Position', [580 50 150 22], 'Text', 'Fundamental Freq (Hz):');
fundField = uieditfield(fig, 'numeric', ...
    'Position', [730 50 80 22], ...
    'Limits', [0 Inf], ...
    'Value', 0);


uilabel(fig, 'Position', [820 50 80 22], 'Text', 'Colormap:');
cmapDropdown = uidropdown(fig, ...
    'Position', [900 50 120 22], ...
    'Items', {'parula', 'jet', 'turbo', 'hsv', 'hot', 'gray'}, ...
    'Value', 'turbo');


uilabel(fig, 'Position', [1040 50 100 22], 'Text', 'Normalization:');
normDropdown = uidropdown(fig, ...
    'Position', [1140 50 80 22], ...
    'Items', {'None', 'dpmw'}, ...
    'Value', 'None');


uilabel(fig, 'Position', [50 150 180 22], 'Text', 'Region FFT Points:');
regionFFTField = uieditfield(fig, 'numeric', ...
    'Position', [200 150 80 22], ...
    'Limits', [128 2^22], ...
    'Value', 16384);

uilabel(fig, 'Position', [300 150 100 22], 'Text', 'Window:');
regionWindowDropdown = uidropdown(fig, ...
    'Position', [370 150 120 22], ...
    'Items', {'None', 'Hann', 'Hamming'}, ...
    'Value', 'Hann');


uilabel(fig, 'Position', [520 150 120 22], 'Text', 'Min Intensity (dB):');
minSlider = uislider(fig, ...
    'Position', [650 160 300 3], ...
    'Limits', [-150 0], ...
    'Value', -120);

uilabel(fig, 'Position', [980 150 120 22], 'Text', 'Max Intensity (dB):');
maxSlider = uislider(fig, ...
    'Position', [1110 160 300 3], ...
    'Limits', [-150 0], ...
    'Value', -20);


uibutton(fig, 'push', 'Text', 'Compute STFT', ...
    'Position', [1040 90 180 30], ...
    'ButtonPushedFcn', @(~,~) computeSTFT());


uibutton(fig, 'push', 'Text', 'Select Time Range for FFT', ...
    'Position', [1240 90 180 30], ...
    'ButtonPushedFcn', @(~,~) selectTimeRangeFFT());

uibutton(fig, 'push', 'Text', 'Select Time Range for Cepstrum', ...
    'Position', [1240 50 180 30], ...
    'ButtonPushedFcn', @(~,~) selectTimeRangeCepstrum());


data.audio = [];
data.fs = [];
data.autoWindow = true;
fig.UserData = data;


fig.WindowScrollWheelFcn = @(src, evt) zoomScroll(evt);


nfftField.ValueChangedFcn = @(s,e) nfftChanged();
windowField.ValueChangedFcn = @(s,e) windowChanged();

    function nfftChanged()
        if fig.UserData.autoWindow
            windowField.Value = nfftField.Value;
        end
    end

    function windowChanged()
        fig.UserData.autoWindow = false;
    end

    function loadWavFile()
        selection = uiconfirm(fig, 'Would you like to load a single WAV file or an entire dataset folder?', ...
            'Select Load Mode', 'Options', {'Single WAV File', 'Entire Dataset Folder', 'Cancel'}, ...
            'DefaultOption', 'Single WAV File');
            
        if strcmp(selection, 'Cancel')
            return;
        end
        
        if strcmp(selection, 'Single WAV File')
            [file, path] = uigetfile('*.wav', 'Select WAV file');
            if isequal(file,0)
                return;
            end
            [y, fs] = audioread(fullfile(path, file));
            if size(y,2)>1
                y = mean(y,2);
            end
            fig.UserData.audio = y;
            fig.UserData.fs = fs;
            uialert(fig, sprintf('Loaded: %s\nFs: %d Hz\nDuration: %.2f sec', ...
                file, fs, numel(y)/fs), 'WAV Loaded', 'Icon', 'info');
        else
            folder_path = uigetdir('', 'Select Dataset Folder');
            if isequal(folder_path,0)
                return;
            end
            
            wav_files = dir(fullfile(folder_path, '*.wav'));
            if isempty(wav_files)
                uialert(fig, 'No WAV files found in selected folder.', 'Error');
                return;
            end
            
            [~, idx] = sort({wav_files.name});
            wav_files = wav_files(idx);
            
            d = uiprogressdlg(fig, 'Title', 'Loading Dataset', ...
                'Message', 'Searching and reading files...', 'Indeterminate', 'off');
                
            y_concat = [];
            target_fs = 4000;
            num_files = numel(wav_files);
            
            for i = 1:num_files
                d.Value = (i-1)/num_files;
                d.Message = sprintf('Reading file %d of %d: %s', i, num_files, wav_files(i).name);
                
                file_path = fullfile(folder_path, wav_files(i).name);
                [y_file, fs_file] = audioread(file_path);
                
                if size(y_file, 2) > 1
                    y_file = mean(y_file, 2);
                end
                
                if fs_file ~= target_fs
                    try
                        y_file = resample(y_file, target_fs, fs_file);
                    catch
                        dec = round(fs_file / target_fs);
                        y_file = y_file(1:dec:end);
                    end
                end
                
                y_concat = [y_concat; y_file];
            end
            
            d.Value = 1.0;
            close(d);
            
            fig.UserData.audio = y_concat;
            fig.UserData.fs = target_fs;
            uialert(fig, sprintf('Successfully loaded, downsampled (4 kHz), and concatenated %d files.\nTotal Duration: %.2f min', ...
                num_files, numel(y_concat)/(target_fs*60)), 'Dataset Loaded', 'Icon', 'info');
        end
    end

    function computeSTFT()
        y = fig.UserData.audio;
        fs = fig.UserData.fs;
        if isempty(y)
            uialert(fig, 'Please load a WAV file first.', 'Error');
            return;
        end

        winLen = windowField.Value;
        nfft = nfftField.Value;
        overlapPct = overlapField.Value;

        if nfft < winLen
            uialert(fig, 'FFT Points must be >= Window Length.', 'Error');
            return;
        end

        window = hann(winLen, 'periodic');
        noverlap = round(overlapPct/100 * winLen);

        [S,F_Hz,T] = spectrogram(y, window, noverlap, nfft, fs);

        S_mag = abs(S);
        if strcmp(normDropdown.Value, 'dpmw')
            meanPower = mean(S_mag, 2);
            normS = S_mag ./ meanPower;
            S_dB = 20*log10(normS + eps);
        else
            S_dB = 20*log10(S_mag + eps);
        end

        F_kHz = F_Hz / 1000;

        cla(ax);
        h = imagesc(ax, T, F_kHz, S_dB);
        axis(ax, 'xy');
        ylim(ax, [0 fs/2000]);
        xlabel(ax, 'Time (s)');
        ylabel(ax, 'Frequency (kHz)');
        title(ax, 'LOFAR Spectrogram');

        try
            if strcmp(cmapDropdown.Value, 'turbo')
                colormap(ax, turbo);
            else
                colormap(ax, cmapDropdown.Value);
            end
        catch
            colormap(ax, parula);
        end
        colorbar(ax);

        caxis(ax, [minSlider.Value, maxSlider.Value]);

        f0 = fundField.Value;
        if f0 > 0
            hold(ax, 'on');
            harmonics_kHz = (f0:f0:(fs/2)) / 1000;
            for k = 1:numel(harmonics_kHz)
                yline(ax, harmonics_kHz(k), '--w', 'LineWidth', 1);
                text(ax, T(end)*0.98, harmonics_kHz(k), sprintf('%d×f0', k), ...
                    'Color', 'w', 'FontSize', 8, 'HorizontalAlignment', 'right');
            end
            hold(ax, 'off');
        end

        h.ButtonDownFcn = @(src,event) showDataTip(event, T, F_Hz, S_dB);
    end

minSlider.ValueChangedFcn = @(s,e) updateCLim();
maxSlider.ValueChangedFcn = @(s,e) updateCLim();

    function updateCLim()
        minVal = minSlider.Value;
        maxVal = maxSlider.Value;
        if minVal >= maxVal
            return;
        end
        caxis(ax, [minVal, maxVal]);
    end

    function zoomScroll(event)
        mods = fig.CurrentModifier;
        p = ax.CurrentPoint;
        cx = p(1,1);
        cy = p(1,2);
        xlim = ax.XLim;
        ylim = ax.YLim;
        if event.VerticalScrollCount > 0
            factor = 1.2;
        else
            factor = 0.8;
        end
        zoomX = ~any(strcmpi(mods,'control'));
        zoomY = ~any(strcmpi(mods,'shift'));
        if any(strcmpi(mods,'control'))
            zoomX = false; zoomY = true;
        elseif any(strcmpi(mods,'shift'))
            zoomX = true; zoomY = false;
        end
        if zoomX
            xRange = diff(xlim)*factor;
            newXLim = [cx - xRange/2, cx + xRange/2];
            ax.XLim = max(min(newXLim,max(ax.Children.XData)), min(ax.Children.XData));
        end
        if zoomY
            yRange = diff(ylim)*factor;
            newYLim = [cy - yRange/2, cy + yRange/2];
            ax.YLim = max(min(newYLim,max(ax.Children.YData)), min(ax.Children.YData));
        end
    end

    function selectTimeRangeFFT()
        y = fig.UserData.audio;
        fs = fig.UserData.fs;
        if isempty(y)
            uialert(fig, 'Load WAV file first.', 'Error');
            return;
        end
        uialert(fig, 'Draw rectangle over time range (height doesn''t matter).', 'Select Region', 'Icon', 'info');
        rect = drawrectangle(ax);
        tStart = rect.Position(1);
        tEnd = tStart + rect.Position(3);
        sampleStart = max(1, floor(tStart * fs));
        sampleEnd = min(length(y), ceil(tEnd * fs));
        segment = y(sampleStart:sampleEnd);
        Nfft = regionFFTField.Value;
        switch regionWindowDropdown.Value
            case 'Hann'
                win = hann(length(segment));
            case 'Hamming'
                win = hamming(length(segment));
            otherwise
                win = ones(length(segment),1);
        end
        segmentWin = segment .* win;
        Y = abs(fft(segmentWin, Nfft));
        f = (0:Nfft-1)*(fs/Nfft);
        figure;
        plot(f,20*log10(Y/max(Y)));
        xlabel('Frequency (Hz)');
        ylabel('Magnitude (dB re max)');
        title(sprintf('FFT of selected time window (%.3f–%.3f s)', tStart, tEnd));
        grid on;
        xlim([0 fs/2]);
    end

    function selectTimeRangeCepstrum()
        y = fig.UserData.audio;
        fs = fig.UserData.fs;
        if isempty(y)
            uialert(fig, 'Load WAV file first.', 'Error');
            return;
        end
        uialert(fig, 'Draw rectangle over time range for Cepstrum analysis.', 'Select Region', 'Icon', 'info');
        rect = drawrectangle(ax);
        tStart = rect.Position(1);
        tEnd = tStart + rect.Position(3);
        sampleStart = max(1, floor(tStart * fs));
        sampleEnd = min(length(y), ceil(tEnd * fs));
        segment = y(sampleStart:sampleEnd);
        
        Nfft = numel(segment);
        win = hann(Nfft);
        segmentWin = segment .* win;
        Y = abs(fft(segmentWin));
        logY = log(Y + eps);
        ceps = abs(ifft(logY));
        t_ceps = (0:numel(ceps)-1) / fs;
        
        idx = (t_ceps >= 0.01 & t_ceps <= 0.1);
        t_sub = t_ceps(idx);
        ceps_sub = ceps(idx);
        freq_sub = 1 ./ t_sub;
        
        f_new = figure('Name', 'Cepstrum Analysis Viewer');
        plot(freq_sub, ceps_sub, 'LineWidth', 1.5, 'Color', [0.6 0 0]);
        xlabel('Equivalent Frequency (Hz = 1/Quefrency)');
        ylabel('Cepstrum Magnitude');
        title(sprintf('Cepstrum of selected time window (%.3f–%.3f s)', tStart, tEnd));
        grid on;
        xlim([10 100]);
        
        [val, p_idx] = max(ceps_sub);
        peak_f = freq_sub(p_idx);
        hold on;
        plot(peak_f, val, 'go', 'MarkerFaceColor', 'g', 'MarkerSize', 8);
        text(peak_f + 2, val, sprintf('Dominant: %.2f Hz (%.1f RPM)', peak_f, peak_f*60), ...
            'Color', 'g', 'FontWeight', 'bold');
        hold off;
    end

    function showDataTip(event, T, F_Hz, S_dB)
        p = event.IntersectionPoint;
        t = p(1);
        f_kHz = p(2);
        f_Hz = f_kHz * 1000;
        [~, tIdx] = min(abs(T - t));
        [~, fIdx] = min(abs(F_Hz - f_Hz));
        dBval = S_dB(fIdx, tIdx);
        uialert(fig, sprintf('Time: %.3f s\nFrequency: %.1f Hz\nPower: %.2f dB', ...
            t, f_Hz, dBval), 'Data Point Info', 'Icon', 'info');
    end
end
