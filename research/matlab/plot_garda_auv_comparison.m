% plot_garda_auv_comparison.m
% Computes and compares Welch PSD and DEMON spectra for the Garda Electric
% datasets and the Itamar AUV straight-line propulsion trials.
% Optimizes and highlights main signals and bandwidths, saving JSON and static plots.

% Resolve output directory relative to script folder
script_dir = fileparts(mfilename('fullpath'));
output_dir = fullfile(script_dir, '..', 'output');

DATASETS = {
    'D:\RoyStudies\Recordings\Garda_2_26\2_Deep Water\Electric', 'Garda_Electric_Deep';
    'D:\RoyStudies\Recordings\Garda_2_26\1_Shallow Water\Electric', 'Garda_Electric_Shallow';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692\leg1_straight_line_2_8m_s_6922_827-837.wav', 'AUV_Leg1_2_8mps';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692\leg2_straight_line_1_8m_s_6922_840-857.wav', 'AUV_Leg2_1_8mps';
    'D:\RoyStudies\Recordings\AUVExp_1_26\Part1_StraightLine\IcListen6692\leg3_straight_line_1_112m_s_6922_900-910.wav', 'AUV_Leg3_1_112mps'
};

% Calibration factor (conversion to micro-Pascals)
calibFactor = 1e6;

% Storage for plotting and export
welch_results = struct();
demon_results = struct();

for d = 1:size(DATASETS, 1)
    PATH_OR_DIR = DATASETS{d, 1};
    DATASET_NAME = DATASETS{d, 2};
    clean_name = regexprep(DATASET_NAME, '[^\w]', '_');
    
    fprintf('Processing %s...\n', DATASET_NAME);
    
    % Check if directory or single file
    if exist(PATH_OR_DIR, 'dir')
        files = dir(fullfile(PATH_OR_DIR, '*.wav'));
        if isempty(files)
            warning('No WAV files found in %s. Skipping.', PATH_OR_DIR);
            continue;
        end
        [~, sortIdx] = sort({files.name});
        files = files(sortIdx);
        target_file = fullfile(files(1).folder, files(1).name);
    else
        target_file = PATH_OR_DIR;
    end
    
    fprintf('  Reading file: %s\n', target_file);
    
    % Load audio data (mono)
    [y, fs] = audioread(target_file);
    if size(y, 2) > 1
        y = mean(y, 2);
    end
    
    % Apply calibration
    y_cal = y * calibFactor;
    
    % -------------------------------------------------------------
    % 1. Welch PSD Analysis
    % -------------------------------------------------------------
    fprintf('  Computing Welch PSD...\n');
    windowLength = 32768; % Smooth curves
    noverlap = windowLength / 2;
    [psd_est, freq_psd] = pwelch(y_cal, windowLength, noverlap, windowLength, fs, 'power');
    psd_db = 10 * log10(psd_est);
    
    % Save Welch results
    idx_4k = (freq_psd <= 4000);
    welch_results.(clean_name).freq = freq_psd(idx_4k);
    welch_results.(clean_name).psd = psd_db(idx_4k);
    
    % -------------------------------------------------------------
    % 2. DEMON Analysis (Envelope Modulation on Noise)
    % -------------------------------------------------------------
    fprintf('  Performing DEMON Analysis...\n');
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
    ds_factor = round(fs / 8000);
    y_env_ds = y_env_lp(1:ds_factor:end);
    fs_env = fs / ds_factor;
    
    % Remove DC component (mean)
    y_env_ds = y_env_ds - mean(y_env_ds);
    
    % Compute PSD of the envelope (DEMON spectrum)
    windowLength_env = 2048; % Smooth curves
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
fid = fopen(fullfile(output_dir, 'garda_auv_spectral_data.json'), 'w');
fprintf(fid, '%s', json_str);
fclose(fid);
fprintf('Saved garda_auv_spectral_data.json to output directory\n');

% -------------------------------------------------------------
% 3. Plotting and Highlight of Main Signals (Static Backup)
% -------------------------------------------------------------
colors = [
    0.0000 0.4470 0.7410; % Blue (Electric Deep)
    0.3010 0.7450 0.9330; % Light Blue (Electric Shallow)
    0.8500 0.3250 0.0980; % Orange (AUV Leg 1 @2.8)
    0.9290 0.6940 0.1250; % Yellow-orange (AUV Leg 2 @1.8)
    0.4940 0.1840 0.5560  % Purple (AUV Leg 3 @1.112)
];

% --- Figure 1: Welch PSD ---
fig_welch = figure('Name', 'Garda Electric & AUV Welch PSD', 'Position', [100, 100, 1200, 700], 'Visible', 'off');
ax_welch = axes(fig_welch);
hold(ax_welch, 'on');

for i = 1:length(fields)
    fn = fields{i};
    f = welch_results.(fn).freq / 1000; % to kHz
    psd = welch_results.(fn).psd;
    col = colors(mod(i-1, 5)+1, :);
    displayName = strrep(fn, '_', ' ');
    
    % Plot raw (noise background)
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
title(ax_welch, 'Garda Electric & AUV Welch PSD: Highlighted Signals & Bandwidths (0-4 kHz)');
grid(ax_welch, 'on');
xlim(ax_welch, [0, 4]);
legend(ax_welch, 'Location', 'northeast');
hold(ax_welch, 'off');
saveas(fig_welch, fullfile(output_dir, 'garda_auv_welch_plot.png'));

% --- Figure 2: DEMON ---
fig_demon = figure('Name', 'Garda Electric & AUV DEMON', 'Position', [100, 100, 1200, 700], 'Visible', 'off');
ax_demon = axes(fig_demon);
hold(ax_demon, 'on');

for i = 1:length(fields)
    fn = fields{i};
    f = demon_results.(fn).freq;
    psd = demon_results.(fn).psd;
    col = colors(mod(i-1, 5)+1, :);
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
title(ax_demon, 'Garda Electric & AUV DEMON Spectrum: Highlighted Signals & Bandwidths (0-4 kHz)');
grid(ax_demon, 'on');
xlim(ax_demon, [0, 4000]);
legend(ax_demon, 'Location', 'northeast');
hold(ax_demon, 'off');
saveas(fig_demon, fullfile(output_dir, 'garda_auv_demon_plot.png'));

fprintf('Garda Electric & AUV comparison analysis finished successfully!\n');
close(fig_welch);
close(fig_demon);
