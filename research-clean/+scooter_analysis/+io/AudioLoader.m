classdef AudioLoader
    % AudioLoader - Robust audio file loading, validation, and resampling.
    %
    % Usage:
    %   [sig, fs, base_time] = scooter_analysis.io.AudioLoader.loadFile(filepath, target_fs);
    %   [sig, fs, base_time] = scooter_analysis.io.AudioLoader.loadAndConcatenate(directory, target_fs);
    %   files = scooter_analysis.io.AudioLoader.findFiles(directory, recursive);
    
    methods (Static)
        
        function [sig, fs, base_time, filename] = loadFile(filepath, target_fs)
            % Load, validate, mono-mix, DC-remove, and resample an audio file.
            %
            % Returns empty sig on failure (caller should check and skip).
            
            sig = [];
            fs = target_fs;
            base_time = datetime('today');
            [~, filename, ~] = fileparts(filepath);
            
            % Read metadata
            try
                info = audioinfo(filepath);
            catch ME
                fprintf('[AudioLoader] Error reading %s: %s\n', filename, ME.message);
                return;
            end
            
            % Skip empty files
            if isfield(info, 'TotalSamples') && info.TotalSamples == 0
                fprintf('[AudioLoader] %s has 0 samples, skipping.\n', filename);
                return;
            end
            
            % Read audio data
            try
                sig = audioread(filepath);
            catch ME
                fprintf('[AudioLoader] Failed to read audio from %s: %s\n', filename, ME.message);
                sig = [];
                return;
            end
            
            if isempty(sig)
                return;
            end
            
            % Mono-mix multi-channel
            if size(sig, 2) > 1
                sig = mean(sig, 2);
            end
            
            % DC removal
            sig = sig - mean(sig);
            
            % Resample if needed
            fs_orig = info.SampleRate;
            if fs_orig ~= target_fs
                [p_res, q_res] = rat(target_fs / fs_orig);
                sig = resample(sig, p_res, q_res);
            end
            fs = target_fs;
            
            % Extract base datetime from filename
            base_time = scooter_analysis.io.AudioLoader.extractDatetime(filename);
        end
        
        
        function [sig, fs, base_time] = loadAndConcatenate(directory, target_fs, recursive)
            % Load all WAV files in a directory and concatenate into a single
            % continuous signal.  Files are sorted by name (assumed
            % chronological).
            %
            % Args:
            %   directory  - path to search
            %   target_fs  - target sample rate
            %   recursive  - (optional, default false) search subdirectories
            %
            % Returns:
            %   sig       - concatenated mono signal
            %   fs        - actual sample rate (== target_fs)
            %   base_time - datetime from first file
            
            if nargin < 3; recursive = false; end
            
            files = scooter_analysis.io.AudioLoader.findFiles(directory, recursive);
            if isempty(files)
                sig = []; fs = target_fs; base_time = datetime('today');
                return;
            end
            
            % Sort by name for chronological order
            [~, sort_idx] = sort({files.name});
            files = files(sort_idx);
            
            % Extract base time from first file
            [~, first_name, ~] = fileparts(files(1).name);
            base_time = scooter_analysis.io.AudioLoader.extractDatetime(first_name);
            
            fprintf('[AudioLoader] Loading and concatenating %d files...\n', length(files));
            continuous_sig = [];
            
            for f_idx = 1:length(files)
                filepath = fullfile(files(f_idx).folder, files(f_idx).name);
                
                try
                    info = audioinfo(filepath);
                catch ME
                    fprintf('[AudioLoader] WARNING: Skipping corrupted file %s\n', files(f_idx).name);
                    continue;
                end
                
                fs_orig = info.SampleRate;
                raw = audioread(filepath);
                if size(raw, 2) > 1
                    raw = mean(raw, 2);
                end
                raw = raw - mean(raw);
                
                if fs_orig ~= target_fs
                    [p_res, q_res] = rat(target_fs / fs_orig);
                    raw = resample(raw, p_res, q_res);
                end
                
                continuous_sig = [continuous_sig; raw]; %#ok<AGROW>
                
                if mod(f_idx, 10) == 0
                    fprintf('[AudioLoader]   Loaded %d/%d files...\n', f_idx, length(files));
                end
            end
            
            sig = continuous_sig;
            fs = target_fs;
            fprintf('[AudioLoader] Concatenation complete. Duration: %.2f minutes.\n', ...
                (length(sig) / fs) / 60);
        end
        
        
        function files = findFiles(directory, recursive)
            % Find all WAV files in a directory.
            %
            % Args:
            %   directory  - path to search
            %   recursive  - (optional, default false) search subdirectories
            
            if nargin < 2
                recursive = false;
            end
            
            if recursive
                files = dir(fullfile(directory, '**', '*.wav'));
            else
                files = dir(fullfile(directory, '*.wav'));
            end
            
            if isempty(files)
                fprintf('[AudioLoader] No WAV files found in %s\n', directory);
            end
        end
        
        
        function dt = extractDatetime(filename)
            % Extract a datetime from a filename containing YYYYMMDD_HHMMSS.
            % Falls back to today's date if no match is found.
            
            time_str = regexp(filename, '\d{8}_\d{6}', 'match', 'once');
            if ~isempty(time_str)
                dt = datetime(time_str, 'InputFormat', 'yyyyMMdd_HHmmss');
            else
                dt = datetime('today');
            end
        end
        
    end
end
