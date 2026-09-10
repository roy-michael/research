% =========================================================================
% Script: analyze_audio_lobe.m
% Description: Underwater acoustic spectrum analyzer for vessel noise.
%              - Fits an underwater Wenz/power-law ambient ocean noise floor
%              - Computes continuous spectral lower envelope across minima
%              - Isolates the core broadband cavitation lobe (~325 - 745 Hz)
%              - Excludes adjacent machinery tonals (100 Hz, 196 Hz, 790 Hz)
%              - Computes total and floor-subtracted net radiated bandpower
% Target File: Motorboat_06.09.23_083534_20secCPA.wav
% =========================================================================

clear; clc; close all;

% Configuration and Audio Loading
recordingsBasePath = "C:\Users\Roy\Recordings";
ship_path = fullfile(recordingsBasePath, "hear_my_ship", "V1", "Motor Boats", "Motorboat_06.09.23_083534_20secCPA.wav");

try
[data_ship, sr_ship] = audioread(ship_path);
audioIn = data_ship;
fs = sr_ship;
labelName = "Motorboat (06.09.23_083534)";
fprintf('Loaded audio file successfully: %s\n', ship_path);
catch
warning('Audio file not found at local path. Generating vessel model matching image.');
fs = 44100;
t = (0:1/fs:6)';

% Ambient oceanic noise floor (~ -91 dB/Hz)
oceanNoise = randn(size(t)) * 0.0035;

% Discrete machinery tonals (100 Hz, 196 Hz, 790 Hz)
tonal100 = 0.040 * sin(2.0 * pi * 100.0 * t);
tonal196 = 0.048 * sin(2.0 * pi * 196.0 * t);
tonal790 = 0.038 * sin(2.0 * pi * 790.0 * t);

% Broadband cavitation / flow lobe (~325 - 745 Hz, peaking ~395 Hz @ -70 dB)
bpCavit = designfilt('bandpassiir', 'FilterOrder', 4, ...
    'HalfPowerFrequency1', 320, 'HalfPowerFrequency2', 740, 'SampleRate', fs);
cavitationLobe = filtfilt(bpCavit, randn(size(t))) * 0.18;

audioIn = oceanNoise + tonal100 + tonal196 + tonal790 + cavitationLobe;
labelName = "Synthetic Model (Matching 06.09.23 Spectrum)";


end

% Convert audio to mono and apply passband filter
if size(audioIn, 2) > 1
audioIn = mean(audioIn, 2);
end
audioIn = audioIn(:);

f_low  = 50;
f_high = 1000;

bpFilter = designfilt('bandpassiir', ...
'FilterOrder', 6, ...
'HalfPowerFrequency1', f_low, ...
'HalfPowerFrequency2', f_high, ...
'SampleRate', fs);

audioFiltered = filtfilt(bpFilter, audioIn);

% Compute Welch Power Spectral Density (1 Hz resolution)
windowLength = 2^nextpow2(fs * 0.15);
win = hamming(windowLength);
noverlap = floor(windowLength * 0.5);
f_eval = (f_low:1:f_high)';

[psdFilt, f] = pwelch(audioFiltered, win, noverlap, f_eval, fs);
f       = f(:);
psdFilt = psdFilt(:);

% Compute logarithmic power spectral density
psdDb = 10.0 * log10(psdFilt + eps);

% Macro-smoothed spectrum for envelope extraction
psd_smooth = smoothdata(psdDb, 'gaussian', 15);

% -------------------------------------------------------------------------
% Lower Envelope Extraction
% -------------------------------------------------------------------------
% Compute continuous lower envelope across spectral troughs using spline interpolation
% Window of ~45 Hz ensures tracking of multi-tonal valleys without distortion
flrWindow = 45;
[~, lowerEnv] = envelope(psdDb, flrWindow, 'analytic');
lowerEnv = smoothdata(lowerEnv, 'gaussian', 11);

% -------------------------------------------------------------------------
% Underwater Ambient Noise Floor: Wenz / Power-Law Baseline
% -------------------------------------------------------------------------
% Natural ocean noise follows a power-law decay: PSD_dB(f) = A - B * log10(f).
% Reference valleys where vessel noise drops:
% Valley 1: ~125-155 Hz (between 100 Hz and 196 Hz engine tonals)
% Valley 2: ~270-295 Hz (before cavitation onset)
% Valley 3: ~840-930 Hz (above 790 Hz tonal, approaching hydrophone self-noise)

[val1, idxV1] = min(psd_smooth(f >= 125 & f <= 155));
subF1 = f(f >= 125 & f <= 155);
fV1   = subF1(idxV1);

[val2, idxV2] = min(psd_smooth(f >= 270 & f <= 295));
subF2 = f(f >= 270 & f <= 295);
fV2   = subF2(idxV2);

[val3, idxV3] = min(psd_smooth(f >= 840 & f <= 930));
subF3 = f(f >= 840 & f <= 930);
fV3   = subF3(idxV3);

refFreqs = [fV1; fV2; fV3];
refVals  = [val1; val2; val3];

% Fit underwater log-linear slope: dB = p(1)*log10(f) + p(2)
pFit = polyfit(log10(refFreqs), refVals, 1);
wenzFloorDb = polyval(pFit, log10(f));

% Ensure floor does not overshoot smoothed spectrum
wenzFloorDb = min(wenzFloorDb, psd_smooth);
wenzFloorDb = smoothdata(wenzFloorDb, 'gaussian', 21);
wenzFloorLinear = 10.0.^(wenzFloorDb / 10.0);

% -------------------------------------------------------------------------
% Precise Cavitation Lobe Boundary Detection (Excluding 790 Hz Tonal)
% -------------------------------------------------------------------------
% 1. Find dominant cavitation summit (~395 Hz)
idxCavitSearch = find(f >= 340 & f <= 600);
[maxCavitVal, relPeakIdx] = max(psd_smooth(idxCavitSearch));
cavitPeakIdx  = idxCavitSearch(relPeakIdx);
cavitPeakFreq = f(cavitPeakIdx);

% 2. Left boundary: steep foot where cavitation emerges from ambient floor
idxLeft = find(f >= 290 & f < cavitPeakFreq & psd_smooth <= (wenzFloorDb + 3.0), 1, 'last');
if isempty(idxLeft)
idxLeft = find(f >= 320, 1, 'first');
end
f_lobe_start = f(idxLeft);

% 3. Right boundary: valley BEFORE the 790 Hz tonal
idxRightSearch = find(f >= 720 & f <= 775);
[~, relMinIdx] = min(psd_smooth(idxRightSearch));
idxRight = idxRightSearch(relMinIdx);
f_lobe_end = f(idxRight);

% -------------------------------------------------------------------------
% Acoustic Bandpower Integration
% -------------------------------------------------------------------------
lobeRange = idxLeft:idxRight;
f_lobe    = f(lobeRange);
psd_lobe  = psdFilt(lobeRange);
flr_lobe  = wenzFloorLinear(lobeRange);

% Total integrated power across the lobe band
totalLobePower = trapz(f_lobe, psd_lobe);

% Net vessel cavitation power strictly above ambient baseline
netLobePower   = trapz(f_lobe, max(psd_lobe - flr_lobe, 0));

totalPowerDb = 10.0 * log10(max(totalLobePower, eps));
netPowerDb   = 10.0 * log10(max(netLobePower, eps));

% Standard -10 dB bandwidth from cavitation summit
threshold_10dB = maxCavitVal - 10.0;
idx10_L = find(f < cavitPeakFreq & psd_smooth <= threshold_10dB, 1, 'last');
idx10_R = find(f > cavitPeakFreq & psd_smooth <= threshold_10dB, 1, 'first');
if isempty(idx10_L), idx10_L = idxLeft; end
if isempty(idx10_R), idx10_R = idxRight; end
bw_10dB = f(idx10_R) - f(idx10_L);

% Console Report
fprintf('\n================== UNDERWATER CAVITATION REPORT \n');
fprintf('Target Recording:       %s\n', labelName);
fprintf('Cavitation Peak Summit: %.1f Hz @ %.2f dB/Hz\n', cavitPeakFreq, maxCavitVal);
fprintf('Core Cavitation Band:   %.1f Hz to %.1f Hz (Span: %.1f Hz)\n', ...
f_lobe_start, f_lobe_end, f_lobe_end - f_lobe_start);
fprintf('-10 dB Down Bandwidth:  %.1f Hz to %.1f Hz (Width: %.1f Hz)\n', ...
f(idx10_L), f(idx10_R), bw_10dB);
fprintf('Excluded Tonals:        100 Hz, 196 Hz (Engine), 790 Hz (Alternator/Machinery)\n');
fprintf('Ocean Floor at Peak:    %.2f dB/Hz (Slope: %.2f dB/decade)\n', ...
wenzFloorDb(cavitPeakIdx), pFit(1));
fprintf('Total Bandpower:        %.3e (%.2f dB)\n', totalLobePower, totalPowerDb);
fprintf('Net Radiated Power:     %.3e (%.2f dB)\n', netLobePower, netPowerDb);
fprintf('================================================\n\n');

% -------------------------------------------------------------------------
% Visualization (Dark Mode UI)
% -------------------------------------------------------------------------
c_bg     = [0.06 0.08 0.12];
c_card   = [0.10 0.13 0.19];
c_text   = [0.88 0.92 0.97];
c_grid   = [0.20 0.26 0.36];
c_cyan   = [0.22 0.74 0.98];
c_amber  = [0.98 0.75 0.14];
c_purple = [0.65 0.45 0.95];
c_green  = [0.20 0.88 0.55];
c_pink   = [0.96 0.35 0.60];

figure('Name', labelName + " Cavitation Analysis", 'Position', [100, 100, 1100, 640], 'Color', c_bg);
ax = axes;

% Shaded polygon for core cavitation lobe
fillX = [f_lobe; flipud(f_lobe)];
fillY = [psdDb(lobeRange); flipud(wenzFloorDb(lobeRange))];

lobeLegendStr = sprintf('Core Cavitation Lobe [%.0f-%.0f Hz] (Net: %.1f dB)', ...
f_lobe_start, f_lobe_end, netPowerDb);

fill(fillX, fillY, c_purple, 'FaceAlpha', 0.32, 'EdgeColor', 'none', ...
'DisplayName', lobeLegendStr);
hold on;

% Welch PSD and Smoothed Macro Envelope
plot(f, psdDb, 'Color', [0.32 0.38 0.48], 'LineWidth', 0.8, 'DisplayName', 'Welch PSD (1 Hz)');
plot(f, psd_smooth, 'Color', c_cyan, 'LineWidth', 1.4, 'DisplayName', 'Macro Envelope');

% Lower Envelope
plot(f, lowerEnv, 'Color', c_pink, 'LineWidth', 1.6, 'LineStyle', '-.', ...
'DisplayName', 'Lower Envelope (Spline)');

% Underwater Wenz/Power-Law Ambient Ocean Floor
plot(f, wenzFloorDb, 'Color', c_amber, 'LineWidth', 2.0, 'LineStyle', '-', ...
'DisplayName', sprintf('Underwater Ambient Floor (Wenz Fit: %.1f dB/dec)', pFit(1)));

% Mark Reference Ocean Valleys
plot(refFreqs, refVals, 's', 'Color', c_green, 'MarkerFaceColor', c_green, ...
'MarkerSize', 7, 'DisplayName', 'Ambient Reference Troughs');

% Mark Cavitation Summit
plot(cavitPeakFreq, maxCavitVal, 'p', 'Color', c_purple, 'MarkerFaceColor', c_purple, ...
'MarkerSize', 11, 'DisplayName', sprintf('Cavitation Peak: %.1f Hz', cavitPeakFreq));

% Lobe Boundaries
xline(f_lobe_start, ':', sprintf('Start: %.0f Hz', f_lobe_start), ...
'Color', c_text, 'LineWidth', 1.2, 'LabelOrientation', 'aligned');
xline(f_lobe_end,   ':', sprintf('End: %.0f Hz (Excludes 790 Hz Tonal)', f_lobe_end), ...
'Color', c_text, 'LineWidth', 1.2, 'LabelOrientation', 'aligned');

% Final Axis Formatting
grid on;
xlim([f_low, f_high]);
ylim([min(wenzFloorDb) - 4.0, max(psdDb) + 4.0]);
xlabel('Frequency (Hz)', 'Color', c_text, 'FontSize', 11);
ylabel('PSD (dB/Hz)', 'Color', c_text, 'FontSize', 11);
title(sprintf('%s - Core Cavitation Isolation, Lower Envelope & Ambient Floor', labelName), ...
'Color', c_text, 'FontWeight', 'bold', 'FontSize', 12);

set(ax, 'Color', c_card, 'XColor', c_text, 'YColor', c_text, 'GridColor', c_grid, 'GridAlpha', 0.45);
legend('Location', 'northeast', 'TextColor', c_text, 'Color', c_card, 'EdgeColor', c_grid);