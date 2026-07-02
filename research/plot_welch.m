% Set the directory path and specific file for the 2407_1 dataset
dirPath = 'C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_1_600m';
fileName = 'RBW6737_20250724_091100.wav';
fullFilePath = fullfile(dirPath, fileName);

% 1. Load the acoustic .wav recording
fprintf('Loading audio data from %s...\n', fullFilePath);
[data, fs] = audioread(fullFilePath);

% 2. Apply Hydrophone Calibration to micro-Pascals (µPa)
% 'audioread' normalizes data to the range [-1.0, 1.0].
% The Ocean Sonics icListen HF has a sensitivity of -172 dB re 1 V/µPa.
% Replace 'calibFactor' with the scalar value converting normalized units to µPa:
calibFactor = 1e6; % <-- Set your precise calibration scalar here
data_uPa = data * calibFactor;

% Check sampling rate dynamically
fs_expected = 128000;
if fs ~= fs_expected
    warning('Sampling frequency is %d Hz, expected %d Hz.', fs, fs_expected);
end


% 3. Configure Welch segment parameters based on dynamic fs
% Window duration = 1 second, achieving df = 1 Hz resolution
windowLength = fs;
noverlap = windowLength / 2; % 50% overlap

% 4. Compute the one-sided PSD using pwelch
% Passing calibrated data_uPa ensures units are referenced directly to uPa
fprintf('Computing PSD using pwelch...\n');
[psd_estimates, frequencies] = pwelch(data_uPa, windowLength, noverlap, windowLength, fs, 'power');

% 5. Convert to dB re 1 µPa²/Hz
psd_db = 10 * log10(psd_estimates);

% 6. Plot the PSD diagram across the principal analysis band up to Nyquist (fs/2 = 64 kHz)
figure;
plot(frequencies / 1000, psd_db, 'Color', [0.85, 0.325, 0.098], 'LineWidth', 1.5);
hold on;

% 7. Identify Multiple Fundamental Signals & Their Harmonics
fprintf('Detecting multiple fundamental frequencies using Harmonic Sum Spectrum (HSS)...\n');

% We search for fundamentals in the 150 - 1000 Hz range
f_search = 150:1:1000;
hss_score = zeros(size(f_search));

% Compute Harmonic Sum Spectrum
for i = 1:length(f_search)
    f0 = f_search(i);
    score = 0;
    % Sum the linear PSD power of the fundamental and its first 9 harmonics
    for h = 1:10
        target_f = f0 * h;
        if target_f > (fs/2), break; end
        [~, c_idx] = min(abs(frequencies - target_f));
        score = score + 10^(psd_db(c_idx) / 10);
    end
    hss_score(i) = score;
end

% Find peaks in the HSS score to identify true fundamental families
[pks, locs] = findpeaks(hss_score);
[pks, sort_idx] = sort(pks, 'descend');
candidate_f0s = f_search(locs(sort_idx));

% Filter for distinct fundamentals (at least 15 Hz apart)
top_fundamentals = [];
for i = 1:length(candidate_f0s)
    f0 = candidate_f0s(i);
    is_distinct = true;
    for j = 1:length(top_fundamentals)
        if abs(f0 - top_fundamentals(j)) < 15
            is_distinct = false;
            break;
        end
    end
    if is_distinct
        top_fundamentals(end+1) = f0;
    end
    if length(top_fundamentals) == 5, break; end
end

top_fundamentals = sort(top_fundamentals);

fprintf('\n--- Top %d Detected Fundamental Families ---\n', length(top_fundamentals));
colors = lines(length(top_fundamentals)); % Generate distinct colors

figure;
plot(frequencies / 1000, psd_db, 'Color', [0.7 0.7 0.7], 'LineWidth', 1);
hold on;

for f_idx = 1:length(top_fundamentals)
    f0 = top_fundamentals(f_idx);
    
    [~, c_idx] = min(abs(frequencies - f0));
    f0_amp = psd_db(c_idx);
    
    fprintf('Family %d: f0 = %.2f Hz (%.2f dB)\n', f_idx, f0, f0_amp);
    
    % Plot fundamental (solid line)
    xline(f0 / 1000, '-', 'Color', colors(f_idx,:), 'LineWidth', 2, 'DisplayName', sprintf('f0=%.1f Hz', f0));
    
    % Plot harmonics (dashed lines)
    num_harmonics = min(15, floor((fs/2) / f0));
    for h = 2:num_harmonics
        xline(f0 * h / 1000, '--', 'Color', colors(f_idx,:), 'Alpha', 0.5, 'HandleVisibility', 'off');
    end
end

title(sprintf('Top %d Acoustic Signatures (Multi-Fundamental): %s', length(top_fundamentals), fileName), 'Interpreter', 'none');
xlabel('Frequency (kHz)');
ylabel('PSD (dB re 1 \mu Pa^2/Hz @ 1 m)');
grid on;
xlim([0, min(10000, fs/2) / 1000]); 
set(gca, 'GridLineStyle', '--');
legend('Location', 'northeast');
hold off;

saveas(gcf, 'psd_plot_multiple.png');
fprintf('Saved psd_plot_multiple.png\n');