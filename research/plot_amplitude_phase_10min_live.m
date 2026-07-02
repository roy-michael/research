% MAIN_LIVE_AMPLITUDE_PHASE_10MIN
% Reads sequential audio files and plots Amplitude and Phase over time

% Define path
DIR_PATH = 'C:\Users\Roy\Recordings\Croatia\Ocean Sonics\2407_1_600m';

% Target tonal frequency to analyze (e.g. 350 Hz)
TARGET_FREQ_HZ = 350; 
% Bandwidth around the target frequency (e.g. 10 Hz)
BANDWIDTH_HZ = 10;

try
    % Get list of all .wav files in the directory
    files = dir(fullfile(DIR_PATH, '*.wav'));
    if isempty(files)
        error('No .wav files found in %s', DIR_PATH);
    end
    
    % Sort files alphabetically by name to ensure sequential order
    [~, sortIdx] = sort({files.name});
    files = files(sortIdx);
    
    % Select a 10 minute segment starting after 20 minutes
    if length(files) < 30
        error('Dataset does not have at least 30 minutes of data.');
    end
    files = files(21:30);
    
    fprintf('Selected %d .wav files for the 10-minute segment.\n', length(files));
    
    % Pre-allocate array for memory efficiency and speed
    total_samples = 0;
    sample_rate = [];
    for i = 1:length(files)
        info = audioinfo(fullfile(files(i).folder, files(i).name));
        total_samples = total_samples + info.TotalSamples;
        if i == 1
            sample_rate = info.SampleRate;
        end
    end
    
    fprintf('Total samples to load: %d. Allocating memory...\n', total_samples);
    continuous_data = zeros(total_samples, 1);
    
    % Read and concatenate sequentially
    current_idx = 1;
    for i = 1:length(files)
        file_path = fullfile(files(i).folder, files(i).name);
        fprintf('Reading [%d/%d]: %s\n', i, length(files), files(i).name);
        
        [y, fs] = audioread(file_path);
        
        % Convert to mono if it happens to be multi-channel
        if size(y, 2) > 1
            y = mean(y, 2);
        end
        
        num_samples = length(y);
        continuous_data(current_idx : current_idx + num_samples - 1) = y;
        current_idx = current_idx + num_samples;
    end
    
    fprintf('Data loaded. Computing Analytic Signal (Hilbert Transform)...\n');
    
    % Remove NaNs and Infs
    clean_data = continuous_data(isfinite(continuous_data));
    
    fprintf('Applying bandpass filter around %d Hz (Bandwidth: %d Hz)...\n', TARGET_FREQ_HZ, BANDWIDTH_HZ);
    f_low = max(0.1, TARGET_FREQ_HZ - (BANDWIDTH_HZ / 2));
    f_high = min(sample_rate/2 - 0.1, TARGET_FREQ_HZ + (BANDWIDTH_HZ / 2));
    
    % Design filter using SOS (Second-Order Sections) via designfilt
    % This prevents the "Matrix is close to singular" error which happens 
    % when designing narrow filters at very high sample rates with standard [b,a] arrays.
    bpFilt = designfilt('bandpassiir', 'FilterOrder', 4, ...
        'HalfPowerFrequency1', f_low, 'HalfPowerFrequency2', f_high, ...
        'SampleRate', sample_rate);
    
    % Use filtfilt for zero phase distortion, which is critical for phase analysis
    fprintf('Filtering (this might take a moment on 76M samples)...\n');
    clean_data = filtfilt(bpFilt, clean_data);
    
    % Compute the analytic signal using Hilbert transform to get envelope & phase
    analytic_signal = hilbert(clean_data);
    
    fprintf('Extracting Instantaneous Amplitude and Phase...\n');
    inst_amplitude = abs(analytic_signal);
    
    % The raw phase wraps between -pi and pi. 
    % We do not unwrap here by default because unwrapping 76M samples can take a long time,
    % but you can change this to unwrap(angle(...)) if you want continuous phase tracking.
    inst_phase = angle(analytic_signal); 
    
    % Create Time vector (offset by 20 minutes)
    time_vec = (0:length(clean_data)-1)' / sample_rate;
    time_vec = time_vec + (20 * 60);
    
    fprintf('Setting up live plots...\n');
    
    % We will plot a downsampled version for the line graphs to prevent UI freeze,
    % but we will use the FULL 76 Million points for the Histograms!
    ds_factor = 100;
    
    t_plot = time_vec(1:ds_factor:end);
    amp_plot = inst_amplitude(1:ds_factor:end);
    phase_plot = inst_phase(1:ds_factor:end);
    
    fig = figure('Name', 'Live Amplitude and Phase of 2407_1 (10-min segment)', ...
                 'Position', [150, 100, 1400, 800]);
             
    % 1. Plot Amplitude over Time
    ax1 = subplot(2, 2, 1);
    plot(ax1, t_plot, amp_plot, 'b');
    ylabel(ax1, 'Amplitude (Envelope)');
    title(ax1, sprintf('Instantaneous Amplitude of %d Hz Tone (Minutes 20-30)', TARGET_FREQ_HZ));
    grid(ax1, 'on');
    axis(ax1, 'tight');
    
    % 2. Plot Amplitude Histogram (Using ALL 76M points)
    ax2 = subplot(2, 2, 3);
    histogram(ax2, inst_amplitude, 200, 'FaceColor', 'b', 'EdgeColor', 'none', 'Normalization', 'pdf');
    xlabel(ax2, 'Amplitude');
    ylabel(ax2, 'Probability Density');
    title(ax2, 'Amplitude Statistical Distribution (Rician/Rayleigh)');
    grid(ax2, 'on');
    
    % 3. Plot Phase over Time
    ax3 = subplot(2, 2, 2);
    plot(ax3, t_plot, phase_plot, 'r');
    xlabel(ax3, 'Time [sec]');
    ylabel(ax3, 'Phase [Radians]');
    title(ax3, sprintf('Instantaneous Phase of %d Hz Tone (Minutes 20-30)', TARGET_FREQ_HZ));
    grid(ax3, 'on');
    axis(ax3, 'tight');
    
    % 4. Plot Phase Histogram (Using ALL 76M points)
    ax4 = subplot(2, 2, 4);
    histogram(ax4, inst_phase, 200, 'FaceColor', 'r', 'EdgeColor', 'none', 'Normalization', 'pdf');
    xlabel(ax4, 'Phase [Radians]');
    ylabel(ax4, 'Probability Density');
    title(ax4, 'Phase Statistical Distribution');
    xlim(ax4, [-pi, pi]);
    grid(ax4, 'on');
    
    % Link X-axes only for the time-domain line plots
    linkaxes([ax1, ax3], 'x');
    
    % Enable zoom mode automatically
    zoom(fig, 'on');
    
    fprintf('Plot is live! Histograms calculated using all %d samples.\n', length(inst_amplitude));

catch e
    fprintf('An error occurred: %s\n', e.message);
    disp(e.getReport());
end
