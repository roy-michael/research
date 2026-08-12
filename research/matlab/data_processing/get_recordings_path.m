function rec_path = get_recordings_path()
    % GET_RECORDINGS_PATH Returns the base path for audio recordings.
    % It reads from config.json in the project root if it exists.
    
    % Get the directory where this script is located
    script_dir = fileparts(mfilename('fullpath'));
    
    % Path to the config.json file (assumed to be one level up, in the project root)
    config_file = fullfile(script_dir, '..', 'config.json');
    
    if exist(config_file, 'file')
        try
            fid = fopen(config_file, 'r');
            raw = fread(fid, inf);
            str = char(raw');
            fclose(fid);
            val = jsondecode(str);
            if isfield(val, 'recordings_path')
                rec_path = val.recordings_path;
                return;
            end
        catch
            warning('Failed to parse config.json. Using default recordings path.');
        end
    end
    
    % Fallback default path if config.json does not exist or lacks the field
    rec_path = 'C:\Users\Roy\Recordings';
end
