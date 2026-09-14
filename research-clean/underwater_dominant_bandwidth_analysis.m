%% UNDERWATER DOMINANT-BANDWIDTH ANALYZER
% Surface-source model: FM from heave + AM-like multipath fading.
% Pipeline:
% 1) Read real WAV files when available; otherwise synthesize a test signal.
% 2) Segment into 1-s buffers.
% 3) Estimate PSD and a robust noise baseline.
% 4) Detect broad spectral lobes and internal narrow peaks.
% 5) Estimate lobe bandwidth using a noise-relative threshold.
% 6) Estimate Hilbert-envelope fading and modulation spectra.
% 7) Aggregate bandwidth estimates robustly across buffers.
%
% The attached report defines the physical model and the 1-s buffering idea.
% The attached target-size paper motivates Hilbert-envelope processing, but
% this script applies it to band-limited received signals rather than echo
% width in a time-distance matrix.
%
% Required MATLAB toolboxes: Signal Processing Toolbox.

clear; close all; clc;
rng(7);

cfg = default_config();

% Edit these paths. If a path is empty or does not exist, the script uses a
% synthetic signal that demonstrates heave FM sidebands and surface fading.
% --- 1. Load Audio Files ---
base_dir = 'D:\RoyStudies\Recordings';
dir_hear_my_ship = fullfile(base_dir, 'hear_my_ship', 'V1', 'Motor Boats');
dir_croatia      = fullfile(base_dir, 'Croatia', 'Ocean Sonics', '2407_1_600m');
cfg.files = { ...
    fullfile(dir_hear_my_ship, "Motorboat_08.08.23_142223_20secCPA.wav"),
    fullfile(dir_croatia, "RBW6737_20250724_093000.wav")
    };
cfg.labels = {'Surface-source example', 'Underwater-source example'};

for d = 1:numel(cfg.files)
    fprintf('\n============================================================\n');
    fprintf('%s\n', cfg.labels{d});
    fprintf('============================================================\n');

    [x, fs, source_name] = load_or_synthesize(cfg.files{d}, cfg, d);
    x = condition_signal(x, fs, cfg);

    result = analyze_recording(x, fs, cfg, source_name);
    print_result(result);
    make_figures(result, cfg);
end

%% Configuration
function cfg = default_config()
cfg = struct();
cfg.duration_s = 20;
cfg.buffer_s = 0.25;
cfg.buffer_overlap = 0.250;
cfg.f_low = 20;
cfg.f_high = 1200;
cfg.nfft = 16384;
cfg.psd_window_s = 0.25;
cfg.psd_overlap = 0.75;
cfg.broad_smooth_hz = 15;
cfg.narrow_smooth_hz = 2;
cfg.noise_smooth_hz = 100;
cfg.noise_percentile = 25;
cfg.activity_threshold_db = 6;
cfg.lobe_edge_threshold_db = 6;
cfg.min_lobe_bw_hz = 10;
cfg.min_lobe_prominence_db = 6;
cfg.min_lobe_energy_fraction = 0.01;
cfg.peak_prominence_db = 3;
cfg.peak_min_distance_hz = 8;
cfg.envelope_smooth_s = 0.02;
cfg.modulation_high_hz = 100;
cfg.plot_max_buffers = 20;
end

%% Input and conditioning
function [x, fs, source_name] = load_or_synthesize(file_name, cfg, dataset_index)
if ~isempty(file_name) && isfile(file_name)
    info = audioinfo(file_name);
    fs_file = info.SampleRate;
    nread = min(info.TotalSamples, round(cfg.duration_s * fs_file));
    [x, ~] = audioread(file_name, [1 nread]);
    if size(x,2) > 1
        x = mean(x,2);
    end
    fs = fs_file;
    source_name = file_name;
    return;
end

fs = 16000;
t = (0:1/fs:cfg.duration_s-1/fs).';
if dataset_index == 1
    % Surface-source demonstration:
    % carrier f0, heave frequency fw, phase/FM modulation, and fading.
    f0 = 1200;
    fw = 2.5;
    beta = 2.2;
    env = 1 + 0.55*cos(2*pi*fw*t + 0.3*sin(2*pi*0.35*t));
    phase = 2*pi*f0*t + beta*sin(2*pi*fw*t);
    x = 0.5*env.*cos(phase);
    x = x + 0.12*cos(2*pi*(f0+85)*t);
    x = x + 0.06*randn(size(t));
    source_name = 'synthetic surface source';
else
    % Underwater-source demonstration:
    % relatively stable source tone plus delayed/low-level echo and noise.
    f0 = 1200;
    x = 0.55*cos(2*pi*f0*t);
    delay = round(0.11*fs);
    echo = zeros(size(x));
    echo(delay+1:end) = 0.16*cos(2*pi*f0*t(1:end-delay));
    x = x + echo + 0.06*randn(size(t));
    source_name = 'synthetic underwater source';
end
end

function x = condition_signal(x, fs, cfg)
x = x(:);
x = x - mean(x,'omitnan');
if numel(x) > round(cfg.duration_s*fs)
    x = x(1:round(cfg.duration_s*fs));
end
[b,a] = butter(4, max(1,cfg.f_low)/(fs/2), 'high');
x = filtfilt(b,a,x);
x = x ./ max(rms(x), eps);
end

%% Main analysis
function result = analyze_recording(x, fs, cfg, source_name)
Nbuf = floor((numel(x)-round(cfg.buffer_s*fs)) / ...
    (round(cfg.buffer_s*fs)*(1-cfg.buffer_overlap))) + 1;
Nbuf = max(1,Nbuf);

buffer_len = round(cfg.buffer_s*fs);
hop = max(1,round(buffer_len*(1-cfg.buffer_overlap)));

% Frequency vector from Welch PSD.
nwelch = min(round(cfg.psd_window_s*fs), buffer_len);
nwelch = 2^nextpow2(max(256,nwelch));
nwelch = min(nwelch, buffer_len);
noverlap = floor(cfg.psd_overlap*nwelch);
nfft = max(cfg.nfft,nwelch);

all_psd = [];
all_mod = [];
all_lobes = cell(Nbuf,1);
all_peaks = cell(Nbuf,1);
all_bw = NaN(Nbuf,1);
all_dom = NaN(Nbuf,1);
all_snr = NaN(Nbuf,1);
all_fading = NaN(Nbuf,1);

tbuf = NaN(Nbuf,1);

for b = 1:Nbuf
    i1 = 1 + (b-1)*hop;
    i2 = i1 + buffer_len - 1;
    if i2 > numel(x), break; end
    xb = x(i1:i2);
    tbuf(b) = mean([i1 i2])/fs;

    [p,f] = pwelch(xb, hamming(nwelch), noverlap, nfft, fs);
    use = f >= cfg.f_low & f <= cfg.f_high;
    f = f(use); p = p(use);
    psd_db = 10*log10(max(p,eps));

    noise_db = estimate_noise_floor(psd_db, f, cfg);
    excess_db = psd_db - noise_db;
    broad = smoothdata(excess_db,'gaussian',bins_from_hz(cfg.broad_smooth_hz,f));
    narrow = smoothdata(excess_db,'gaussian',bins_from_hz(cfg.narrow_smooth_hz,f));

    [lobes, peaks] = detect_lobes_and_peaks(f,broad,narrow,noise_db,cfg);
    all_lobes{b} = lobes;
    all_peaks{b} = peaks;

    if ~isempty(lobes)
        [~,q] = max([lobes.snr_db]);
        dom = lobes(q);
        all_bw(b) = dom.f_high-dom.f_low;
        all_dom(b) = dom.f_peak;
        all_snr(b) = dom.snr_db;

        % Hilbert envelope of the selected dominant lobe.
        A = band_envelope(xb,fs,dom.f_low,dom.f_high,cfg);
        A = A(:);
        A(~isfinite(A)) = 0;

        muA = mean(A);

        if muA > eps
            all_fading(b) = std(A)/muA;
        else
            all_fading(b) = NaN;
        end

        A = A - mean(A);

        if any(~isfinite(A)) || all(abs(A) < eps)
            continue;
        end

        nA = numel(A);
        nmod = max(4096,nA);

        [m,fm] = periodogram(A,hann(nA),nmod,fs);

        m = max(real(m(:)),0);
        fm = fm(:);

        if isempty(all_mod)
            all_mod = NaN(numel(m),Nbuf);
            mod_frequency = fm;
        elseif numel(m) ~= size(all_mod,1) || ...
                any(abs(fm-mod_frequency) > 10*eps)

            m = interp1(fm,m,mod_frequency,'linear',NaN);
        end

        all_mod(:,b) = m(:);
    end

    if isempty(all_psd)
        all_psd = NaN(numel(f),Nbuf);
    end
    all_psd(:,b) = psd_db;
end

valid = isfinite(all_bw);
result = struct();
result.source_name = source_name;
result.fs = fs;
result.f = f;
result.psd_db = all_psd;
result.t_buffer = tbuf;
result.lobes = all_lobes;
result.peaks = all_peaks;
result.bandwidth = all_bw;
result.dominant_frequency = all_dom;
result.snr_db = all_snr;
result.fading_index = all_fading;
result.valid_fraction = mean(valid);
result.robust_bandwidth_hz = median(all_bw(valid));
result.robust_frequency_hz = median(all_dom(valid));
result.robust_snr_db = median(all_snr(valid));
result.robust_fading_index = median(all_fading(valid));
result.env_frequency = [];
result.env_spectrum_db = [];

if any(valid) && ~isempty(all_mod)
    result.env_frequency = mod_frequency;
    result.env_spectrum_db = 10*log10(max(median(all_mod(:,valid),2,'omitnan'),eps));
end

if any(valid)
    % Use the median valid envelope spectrum for a modulation summary.
    env_matrix = all_mod(:,valid);
    result.env_frequency = (0:size(env_matrix,1)-1).';
    result.env_spectrum_db = 10*log10(max(median(env_matrix,2,'omitnan'),eps));
end
end

%% Noise, lobe and peak detection
function noise_db = estimate_noise_floor(psd_db, f, cfg)
% Robust frequency-dependent baseline. The low percentile suppresses peaks.
span = bins_from_hz(cfg.noise_smooth_hz,f);
raw = movmedian(psd_db, max(3,2*span+1));
noise_db = smoothdata(raw,'gaussian',max(3,span));
noise_db = noise_db - prctile(noise_db,cfg.noise_percentile) + ...
    prctile(psd_db,cfg.noise_percentile);
end

function [lobes, peaks_out] = detect_lobes_and_peaks(f,broad,narrow,noise_db,cfg)
peaks = findpeaks_safe(broad, f, cfg.min_lobe_prominence_db, ...
    cfg.min_lobe_bw_hz);
peaks_out = findpeaks_safe(narrow, f, cfg.peak_prominence_db, ...
    cfg.peak_min_distance_hz);

lobes = struct('f_low',{},'f_high',{},'f_peak',{},'energy',{},...
    'energy_fraction',{},'snr_db',{},'internal_peaks',{});
if isempty(peaks), return; end

% Bound each broad lobe at the nearest crossings of peak - edge threshold.
for k = 1:numel(peaks)
    ip = peaks(k).index;
    level = broad(ip)-cfg.lobe_edge_threshold_db;
    il = ip;
    while il > 1 && broad(il) >= level, il=il-1; end
    ir = ip;
    while ir < numel(f) && broad(ir) >= level, ir=ir+1; end
    if f(ir)-f(il) < cfg.min_lobe_bw_hz, continue; end

    local = f>=f(il) & f<=f(ir);
    pexcess = max(10.^(narrow/10)-10.^(noise_db/10),0);
    energy = trapz(f(local),pexcess(local));
    total = trapz(f,max(10.^(narrow/10)-10.^(noise_db/10),0));
    frac = energy/max(total,eps);
    if frac < cfg.min_lobe_energy_fraction, continue; end

    internal = peaks_out([peaks_out.f]>=f(il) & [peaks_out.f]<=f(ir));
    lobes(end+1) = struct( ...
        'f_low',f(il),'f_high',f(ir),'f_peak',f(ip), ...
        'energy',energy,'energy_fraction',frac, ...
        'snr_db',10*log10(max(energy,eps)/max(trapz(f(local),10.^(noise_db(local)/10)),eps)), ...
        'internal_peaks',internal); %#ok<AGROW>
end

% Merge overlapping lobes generated by nearby broad maxima.
if numel(lobes)>1
    lobes = merge_overlapping_lobes(lobes);
end
end

function out = findpeaks_safe(y,f,prominence,min_distance_hz)

if numel(y) < 3
    out = struct('f',{},'index',{},'height',{},'prominence',{});
    return;
end

y = y(:);
f = f(:);

try
    [pks,locs,~,prom] = findpeaks(y,f, ...
        'MinPeakProminence',prominence, ...
        'MinPeakDistance',min_distance_hz);
catch
    [pks,idx,~,prom] = findpeaks(y, ...
        'MinPeakProminence',prominence);
    locs = f(idx);
end

pks = pks(:);
locs = locs(:);
prom = prom(:);

n = numel(locs);

out = repmat(struct( ...
    'f',NaN, ...
    'index',NaN, ...
    'height',NaN, ...
    'prominence',NaN), n, 1);

for k = 1:n
    [~,idx] = min(abs(f-locs(k)));

    out(k).f = locs(k);
    out(k).index = idx;
    out(k).height = pks(k);
    out(k).prominence = prom(k);
end

end

function lobes = merge_overlapping_lobes(lobes)
changed = true;

while changed
    changed = false;

    for i = 1:numel(lobes)-1
        if lobes(i).f_high >= lobes(i+1).f_low
            a = lobes(i);
            b = lobes(i+1);

            if a.snr_db >= b.snr_db
                fpk = a.f_peak;
            else
                fpk = b.f_peak;
            end

            peaks_a = a.internal_peaks(:);
            peaks_b = b.internal_peaks(:);
            merged_peaks = [peaks_a; peaks_b];

            merged = struct( ...
                'f_low', min(a.f_low,b.f_low), ...
                'f_high', max(a.f_high,b.f_high), ...
                'f_peak', fpk, ...
                'energy', a.energy + b.energy, ...
                'energy_fraction', a.energy_fraction + b.energy_fraction, ...
                'snr_db', max(a.snr_db,b.snr_db), ...
                'internal_peaks', merged_peaks);

            lobes(i) = merged;
            lobes(i+1) = [];
            changed = true;
            break;
        end
    end
end
end

%% Hilbert envelope and modulation spectrum
function A = band_envelope(x,fs,f1,f2,cfg)

x = x(:);
nyq = fs/2;

f1 = max(f1,5);
f2 = min(f2,0.90*nyq);

if f2 <= f1 || numel(x) < 64
    A = abs(hilbert(x));
    return;
end

order = 2;

[b1,a1] = butter(order,f1/nyq,'high');
[b2,a2] = butter(order,f2/nyq,'low');

x1 = filtfilt(b1,a1,x);
y  = filtfilt(b2,a2,x1);

A = abs(hilbert(y));

ns = round(cfg.envelope_smooth_s*fs);
if ns > 2
    A = movmean(A,ns);
end

A(~isfinite(A)) = 0;

end

%% Figures and reporting
function make_figures(r,cfg)
valid = isfinite(r.bandwidth);
figure('Color','w','Name',r.source_name);

subplot(2,2,1);
imagesc(r.t_buffer,r.f/1000,r.psd_db); axis xy; colorbar;
xlabel('Time (s)'); ylabel('Frequency (kHz)');
title('Buffer PSD (dB/Hz)'); hold on;
plot(r.t_buffer(valid),r.dominant_frequency(valid)/1000,'w.-');

subplot(2,2,2);
plot(r.t_buffer,r.bandwidth,'o-'); hold on;
yline(r.robust_bandwidth_hz,'r--','Median');
xlabel('Time (s)'); ylabel('Dominant lobe bandwidth (Hz)');
title('Bandwidth per buffer'); grid on;

subplot(2,2,3);
plot(r.t_buffer,r.snr_db,'o-'); hold on;
yline(r.robust_snr_db,'r--','Median');
xlabel('Time (s)'); ylabel('Integrated band SNR (dB)');
title('Dominant-band SNR'); grid on;

subplot(2,2,4);
plot(r.t_buffer,r.fading_index,'o-'); hold on;
yline(r.robust_fading_index,'r--','Median');
xlabel('Time (s)'); ylabel('Envelope fading index');
title('Hilbert-envelope stability'); grid on;
end

function print_result(r)
fprintf('Input: %s\n',r.source_name);
fprintf('Valid buffers: %.1f %%\n',100*r.valid_fraction);
fprintf('Robust dominant frequency: %.2f Hz\n',r.robust_frequency_hz);
fprintf('Robust dominant lobe bandwidth: %.2f Hz\n',r.robust_bandwidth_hz);
fprintf('Robust integrated lobe SNR: %.2f dB\n',r.robust_snr_db);
fprintf('Robust envelope fading index: %.4f\n',r.robust_fading_index);
end

function n = bins_from_hz(width_hz,f)
%BINS_FROM_HZ Convert a frequency width in Hz to PSD-bin count.

f = f(:);

if numel(f) < 2 || ~isfinite(width_hz) || width_hz <= 0
    n = 1;
    return;
end

df = median(diff(f));

if ~isfinite(df) || df <= 0
    n = 1;
else
    n = max(1,round(width_hz/df));
end

end

function y = sosfiltfilt_compat(sos,g,x)
% Zero-phase filtering of a standard 6-column SOS matrix.

x = x(:);
y = x;

if size(sos,2) ~= 6
    error(['Expected a 6-column SOS matrix. Use ', ...
        '[sos,g] = butter(order,Wn,''bandpass'');']);
end

for k = 1:size(sos,1)
    b = sos(k,1:3);
    a = sos(k,4:6);

    a0 = a(1);
    b = b/a0;
    a = a/a0;

    y = filtfilt(b,a,y);
end

y = y*g;
end