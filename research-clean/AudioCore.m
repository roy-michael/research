classdef AudioCore
    % Handles configuration and raw signal ingestion.
    methods (Static)



        function [conditioned_sig, fs_target] = ingest_and_condition_audio(d_meta, cfg)
        % Reads audio files up to the target duration or generates a synthetic benchmark.
        fs_target = cfg.fs_common;
        dur = cfg.dur_common;
        target_samples = round(dur * fs_target);
        
        raw_data = [];
        fs_file = fs_target;
        
        if exist(d_meta.path, 'file') == 2
            fprintf('  Loading raw data starting from: %s\n', d_meta.path);
            [dir_path, name, ext] = fileparts(d_meta.path);
            info = audioinfo(d_meta.path);
            fs_file = info.SampleRate;
        
            % If a single file satisfies the duration, center the extraction
            if info.Duration >= dur
                t_start = max(0, (info.Duration - dur) / 2);
                sample_bounds = round([t_start * fs_file + 1, (t_start + dur) * fs_file]);
                sample_bounds(2) = min(sample_bounds(2), info.TotalSamples);
                [sig, ~] = audioread(d_meta.path, sample_bounds);
                if size(sig, 2) > 1, sig = mean(sig, 2); end
                raw_data = sig;
                fprintf('    Loaded centered segment: %s\n', [name, ext]);
            else
                % We need to read this file and subsequent files from the directory
                [sig, ~] = audioread(d_meta.path);
                if size(sig, 2) > 1, sig = mean(sig, 2); end
                raw_data = sig;
                fprintf('    Loaded initial segment: %s\n', [name, ext]);
        
                % Get list of files in directory
                wavs = dir(fullfile(dir_path, '*.wav'));
        
                % Find the starting file index
                start_idx = 1;
                for w = 1:length(wavs)
                    if strcmp(wavs(w).name, [name, ext])
                        start_idx = w + 1;
                        break;
                    end
                end
        
                % Load subsequent files
                for w = start_idx:length(wavs)
                    samples_needed = target_samples - length(raw_data);
                    if samples_needed <= 0
                        break;
                    end
        
                    file_path = fullfile(wavs(w).folder, wavs(w).name);
                    info = audioinfo(file_path);
                    read_len = min(info.TotalSamples, samples_needed);
        
                    [sig, ~] = audioread(file_path, [1, read_len]);
                    if size(sig, 2) > 1, sig = mean(sig, 2); end
        
                    raw_data = [raw_data; sig];
                    fprintf('    Loaded appended segment: %s\n', wavs(w).name);
                end
            end
        end
        
        if isempty(raw_data)
            fprintf('  File not located. Generating synthetic benchmark signal...\n');
            return;
            t = (0 : 1 / fs_target : dur)';
            if contains(d_meta.name, 'Motorboat')
                % STREAMING_CHUNK:Synthesizing motorboat benchmark signal with explicit multiplication...
                % Motorboat: compound machinery (58 Hz, 140 Hz, 220 Hz) + cavitation (500-1100 Hz)
                sig = 0.09 * sin(2 * pi * 58.0 * t) + ...
                    0.07 * sin(2 * pi * 140.5 * t) + ...
                    0.04 * sin(2 * pi * 218.0 * t) + ...
                    0.02 * sin(2 * pi * 920.0 * t);
                [b_cav, a_cav] = butter(3, [500 1100] / (fs_target / 2), 'bandpass');
                sig = sig + 0.12 * filter(b_cav, a_cav, randn(size(t))) + 0.003 * randn(size(t));
            else
                % STREAMING_CHUNK:Synthesizing Croatia benchmark signal with explicit multiplication...
                % Croatia: clean ambient ocean + two independent stationary CW tonals
                sig = 0.04 * sin(2 * pi * 583.0 * t) + ...
                    0.08 * sin(2 * pi * 631.5 * t) + ...
                    0.01 * sin(2 * pi * 1263.0 * t) + ...
                    0.0015 * randn(size(t));
            end
            raw_data = sig;
            fs_file = fs_target;
        end
        
        % Convert to mono
        if size(raw_data, 2) > 1
            raw_data = mean(raw_data, 2);
        end
        
        % Resample if necessary
        if fs_file ~= fs_target
            conditioned_sig = resample(raw_data, fs_target, fs_file);
        else
            conditioned_sig = raw_data;
        end
        
        % Enforce uniform record length
        if length(conditioned_sig) < target_samples
            conditioned_sig = [conditioned_sig; zeros(target_samples - length(conditioned_sig), 1)];
        else
            conditioned_sig = conditioned_sig(1:target_samples);
        end
        
        % DC offset removal and 20 Hz high-pass conditioning
        conditioned_sig = conditioned_sig - mean(conditioned_sig);
        [b_hp, a_hp] = butter(4, 20.0 / (fs_target / 2), 'high');
        conditioned_sig = filtfilt(b_hp, a_hp, conditioned_sig);
        end
        
        % MODULE 4: WELCH POWER SPECTRAL DENSITY ESTIMATION

    end
end
