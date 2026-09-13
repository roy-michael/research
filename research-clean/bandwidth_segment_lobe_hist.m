% =========================================================================
% UNDERWATER ACOUSTIC LOBE, NOISE FLOOR & FAIRNESS ANALYZER
% Streamlined & Modular Pipeline for Passive Acoustic Signal Analysis
% =========================================================================
% Pipeline Outline:
%   1. Central Configuration
%   2. Main Pipeline Orchestrator
%   3. Audio Ingestion & Conditioning
%   4. Spectral Estimation (Welch PSD & Baselines)
%   5. Macro-Lobe Watershed Segmentation
%   6. Sub-Bin 20% Prominence Bandwidth & Temporal Fairness Tracking
%   7. Diagnostic Visual Suite (Figures 1, 2, 3, and 4)
%   8. Summary Reporting
% =========================================================================

clear; close all; clc;

% =========================================================================
% 1. CENTRAL CONFIGURATION
% =========================================================================
function cfg = get_config()
cfg = struct();

% File paths & dataset definitions
base_dir   = 'D:\RoyStudies\Recordings';
dir_boat   = fullfile(base_dir, 'hear_my_ship', 'V1', 'Motor Boats');
dir_croat  = fullfile(base_dir, 'Croatia', 'Ocean Sonics', '2407_1_600m');

cfg.datasets = struct(...
    'name',   {'Dataset 1: Motorboat (Hear My Ship)', ...
               'Dataset 2: Ocean Sonics (Croatia 600m)'}, ...
    'folder', {dir_boat, dir_croat}, ...
    'path',   {fullfile(dir_boat, 'Motorboat (06.09.23_083534).wav'), ...
               fullfile(dir_croat, 'RBW6737_20250724_093000.wav')}, ...
    'f_low',  {50, 400}, ...
    'f_high', {2000, 2000} ...
);

% Sampling and analysis windows
cfg.fs             = 48000;   % Standardized sample rate (Hz)
cfg.dur_sec        = 20.0;    % Segment duration to analyze (s)
cfg.df_eval        = 0.5;     % Uniform PSD evaluation resolution (Hz)
cfg.twin_welch     = 0.050;   % Welch window length (s) -> ~20 Hz resolution
cfg.slice_dur      = 0.500;   % Time slice for peak tracking (s) -> 2 Hz resolution

% Two-Pass Split-Window (TPSW) CFAR parameters
cfg.tpsw_guard_hz  = 2.5;     % Guard band half-width (Hz)
cfg.tpsw_ref_hz    = 30.0;    % Reference noise band half-width (Hz)
cfg.tpsw_gate_db   = 3.0;     % Pass 1 peak censoring threshold (dB)
cfg.tpsw_thresh_db = 3.8;     % Pass 2 CFAR detection threshold (dB)

% Macro-lobe & Bandwidth parameters
cfg.prom_split_db  = 5.0;     % Minimum prominence valley drop for macro-lobes (dB)
cfg.bw_prom_ratio  = 0.20;    % Prominence fraction above lower noise floor (20%)
cfg.track_tol_hz   = 25.0;    % Search window around target peak (+/- Hz)
cfg.fairness_win   = 5;       % Rolling window size (slices) for Jain's fairness index
cfg.win_radius_hz  = 35.0;    % Evaluation radius flanking target peak (+/- Hz)
cfg.kde_bw         = 1.5;     % KDE kernel bandwidth for BW (Hz)
cfg.kde_fairness   = 0.02;    % KDE kernel bandwidth for fairness index


end

% =========================================================================
% 2. MAIN PIPELINE ORCHESTRATOR
% =========================================================================
cfg = get_config();
num_datasets = length(cfg.datasets);
results = cell(num_datasets, 1);

for k = 1:num_datasets
meta = cfg.datasets(k);
fprintf('\n============================================================\n');
fprintf('PROCESSING: %s\n', meta.name);
fprintf('============================================================\n');

% Step 1: Ingest and condition audio
[audio, fs] = ingest_audio(meta, cfg);

% Step 2: Welch PSD and order-statistic baselines
[psd_db, f_grid, df, k_welch] = compute_welch_psd(audio, fs, meta.f_low, meta.f_high, cfg);
[b_tpsw, b_med, idx_tonals, d_tpsw] = compute_baselines(psd_db, df, k_welch, cfg);

% Step 3: Macro-lobe watershed segmentation
[macro_lobes, dom_lobe, ocean_floor, ocean_amb_db] = ...
    segment_macro_lobes(psd_db, f_grid, df, cfg.prom_split_db, idx_tonals);

% Step 4: Midpoint sub-bin 20% prominence bandwidth
slice_len = round(fs * cfg.slice_dur);
mid_idx   = round(length(audio) / 2);
st_idx    = max(1, mid_idx - floor(slice_len / 2));
mid_chunk = audio(st_idx : st_idx + slice_len - 1);
[spec_mid, f_pos_mid] = compute_fft_slice(mid_chunk, fs);

lobe_bw = extract_subbin_bandwidth(spec_mid, f_pos_mid, dom_lobe.peak_freq, ...
    cfg.bw_prom_ratio, cfg.win_radius_hz, true);

% Step 5: Temporal peak tracking & rolling Jain's fairness
temporal = track_temporal_metrics(audio, fs, dom_lobe.peak_freq, cfg);

% Step 6: 2D Spectrogram
[t_spec, f_spec, p_spec_db] = compute_spectrogram(audio, fs, meta.f_low, meta.f_high);

% Store results
res = struct();
res.meta         = meta;
res.f_grid       = f_grid;
res.psd_db       = psd_db;
res.b_tpsw       = b_tpsw;
res.b_med        = b_med;
res.d_tpsw       = d_tpsw;
res.idx_tonals   = idx_tonals;
res.macro_lobes  = macro_lobes;
res.dom_lobe     = dom_lobe;
res.ocean_floor  = ocean_floor;
res.ocean_amb_db = ocean_amb_db;
res.lobe_bw      = lobe_bw;
res.temporal     = temporal;
res.t_spec       = t_spec;
res.f_spec       = f_spec;
res.p_spec_db    = p_spec_db;

results{k} = res;


end

% Render visualizations and print report
render_fig1_psd_cfar(results, cfg);
render_fig2_lobe_profile(results);
render_fig3_spectrograms(results);
render_fig4_fairness_and_histograms(results, cfg);
print_summary(results);

% =========================================================================
% 3. AUDIO INGESTION & CONDITIONING
% =========================================================================
function [sig_clean, fs_target] = ingest_audio(meta, cfg)
fs_target = cfg.fs;
target_len = round(cfg.dur_sec * fs_target);

% Locate file or synthetic fallback
resolved_file = '';
if exist(meta.path, 'file') == 2
    resolved_file = meta.path;
elseif exist(meta.folder, 'dir') == 7
    wavs = dir(fullfile(meta.folder, '*.wav'));
    if ~isempty(wavs)
        resolved_file = fullfile(wavs(1).folder, wavs(1).name);
    end
end

if ~isempty(resolved_file)
    fprintf('  Loading: %s\n', resolved_file);
    info = audioinfo(resolved_file);
    fs_file = info.SampleRate;

    if info.Duration > cfg.dur_sec
        t_start = max(0, (info.Duration - cfg.dur_sec) / 2);
        sample_bounds = round([t_start * fs_file + 1, (t_start + cfg.dur_sec) * fs_file]);
        sample_bounds(2) = min(sample_bounds(2), info.TotalSamples);
        [raw, ~] = audioread(resolved_file, sample_bounds);
    else
        [raw, ~] = audioread(resolved_file);
    end
else
    fprintf('  File not found. Synthesizing realistic benchmark signal...\n');
    t = (0 : 1 / fs_target : cfg.dur_sec)';
    if contains(meta.name, 'Motorboat')
        % Multi-harmonic machinery lines + cavitation band
        raw = 0.09 * sin(2*pi*58*t) + 0.08 * sin(2*pi*138*t) + ...
              0.05 * sin(2*pi*144.5*t) + 0.03 * sin(2*pi*151*t) + ...
              0.04 * sin(2*pi*218*t) + 0.003 * randn(size(t));
        [b_cav, a_cav] = butter(3, [500 1100] / (fs_target / 2), 'bandpass');
        raw = raw + 0.12 * filter(b_cav, a_cav, randn(size(t)));
    else
        % Clean stationary ocean with isolated CW carriers (Croatia)
        raw = 0.04 * sin(2*pi*583*t) + 0.09 * sin(2*pi*632*t) + 0.0015 * randn(size(t));
    end
    fs_file = fs_target;
end

% Convert to mono
if size(raw, 2) > 1
    raw = mean(raw, 2);
end

% Resample if necessary
if fs_file ~= fs_target
    sig = resample(raw, fs_target, fs_file);
else
    sig = raw;
end

% Length alignment
if length(sig) < target_len
    sig = [sig; zeros(target_len - length(sig), 1)];
else
    sig = sig(1:target_len);
end

% DC offset removal & 20 Hz high-pass conditioning
sig = sig - mean(sig);
[b_hp, a_hp] = butter(4, 20.0 / (fs_target / 2), 'high');
sig_clean = filtfilt(b_hp, a_hp, sig);


end

% =========================================================================
% 4. SPECTRAL ESTIMATION & ORDER-STATISTIC BASELINES
% =========================================================================
function [psd_db, f_grid, df, k_welch] = compute_welch_psd(signal, fs, f_min, f_max, cfg)
nwin = 2^nextpow2(fs * cfg.twin_welch);
win  = hamming(nwin);
nov  = floor(nwin * 0.75);
nfft = max(nwin, 8192);

[psd_raw, f_raw] = pwelch(signal, win, nov, nfft, fs);
k_welch = floor((length(signal) - nov) / (nwin - nov));

df = cfg.df_eval;
f_grid = (f_min : df : f_max)';
psd_interp = interp1(f_raw, psd_raw, f_grid, 'pchip');
psd_db = 10 * log10(max(psd_interp, eps));


end

function [b_tpsw_db, b_med_db, idx_tonals, delta_tpsw] = compute_baselines(psd_db, df, k_welch, cfg)
p_lin = 10.^(psd_db / 10);

% Moving Median Baseline (with Erlang bias correction factor)
bw_peak_hz = 1.3 / cfg.twin_welch;
win_med = 2 * ceil(1.5 * ceil(bw_peak_hz / df)) + 1;
scale_welch = 1 / (1 - 1 / (3 * max(k_welch, 2)))^3;
b_med_db = 10 * log10(max(scale_welch * movmedian(p_lin, win_med), eps));

% Two-Pass Split-Window (TPSW) CFAR Baseline
g_bins = max(1, round(cfg.tpsw_guard_hz / df));
r_bins = max(2, round(cfg.tpsw_ref_hz / df));

% Build split-window averaging kernel
kernel_len = 2 * (g_bins + r_bins) + 1;
kernel = zeros(kernel_len, 1);
kernel([1:r_bins, (kernel_len - r_bins + 1):kernel_len]) = 1 / (2 * r_bins);

% Pass 1: Local reference average & peak censoring
b_p1 = conv(psd_db, kernel, 'same');
mask_censor = (psd_db - b_p1) > cfg.tpsw_gate_db;
psd_censored = psd_db;
psd_censored(mask_censor) = b_p1(mask_censor);

% Pass 2: Final baseline from censored spectrum
b_tpsw_db = conv(psd_censored, kernel, 'same');
delta_tpsw = psd_db - b_tpsw_db;

% CFAR tonal line extraction
is_peak = [false; (delta_tpsw(2:end-1) > delta_tpsw(1:end-2)) & ...
                  (delta_tpsw(2:end-1) >= delta_tpsw(3:end)); false];
idx_tonals = find(is_peak & (delta_tpsw >= cfg.tpsw_thresh_db));


end

% =========================================================================
% 5. PROMINENCE-BASED MACRO-LOBE WATERSHED SEGMENTATION
% =========================================================================
function [macro_lobes, dom_lobe, ocean_floor, ocean_amb_db] = ...
segment_macro_lobes(psd_db, f_grid, df, prom_split_db, idx_tonals)

N = length(psd_db);
win_bg = 2 * ceil(100.0 / df) + 1;
ocean_floor = smoothdata(movmin(psd_db, win_bg), 'gaussian', round(40.0 / df));
ocean_amb_db = prctile(ocean_floor, 15);

delta_amb = psd_db - ocean_floor;
p_net = max(0, 10.^(psd_db / 10) - 10.^(ocean_floor / 10));
total_energy = trapz(f_grid, p_net);

% Smooth spectral envelope & find topographic saddles
psd_env = smoothdata(psd_db, 'gaussian', max(3, round(6.0 / df)));
valleys = find([false; (psd_env(2:end-1) < psd_env(1:end-2)) & ...
                       (psd_env(2:end-1) <= psd_env(3:end)); false]);
peaks   = find([false; (psd_env(2:end-1) > psd_env(1:end-2)) & ...
                       (psd_env(2:end-1) >= psd_env(3:end)); false]);

valid_valleys = [];
for v = 1:length(valleys)
    idx_v = valleys(v);
    lp = peaks(peaks < idx_v);
    rp = peaks(peaks > idx_v);
    if ~isempty(lp) && ~isempty(rp)
        drop = min(psd_env(lp(end)) - psd_env(idx_v), psd_env(rp(1)) - psd_env(idx_v));
        if (delta_amb(idx_v) <= 3.0) || ((drop >= prom_split_db) && (delta_amb(idx_v) <= 5.0))
            valid_valleys = [valid_valleys; idx_v];
        end
    end
end

boundaries = unique([1; valid_valleys; N]);
cand_lobes = [];

for b = 1:length(boundaries) - 1
    i_st = boundaries(b);
    i_en = boundaries(b + 1);
    f_sub = f_grid(i_st:i_en);
    p_sub = psd_db(i_st:i_en);

    [pk_val, pk_loc] = max(p_sub);
    e_sub = trapz(f_sub, p_net(i_st:i_en));
    pct_e = 100 * (e_sub / max(total_energy, eps));

    if (pct_e >= 1.0) && ((pk_val - ocean_floor(i_st + pk_loc - 1)) >= 2.5)
        % Trim tails near ambient floor
        while (i_st < i_st + pk_loc - 1) && (delta_amb(i_st) <= 1.0), i_st = i_st + 1; end
        while (i_en > i_st + pk_loc - 1) && (delta_amb(i_en) <= 1.0), i_en = i_en - 1; end

        lobe = struct('f_start', f_grid(i_st), 'f_end', f_grid(i_en), ...
                      'bandwidth', f_grid(i_en) - f_grid(i_st), ...
                      'peak_freq', f_sub(pk_loc), 'peak_psd', pk_val, ...
                      'energy', e_sub, 'pct_energy', pct_e);

        tonals = f_grid(idx_tonals);
        lobe.internal_tonals = tonals(tonals >= lobe.f_start & tonals <= lobe.f_end);
        cand_lobes = [cand_lobes; lobe];
    end
end

if isempty(cand_lobes)
    [max_val, max_idx] = max(psd_db);
    dom_lobe = struct('f_start', f_grid(1), 'f_end', f_grid(end), ...
                      'bandwidth', f_grid(end) - f_grid(1), ...
                      'peak_freq', f_grid(max_idx), 'peak_psd', max_val, ...
                      'energy', total_energy, 'pct_energy', 100, 'internal_tonals', []);
    macro_lobes = dom_lobe;
else
    [~, max_e] = max([cand_lobes.energy]);
    dom_lobe = cand_lobes(max_e);
    macro_lobes = cand_lobes;
end


end

% =========================================================================
% 6. BANDWIDTH ENGINE & TEMPORAL FAIRNESS TRACKING
% =========================================================================
function [spec_db, f_pos] = compute_fft_slice(chunk, fs)
% Computes single-sided FFT dB spectrum and frequency axis from a time chunk
len = length(chunk);
win = hann(len);
chunk_fft = fft(chunk .* win);
n_pos = floor(len / 2) + 1;
f_pos = (0 : n_pos - 1)' * (fs / len);
spec_db = 20 * log10(abs(chunk_fft(1 : n_pos)) + 1e-12);
end

function out = extract_subbin_bandwidth(spec_db, f_pos, target_freq, prom_ratio, radius_hz, return_details)
% Unified sub-bin 20% prominence bandwidth calculator from a dB spectrum
if nargin < 6, return_details = false; end

out = struct('found', false, 'bandwidth', NaN, 'dom_freq', target_freq, ...
             'peak_amp', NaN, 'f_segment', [], 'fft_segment', [], ...
             'lobe_shape', [], 'noise_floor', [], 'thresh_contour', [], ...
             'l_freq', NaN, 'r_freq', NaN, 'l_amp', NaN, 'r_amp', NaN);

if isempty(spec_db) || isnan(target_freq) || length(f_pos) < 3, return; end

df = f_pos(2) - f_pos(1);

% Locate local peak summit
[~, bin_pk] = min(abs(f_pos - target_freq));
search_rad  = max(2, round(8.0 / df));
search_rng  = max(1, bin_pk - search_rad) : min(length(spec_db), bin_pk + search_rad);
[~, rel_pk] = max(spec_db(search_rng));
pk_idx = search_rng(rel_pk);

% Segment window around peak
win_rad_bins = max(10, round(radius_hz / df));
i1 = max(1, pk_idx - win_rad_bins);
i2 = min(length(spec_db), pk_idx + win_rad_bins);

f_seg   = f_pos(i1:i2);
fft_seg = spec_db(i1:i2);
pk_local = pk_idx - i1 + 1;

% 1. Smoothed acoustic lobe contour
lobe = smoothdata(fft_seg, 'gaussian', 5);

% 2. Lower noise floor baseline
excl = max(3, round(6.0 / df));
flank_mask = true(size(fft_seg));
flank_mask(max(1, pk_local - excl) : min(length(fft_seg), pk_local + excl)) = false;

if sum(flank_mask) >= 6
    floor_level = median(lobe(flank_mask));
else
    floor_level = median(lobe);
end
noise_floor = smoothdata(movmin(lobe, max(5, round(12.0 / df))), 'gaussian', 7);
noise_floor = min(noise_floor, floor_level);

% 3. 20% Prominence Threshold: Floor + 0.20 * (Peak - Floor)
prom = max(2.0, lobe(pk_local) - noise_floor(pk_local));
thresh = noise_floor + (prom * prom_ratio);
delta = lobe - thresh;

% Sub-bin root finding: Left crossing
l_f = f_seg(1); l_a = thresh(1);
for i = pk_local : -1 : 2
    if (delta(i) >= 0) && (delta(i - 1) < 0)
        a = -delta(i - 1) / (delta(i) - delta(i - 1));
        l_f = f_seg(i - 1) + a * (f_seg(i) - f_seg(i - 1));
        l_a = thresh(i - 1) + a * (thresh(i) - thresh(i - 1));
        break;
    end
end

% Sub-bin root finding: Right crossing
r_f = f_seg(end); r_a = thresh(end);
for i = pk_local : (length(delta) - 1)
    if (delta(i) >= 0) && (delta(i + 1) < 0)
        a = -delta(i) / (delta(i + 1) - delta(i));
        r_f = f_seg(i) + a * (f_seg(i + 1) - f_seg(i));
        r_a = thresh(i) + a * (thresh(i + 1) - thresh(i));
        break;
    end
end

out.found     = true;
out.dom_freq  = f_pos(pk_idx);
out.peak_amp  = fft_seg(pk_local);
out.bandwidth = abs(r_f - l_f);
out.l_freq    = l_f;
out.r_freq    = r_f;
out.l_amp     = l_a;
out.r_amp     = r_a;

if return_details
    out.f_segment       = f_seg;
    out.fft_segment     = fft_seg;
    out.lobe_shape      = lobe;
    out.noise_floor     = noise_floor;
    out.thresh_contour  = thresh;
end


end

function metrics = track_temporal_metrics(signal, fs, target_freq, cfg)
slice_len = round(fs * cfg.slice_dur);
num_slices = floor(length(signal) / slice_len);

metrics = struct('t_slices', [], 'bw_tracked', [], 'rolling_fairness', [], ...
                 't_fairness', [], 'mean_bw', NaN, 'median_bw', NaN, ...
                 'std_bw', NaN, 'mean_fairness', NaN);

if num_slices < 1, return; end

bws = NaN(num_slices, 1);
t_slices = ((1:num_slices)' - 0.5) * cfg.slice_dur;

for i = 1:num_slices
    st = (i - 1) * slice_len + 1;
    chunk = signal(st : st + slice_len - 1);
    [spec_pos, f_pos] = compute_fft_slice(chunk, fs);

    % Track peak within tolerance
    search_mask = (f_pos >= (target_freq - cfg.track_tol_hz)) & ...
                  (f_pos <= (target_freq + cfg.track_tol_hz));
    sub_f = f_pos(search_mask);
    sub_p = spec_pos(search_mask);

    if ~isempty(sub_p)
        [~, rel_pk] = max(sub_p);
        slice_bw = extract_subbin_bandwidth(spec_pos, f_pos, sub_f(rel_pk), ...
            cfg.bw_prom_ratio, cfg.win_radius_hz, false);
        bws(i) = slice_bw.bandwidth;
    end
end

% Rolling Jain's Fairness Index: J(x) = (sum(x)^2) / (N * sum(x^2))
w = cfg.fairness_win;
num_wins = num_slices - w + 1;
fairness = NaN(num_wins, 1);
t_fair   = NaN(num_wins, 1);

for i = 1:num_wins
    win_vals = bws(i : i + w - 1);
    valid = win_vals(~isnan(win_vals) & (win_vals > 0));
    if length(valid) >= max(2, floor(w / 2))
        s1 = sum(valid); s2 = sum(valid.^2);
        if s2 > 0, fairness(i) = (s1^2) / (length(valid) * s2); end
    end
    t_fair(i) = mean(t_slices(i : i + w - 1));
end

valid_bw = bws(~isnan(bws) & (bws > 0));
valid_f  = fairness(~isnan(fairness));

metrics.t_slices         = t_slices;
metrics.bw_tracked       = bws;
metrics.rolling_fairness = fairness;
metrics.t_fairness       = t_fair;
metrics.mean_bw          = mean(valid_bw);
metrics.median_bw        = median(valid_bw);
metrics.std_bw           = std(valid_bw);
metrics.mean_fairness    = mean(valid_f);


end

function [t_spec, f_spec_crop, p_spec_db] = compute_spectrogram(signal, fs, f_min, f_max)
nwin = 2^nextpow2(fs * 0.250);
[~, f_raw, t_spec, p_raw] = spectrogram(signal, hamming(nwin), floor(nwin * 0.9), max(nwin, 4096), fs);
mask = (f_raw >= f_min) & (f_raw <= f_max);
f_spec_crop = f_raw(mask);
p_spec_db   = 10 * log10(max(p_raw(mask, :), eps));
end

% =========================================================================
% 7. VISUAL DIAGNOSTIC SUITE
% =========================================================================
function apply_plot_style(ax, title_str, xlabel_str, ylabel_str)
c_ax   = [0.10 0.12 0.18];
c_text = [0.92 0.94 0.97];
c_grid = [0.20 0.24 0.32];

set(ax, 'Color', c_ax, 'XColor', c_text, 'YColor', c_text, ...
        'GridColor', c_grid, 'GridAlpha', 0.5, 'LineWidth', 1.0);
hold(ax, 'on'); grid(ax, 'on'); box(ax, 'on');

if nargin >= 2 && ~isempty(title_str)
    title(ax, title_str, 'FontSize', 10, 'FontWeight', 'bold', 'Color', c_text);
end
if nargin >= 3 && ~isempty(xlabel_str)
    xlabel(ax, xlabel_str, 'FontSize', 9.5, 'FontWeight', 'bold', 'Color', c_text);
end
if nargin >= 4 && ~isempty(ylabel_str)
    ylabel(ax, ylabel_str, 'FontSize', 9.5, 'FontWeight', 'bold', 'Color', c_text);
end


end

function render_fig1_psd_cfar(results, cfg)
figure('Name', 'Figure 1: Macro-Lobe Watershed & Order-Statistic Baselines', ...
'Color', [0.07 0.09 0.13], 'Position', [30, 40, 1600, 940]);
N = length(results);

for k = 1:N
    r = results{k};

    % Top: PSD & Macro-Lobes
    ax_top = subplot(2, N, k);
    apply_plot_style(ax_top, sprintf('%s\nMacro-Lobes & Acoustic Baselines', r.meta.name), '', 'PSD (dB/Hz)');

    % Highlight Dominant Lobe
    dom = r.dom_lobe;
    m_dom = (r.f_grid >= dom.f_start) & (r.f_grid <= dom.f_end);
    y_bot = min(r.psd_db) - 4;
    fill(ax_top, [r.f_grid(m_dom); flipud(r.f_grid(m_dom))], ...
         [r.psd_db(m_dom); y_bot * ones(sum(m_dom), 1)], [0.90 0.25 0.35], ...
         'FaceAlpha', 0.35, 'EdgeColor', 'none', ...
         'DisplayName', sprintf('Dominant [%0.1f-%0.1f Hz | %0.1f%%]', dom.f_start, dom.f_end, dom.pct_energy));

    % Traces
    plot(ax_top, r.f_grid, r.psd_db, 'Color', [0.20 0.82 1.00], 'LineWidth', 1.2, 'DisplayName', 'Welch PSD (50 ms)');
    plot(ax_top, r.f_grid, r.b_med,  'Color', [0.85 0.38 1.00], 'LineWidth', 1.1, 'LineStyle', '--', 'DisplayName', 'Moving Median');
    plot(ax_top, r.f_grid, r.b_tpsw, 'Color', [0.95 0.78 0.20], 'LineWidth', 1.2, 'LineStyle', '-.', 'DisplayName', 'TPSW Baseline');
    plot(ax_top, r.f_grid, r.ocean_floor, 'Color', [0.50 0.55 0.65], 'LineWidth', 1.2, 'LineStyle', ':', ...
         'DisplayName', sprintf('Ambient Baseline (%0.1f dB)', r.ocean_amb_db));

    xlim(ax_top, [r.meta.f_low, r.meta.f_high]);
    legend(ax_top, 'Location', 'northeast', 'TextColor', [0.92 0.94 0.97], 'Color', [0.08 0.10 0.15], 'FontSize', 7.5);

    % Bottom: Whitened CFAR Deflection
    ax_bot = subplot(2, N, k + N);
    apply_plot_style(ax_bot, 'Equalized Spectrum & CFAR Line Extraction', 'Frequency (Hz)', 'Deflection (dB)');

    pos_def = max(r.d_tpsw, 0);
    fill(ax_bot, [r.f_grid; flipud(r.f_grid)], [pos_def; zeros(size(pos_def))], ...
         [0.95 0.78 0.20], 'FaceAlpha', 0.25, 'EdgeColor', 'none', 'HandleVisibility', 'off');
    plot(ax_bot, r.f_grid, r.d_tpsw, 'Color', [0.95 0.78 0.20], 'LineWidth', 1.1, 'DisplayName', '\Delta_{TPSW}');
    yline(ax_bot, cfg.tpsw_thresh_db, 'Color', [1.0 0.35 0.40], 'LineStyle', ':', 'LineWidth', 1.2, ...
          'DisplayName', sprintf('CFAR Threshold (+%0.1f dB)', cfg.tpsw_thresh_db));

    if ~isempty(r.idx_tonals)
        scatter(ax_bot, r.f_grid(r.idx_tonals), r.d_tpsw(r.idx_tonals), 36, ...
                [0.25 0.92 0.60], 'filled', '^', 'DisplayName', sprintf('Tonals (N = %d)', length(r.idx_tonals)));
    end
    xlim(ax_bot, [r.meta.f_low, r.meta.f_high]);
    legend(ax_bot, 'Location', 'northeast', 'TextColor', [0.92 0.94 0.97], 'Color', [0.08 0.10 0.15], 'FontSize', 8);
end


end

function render_fig2_lobe_profile(results)
figure('Name', 'Figure 2: Dominant Peak Bandwidth via 20% Prominence Lobe Profile', ...
'Color', [0.07 0.09 0.13], 'Position', [60, 80, 1500, 580]);
N = length(results);

for k = 1:N
    r = results{k};
    b = r.lobe_bw;
    ax = subplot(1, N, k);

    title_str = sprintf('%s\nPeak = %0.1f Hz | Sub-Bin 20%% Prominence BW = %0.2f Hz', ...
                        r.meta.name, b.dom_freq, b.bandwidth);
    apply_plot_style(ax, title_str, 'Frequency (Hz)', 'Magnitude (dB)');

    if b.found
        plot(ax, b.f_segment, b.fft_segment, 'Color', [0.60 0.65 0.75], 'LineWidth', 1.1, 'DisplayName', 'Signal FFT (0.50 s Hann)');
        plot(ax, b.f_segment, b.lobe_shape,   'Color', [0.20 0.85 1.00], 'LineWidth', 2.0, 'DisplayName', 'Acoustic Lobe Contour');
        plot(ax, b.f_segment, b.noise_floor,  'Color', [1.00 0.78 0.25], 'LineWidth', 1.5, 'LineStyle', ':', 'DisplayName', 'Noise Floor Baseline');
        plot(ax, b.f_segment, b.thresh_contour, 'Color', [1.00 0.38 0.75], 'LineWidth', 1.6, 'LineStyle', '--', 'DisplayName', '20% Prominence Contour');

        % Fill bandwidth area
        m_bw = (b.f_segment >= b.l_freq) & (b.f_segment <= b.r_freq);
        if any(m_bw)
            f_fill = [b.l_freq; b.f_segment(m_bw); b.r_freq];
            y_fill = [b.l_amp; b.lobe_shape(m_bw); b.r_amp];
            fill(ax, [f_fill; flipud(f_fill)], [y_fill; b.l_amp * ones(size(f_fill))], ...
                 [0.20 0.85 1.00], 'FaceAlpha', 0.15, 'EdgeColor', 'none', 'HandleVisibility', 'off');
        end

        % Exact Sub-Bin Markers
        plot(ax, [b.l_freq, b.r_freq], [b.l_amp, b.r_amp], 'ro', ...
             'MarkerFaceColor', [1.00 0.20 0.30], 'MarkerSize', 8.5, 'LineWidth', 1.5, ...
             'DisplayName', sprintf('Sub-Bin Limits (BW = %0.2f Hz)', b.bandwidth));
        xline(ax, b.dom_freq, 'Color', [0.20 0.90 0.55], 'LineWidth', 1.5, 'LineStyle', '-.', ...
              'DisplayName', sprintf('Peak: %0.1f Hz', b.dom_freq));

        legend(ax, 'Location', 'northeast', 'TextColor', [0.92 0.94 0.97], 'Color', [0.08 0.10 0.15], 'FontSize', 8);
    end
end


end

function render_fig3_spectrograms(results)
figure('Name', 'Figure 3: 2D Time-Frequency Spectrograms with Dominant Lobe Boundaries', ...
'Color', [0.07 0.09 0.13], 'Position', [90, 120, 1500, 600]);
N = length(results);

for k = 1:N
    r = results{k};
    ax = subplot(1, N, k);
    apply_plot_style(ax, sprintf('%s: Spectrogram [%d-%d Hz]', r.meta.name, r.meta.f_low, r.meta.f_high), ...
                     'Time (s)', 'Frequency (kHz)');

    imagesc(ax, r.t_spec, r.f_spec / 1000, r.p_spec_db);
    set(ax, 'YDir', 'normal');
    colormap(ax, 'turbo');

    c_lo = prctile(r.p_spec_db(:), 10);
    c_hi = prctile(r.p_spec_db(:), 99.7);
    if c_hi <= c_lo, c_hi = c_lo + 25; end
    caxis(ax, [c_lo, c_hi]);

    cb = colorbar(ax);
    cb.Color = [0.92 0.94 0.97];
    ylabel(cb, 'PSD (dB/Hz)', 'Color', [0.92 0.94 0.97], 'FontSize', 9);

    % Overlay dominant lobe frequency bounds
    yline(ax, r.dom_lobe.f_start / 1000, 'Color', 'w', 'LineStyle', '--', 'LineWidth', 1.4);
    yline(ax, r.dom_lobe.f_end   / 1000, 'Color', 'w', 'LineStyle', '--', 'LineWidth', 1.4);
end


end

function render_fig4_fairness_and_histograms(results, cfg)
figure('Name', 'Figure 4: Temporal Bandwidth Tracking, Rolling Fairness & Distributions', ...
'Color', [0.07 0.09 0.13], 'Position', [120, 100, 1550, 880]);

c_d1 = [0.20 0.70 1.00];  % Motorboat (Cyan)
c_d2 = [1.00 0.42 0.35];  % Croatia (Coral)
r1 = results{1}; r2 = results{2};
m1 = r1.temporal; m2 = r2.temporal;

% 1. Top-Left: Bandwidth Tracking Over Time
ax1 = subplot(2, 2, 1);
apply_plot_style(ax1, 'Temporal Dominant Peak Bandwidth Tracking', 'Time (s)', 'Bandwidth (Hz)');
plot(ax1, m1.t_slices, m1.bw_tracked, '-o', 'Color', c_d1, 'LineWidth', 1.5, 'MarkerSize', 4, ...
     'MarkerFaceColor', c_d1, 'DisplayName', sprintf('%s (Mean: %0.2f Hz)', r1.meta.name, m1.mean_bw));
plot(ax1, m2.t_slices, m2.bw_tracked, '-s', 'Color', c_d2, 'LineWidth', 1.5, 'MarkerSize', 4, ...
     'MarkerFaceColor', c_d2, 'DisplayName', sprintf('%s (Mean: %0.2f Hz)', r2.meta.name, m2.mean_bw));
yline(ax1, m1.mean_bw, 'Color', c_d1, 'LineStyle', ':', 'LineWidth', 1.2, 'HandleVisibility', 'off');
yline(ax1, m2.mean_bw, 'Color', c_d2, 'LineStyle', ':', 'LineWidth', 1.2, 'HandleVisibility', 'off');
legend(ax1, 'Location', 'best', 'TextColor', [0.92 0.94 0.97], 'Color', [0.08 0.10 0.15], 'FontSize', 8);

% 2. Top-Right: Comparative Bandwidth KDE Distributions
ax2 = subplot(2, 2, 2);
apply_plot_style(ax2, 'Comparative Bandwidth Distribution (KDE)', 'Bandwidth (Hz)', 'Probability Density');
plot_kde(ax2, m1.bw_tracked, r1.meta.name, cfg.kde_bw, c_d1);
plot_kde(ax2, m2.bw_tracked, r2.meta.name, cfg.kde_bw, c_d2);
legend(ax2, 'Location', 'best', 'TextColor', [0.92 0.94 0.97], 'Color', [0.08 0.10 0.15], 'FontSize', 8);

% 3. Bottom-Left: Rolling Jain's Fairness Index Over Time
ax3 = subplot(2, 2, 3);
apply_plot_style(ax3, sprintf('Rolling Jain''s Fairness Index (Window = %d Slices)', cfg.fairness_win), ...
                 'Time (s)', 'Jain''s Fairness Index');
plot(ax3, m1.t_fairness, m1.rolling_fairness, '-o', 'Color', c_d1, 'LineWidth', 1.5, 'MarkerSize', 4, ...
     'MarkerFaceColor', c_d1, 'DisplayName', sprintf('%s (Mean J: %0.3f)', r1.meta.name, m1.mean_fairness));
plot(ax3, m2.t_fairness, m2.rolling_fairness, '-s', 'Color', c_d2, 'LineWidth', 1.5, 'MarkerSize', 4, ...
     'MarkerFaceColor', c_d2, 'DisplayName', sprintf('%s (Mean J: %0.3f)', r2.meta.name, m2.mean_fairness));
yline(ax3, 1.0, 'Color', [0.20 0.90 0.55], 'LineStyle', '--', 'LineWidth', 1.2, 'DisplayName', 'Ideal Uniformity (J = 1.00)');
ylim(ax3, [min(0.5, min([m1.rolling_fairness; m2.rolling_fairness]) - 0.05), 1.05]);
legend(ax3, 'Location', 'southwest', 'TextColor', [0.92 0.94 0.97], 'Color', [0.08 0.10 0.15], 'FontSize', 8);

% 4. Bottom-Right: Comparative Fairness KDE Distributions
ax4 = subplot(2, 2, 4);
apply_plot_style(ax4, 'Comparative Fairness Distribution (KDE)', 'Jain''s Fairness Index', 'Probability Density');
plot_kde(ax4, m1.rolling_fairness, r1.meta.name, cfg.kde_fairness, c_d1);
plot_kde(ax4, m2.rolling_fairness, r2.meta.name, cfg.kde_fairness, c_d2);
legend(ax4, 'Location', 'best', 'TextColor', [0.92 0.94 0.97], 'Color', [0.08 0.10 0.15], 'FontSize', 8);


end

function plot_kde(ax, data, label_str, kde_bw, color_vec)
valid = data(~isnan(data) & (data > 0));
if length(valid) >= 3
[f, xi] = ksdensity(valid, 'Bandwidth', kde_bw);
fill(ax, [xi, fliplr(xi)], [f, zeros(size(f))], color_vec, ...
'FaceAlpha', 0.35, 'EdgeColor', color_vec, 'LineWidth', 1.8, ...
'DisplayName', sprintf('%s (KDE)', label_str));
end
end

% =========================================================================
% 8. SUMMARY REPORTING
% =========================================================================
function print_summary(results)
fprintf('\n============================================================\n');
fprintf('ACOUSTIC LOBE, BANDWIDTH & FAIRNESS ANALYSIS SUMMARY\n');
fprintf('============================================================\n');

for k = 1:length(results)
    r = results{k};
    fprintf('\n------------------------------------------------------------\n');
    fprintf('  %s\n', r.meta.name);
    fprintf('  Passband:                   %d - %d Hz\n', r.meta.f_low, r.meta.f_high);
    fprintf('  Ambient Ocean Noise Floor:  %0.1f dB/Hz\n', r.ocean_amb_db);
    fprintf('  Detected Macro-Lobes:       %d partitioned regions\n', length(r.macro_lobes));

    dom = r.dom_lobe;
    fprintf('  Dominant Energetic Lobe:    [%0.1f - %0.1f Hz] (BW: %0.1f Hz)\n', ...
            dom.f_start, dom.f_end, dom.bandwidth);
    fprintf('    Summit Peak:              %0.2f dB/Hz @ %0.1f Hz\n', dom.peak_psd, dom.peak_freq);
    fprintf('    Energy Fraction:          %0.2f%% OF TOTAL BAND POWER\n', dom.pct_energy);

    b = r.lobe_bw;
    if b.found
        fprintf('  Dominant Peak Bandwidth:    %0.2f Hz (Bounds: %0.2f - %0.2f Hz)\n', ...
                b.bandwidth, b.l_freq, b.r_freq);
    end

    t = r.temporal;
    if ~isnan(t.mean_bw)
        fprintf('  Temporal Slices (0.50 s):   Mean BW: %0.2f Hz | Std: %0.2f Hz | Mean J: %0.4f\n', ...
                t.mean_bw, t.std_bw, t.mean_fairness);
    end
end
fprintf('\n============================================================\n\n');


end