% Script to plot spectrograms for specific experiment directories

clear; clc; close all;

%% Part 1: Plot all files in Ashdod scooter_exp as a SINGLE spectrogram
ashdod_dir = 'C:\Users\Roy\Recordings\Ashdod\scooter_exp';
fprintf('--- Part 1: Processing Ashdod scooter_exp ---\n');
wav_files_ashdod = dir(fullfile(ashdod_dir, '*.wav'));

if isempty(wav_files_ashdod)
    warning('No .wav files found in %s', ashdod_dir);
else
    y_combined = [];
    fs_combined = 0;
    
    % Sort files by name to concatenate them in order
    [~, sort_idx] = sort({wav_files_ashdod.name});
    wav_files_ashdod = wav_files_ashdod(sort_idx);
    
    for i = 1:length(wav_files_ashdod)
        file_path = fullfile(wav_files_ashdod(i).folder, wav_files_ashdod(i).name);
        fprintf('Reading %s...\n', wav_files_ashdod(i).name);
        [y, fs] = audioread(file_path);
        
        % Ensure mono
        if size(y, 2) > 1
            y = select_best_channel(y);
        end
        
        % Ensure column vector
        y = y(:);
        
        % Handle sample rate mismatches
        if fs_combined == 0
            fs_combined = fs;
        elseif fs ~= fs_combined
            warning('Sample rate mismatch in %s. Resampling from %d to %d...', wav_files_ashdod(i).name, fs, fs_combined);
            y = resample(y, fs_combined, fs);
        end
        
        % Concatenate
        y_combined = [y_combined; y];
    end
    
    if ~isempty(y_combined)
        fprintf('Computing combined spectrogram (total duration: %.2f sec)...\n', length(y_combined)/fs_combined);
        [P, F, T] = compute_spectrogram(y_combined, fs_combined);
        P_dB = 10 * log10(P + eps);
        
        figure('Name', 'Combined Spectrogram: Ashdod scooter_exp', 'NumberTitle', 'off', 'Position', [50, 50, 1400, 700]);
        imagesc(T, F, P_dB);
        axis xy;
        colormap jet;
        colorbar;
        title('Combined Spectrogram: Ashdod scooter\_exp');
        xlabel('Time (s)');
        ylabel('Frequency (Hz)');
        % Limit to 5kHz for visibility, or up to Nyquist if lower
        ylim([0 min(fs_combined/2, 5000)]);
        drawnow;
    end
end

%% Part 2: Plot a spectrogram for EACH file in AUVExp_1_26
auv_dir = 'C:\Users\Roy\Recordings\AUVExp_1_26';
fprintf('\n--- Part 2: Processing AUVExp_1_26 ---\n');
wav_files_auv = dir(fullfile(auv_dir, '*.wav'));

if isempty(wav_files_auv)
    warning('No .wav files found in %s', auv_dir);
else
    for i = 1:length(wav_files_auv)
        file_path = fullfile(wav_files_auv(i).folder, wav_files_auv(i).name);
        fprintf('Processing %s...\n', wav_files_auv(i).name);
        
        try
            [y, fs] = audioread(file_path);
            
            % Ensure mono
            if size(y, 2) > 1
                y = select_best_channel(y);
            end
            
            [P, F, T] = compute_spectrogram(y, fs);
            P_dB = 10 * log10(P + eps);
            
            figure('Name', sprintf('Spectrogram: %s', wav_files_auv(i).name), 'NumberTitle', 'off', 'Position', [100 + i*20, 100 + i*20, 1000, 600]);
            imagesc(T, F, P_dB);
            axis xy;
            colormap jet;
            colorbar;
            title(sprintf('Spectrogram: %s (AUVExp\\_1\\_26)', strrep(wav_files_auv(i).name, '_', '\_')));
            xlabel('Time (s)');
            ylabel('Frequency (Hz)');
            % Limit to 5kHz for visibility
            ylim([0 min(fs/2, 5000)]);
            drawnow;
        catch ME
            warning('Failed to process %s: %s', wav_files_auv(i).name, ME.message);
        end
    end
end

fprintf('\nDone processing all files.\n');

% =========================================================================
%                         LOCAL FUNCTIONS
% =========================================================================

function sig_mono = select_best_channel(sig_matrix)
    % Selects the channel with the highest RMS power
    if size(sig_matrix, 2) > 1
        channel_power = rms(sig_matrix, 1);
        [~, best_idx] = max(channel_power);
        sig_mono = sig_matrix(:, best_idx);
    else
        sig_mono = sig_matrix;
    end
end

function [P, F, T] = compute_spectrogram(signal, fs)
    % Computes spectrogram using standard parameters
    window_size = round(fs * 0.25);
    noverlap = round(window_size * 0.5);
    nfft = 65536;
    [S, F, T] = spectrogram(signal, window_size, noverlap, nfft, fs);
    P = abs(S).^2;
end
