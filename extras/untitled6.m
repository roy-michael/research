clear; clc; close all;

dataset_path = 'D:\RoyStudies\Recordings\Ashdod\scooter_exp';
files = dir(fullfile(dataset_path, '*.wav'));
duration = 10;

for j = 1:length(files)
    % Choose a file (change to files(j).name to process all)
    file_name = "record_20260824_123438.wav"; % files(j).name
    file_path = fullfile(dataset_path, file_name);

    try
        [signal_full, fs] = audioread(file_path);
        signal_full = signal_full(1:min(duration*fs, size(signal_full,1)), :);
        t_full = (0:size(signal_full,1)-1)/fs;

        % Plot multi-channel time series
        figure('Name','Time Domain Multi-Channel','NumberTitle','off');
        plot(t_full, signal_full);
        xlabel('Time (s)'); ylabel('Amplitude');
        legend(arrayfun(@(k) sprintf('Ch%d',k), 1:size(signal_full,2), 'UniformOutput', false));
        grid on;

        % Per-channel time plots
        figure('Name','Per-Channel Time Domain','NumberTitle','off');
        for ch = 1:size(signal_full,2)
            subplot(size(signal_full,2),1,ch);
            plot(t_full, signal_full(:,ch));
            ylabel(sprintf('Ch%d',ch));
            if ch==1, title('Time Domain Channels'); end
            if ch==size(signal_full,2), xlabel('Time (s)'); end
            grid on;
        end

        % Pick best channel by power
        if size(signal_full,2) > 1
            channel_power = rms(signal_full, 1);
            [~, best_idx] = max(channel_power);
            signal = signal_full(:, best_idx);
            fprintf('Using channel: %d\n', best_idx);
        else
            signal = signal_full(:);
        end
        t = (0:length(signal)-1)/fs;
        N = length(signal);

        %% Time-domain envelopes
        env_hil = abs(hilbert(signal));                          % analytic envelope
        env_rms = envelope(signal, round(0.02*fs), 'rms');       % RMS (20 ms)
        env_peak = envelope(signal, round(0.05*fs), 'peak');     % peak (50 ms)

        figure('Name','Time Domain + Envelopes','NumberTitle','off');
        plot(t, signal, 'k-'); hold on;
        plot(t, env_hil, 'r-', 'LineWidth', 1.2);
        plot(t, env_rms, 'g-', 'LineWidth', 1.2);
        plot(t, env_peak, 'm-', 'LineWidth', 1.2);
        xlabel('Time (s)'); ylabel('Amplitude');
        legend('Signal','Analytic Env','RMS Env','Peak Env');
        title('Signal with Envelopes'); grid on; hold off;

        %% FFT one-sided and top-10 peaks
        Y = fft(signal);
        Mag = abs(Y)/N;
        if rem(N,2)==0
            MagPos = Mag(1:N/2+1);
            fPos = (0:N/2)*(fs/N);
        else
            MagPos = Mag(1:(N+1)/2);
            fPos = (0:(N-1)/2)*(fs/N);
        end
        MagSmooth = movmedian(MagPos, max(3,round(length(MagPos)/200)));

        % findpeaks and top-10
        minProm = 0.02*max(MagSmooth);
        minHt = 0.005*max(MagSmooth);
        [pkValsF, pkLocsF] = findpeaks(MagSmooth, fPos, 'MinPeakProminence',minProm, ...
            'MinPeakHeight',minHt, 'MinPeakDistance', 0.5);
        % fallback to islocalmax if too few
        if numel(pkValsF) < 10
            locsLogical = islocalmax(MagSmooth);
            candFreqs = fPos(locsLogical);
            candMags = MagSmooth(locsLogical);
            [~, sidx] = sort(candMags,'descend');
            topN = min(10, numel(sidx));
            topFreqsFFT = candFreqs(sidx(1:topN));
            topMagsFFT  = candMags(sidx(1:topN));
        else
            [~, sidx] = sort(pkValsF,'descend');
            topN = min(10, numel(sidx));
            topFreqsFFT = pkLocsF(sidx(1:topN));
            topMagsFFT  = pkValsF(sidx(1:topN));
        end

        figure('Name','One-Sided FFT with Top Peaks','NumberTitle','off');
        plot(fPos, MagSmooth, 'b-'); hold on;
        plot(topFreqsFFT, topMagsFFT, 'ro','MarkerFaceColor','r','MarkerSize',6);
        for k=1:numel(topFreqsFFT)
            text(topFreqsFFT(k), topMagsFFT(k), sprintf(' %.1f Hz', topFreqsFFT(k)), 'VerticalAlignment','bottom','FontSize',9);
        end
        xlabel('Frequency (Hz)'); ylabel('Magnitude'); xlim([0 fs/2]); grid on; title('FFT (smoothed)');

        %% Welch PSD (noise-floor removed) and top-10 peaks
        nfft_pwelch = 8192;
        win = hamming(round(0.5*fs));
        ov = round(0.5*length(win));
        [pxx, f_pxx] = pwelch(signal, win, ov, nfft_pwelch, fs);

        maxf = min(fs/2, 4000);
        mask = f_pxx <= maxf;
        f_zoom = f_pxx(mask);
        pxx_zoom = pxx(mask);

        mf_win = max(5, round(length(pxx_zoom)/200));
        noise_floor = movmedian(pxx_zoom, mf_win);
        spec = pxx_zoom - noise_floor;
        spec(spec<0) = 0;

        minProm = 0.02*max(spec);
        minHt = 0.005*max(spec);
        [pkValsP, pkIdxP] = findpeaks(spec, f_zoom, 'MinPeakProminence', minProm, ...
            'MinPeakHeight', minHt, 'MinPeakDistance', 0.5);

        [~, sidx] = sort(pkValsP,'descend');
        topN = min(10, numel(sidx));
        topFreqsPwelch = pkIdxP(sidx(1:topN));
        topMagsPwelch  = pkValsP(sidx(1:topN));

        figure('Name','Welch PSD (noise-floor removed)','NumberTitle','off');
        plot(f_zoom, spec, 'b-'); hold on;
        plot(topFreqsPwelch, topMagsPwelch, 'ro','MarkerFaceColor','r');
        for k=1:numel(topFreqsPwelch)
            text(topFreqsPwelch(k), topMagsPwelch(k), sprintf(' %.1f Hz', topFreqsPwelch(k)), 'VerticalAlignment','bottom');
        end
        xlabel('Frequency (Hz)'); ylabel('PSD (a.u.)'); xlim([0 maxf]); grid on;
        title('Welch PSD (noise-floor removed) with Top Peaks');

        %% Spectrogram and frequency envelopes (max and mean) + persistence map
        spec_win = round(0.1*fs);            % 100 ms window for freq resolution
        spec_noverlap = round(0.85*spec_win);
        spec_nfft = 4096;
        [S, F, T] = spectrogram(signal, spec_win, spec_noverlap, spec_nfft, fs);
        Smag = abs(S);

        spec_mean = mean(Smag,2);
        spec_max = max(Smag,[],2);

        spec_mean_s = movmedian(spec_mean, max(3,round(length(spec_mean)/200)));
        spec_max_s  = movmedian(spec_max,  max(3,round(length(spec_max)/200)));

        % noise-floor remove
        nf_mean = movmedian(spec_mean_s, max(5,round(length(spec_mean_s)/100)));
        nf_max  = movmedian(spec_max_s,  max(5,round(length(spec_max_s)/100)));
        spec_mean_n = spec_mean_s - nf_mean; spec_mean_n(spec_mean_n<0)=0;
        spec_max_n  = spec_max_s - nf_max;  spec_max_n(spec_max_n<0)=0;

        % find peaks on aggregated spectrogram (max)
        minProm = 0.02*max(spec_max_n);
        minHt = 0.005*max(spec_max_n);
        [pkValsS, pkFreqsS] = findpeaks(spec_max_n, F, 'MinPeakProminence', minProm, 'MinPeakHeight', minHt, 'MinPeakDistance', 0.5);
        [~, sidx] = sort(pkValsS,'descend');
        topN = min(10, numel(sidx));
        topFreqsSpec = pkFreqsS(sidx(1:topN));
        topMagsSpec  = pkValsS(sidx(1:topN));

        % Persistence: fraction of time magnitude exceeds a fraction of local max
        fracThreshold = 0.3;
        Flen = length(F);
        persistence = zeros(Flen,1);
        for ii = 1:Flen
            row = Smag(ii,:);
            if max(row) > 0
                persistence(ii) = sum(row > fracThreshold*max(row))/numel(row);
            else
                persistence(ii) = 0;
            end
        end

        % Plot spectrogram (dB) and overlay envelopes
        figure('Name','Spectrogram with Frequency Envelopes','NumberTitle','off');
        imagesc(T, F, 20*log10(Smag+eps)); axis xy;
        colormap jet; colorbar;
        hold on;
        plot(mean([T(1) T(end)]), -1, 'w.'); % ensure overlay works
        % overlay mean and max envelopes (scaled)
        plot([T(1) T(end)], [0 0], 'w:'); % visual anchor
        plot(linspace(T(1), T(end), numel(F)), F, 'w', 'Visible','off'); %placeholder
        % plot envelopes as white curves along frequency axis
        % mean envelope (scaled to frequency axis for visual)
        normMean = spec_mean_n / max(spec_mean_n + eps);
        normMax  = spec_max_n  / max(spec_max_n + eps);
        freqCurveMean = interp1(F, normMean * max(F) * 0.9, linspace(F(1),F(end),numel(F)));
        freqCurveMax  = interp1(F, normMax  * max(F) * 0.9, linspace(F(1),F(end),numel(F)));
        plot(linspace(T(1), T(end), numel(freqCurveMean)), freqCurveMean, 'w-', 'LineWidth', 2);
        plot(linspace(T(1), T(end), numel(freqCurveMax)),  freqCurveMax,  'c--', 'LineWidth', 1.5);
        % annotate top spectral peaks
        for k=1:numel(topFreqsSpec)
            plot([T(1) T(end)], topFreqsSpec(k)*[1 1], 'r:', 'LineWidth', 0.8);
            text(T(end), topFreqsSpec(k), sprintf(' %.1f Hz', topFreqsSpec(k)), 'Color','r','VerticalAlignment','bottom');
        end
        ylim([0 min(fs/2,4000)]);
        xlabel('Time (s)'); ylabel('Frequency (Hz)');
        title('Spectrogram (dB) with Frequency Envelopes (white=mean, cyan=max)'); hold off;

        % Plot persistence map below spectrogram
        figure('Name','Persistence Map + Spec Envelopes','NumberTitle','off');
        subplot(2,1,1);
        imagesc(T, F, 20*log10(Smag+eps)); axis xy; colormap jet; colorbar; ylim([0 min(fs/2,4000)]);
        title('Spectrogram (dB)'); ylabel('Frequency (Hz)');
        subplot(2,1,2);
        plot(F, persistence, 'k-','LineWidth',1.2); grid on;
        xlabel('Frequency (Hz)'); ylabel('Persistence (fraction of time)'); ylim([0 1]);
        title('Persistence (fraction of time magnitude > 30% of local max)');

        fprintf('Finished plotting for %s\n', file_name);

    catch ME
        fprintf('  Failed %s: %s\n', files(j).name, ME.message);
    end

    % If you want to process all files, remove the return below
    return
end

fprintf('Done.\n');