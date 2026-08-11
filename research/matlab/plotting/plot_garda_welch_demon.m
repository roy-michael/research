% plot_garda_welch_demon.m
% Computes and compares Welch PSD and DEMON spectra for the Garda datasets
% (Petrol Deep/Shallow, Electric Deep/Shallow), highlighting the main signals
% and their bandwidths, and exporting the data to JSON.
% Uses the optimized smaller NFFT for variance reduction.

% Resolve output directory robustly
script_dir = fileparts(mfilename('fullpath'));
output_dir = fullfile(script_dir, '..', '..', 'output', 'garda');

DATASETS = {
    'D:\RoyStudies\Recordings\Garda_2_26\2_Deep Water\Petrol', 'Petrol_Deep_Water';
    'D:\RoyStudies\Recordings\Garda_2_26\1_Shallow Water\Petrol', 'Petrol_Shallow_Water';
    'D:\RoyStudies\Recordings\Garda_2_26\2_Deep Water\Electric', 'Electric_Deep_Water';
    'D:\RoyStudies\Recordings\Garda_2_26\1_Shallow Water\Electric', 'Electric_Shallow_Water'
};

% Calibration factor (conversion to micro-Pascals)
calibFactor = 1e6;

% Storage for plotting and export
welch_results = struct();
demon_results = struct();

for d = 1:size(DATASETS, 1)
    DIR_PATH = DATASETS{d, 1};
    DATASET_NAME = DATASETS{d, 2};
    clean_name = regexprep(DATASET_NAME, '[^\w]', '_');
    
    fprintf('Processing %s...\n', DATASET_NAME);
    files = dir(fullfile(DIR_PATH, '*.wav'));
    if isempty(files)
        warning('No WAV files found in %s. Skipping.', DIR_PATH);
        continue;
    end
    
    % Sort and pick the first WAV file as a representative sample
    [~, sortIdx] = sort({files.name});
    files = files(sortIdx);
    first_file = fullfile(files(1).folder, files(1).name);
    fprintf('  Reading representative file: %s\n', files(1).name);
    
    % Load audio data (mono)
    [y, fs] = audioread(first_file);
    if size(y, 2) > 1
        y = mean(y, 2);
    end
    
    % Apply calibration
    y_cal = y * calibFactor;
    
    % -------------------------------------------------------------
    % 1. Welch PSD Analysis
    % -------------------------------------------------------------
    fprintf('  Computing Welch PSD...\n');
    windowLength = 32768; % ~0.25 second window for variance reduction (smoothing)
    noverlap = windowLength / 2;
    [psd_est, freq_psd] = pwelch(y_cal, windowLength, noverlap, windowLength, fs, 'power');
    psd_db = 10 * log10(psd_est);
    
    % Save Welch results
    idx_4k = (freq_psd <= 4000);
    welch_results.(clean_name).freq = freq_psd(idx_4k);
    welch_results.(clean_name).psd = psd_db(idx_4k);
    
    % -------------------------------------------------------------
    % 2. DEMON Analysis (Detection of Envelope Modulation on Noise)
    % -------------------------------------------------------------
    fprintf('  Performing DEMON Analysis...\n');
    % Bandpass filter to capture high-frequency modulation (e.g., cavitation band 15-45 kHz)
    f_low = 15000;
    f_high = 45000;
    nyquist = fs / 2;
    if f_high >= nyquist
        f_high = 0.9 * nyquist;
    end
    
    [b_bp, a_bp] = butter(4, [f_low f_high] / nyquist, 'bandpass');
    y_bp = filtfilt(b_bp, a_bp, y_cal);
    
    % Full-wave rectification (envelope detection)
    y_env = abs(y_bp);
    
    % Low-pass filter envelope at 3800 Hz before downsampling to avoid aliasing
    f_lp_cutoff = 3800;
    [b_lp, a_lp] = butter(4, f_lp_cutoff / nyquist, 'low');
    y_env_lp = filtfilt(b_lp, a_lp, y_env);
    
    % Downsample envelope to fs_env = 8000 Hz
    ds_factor = 16; % 128000 Hz / 16 = 8000 Hz
    y_env_ds = y_env_lp(1:ds_factor:end);
    fs_env = fs / ds_factor;
    
    % Remove DC component (mean)
    y_env_ds = y_env_ds - mean(y_env_ds);
    
    % Compute PSD of the envelope (DEMON spectrum)
    windowLength_env = 2048; % ~0.25 second window for variance reduction (smoothing)
    noverlap_env = windowLength_env / 2;
    [psd_env, freq_env] = pwelch(y_env_ds, windowLength_env, noverlap_env, windowLength_env, fs_env, 'power');
    psd_env_db = 10 * log10(psd_env);
    
    % Save DEMON results
    idx_env_4k = (freq_env <= 4000);
    demon_results.(clean_name).freq = freq_env(idx_env_4k);
    demon_results.(clean_name).psd = psd_env_db(idx_env_4k);
end

% Detect and compute peak metadata for JSON export
fields = fieldnames(welch_results);
peak_metadata = struct();

for i = 1:length(fields)
    fn = fields{i};
    
    % Welch Peaks
    f_w = welch_results.(fn).freq;
    psd_w = welch_results.(fn).psd;
    [pks, locs] = findpeaks(psd_w, f_w, 'MinPeakProminence', 5, 'SortStr', 'descend');
    num_peaks = min(3, length(pks));
    welch_peaks = [];
    for p = 1:num_peaks
        fp = locs(p);
        val_p = pks(p);
        [~, p_idx] = min(abs(f_w - fp));
        l_idx = p_idx;
        while l_idx > 1 && psd_w(l_idx) > (val_p - 3), l_idx = l_idx - 1; end
        r_idx = p_idx;
        while r_idx < length(f_w) && psd_w(r_idx) > (val_p - 3), r_idx = r_idx + 1; end
        
        welch_peaks = [welch_peaks; struct('freq', fp, 'psd', val_p, 'bw_low', f_w(l_idx), 'bw_high', f_w(r_idx))];
    end
    peak_metadata.(fn).welch_peaks = welch_peaks;
    
    % DEMON Peaks
    f_d = demon_results.(fn).freq;
    psd_d = demon_results.(fn).psd;
    [pks_d, locs_d] = findpeaks(psd_d, f_d, 'MinPeakProminence', 4, 'SortStr', 'descend');
    num_peaks_d = min(4, length(pks_d));
    demon_peaks = [];
    for p = 1:num_peaks_d
        fp = locs_d(p);
        val_p = pks_d(p);
        [~, p_idx] = min(abs(f_d - fp));
        l_idx = p_idx;
        while l_idx > 1 && psd_d(l_idx) > (val_p - 3), l_idx = l_idx - 1; end
        r_idx = p_idx;
        while r_idx < length(f_d) && psd_d(r_idx) > (val_p - 3), r_idx = r_idx + 1; end
        
        demon_peaks = [demon_peaks; struct('freq', fp, 'psd', val_p, 'bw_low', f_d(l_idx), 'bw_high', f_d(r_idx))];
    end
    peak_metadata.(fn).demon_peaks = demon_peaks;
end

% Export to JSON in output folder
export_data = struct('welch', welch_results, 'demon', demon_results, 'peaks', peak_metadata);
json_str = jsonencode(export_data);
fid = fopen(fullfile(output_dir, 'garda_spectral_data.json'), 'w');
fprintf(fid, '%s', json_str);
fclose(fid);
fprintf('Saved garda_spectral_data.json to output directory\n');

% -------------------------------------------------------------
% 3. Plotting and Highlight of Main Signals (Static Backup)
% -------------------------------------------------------------
colors = [
    0.8500 0.3250 0.0980; % Orange-red (Petrol Deep)
    0.9290 0.6940 0.1250; % Yellow-orange (Petrol Shallow)
    0.0000 0.4470 0.7410; % Blue (Electric Deep)
    0.3010 0.7450 0.9330  % Light Blue (Electric Shallow)
];

% --- Figure 1: Welch PSD ---
fig_welch = figure('Name', 'Garda Welch PSD (Signals Highlighted)', 'Position', [100, 100, 1200, 700], 'Visible', 'off');
ax_welch = axes(fig_welch);
hold(ax_welch, 'on');

for i = 1:length(fields)
    fn = fields{i};
    f = welch_results.(fn).freq / 1000; % to kHz
    psd = welch_results.(fn).psd;
    col = colors(mod(i-1, 4)+1, :);
    displayName = strrep(fn, '_', ' ');
    
    % Plot raw
    plot(ax_welch, f, psd, 'Color', [col, 0.15], 'LineWidth', 0.8, 'HandleVisibility', 'off');
    
    % Highlight peaks
    w_peaks = peak_metadata.(fn).welch_peaks;
    for p = 1:length(w_peaks)
        fp = w_peaks(p).freq / 1000;
        val_p = w_peaks(p).psd;
        bw_l = w_peaks(p).bw_low / 1000;
        bw_h = w_peaks(p).bw_high / 1000;
        
        [~, l_idx] = min(abs(f - bw_l));
        [~, r_idx] = min(abs(f - bw_h));
        
        h_seg = plot(ax_welch, f(l_idx:r_idx), psd(l_idx:r_idx), 'Color', col, 'LineWidth', 2.5);
        if p == 1
            set(h_seg, 'DisplayName', displayName);
        else
            set(h_seg, 'HandleVisibility', 'off');
        end
        plot(ax_welch, fp, val_p, '^', 'Color', col, 'MarkerFaceColor', col, 'MarkerSize', 8, 'HandleVisibility', 'off');
    end
end

xlabel(ax_welch, 'Frequency [kHz]');
ylabel(ax_welch, 'PSD [dB re 1 \muPa^2/Hz]');
title(ax_welch, 'Garda Welch PSD: Highlighted Signals & Bandwidths (0-4 kHz)');
grid(ax_welch, 'on');
xlim(ax_welch, [0, 4]);
legend(ax_welch, 'Location', 'northeast');
hold(ax_welch, 'off');
saveas(fig_welch, fullfile(output_dir, 'garda_welch_plot.png'));

% --- Figure 2: DEMON ---
fig_demon = figure('Name', 'Garda DEMON (Signals Highlighted)', 'Position', [100, 100, 1200, 700], 'Visible', 'off');
ax_demon = axes(fig_demon);
hold(ax_demon, 'on');

for i = 1:length(fields)
    fn = fields{i};
    f = demon_results.(fn).freq;
    psd = demon_results.(fn).psd;
    col = colors(mod(i-1, 4)+1, :);
    displayName = strrep(fn, '_', ' ');
    
    % Plot raw
    plot(ax_demon, f, psd, 'Color', [col, 0.15], 'LineWidth', 0.8, 'HandleVisibility', 'off');
    
    % Highlight peaks
    d_peaks = peak_metadata.(fn).demon_peaks;
    for p = 1:length(d_peaks)
        fp = d_peaks(p).freq;
        val_p = d_peaks(p).psd;
        bw_l = d_peaks(p).bw_low;
        bw_h = d_peaks(p).bw_high;
        
        [~, l_idx] = min(abs(f - bw_l));
        [~, r_idx] = min(abs(f - bw_h));
        
        h_seg = plot(ax_demon, f(l_idx:r_idx), psd(l_idx:r_idx), 'Color', col, 'LineWidth', 2.5);
        if p == 1
            set(h_seg, 'DisplayName', displayName);
        else
            set(h_seg, 'HandleVisibility', 'off');
        end
        plot(ax_demon, fp, val_p, 'o', 'Color', col, 'MarkerFaceColor', col, 'MarkerSize', 6, 'HandleVisibility', 'off');
    end
end

xlabel(ax_demon, 'Modulation Frequency [Hz]');
ylabel(ax_demon, 'DEMON PSD [dB re 1 \muPa^2/Hz]');
title(ax_demon, 'Garda DEMON Spectrum: Highlighted Signals & Bandwidths (0-4 kHz)');
grid(ax_demon, 'on');
xlim(ax_demon, [0, 4000]);
legend(ax_demon, 'Location', 'northeast');
hold(ax_demon, 'off');
saveas(fig_demon, fullfile(output_dir, 'garda_demon_plot.png'));

fprintf('Garda analysis and exports finished successfully!\n');
close(fig_welch);
close(fig_demon);
