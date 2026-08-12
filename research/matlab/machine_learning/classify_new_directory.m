function classify_new_directory()
    test_dir = 'C:\Users\Roy\Recordings\Croatia\Ocean Sonics';
    artifact_dir = 'C:\Users\Roy\.gemini\antigravity-ide\brain\80253fc1-2f58-4f2e-ba60-1b773092b2dc';
    
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
    
    % --- STEP 2: Extract Test Set from New Directory ---
    fprintf('\n=== STEP 2: Extracting Features from New Directory ===\n');
    if ~exist(test_dir, 'dir')
        error('Test directory not found: %s', test_dir);
    end
    
    test_files = dir(fullfile(test_dir, '**', '*.wav'));
    if isempty(test_files)
        error('No WAV files found in: %s', test_dir);
    end
    
    X_test = [];
    test_filenames = {};
    
    for f_idx = 1:length(test_files)
        filepath = fullfile(test_files(f_idx).folder, test_files(f_idx).name);
        try
            info = audioinfo(filepath);
            fs = info.SampleRate;
            block_samples = block_len_sec * fs;
            
            if info.TotalSamples < block_samples
                fprintf('  Skipping %s (too short)\n', test_files(f_idx).name);
                continue;
            end
            
            % Read 30 seconds from the middle
            start_sample = max(1, round(info.TotalSamples/2 - block_samples/2));
            sig = audioread(filepath, [start_sample, start_sample + block_samples - 1]);
            if size(sig, 2) > 1, sig = mean(sig, 2); end
            
            % Apply 100 Hz high-pass Butter filter to remove handling transients
            [b_hp, a_hp] = butter(2, 100 / (fs/2), 'high');
            sig_filt = filter(b_hp, a_hp, sig);
            
            feat = extract_features_block(sig_filt, fs);
            X_test = [X_test; feat];
            test_filenames{end+1} = test_files(f_idx).name;
        catch ME
            fprintf('  Skipping %s (Error reading: %s)\n', test_files(f_idx).name, ME.message);
        end
    end
    if isempty(X_test)
        error('No valid features extracted from test directory.');
    end
    X_test = X_test(:, 3:4);
    
    % --- STEP 3: Normalize and Classify ---
    fprintf('\n=== STEP 3: Classifying New Recordings ===\n');
    mu = mean(X_train);
    sigma = std(X_train);
    sigma(sigma == 0) = 1;
    
    X_train_norm = (X_train - mu) ./ sigma;
    X_test_norm = (X_test - mu) ./ sigma;
    
    % Custom Random Forest Classifier
    probs_rf = predict_forest(forest_model, X_test);
    pred_test = (probs_rf >= 0.5);
    
    % Summarize predictions (2 Classes)
    num_underwater = sum(pred_test == 0);
    num_surface = sum(pred_test == 1);
    total_classified = length(pred_test);
    
    fprintf('\n----------------- CLASSIFICATION SUMMARY -----------------\n');
    fprintf('Total files classified       : %d\n', total_classified);
    fprintf('Underwater-based (Scooter)   : %d (%.2f%%)\n', num_underwater, (num_underwater / total_classified) * 100);
    fprintf('Surface-based (Boats)        : %d (%.2f%%)\n', num_surface, (num_surface / total_classified) * 100);
    fprintf('----------------------------------------------------------\n');
    
    % Print first 30 file predictions
    fprintf('\nFirst 30 predictions:\n');
    for i = 1:min(30, total_classified)
        if pred_test(i) == 0
            lbl = 'Underwater Vessel (Scooter)';
        else
            lbl = 'Surface Vessel (Boat)';
        end
        fprintf('  %-30s : %s\n', test_filenames{i}, lbl);
    end
    
    % --- STEP 4: Save Decision Boundary plot with test points ---
    imp = zeros(size(X_train, 2), 1);
    for j = 1:size(X_train, 2)
        x_class0 = X_train(y_train == 0, j);
        x_class1 = X_train(y_train == 1, j);
        imp(j) = (mean(x_class0) - mean(x_class1))^2 / (var(x_class0) + var(x_class1) + eps);
    end
    [~, sorted_idx] = sort(imp, 'descend');
    feat1_idx = sorted_idx(1);
    feat2_idx = sorted_idx(2);
    
    feature_names = {'SampEn', 'CohTime', 'SpecEnt', 'SpecBW', 'SpecCentroid', 'HjComplexity', 'HjMobility'};
    
    X_train_top2 = X_train_norm(:, [feat1_idx, feat2_idx]);
    X_test_top2 = X_test_norm(:, [feat1_idx, feat2_idx]);
    
    fig = figure('Visible', 'off', 'Position', [100, 100, 950, 800]);
    hold on;
    
    x1range = min([X_train_top2(:, 1); X_test_top2(:, 1)])-0.5 : 0.05 : max([X_train_top2(:, 1); X_test_top2(:, 1)])+0.5;
    x2range = min([X_train_top2(:, 2); X_test_top2(:, 2)])-0.5 : 0.05 : max([X_train_top2(:, 2); X_test_top2(:, 2)])+0.5;
    [XX1, XX2] = meshgrid(x1range, x2range);
    XGrid = [XX1(:), XX2(:)];
    
    grid_preds = knn_classify(X_train_top2, y_train, XGrid, 5);
    
    contourf(XX1, XX2, reshape(grid_preds, size(XX1)), 'LineColor', 'none');
    colormap([1 0.9 0.9; 0.9 1 0.9; 0.9 0.9 0.9]);
    
    % Plot training points
    h1 = scatter(X_train_top2(y_train==0, 1), X_train_top2(y_train==0, 2), 40, 'r', 'filled', 'MarkerFaceAlpha', 0.4, 'DisplayName', 'Train: Underwater');
    h2 = scatter(X_train_top2(y_train==1, 1), X_train_top2(y_train==1, 2), 40, 'g', 'filled', 'MarkerFaceAlpha', 0.4, 'DisplayName', 'Train: Surface');
    h3 = scatter(X_train_top2(y_train==2, 1), X_train_top2(y_train==2, 2), 40, 'filled', 'MarkerFaceColor', [0.5 0.5 0.5], 'MarkerFaceAlpha', 0.4, 'DisplayName', 'Train: Ambient');
    
    % Plot new classified test points
    t0 = scatter(X_test_top2(pred_test==0, 1), X_test_top2(pred_test==0, 2), 80, 'filled', 'o', 'MarkerFaceColor', '#7E2F8E', 'MarkerEdgeColor', 'w', 'LineWidth', 1, 'DisplayName', 'New: Classified Underwater');
    t1 = scatter(X_test_top2(pred_test==1, 1), X_test_top2(pred_test==1, 2), 80, 'filled', 'd', 'MarkerFaceColor', '#0072BD', 'MarkerEdgeColor', 'w', 'LineWidth', 1, 'DisplayName', 'New: Classified Surface');
    t2 = scatter(X_test_top2(pred_test==2, 1), X_test_top2(pred_test==2, 2), 80, 'filled', 's', 'MarkerFaceColor', '#EDB120', 'MarkerEdgeColor', 'w', 'LineWidth', 1, 'DisplayName', 'New: Classified Ambient');
    
    title(sprintf('New Dataset Classification Boundary & Predictions (3-Class)\nDirectory: %s', 'Croatia - Ocean Sonics'), 'FontSize', 11);
    xlabel(sprintf('%s (Normalized)', feature_names{feat1_idx}));
    ylabel(sprintf('%s (Normalized)', feature_names{feat2_idx}));
    legend([h1, h2, h3, t0, t1, t2], 'Location', 'best');
    grid on;
    
    out_img = fullfile(artifact_dir, 'new_dataset_classification_boundary.png');
    saveas(fig, out_img);
    close(fig);
    
    fprintf('\nClassification boundary plot with new predictions saved to: %s\n', out_img);
end

function pred = knn_classify(X_train, y_train, X_test, k)
    num_test = size(X_test, 1);
    pred = zeros(num_test, 1);
    for i = 1:num_test
        test_pt = X_test(i, :);
        dists = sum((X_train - test_pt).^2, 2);
        [~, sorted_idx] = sort(dists, 'ascend');
        nearest_labels = y_train(sorted_idx(1:k));
        pred(i) = mode(nearest_labels);
    end
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
