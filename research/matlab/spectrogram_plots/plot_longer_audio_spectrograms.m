% Script to plot spectrograms of longer audio files from specific directories.
% Reuses spectrogram computation code from previous scripts.

clear; clc; close all;

% Directories/keywords to search for
target_dirs = {'croatia', 'haifa', 'auv', 'ashdod'};
base_dir = 'C:\Users\Roy\dev\research'; % Root search directory

% Minimum duration for "longer" audio files (in seconds)
min_duration_sec = 60; 

% Find all .wav files in the base directory
fprintf('Searching for audio files...\n');
all_wav_files = dir(fullfile(base_dir, '**', '*.wav'));

for i = 1:length(all_wav_files)
    file_path = fullfile(all_wav_files(i).folder, all_wav_files(i).name);
    
    % Check if file is in one of the target directories (case-insensitive)
    in_target_dir = false;
    for j = 1:length(target_dirs)
        if contains(lower(file_path), lower(target_dirs{j}))
            in_target_dir = true;
            break;
        end
    end
    
    if ~in_target_dir
        continue;
    end
    
    % Read audio info to get duration
    try
        info = audioinfo(file_path);
    catch
        warning('Could not read audio info for: %s', file_path);
        continue;
    end
    
    if info.Duration >= min_duration_sec
        fprintf('Processing %s (Duration: %.2f sec)\n', all_wav_files(i).name, info.Duration);
        
        try
            [y, fs] = audioread(file_path);
            
            % Select best channel if stereo
            if size(y, 2) > 1
                y = select_best_channel(y);
            end
            
            % Compute spectrogram
            [P, F, T] = compute_spectrogram(y, fs);
            
            % Plot
            P_dB = 10 * log10(P + eps); % add eps to avoid log(0)
            
            figure('Name', sprintf('Spectrogram: %s', all_wav_files(i).name), 'NumberTitle', 'off', 'Position', [100, 100, 1000, 600]);
            imagesc(T, F, P_dB);
            axis xy;
            colormap jet;
            colorbar;
            title(sprintf('Spectrogram: %s', strrep(all_wav_files(i).name, '_', '\_')));
            xlabel('Time (s)');
            ylabel('Frequency (Hz)');
            
            % Limit frequency axis to 2000Hz to focus on typical targets if needed, 
            % but let's keep it full or up to Nyquist for now.
            ylim([0 min(fs/2, 5000)]); % Show up to 5kHz for better visibility
            
            drawnow;
        catch ME
            warning('Error processing %s: %s', file_path, ME.message);
        end
    end
end

fprintf('Done.\n');

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
    % Computes spectrogram. Reused from untitled11.m
    window_size = round(fs * 0.25);
    noverlap = round(window_size * 0.5);
    nfft = 65536;
    [S, F, T] = spectrogram(signal, window_size, noverlap, nfft, fs);
    P = abs(S).^2;
end
