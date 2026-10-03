folder = 'D:\RoyStudies\Recordings\Ashdod\scooter_exp';
files = dir(fullfile(folder, '*.wav'));

% Filter out combined files
isCombined = startsWith({files.name}, 'combined_');
files = files(~isCombined);
[~, idx] = sort({files.name});
files = files(idx);

fileID = fopen('d:\dev\research\research-clean\channel_energies.txt', 'w');
fprintf(fileID, 'FileIndex\tFilename\tCh1\tCh2\tCh3\tCh4\tCh5\tCh6\tCh7\tCh8\n');

for i = 1:length(files)
    filepath = fullfile(folder, files(i).name);
    [y, fs] = audioread(filepath, 'native');
    
    % Compute mean absolute amplitude for each channel
    amps = mean(abs(double(y)));
    
    fprintf(fileID, '%d\t%s\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\t%.1f\n', ...
            i, files(i).name, amps(1), amps(2), amps(3), amps(4), amps(5), amps(6), amps(7), amps(8));
end

fclose(fileID);
exit;
