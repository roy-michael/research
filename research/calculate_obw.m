% calculate_obw_fix.m
% Optimized to process large files using native sampling rate (128kHz) 
% and internal spectral estimation to avoid memory crashes.

DATASETS = {
    'C:\Users\Roy\Recordings\Garda_2_26\2_Deep Water\Petrol', 'Petrol (Deep Water)';
    'C:\Users\Roy\Recordings\Garda_2_26\1_Shallow Water\Petrol', 'Petrol (Shallow Water)';
    'C:\Users\Roy\Recordings\Garda_2_26\2_Deep Water\Electric', 'Electric (Deep Water)';
    'C:\Users\Roy\Recordings\Garda_2_26\1_Shallow Water\Electric', 'Electric (Shallow Water)'
};

results = [];

for d = 1:size(DATASETS, 1)
    DIR_PATH = DATASETS{d, 1};
    DATASET_NAME = DATASETS{d, 2};
    
    fprintf('\nProcessing: %s\n', DATASET_NAME);
    files = dir(fullfile(DIR_PATH, '*.wav'));
    
    if isempty(files)
        fprintf('  No files found. Skipping.\n');
        continue;
    end
    
    % --- Load and Concatenate ---
    [~, fs_original] = audioread(fullfile(files(1).folder, files(1).name), [1 1]);
    
    continuous_data = [];
    for i = 1:length(files)
        [y, ~] = audioread(fullfile(files(i).folder, files(i).name));
        if size(y, 2) > 1, y = mean(y, 2); end
        continuous_data = [continuous_data; y];
    end
    
    % --- Memory-Efficient Pre-processing ---
    % Use native sampling rate directly
    target_fs = fs_original;
    clean_data = continuous_data;
    clear continuous_data; % Free memory
    
    % Apply Low-pass filter to remove electronic artifacts 
    % Target 45kHz cutoff with 128kHz sampling (Nyquist = 64kHz)
    nyquist = target_fs / 2;
    cutoff = 45000; 
    
    % Safety check: ensure cutoff is strictly within Nyquist range
    if cutoff >= nyquist
        cutoff = 0.9 * nyquist;
    end
    
    [b, a] = butter(4, cutoff / nyquist, 'low');
    clean_data = filter(b, a, clean_data);
    
    fprintf('  Calculating OBW (Occupied Bandwidth) directly at %d Hz...\n', target_fs);
    
    % Use obw directly on the signal
    [bw, flo, fhi, ~] = obw(clean_data, target_fs);
    
    fprintf('  OBW: %.2f Hz (Band: %.2f Hz to %.2f Hz)\n', bw, flo, fhi);
    results = [results; struct('Name', DATASET_NAME, 'OBW', bw, 'FLo', flo, 'FHi', fhi)];
end

fprintf('\n=======================================================\n');
fprintf('OCCUPIED BANDWIDTH (OBW) SUMMARY\n');
fprintf('=======================================================\n');
for i = 1:length(results)
    fprintf('%-25s : %8.2f Hz  [%.2f - %.2f Hz]\n', results(i).Name, results(i).OBW, results(i).FLo, results(i).FHi);
end

% Plot a bar chart comparing the OBW
if ~isempty(results)
    fig = figure('Name', 'Occupied Bandwidth Comparison', 'Position', [100, 100, 800, 600]);
    ax = axes(fig);
    b = bar(ax, [results.OBW], 'FaceColor', [0.2 0.6 0.8]);
    
    set(ax, 'xtick', 1:length(results), 'xticklabel', {results.Name});
    xtickangle(ax, 25);
    ylabel(ax, 'Occupied Bandwidth (Hz)');
    title(ax, 'Occupied Bandwidth (OBW) Comparison: Petrol vs Electric');
    grid(ax, 'on');
    
    % Add value labels on top of bars
    for i = 1:length(results)
        text(ax, i, results(i).OBW, sprintf('%.1f Hz', results(i).OBW), ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
             'FontWeight', 'bold');
    end
end +