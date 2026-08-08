function extract_vessel_timeframes()
    test_dir = 'D:\RoyStudies\Recordings\DepartmentalCruise-2025-06-12\icListen\wav';
    artifact_dir = 'C:\Users\gorke\.gemini\antigravity-ide\brain\a09a1b5f-d3a3-40cf-b59b-54d19ca16f61';
    
    block_len_sec = 30;
    
    % --- STEP 1: Load Training Set ---
    fprintf('=== STEP 1: Loading Training Reference Set ===\n');
    model_path = fullfile(artifact_dir, 'vessel_classifier_model.mat');
    if ~exist(model_path, 'file')
        error('Model file not found. Run train_vessel_classifier first.');
    end
    load(model_path, 'X', 'y', 'forest_model');
    X_train = X;
    y_train = y;
    fprintf('  Loaded %d reference blocks.\n', length(y_train));
    
    % --- STEP 2: Process Test Files and Extract Timestamps and RMS ---
    fprintf('\n=== STEP 2: Processing Test WAV Files ===\n');
    test_files = dir(fullfile(test_dir, '*.wav'));
    test_records = [];
    
    for f_idx = 1:length(test_files)
        filename = test_files(f_idx).name;
        filepath = fullfile(test_files(f_idx).folder, filename);
        
        tokens = regexp(filename, 'RBW6922_20250612_(\d{6})\.wav', 'tokens');
        if isempty(tokens), continue; end
        
        t_str = tokens{1}{1};
        h_utc = str2double(t_str(1:2));
        m_utc = str2double(t_str(3:4));
        s_utc = str2double(t_str(5:6));
        
        % Convert UTC to Local Time (UTC + 3)
        h_local = h_utc + 3;
        t_local_seconds = h_local * 3600 + m_utc * 60 + s_utc;
        time_formatted_local = sprintf('%02d:%02d:%02d', h_local, m_utc, s_utc);
        
        try
            info = audioinfo(filepath);
            fs = info.SampleRate;
            block_samples = block_len_sec * fs;
            
            if info.TotalSamples < block_samples, continue; end
            
            start_sample = max(1, round(info.TotalSamples/2 - block_samples/2));
            sig = audioread(filepath, [start_sample, start_sample + block_samples - 1]);
            if size(sig, 2) > 1, sig = mean(sig, 2); end
            
            % Apply 100 Hz high-pass filter
            [b_hp, a_hp] = butter(2, 100 / (fs/2), 'high');
            sig_filt = filter(b_hp, a_hp, sig);
            
            rms_val = rms(sig_filt);
            feat = extract_features_block(sig_filt, fs);
            
            rec = struct('filename', filename, 't_sec', t_local_seconds, 'time_str', time_formatted_local, 'rms', rms_val, 'features', feat);
            test_records = [test_records; rec];
        catch ME
            % skip corrupted
        end
    end
    
    % Sort by time
    [~, sort_idx] = sort([test_records.t_sec]);
    test_records = test_records(sort_idx);
    
    % --- STEP 3: Automated Classification with Distance/Confidence Threshold ---
    fprintf('\n=== STEP 3: Running Automated Out-of-Distribution KNN Classification ===\n');
    mu = mean(X_train);
    sigma = std(X_train);
    sigma(sigma == 0) = 1;
    
    X_train_norm = (X_train - mu) ./ sigma;
    
    classified_records = [];
    for i = 1:length(test_records)
        rec = test_records(i);
        
        % Stage 1: RMS energy gating to filter ambient silence
        if rec.rms <= 0.00052
            state = -1; % -1 = Ambient / No Vessel
            state_str = 'No Vessel (Ambient)';
            mean_dist = 0;
            confidence = 0;
        else
            % Stage 2: Feature classification on active signals using custom Random Forest
            prob = predict_forest(forest_model, rec.features(3:4));
            pred = (prob >= 0.5);
            confidence = max(prob, 1 - prob);
            mean_dist = 0;
            
            if pred == 0
                state = 0; % 0 = Underwater
                state_str = 'Underwater Vessel (Scooter)';
            else
                state = 1; % 1 = Surface
                state_str = 'Surface Vessel (Boat)';
            end
        end
        
        % Log details for files in the scooter run (09:00 to 09:40 Local) to verify features
        if rec.t_sec >= 9*3600 && rec.t_sec <= 9*3600 + 40*60
            fprintf('  File: %s | Local Time: %s | RMS: %.6f | MeanDist: %.2f | Conf: %d%% | Pred: %s\n', ...
                rec.filename, rec.time_str, rec.rms, mean_dist, round(confidence*100), state_str);
        end
        
        rec.state = state;
        rec.state_str = state_str;
        classified_records = [classified_records; rec];
    end
    
    % --- STEP 4: Group into Timeframes ---
    fprintf('\n=== STEP 4: Chronological Vessel Activity Timeframes (100%% Automated) ===\n');
    fprintf('%-10s - %-10s | %-30s\n', 'Start Time', 'End Time', 'Status');
    fprintf('%s\n', repmat('-', 1, 60));
    
    timeframes = {};
    
    start_idx = 1;
    current_state = classified_records(1).state;
    
    for i = 2:length(classified_records)
        if classified_records(i).state ~= current_state
            tf = struct( ...
                'start_time', classified_records(start_idx).time_str, ...
                'end_time', classified_records(i-1).time_str, ...
                'state', current_state, ...
                'state_str', classified_records(start_idx).state_str ...
            );
            timeframes{end+1} = tf;
            fprintf('%-10s - %-10s | %-30s\n', tf.start_time, tf.end_time, tf.state_str);
            
            start_idx = i;
            current_state = classified_records(i).state;
        end
    end
    
    tf = struct( ...
        'start_time', classified_records(start_idx).time_str, ...
        'end_time', classified_records(end).time_str, ...
        'state', current_state, ...
        'state_str', classified_records(start_idx).state_str ...
    );
    timeframes{end+1} = tf;
    fprintf('%-10s - %-10s | %-30s\n', tf.start_time, tf.end_time, tf.state_str);
    
    % --- STEP 5: Generate and Save Activity Timeline Plot ---
    t_min = ([classified_records.t_sec] - classified_records(1).t_sec) / 60;
    all_rms = [classified_records.rms];
    
    fig = figure('Visible', 'off', 'Position', [100, 100, 1500, 700]);
    hold on;
    
    for i = 1:length(classified_records)
        t_start = t_min(i);
        if i < length(classified_records)
            t_end = t_min(i+1);
        else
            t_end = t_start + 1.0;
        end
        
        if classified_records(i).state == -1
            c = [0.9 0.9 0.9];
        elseif classified_records(i).state == 0
            c = [1.0 0.85 0.85];
        else
            c = [0.85 1.0 0.85];
        end
        patch([t_start, t_end, t_end, t_start], [0, 0, max(all_rms)*1.1, max(all_rms)*1.1], c, 'EdgeColor', 'none', 'FaceAlpha', 0.5, 'HandleVisibility', 'off');
    end
    
    plot(t_min, all_rms, 'LineWidth', 2, 'Color', '#0072BD', 'DisplayName', 'Signal Energy (RMS)');
    
    title(sprintf('Vessel Detection & Activity Timeline (100%% Automated - June 12, 2025 Cruise)\nStart time: %s Local', classified_records(1).time_str), 'FontSize', 12);
    xlabel('Timeline (minutes from start)');
    ylabel('RMS Amplitude');
    xlim([0, t_min(end)]);
    ylim([0, max(all_rms)*1.1]);
    grid on;
    
    h_dummy_amb = patch(NaN, NaN, [0.9 0.9 0.9], 'DisplayName', 'Ambient Noise (No Vessel)');
    h_dummy_und = patch(NaN, NaN, [1.0 0.85 0.85], 'DisplayName', 'Underwater Vessel (Scooter)');
    h_dummy_sur = patch(NaN, NaN, [0.85 1.0 0.85], 'DisplayName', 'Surface Vessel (Boat)');
    legend([h_dummy_amb, h_dummy_und, h_dummy_sur], 'Location', 'best');
    
    out_img = fullfile(artifact_dir, 'vessel_activity_timeline.png');
    saveas(fig, out_img);
    close(fig);
    fprintf('\nVessel activity timeline plot saved to: %s\n', out_img);
    
    % --- STEP 6: Generate and Save Raw Predictions Timeline Plot ---
    fig2 = figure('Visible', 'off', 'Position', [100, 100, 1500, 700]);
    hold on;
    
    states = [classified_records.state];
    
    h_amb = scatter(t_min(states == -1), repmat(-1, 1, sum(states == -1)), 100, 'filled', 's', 'MarkerFaceColor', [0.5 0.5 0.5], 'DisplayName', 'Classified: Ambient Silence');
    h_und = scatter(t_min(states == 0), repmat(0, 1, sum(states == 0)), 100, 'filled', 'o', 'MarkerFaceColor', 'r', 'DisplayName', 'Classified: Underwater Scooter');
    h_sur = scatter(t_min(states == 1), repmat(1, 1, sum(states == 1)), 100, 'filled', 'd', 'MarkerFaceColor', 'g', 'DisplayName', 'Classified: Surface Boat');
    
    plot(t_min, states, '--', 'Color', [0.7 0.7 0.7], 'LineWidth', 1, 'HandleVisibility', 'off');
    
    set(gca, 'YTick', [-1, 0, 1], 'YTickLabel', {'Ambient Silence', 'Underwater Scooter', 'Surface Boat'});
    ylim([-1.5, 1.5]);
    xlabel('Timeline (minutes from start)');
    ylabel('Raw Classifier Output');
    title(sprintf('Raw Classifier Predictions (File-by-File, Unsmoothed)\nStart time: %s Local', classified_records(1).time_str), 'FontSize', 12);
    legend('Location', 'best');
    grid on;
    
    out_img2 = fullfile(artifact_dir, 'vessel_raw_predictions_timeline.png');
    saveas(fig2, out_img2);
    close(fig2);
    fprintf('Raw predictions timeline plot saved to: %s\n', out_img2);
end

function feat = extract_features_block(y, fs)
    % --- Part 1: Raw Signal Features ---
    [b_hp, a_hp] = butter(2, 100 / (fs/2), 'high');
    y_filt = filter(b_hp, a_hp, y);
    
    [pxx, f] = periodogram(y_filt, [], [], fs);
    p = pxx / (sum(pxx) + eps);
    raw_ent = -sum(p .* log(p + eps)) / log(length(p));
    raw_centroid = sum(f .* p);
    
    % --- Part 2: Envelope Features ---
    fs_intermediate = 8000;
    y_ds = resample(y_filt, fs_intermediate, fs);
    
    env = abs(hilbert(y_ds));
    
    fs_env = 2000;
    env_ds = resample(env, fs_env, fs_intermediate);
    
    env_sub = env_ds(1:min(fs_env, length(env_ds)));
    env_ds_se = resample(env_sub, 1000, fs_env);
    env_sampen = calculate_sampen(env_ds_se, 2, 0.2);
    
    max_lag_env = round(0.5 * fs_env);
    env_det = env_ds - mean(env_ds);
    [acf, ~] = xcorr(env_det, max_lag_env, 'coeff');
    acf_pos = acf(max_lag_env + 1:end);
    idx = find(acf_pos <= exp(-1), 1, 'first');
    if ~isempty(idx)
        env_cohtime = (idx - 1) / fs_env;
    else
        env_cohtime = max_lag_env / fs_env;
    end
    
    feat = [raw_centroid / 1000, raw_ent, env_sampen, env_cohtime * 1000];
end

function [activity, mobility, complexity] = calculate_hjorth(x)
    dx = diff(x);
    ddx = diff(dx);
    
    var_x = var(x);
    var_dx = var(dx);
    var_ddx = var(ddx);
    
    activity = var_x;
    if var_x > 0
        mobility = sqrt(var_dx / var_x);
    else
        mobility = 0;
    end
    
    if var_dx > 0 && mobility > 0
        complexity = sqrt(var_ddx / var_dx) / mobility;
    else
        complexity = 0;
    end
end

function se = calculate_sampen(x, m, r)
    N = length(x);
    r_val = r * std(x);
    if r_val == 0
        se = NaN;
        return;
    end
    
    X2 = [x(1:N-2), x(2:N-1)];
    X3 = [x(1:N-2), x(2:N-1), x(3:N)];
    
    B = 0;
    A = 0;
    
    for i = 1:(N - m)
        diff_m = max(abs(X2 - X2(i, :)), [], 2);
        B = B + sum(diff_m < r_val) - 1;
        
        if i <= N - (m + 1)
            diff_m1 = max(abs(X3 - X3(i, :)), [], 2);
            A = A + sum(diff_m1 < r_val) - 1;
        end
    end
    
    if A > 0 && B > 0
        se = -log(A / B);
    else
        se = NaN;
    end
end

function prob = predict_logistic_regression(X, w, mu, sigma)
    X_norm = (X - mu) ./ sigma;
    X_poly = [X_norm, X_norm.^2, X_norm(:, 1) .* X_norm(:, 2)];
    X_bias = [ones(size(X_poly, 1), 1), X_poly];
    prob = 1 ./ (1 + exp(-X_bias * w));
end

function probs = predict_forest(forest, X)
    N = size(X, 1);
    num_trees = length(forest);
    votes = zeros(N, num_trees);
    for b = 1:num_trees
        votes(:, b) = predict_tree(forest{b}, X);
    end
    probs = mean(votes, 2);
end

function pred = predict_tree(node, X)
    N = size(X, 1);
    pred = zeros(N, 1);
    for i = 1:N
        curr = node;
        while ~curr.is_leaf
            if X(i, curr.feat) <= curr.thresh
                curr = curr.left;
            else
                curr = curr.right;
            end
        end
        pred(i) = curr.class;
    end
end
