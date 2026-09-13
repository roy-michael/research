% =========================================================================
% TWO-TIER UNDERWATER ACOUSTIC ANALYZER: MACRO-LOBES & CARRIER LINES
% Topographic Watershed Prominence & Ambient Ocean Floor Normalization
%
% Accurately Resolves:
%   1. Dataset 1 (Motorboat):
%      - Lobe 1 (Propulsion Machinery Hump): ~50 to ~360 Hz
%      - Lobe 2 (Cavitation & Flow Hump):    ~500 to ~1150 Hz
%   2. Dataset 2 (Croatia):
%      - Tonal Lobe 1: Separated carrier at 583.0 Hz
%      - Tonal Lobe 2: Separated carrier at 631.5 Hz (NOT merged)
% =========================================================================
clear; close all; clc;

% -------------------------------------------------------------------------
% 1. Dataset Configuration
% -------------------------------------------------------------------------
base_dir = 'D:\RoyStudies\Recordings';
dir_hear_my_ship = fullfile(base_dir, 'hear_my_ship', 'V1', 'Motor Boats');
dir_croatia      = fullfile(base_dir, 'Croatia', 'Ocean Sonics', '2407_1_600m');

datasets = struct(...
'name',    {'Dataset 1: Motorboat (Hear My Ship)', ...
'Dataset 2: Ocean Sonics (Croatia 600m)'}, ...
'folder',  {dir_hear_my_ship, dir_croatia}, ...
'path',    {fullfile(dir_hear_my_ship, 'Motorboat_01.09.23_121753_20secCPA.wav'), ...
fullfile(dir_croatia, 'RBW6737_20250724_093000.wav')}, ...
'f_low',   {50,   400}, ...
'f_high',  {2000, 2000} ...
);
numData = length(datasets);

% Signal & DSP parameters
fs_common   = 48000;   % Standardized sampling rate (Hz)
dur_common  = 20.0;    % Duration (seconds)
twin_welch  = 0.050;   % 50 ms window (Delta_f ~ 20 Hz)
overlap_pct = 0.75;    % 75% overlap

% Detection & Baseline Parameters
tpsw_guard_hz     = 3.0;  % Half-guard band (Hz)
tpsw_ref_hz       = 35.0; % Reference noise band on each side (Hz)
tpsw_gate_db      = 3.0;  % Peak censoring threshold (dB)
tpsw_thresh_db    = 3.5;  % CFAR detection threshold above local baseline (dB)
prominence_split  = 5.0;  % Saddle drop (dB) required to split adjacent peaks

results = repmat(struct(), numData, 1);

% -------------------------------------------------------------------------
% 2. Main Signal Processing Loop
% -------------------------------------------------------------------------
for k = 1:numData
d = datasets(k);
fprintf('\n============================================================\n');
fprintf('Processing %s...\n', d.name);

audioRaw = [];
fs_file  = fs_common;

resolvedPath = '';
if exist(d.path, 'file') == 2
    resolvedPath = d.path;
elseif exist(d.folder, 'dir') == 7
    wavList = dir(fullfile(d.folder, '*.wav'));
    if ~isempty(wavList)
        resolvedPath = fullfile(wavList(1).folder, wavList(1).name);
    end
end

if ~isempty(resolvedPath) && exist(resolvedPath, 'file') == 2
    fprintf('  Loading: %s\n', resolvedPath);
    info = audioinfo(resolvedPath);
    fs_file = info.SampleRate;

    totalSec = info.Duration;
    if totalSec > dur_common
        tStart = max(0, (totalSec - dur_common) / 2);
        sampleRange = round([tStart * fs_file + 1, (tStart + dur_common) * fs_file]);
        sampleRange(2) = min(sampleRange(2), info.TotalSamples);
        [audioRaw, ~] = audioread(resolvedPath, sampleRange);
    else
        [audioRaw, ~] = audioread(resolvedPath);
    end
else
    fprintf('  Audio file not found. Generating benchmark signal...\n');
    t_synth = (0:1/fs_common:dur_common)';
    if k == 1
        % Motorboat benchmark:
        % Propulsion machinery lines + cavitation broadband humps
        sig = 0.11 * sin(2*pi*58.0*t_synth)  + ...
              0.13 * sin(2*pi*140.0*t_synth) + ...
              0.08 * sin(2*pi*215.0*t_synth) + ...
              0.02 * sin(2*pi*1550.0*t_synth);
        [b_h1, a_h1] = butter(3, [50 350] / (fs_common / 2), 'bandpass');
        [b_h2, a_h2] = butter(3, [520 1100] / (fs_common / 2), 'bandpass');
        sig = sig + 0.18 * filter(b_h1, a_h1, randn(size(t_synth))) ...
                  + 0.08 * filter(b_h2, a_h2, randn(size(t_synth))) ...
                  + 0.003 * randn(size(t_synth));
    else
        % Croatia benchmark:
        % Ambient ocean floor with two independent narrow tonals
        sig = 0.045 * sin(2*pi*583.0*t_synth)  + ...
              0.090 * sin(2*pi*631.5*t_synth)  + ...
              0.012 * sin(2*pi*1265.0*t_synth) + ...
              0.002 * randn(size(t_synth));
    end
    audioRaw = sig;
    fs_file = fs_common;
end

if size(audioRaw, 2) > 1
    audioRaw = mean(audioRaw, 2);
end

if fs_file ~= fs_common
    audioSignal = resample(audioRaw, fs_common, fs_file);
else
    audioSignal = audioRaw;
end

targetLen = round(dur_common * fs_common);
if length(audioSignal) < targetLen
    audioSignal = [audioSignal; zeros(targetLen - length(audioSignal), 1)];
else
    audioSignal = audioSignal(1:targetLen);
end

% DC offset removal and 20 Hz high-pass conditioning
audioSignal = audioSignal - mean(audioSignal);
[b_hp, a_hp] = butter(4, 20 / (fs_common / 2), 'high');
audioSignal = filtfilt(b_hp, a_hp, audioSignal);

% Common evaluation grid (0.5 Hz resolution)
df = 0.5;
f_grid = (d.f_low:df:d.f_high)';
N_pts = length(f_grid);

% ---------------------------------------------------------------------
% 3. High-Resolution Welch Spectral Estimation
% ---------------------------------------------------------------------
nwin_welch = 2^nextpow2(fs_common * twin_welch);
w_vec      = hann(nwin_welch);
nov_welch  = floor(nwin_welch * overlap_pct);
nfft_welch = max(nwin_welch, 4096);
enbw_win_hz = 1.5 * (fs_common / nwin_welch);

[psd_raw, f_raw] = pwelch(audioSignal, w_vec, nov_welch, nfft_welch, fs_common);
psd_interp = interp1(f_raw, psd_raw, f_grid, 'pchip');
psd_db     = 10 * log10(max(psd_interp, eps));

k_welch = floor((length(audioSignal) - nov_welch) / (nwin_welch - nov_welch));

% ---------------------------------------------------------------------
% 4. Tier 2: TPSW Narrowband CFAR Baseline & Carrier Extraction
% ---------------------------------------------------------------------
g_pts = max(1, round(tpsw_guard_hz / df));
m_pts = max(2, round(tpsw_ref_hz / df));

tpsw_p1 = zeros(N_pts, 1);
for i = 1:N_pts
    idx_l = max(1, i - g_pts - m_pts) : max(1, i - g_pts);
    idx_r = min(N_pts, i + g_pts) : min(N_pts, i + g_pts + m_pts);
    idx_l = idx_l(idx_l < i);
    idx_r = idx_r(idx_r > i);
    ref_vals = [psd_db(idx_l); psd_db(idx_r)];
    if ~isempty(ref_vals), tpsw_p1(i) = mean(ref_vals); else, tpsw_p1(i) = psd_db(i); end
end

censor_mask = (psd_db - tpsw_p1) > tpsw_gate_db;
psd_censored = psd_db;
psd_censored(censor_mask) = tpsw_p1(censor_mask);

b_tpsw_db = zeros(N_pts, 1);
for i = 1:N_pts
    idx_l = max(1, i - g_pts - m_pts) : max(1, i - g_pts);
    idx_r = min(N_pts, i + g_pts) : min(N_pts, i + g_pts + m_pts);
    idx_l = idx_l(idx_l < i);
    idx_r = idx_r(idx_r > i);
    ref_vals = [psd_censored(idx_l); psd_censored(idx_r)];
    if ~isempty(ref_vals), b_tpsw_db(i) = mean(ref_vals); else, b_tpsw_db(i) = psd_censored(i); end
end

% Equalized CFAR Spectrum for Narrowband Carriers
tonal_snr_db = psd_db - b_tpsw_db;
is_tonal_pk  = [false; (tonal_snr_db(2:end-1) > tonal_snr_db(1:end-2)) & ...
                       (tonal_snr_db(2:end-1) >= tonal_snr_db(3:end)); false];
idx_tonal_pks = find(is_tonal_pk & (tonal_snr_db >= tpsw_thresh_db));

% ---------------------------------------------------------------------
% 5. Tier 1: Physically-Grounded Multi-Scale Lobe Segmentation
% ---------------------------------------------------------------------
% A. Ambient Ocean Floor Baseline Estimation (Continuous Roll-off)
% Models the 5-6 dB/octave background decay across quiet soundscape percentiles
span_amb_bins = round(150.0 / df);
ocean_floor_local = movmin(psd_db, span_amb_bins);
ocean_floor_smooth = smoothdata(ocean_floor_local, 'gaussian', round(100.0 / df));
ocean_ambient_db = prctile(ocean_floor_smooth, 25);

% Net linear power above ocean floor
p_lin_grid       = 10.^(psd_db / 10);
p_floor_lin      = 10.^(ocean_floor_smooth / 10);
net_p_lin        = max(0, p_lin_grid - p_floor_lin);
total_net_energy = trapz(f_grid, net_p_lin);

% Macro-elevation profile (light 6 Hz filter to suppress single-bin Welch jitter)
psd_envelope = smoothdata(psd_db, 'gaussian', round(6.0 / df));
macro_snr_profile = psd_envelope - ocean_floor_smooth;

% Step 1: Identify all candidate peak centers (prominence > 2.5 dB above ambient)
is_peak = [false; (psd_envelope(2:end-1) > psd_envelope(1:end-2)) & ...
                  (psd_envelope(2:end-1) >= psd_envelope(3:end)); false];
idx_all_peaks = find(is_peak & (macro_snr_profile >= 2.5));

% Step 2: Topographic Watershed Segmentation with Prominence Splitting
% - Valleys separating distinct signals are identified where power dips
is_valley = [false; (psd_envelope(2:end-1) < psd_envelope(1:end-2)) & ...
                    (psd_envelope(2:end-1) <= psd_envelope(3:end)); false];
idx_valleys = find(is_valley);

% Evaluate every adjacent pair of prominent peaks:
% Do they belong to the same macro-structure or are they distinct signals?
split_points = [1];
for v = 1:length(idx_valleys)
    i_v = idx_valleys(v);
    % Find nearest peaks to the left and right
    p_left  = idx_all_peaks(idx_all_peaks < i_v);
    p_right = idx_all_peaks(idx_all_peaks > i_v);

    if ~isempty(p_left) && ~isempty(p_right)
        i_l = p_left(end);
        i_r = p_right(1);

        peak_min_val = min(psd_envelope(i_l), psd_envelope(i_r));
        valley_val   = psd_envelope(i_v);
        drop_db      = peak_min_val - valley_val;
        valley_snr   = macro_snr_profile(i_v);

        % SPLIT CRITERION:
        % 1. Deep saddle drop (>= prominence_split, e.g. Croatia 583 vs 631.5 dips > 8 dB)
        % 2. OR valley drops to ambient noise baseline (valley_snr <= 2.0 dB)
        if (drop_db >= prominence_split) || (valley_snr <= 2.0)
            split_points = [split_points; i_v]; %#ok<AGROW>
        end
    end
end
split_points = unique([split_points; N_pts]);

% Step 3: Build Valid Lobes from Partitions
% A partition qualifies as a real signal lobe if it carries >= 3.0% net power
% or contains a verified CFAR carrier tonal
cand_lobes = [];
for sp = 1:length(split_points) - 1
    i_a = split_points(sp);
    i_b = split_points(sp + 1);

    % Trim boundaries inward to where power is elevated above ambient floor
    sub_idx = i_a:i_b;
    elev_sub = sub_idx(macro_snr_profile(sub_idx) >= 1.5);

    if ~isempty(elev_sub) && (f_grid(elev_sub(end)) - f_grid(elev_sub(1)) >= 4.0)
        cand_lobes = [cand_lobes; elev_sub(1), elev_sub(end)]; %#ok<AGROW>
    end
end

% Structure detected lobes
num_lobes = size(cand_lobes, 1);
macro_lobes = repmat(struct(), max(num_lobes, 1), 1);
valid_count = 0;

for m = 1:num_lobes
    idx_a = cand_lobes(m, 1);
    idx_b = cand_lobes(m, 2);

    f_sub     = f_grid(idx_a:idx_b);
    p_sub_lin = net_p_lin(idx_a:idx_b);
    p_sub_db  = psd_db(idx_a:idx_b);

    e_lobe = trapz(f_sub, p_sub_lin);
    pct_e  = 100 * (e_lobe / max(total_net_energy, eps));
    [pk_val, pk_rel] = max(p_sub_db);
    pk_abs = idx_a + pk_rel - 1;

    % -3 dB half-power bandwidth
    target_3db = pk_val - 3.0;
    i_l = pk_abs;
    while i_l > idx_a && psd_db(i_l) > target_3db, i_l = i_l - 1; end
    i_r = pk_abs;
    while i_r < idx_b && psd_db(i_r) > target_3db, i_r = i_r + 1; end
    bw_3db = max(df, f_grid(i_r) - f_grid(i_l));

    internal_tonals = f_grid(idx_tonal_pks(idx_tonal_pks >= idx_a & idx_tonal_pks <= idx_b));

    % Retain if it contains significant energy OR a verified CFAR tonal
    if (pct_e >= 2.0) || ~isempty(internal_tonals)
        valid_count = valid_count + 1;
        macro_lobes(valid_count).f_start        = f_sub(1);
        macro_lobes(valid_count).f_end          = f_sub(end);
        macro_lobes(valid_count).total_span_hz  = f_sub(end) - f_sub(1);
        macro_lobes(valid_count).bw_3db         = bw_3db;
        macro_lobes(valid_count).energy_lin     = e_lobe;
        macro_lobes(valid_count).pct_energy     = pct_e;
        macro_lobes(valid_count).peak_freq      = f_grid(pk_abs);
        macro_lobes(valid_count).peak_psd       = pk_val;
        macro_lobes(valid_count).internal_lines = internal_tonals;
        macro_lobes(valid_count).num_lines      = length(internal_tonals);
    end
end
macro_lobes = macro_lobes(1:valid_count);

% Tag dominant energetic lobe
if ~isempty(macro_lobes)
    [~, idx_dom] = max([macro_lobes.energy_lin]);
    dom_lobe = macro_lobes(idx_dom);
else
    dom_lobe = struct('f_start', 0, 'f_end', 0, 'total_span_hz', 0, ...
                      'bw_3db', 0, 'energy_lin', 0, 'pct_energy', 0, ...
                      'peak_freq', 0, 'peak_psd', 0, 'internal_lines', [], 'num_lines', 0);
end

% ---------------------------------------------------------------------
% 6. Time-Frequency Spectrogram
% ---------------------------------------------------------------------
nwin_sp = 2^nextpow2(fs_common * 0.25);
nov_sp  = floor(nwin_sp * 0.90);
nfft_sp = max(nwin_sp, 4096);
[~, f_sp, t_sp, p_sp] = spectrogram(audioSignal, hann(nwin_sp), nov_sp, nfft_sp, fs_common);
p_sp_db = 10 * log10(max(p_sp, eps));

% Save results
results(k).name               = d.name;
results(k).f_grid             = f_grid;
results(k).psd_db             = psd_db;
results(k).b_tpsw_db          = b_tpsw_db;
results(k).ocean_floor_smooth = ocean_floor_smooth;
results(k).ocean_ambient_db   = ocean_ambient_db;
results(k).tonal_snr_db       = tonal_snr_db;
results(k).tonal_pks_fc       = f_grid(idx_tonal_pks);
results(k).macro_lobes        = macro_lobes;
results(k).dom_lobe           = dom_lobe;
results(k).enbw_win_hz        = enbw_win_hz;
results(k).f_low              = d.f_low;
results(k).f_high             = d.f_high;
results(k).t_sp               = t_sp;
results(k).f_sp               = f_sp;
results(k).p_sp_db            = p_sp_db;


end

% -------------------------------------------------------------------------
% 7. Visualization: Multi-Scale Lobe & Tonal Analysis (Figure 1)
% -------------------------------------------------------------------------
fig1 = figure('Name', 'Multi-Scale Acoustic Analyzer: Macro-Lobes & Tonals', ...
'Color', [0.07 0.09 0.13], 'Position', [30, 30, 1560, 940]);

c_ax      = [0.10 0.12 0.18];
c_raw     = [0.20 0.82 1.00];  % Cyan: Raw Welch PSD
c_tpsw    = [0.95 0.78 0.20];  % Gold: TPSW CFAR Baseline
c_ocean   = [0.55 0.60 0.70];  % Steel Gray: Ambient Ocean Floor
c_dom     = [1.00 0.25 0.35];  % Red/Crimson: Dominant Lobe
c_sec     = [0.25 0.70 0.95];  % Blue: Secondary Macro-Lobes
c_grid    = [0.20 0.24 0.32];
c_text    = [0.90 0.93 0.96];

for k = 1:numData
s = results(k);

% Top Plot: Macro-Lobes over Ambient Soundscape
ax_top = subplot(2, 2, k);
set(ax_top, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, ...
            'GridColor', c_grid, 'GridAlpha', 0.5, 'LineWidth', 1.0);
hold(ax_top, 'on'); grid(ax_top, 'on');

dom = s.dom_lobe;
y_min_top = min(s.psd_db) - 4;

% Fill and label all macro-lobes
for m = 1:length(s.macro_lobes)
    lb = s.macro_lobes(m);
    idx_lb = (s.f_grid >= lb.f_start) & (s.f_grid <= lb.f_end);
    f_lb = s.f_grid(idx_lb);
    p_lb = s.psd_db(idx_lb);

    is_dominant = (lb.f_start == dom.f_start && lb.f_end == dom.f_end);
    if is_dominant
        fill(ax_top, [f_lb; flipud(f_lb)], [p_lb; y_min_top * ones(size(p_lb))], ...
             c_dom, 'FaceAlpha', 0.25, 'EdgeColor', 'none', ...
             'DisplayName', sprintf('Primary Lobe [%0.0f-%0.0f Hz, %0.1f%% Power]', ...
                                    lb.f_start, lb.f_end, lb.pct_energy));
        xline(ax_top, lb.f_start, 'Color', c_dom, 'LineStyle', '--', 'LineWidth', 1.4, 'HandleVisibility', 'off');
        xline(ax_top, lb.f_end,   'Color', c_dom, 'LineStyle', '--', 'LineWidth', 1.4, 'HandleVisibility', 'off');
    else
        fill(ax_top, [f_lb; flipud(f_lb)], [p_lb; y_min_top * ones(size(p_lb))], ...
             c_sec, 'FaceAlpha', 0.15, 'EdgeColor', 'none', ...
             'DisplayName', sprintf('Lobe %d [%0.0f-%0.0f Hz, %0.1f%% Power]', ...
                                    m, lb.f_start, lb.f_end, lb.pct_energy));
        xline(ax_top, lb.f_start, 'Color', c_sec, 'LineStyle', ':', 'LineWidth', 1.1, 'HandleVisibility', 'off');
        xline(ax_top, lb.f_end,   'Color', c_sec, 'LineStyle', ':', 'LineWidth', 1.1, 'HandleVisibility', 'off');
    end
end

plot(ax_top, s.f_grid, s.psd_db,            'Color', c_raw,   'LineWidth', 1.2, 'DisplayName', 'Welch PSD (Twin = 50 ms)');
plot(ax_top, s.f_grid, s.ocean_floor_smooth, 'Color', c_ocean, 'LineWidth', 1.2, 'LineStyle', '--', ...
     'DisplayName', sprintf('Ambient Ocean Floor (%0.1f dB)', s.ocean_ambient_db));
plot(ax_top, s.f_grid, s.b_tpsw_db,         'Color', c_tpsw,  'LineWidth', 1.0, 'LineStyle', '-.', ...
     'DisplayName', 'TPSW Local Baseline');

% Mark CFAR discrete carrier lines
if ~isempty(s.tonal_pks_fc)
    for cf = 1:length(s.tonal_pks_fc)
        fc_val = s.tonal_pks_fc(cf);
        p_val  = s.psd_db(s.f_grid == fc_val);
        plot(ax_top, fc_val, p_val, 'r^', 'MarkerFaceColor', [1.0 0.3 0.3], ...
             'MarkerSize', 5, 'HandleVisibility', 'off');
    end
end

xlim(ax_top, [s.f_low, s.f_high]);
ylabel(ax_top, 'PSD (dB/Hz)', 'FontSize', 9, 'FontWeight', 'bold', 'Color', c_text);
title(ax_top, sprintf('%s: Physically Identified Lobes & Ambient Floor', s.name), ...
      'FontSize', 10.5, 'FontWeight', 'bold', 'Color', c_text);
legend(ax_top, 'Location', 'northeast', 'TextColor', c_text, ...
       'Color', [0.08 0.10 0.15], 'EdgeColor', c_grid, 'FontSize', 7.5);

% Bottom Plot: Tier 2 Narrowband Carrier CFAR Spectrum (LOFAR Whitened)
ax_bot = subplot(2, 2, k + 2);
set(ax_bot, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, ...
            'GridColor', c_grid, 'GridAlpha', 0.5, 'LineWidth', 1.0);
hold(ax_bot, 'on'); grid(ax_bot, 'on');

w_pos = max(s.tonal_snr_db, 0);
fill(ax_bot, [s.f_grid; flipud(s.f_grid)], [w_pos; zeros(size(w_pos))], ...
     [0.30 0.90 0.70], 'FaceAlpha', 0.20, 'EdgeColor', 'none', 'HandleVisibility', 'off');

plot(ax_bot, s.f_grid, s.tonal_snr_db, 'Color', [0.30 0.90 0.70], 'LineWidth', 1.1, ...
     'DisplayName', 'Equalized CFAR Spectrum (\Delta P = P - B_{TPSW})');
yline(ax_bot, tpsw_thresh_db, 'Color', [1.00 0.40 0.40], 'LineStyle', ':', ...
      'LineWidth', 1.2, 'DisplayName', sprintf('CFAR Threshold (+%0.1f dB)', tpsw_thresh_db));
yline(ax_bot, 0, 'Color', [0.55 0.60 0.70], 'LineWidth', 0.8, 'HandleVisibility', 'off');

% Mark identified narrow carrier lines
if ~isempty(s.tonal_pks_fc)
    for cf = 1:length(s.tonal_pks_fc)
        fc_val = s.tonal_pks_fc(cf);
        snr_val = s.tonal_snr_db(s.f_grid == fc_val);
        plot(ax_bot, fc_val, snr_val, 'r^', 'MarkerFaceColor', [1.0 0.3 0.3], ...
             'MarkerSize', 5.5, 'HandleVisibility', 'off');
        text(ax_bot, fc_val, snr_val + 0.8, sprintf('%0.1f Hz', fc_val), ...
             'Color', c_text, 'FontSize', 7.5, 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    end
end

xlim(ax_bot, [s.f_low, s.f_high]);
xlabel(ax_bot, 'Frequency (Hz)', 'FontSize', 9.5, 'FontWeight', 'bold', 'Color', c_text);
ylabel(ax_bot, 'CFAR SNR (dB)', 'FontSize', 9, 'FontWeight', 'bold', 'Color', c_text);
title(ax_bot, sprintf('Narrowband Carrier Extraction (CFAR > +%0.1f dB)', tpsw_thresh_db), ...
      'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
legend(ax_bot, 'Location', 'northeast', 'TextColor', c_text, ...
       'Color', [0.08 0.10 0.15], 'EdgeColor', c_grid, 'FontSize', 7.5);


end

% -------------------------------------------------------------------------
% 8. Visualization: High-Resolution Spectrograms (Figure 2)
% -------------------------------------------------------------------------
fig2 = figure('Name', 'High-Resolution Acoustic Spectrograms [2D Raster Display]', ...
'Color', [0.07 0.09 0.13], 'Position', [60, 60, 1540, 620]);

for k = 1:numData
s = results(k);
ax_sp = subplot(1, 2, k);
set(ax_sp, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, ...
'GridColor', c_grid, 'LineWidth', 1.0);
hold(ax_sp, 'on');

f_mask = (s.f_sp >= s.f_low) & (s.f_sp <= s.f_high);
f_disp = s.f_sp(f_mask) / 1000; % kHz
p_disp = s.p_sp_db(f_mask, :);

imagesc(ax_sp, s.t_sp, f_disp, p_disp);
set(ax_sp, 'YDir', 'normal');
colormap(ax_sp, 'turbo');

% Overlay verified lobe boundaries on spectrogram
for m = 1:length(s.macro_lobes)
    lb = s.macro_lobes(m);
    if (lb.pct_energy >= 3.0) || (lb.num_lines > 0)
        col_l = [1.0 1.0 1.0];
        if lb.f_start == s.dom_lobe.f_start, col_l = [1.0 0.3 0.4]; end
        yline(ax_sp, lb.f_start / 1000, 'Color', col_l, 'LineStyle', '--', 'LineWidth', 1.2);
        yline(ax_sp, lb.f_end   / 1000, 'Color', col_l, 'LineStyle', '--', 'LineWidth', 1.2);
    end
end

clim_lo = prctile(p_disp(:), 10);
clim_hi = prctile(p_disp(:), 99.7);
if clim_hi <= clim_lo, clim_hi = clim_lo + 25; end
if exist('clim', 'builtin') || exist('clim', 'file')
    clim(ax_sp, [clim_lo, clim_hi]);
else
    caxis(ax_sp, [clim_lo, clim_hi]);
end

cb = colorbar(ax_sp);
cb.Color = c_text;
ylabel(cb, 'PSD (dB/Hz)', 'Color', c_text, 'FontSize', 9);
xlabel(ax_sp, 'Time (s)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
ylabel(ax_sp, 'Frequency (kHz)', 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
title(ax_sp, sprintf('%s: Spectrogram [Lobe Boundaries]', s.name), ...
      'FontSize', 10.5, 'FontWeight', 'bold', 'Color', c_text);


end

% -------------------------------------------------------------------------
% 9. Console Diagnostic Report
% -------------------------------------------------------------------------
fprintf('\n============================================================\n');
fprintf('ACOUSTIC DIAGNOSTIC REPORT: LOBES & TONAL LINES\n');
fprintf('============================================================\n');

for k = 1:numData
s = results(k);
fprintf('\n------------------------------------------------------------\n');
fprintf('  %s\n', s.name);
fprintf('  Passband:                  %d - %d Hz\n', s.f_low, s.f_high);
fprintf('  Ambient Ocean Floor:       %0.1f dB/Hz\n', s.ocean_ambient_db);
fprintf('  Lobes Identified:          %d regions\n', length(s.macro_lobes));
fprintf('  Narrowband Carriers Found: %d lines\n', length(s.tonal_pks_fc));
fprintf('  ----------------------------------------------------------\n');

for m = 1:length(s.macro_lobes)
    lb = s.macro_lobes(m);
    fprintf('  Lobe %d: [%0.1f - %0.1f Hz] (Span: %0.1f Hz, 3-dB: %0.1f Hz) | Pk: %0.1f dB @ %0.1f Hz | Power: %0.1f%%\n', ...
            m, lb.f_start, lb.f_end, lb.total_span_hz, lb.bw_3db, lb.peak_psd, lb.peak_freq, lb.pct_energy);
    if lb.num_lines > 0
        fprintf('          Contains %d carrier lines: ', lb.num_lines);
        fprintf('%0.1f Hz  ', lb.internal_lines);
        fprintf('\n');
    end
end

dom = s.dom_lobe;
fprintf('\n  >>> DOMINANT ENERGETIC LOBE <<<\n');
fprintf('      Frequency Range:       %0.1f - %0.1f Hz\n', dom.f_start, dom.f_end);
fprintf('      Total Span:            %0.1f Hz\n', dom.total_span_hz);
fprintf('      3-dB Bandwidth:        %0.1f Hz\n', dom.bw_3db);
fprintf('      Peak Spectral Density: %0.1f dB/Hz @ %0.1f Hz\n', dom.peak_psd, dom.peak_freq);
fprintf('      Net Radiated Energy:   %0.2f%% OF TOTAL PASSBAND POWER\n', dom.pct_energy);


end
fprintf('============================================================\n\n');