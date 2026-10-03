directory = 'D:\RoyStudies\Recordings\Croatia\data';
start_file = 'record_20250722_183004';
end_file = 'record_20250722_192013';

files = dir(fullfile(directory, '*.wav'));
fileNames = {files.name};
fileNames = sort(fileNames);

start_idx = find(startsWith(fileNames, start_file));
end_idx = find(startsWith(fileNames, end_file));

if isempty(start_idx) || isempty(end_idx)
    disp('Start or end file not found.');
    exit(1);
else
    start_idx = start_idx(1);
    end_idx = end_idx(1);
    files_to_merge = fileNames(start_idx:end_idx);
    disp(['Merging ', num2str(length(files_to_merge)), ' files...']);
    
    all_data = [];
    fs = 0;
    for i = 1:length(files_to_merge)
        [y, fs_current] = audioread(fullfile(directory, files_to_merge{i}));
        if i == 1
            fs = fs_current;
        end
        all_data = [all_data; y];
    end
    
    out_file = fullfile(directory, ['merged_', start_file, '_to_', end_file, '.wav']);
    audiowrite(out_file, all_data, fs);
    disp(['Saved merged file to ', out_file]);
    exit(0);
end
