folder = 'D:\RoyStudies\Recordings\Ashdod\scooter_exp';
files = dir(fullfile(folder, '*.wav'));

% Filter out any combined files that already exist
isCombined = startsWith({files.name}, 'combined_');
files = files(~isCombined);

% Sort by name to ensure chronological order
[~, idx] = sort({files.name});
files = files(idx);

disp(['Found ', num2str(length(files)), ' raw files.']);

all_audio = cell(length(files), 1);
fs = 0;

for i = 1:length(files)
    filepath = fullfile(folder, files(i).name);
    disp(['Reading ', files(i).name, '...']);
    [y, fs_current] = audioread(filepath, 'native');
    if i == 1
        fs = fs_current;
    elseif fs ~= fs_current
        error('Sample rates do not match.');
    end
    
    % Only File 12 (123338.wav) is genuinely swapped in the entire dataset!
    if strcmp(files(i).name, 'record_20260824_123338.wav')
        disp(['Fixing genuinely swapped channels in ', files(i).name, '...']);
        y = [y(:, 5:8), y(:, 1:4)];
    end
    
    all_audio{i} = y;
end

disp('Concatenating audio...');
y_combined = vertcat(all_audio{:});
clear all_audio;

outputFile = fullfile(folder, 'combined_scooter_perfect.wav');
disp(['Writing to ', outputFile, '...']);
audiowrite(outputFile, y_combined, fs);
disp('Done.');
exit;
