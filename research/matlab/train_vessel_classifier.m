function train_vessel_classifier()
    datasets = {
        struct('name', 'Croatia 2307 Free', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2307_free.wav', 'isFile', true, 'label', 0), ... % 0 = Underwater
        struct('name', 'Croatia 2407_1 600m', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2407_1_600m.wav', 'isFile', true, 'label', 0), ...
        struct('name', 'Croatia 2407_2 Snake', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2407_2_snake.wav', 'isFile', true, 'label', 0), ...
        struct('name', 'Croatia 2507_1 1k', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2507_1_1k.wav', 'isFile', true, 'label', 0), ...
        struct('name', 'Croatia 2507_2 Joint', 'path', 'D:\RoyStudies\Recordings\Croatia\Ocean Sonics\merged\merged_2507_2_joint.wav', 'isFile', true, 'label', 0), ...
        struct('name', 'Garda Shallow Electric', 'path', 'D:\RoyStudies\Recordings\Garda_2_26\1_Shallow Water\Electric', 'isFile', false, 'label', 1), ... % 1 = Surface
        struct('name', 'Garda Shallow Petrol', 'path', 'D:\RoyStudies\Recordings\Garda_2_26\1_Shallow Water\Petrol', 'isFile', false, 'label', 1), ...
        struct('name', 'Garda Deep Electric', 'path', 'D:\RoyStudies\Recordings\Garda_2_26\2_Deep Water\Electric', 'isFile', false, 'label', 1), ...
        struct('name', 'Garda Deep Petrol', 'path', 'D:\RoyStudies\Recordings\Garda_2_26\2_Deep Water\Petrol', 'isFile', false, 'label', 1)
    };
    
    artifact_dir = 'C:\Users\gorke\.gemini\antigravity-ide\brain\a09a1b5f-d3a3-40cf-b59b-54d19ca16f61';
    if ~exist(artifact_dir, 'dir')
        mkdir(artifact_dir);
    end
    
    block_len_sec = 30;
    
    X = []; % Feature matrix
    y = []; % Label vector
    
    fprintf('=== STEP 1: Feature Extraction ===\n');
    for d = 1:length(datasets)
        ds = datasets{d};
        fprintf('Processing dataset: %s (Label: %d)...\n', ds.name, ds.label);
        
        temp_X = [];
        temp_rms = [];
        
        if ds.isFile
            if ~exist(ds.path, 'file')
                continue;
            end
            info = audioinfo(ds.path);
            fs = info.SampleRate;
            total_samples = info.TotalSamples;
            block_samples = block_len_sec * fs;
            num_blocks = floor(total_samples / block_samples);
            
            for b = 1:num_blocks
                start_sample = (b - 1) * block_samples + 1;
                end_sample = b * block_samples;
                sig = audioread(ds.path, [start_sample, end_sample]);
                if size(sig, 2) > 1, sig = mean(sig, 2); end
                
                [b_hp, a_hp] = butter(2, 100 / (fs/2), 'high');
                sig_filt = filter(b_hp, a_hp, sig);
                
                feat = extract_features_block(sig_filt, fs);
                temp_X = [temp_X; feat];
                temp_rms = [temp_rms; rms(sig_filt)];
            end
        else
            if ~exist(ds.path, 'dir')
                continue;
            end
            files = dir(fullfile(ds.path, '*.wav'));
            if isempty(files), continue; end
            
            for f_idx = 1:length(files)
                filepath = fullfile(files(f_idx).folder, files(f_idx).name);
                info = audioinfo(filepath);
                fs = info.SampleRate;
                block_samples = block_len_sec * fs;
                
                num_file_blocks = floor(info.TotalSamples / block_samples);
                for b = 1:num_file_blocks
                    start_sample = (b - 1) * block_samples + 1;
                    end_sample = b * block_samples;
                    sig = audioread(filepath, [start_sample, end_sample]);
                    if size(sig, 2) > 1, sig = mean(sig, 2); end
                    
                    [b_hp, a_hp] = butter(2, 100 / (fs/2), 'high');
                    sig_filt = filter(b_hp, a_hp, sig);
                    
                    feat = extract_features_block(sig_filt, fs);
                    temp_X = [temp_X; feat];
                    temp_rms = [temp_rms; rms(sig_filt)];
                end
            end
        end
        
        if ~isempty(temp_rms)
            local_noise_floor = percentile(temp_rms, 15);
            keep_idx = find(temp_rms > 1.8 * local_noise_floor);
            fprintf('  Local noise floor: %.6f, kept %d/%d blocks\n', local_noise_floor, length(keep_idx), length(temp_rms));
            
            X = [X; temp_X(keep_idx, :)];
            y = [y; repmat(ds.label, length(keep_idx), 1)];
        end
    end
    
    X = X(:, 3:4);
    feature_names = {'EnvSampEn', 'EnvCohTime'};
    
    N = size(X, 1);
    fprintf('\nExtracted total %d samples with %d features.\n', N, size(X, 2));
    
    % Custom 5-Fold Cross Validation & Classifier Training
    fprintf('\n=== STEP 2: Training & Custom Cross-Validation ===\n');
    
    % Shuffle indices
    rng(42);
    indices = randperm(N);
    fold_sizes = floor(N / 5);
    
    acc_knn = zeros(5, 1);
    conf_knn_total = zeros(2, 2);
    
    acc_lr = zeros(5, 1);
    conf_lr_total = zeros(2, 2);
    
    acc_rf = zeros(5, 1);
    conf_rf_total = zeros(2, 2);
    
    for fold = 1:5
        test_idx = indices((fold-1)*fold_sizes + 1 : fold*fold_sizes);
        train_mask = true(N, 1);
        train_mask(test_idx) = false;
        
        X_train = X(train_mask, :);
        y_train = y(train_mask);
        X_test = X(test_idx, :);
        y_test = y(test_idx);
        
        % Normalize for KNN
        mu = mean(X_train);
        sigma = std(X_train);
        sigma(sigma == 0) = 1;
        X_train_norm = (X_train - mu) ./ sigma;
        X_test_norm = (X_test - mu) ./ sigma;
        
        % KNN Classification (K = 5)
        pred_knn = knn_classify(X_train_norm, y_train, X_test_norm, 5);
        acc_knn(fold) = sum(pred_knn == y_test) / length(y_test);
        
        for i = 1:length(y_test)
            r = y_test(i) + 1;
            c = pred_knn(i) + 1;
            conf_knn_total(r, c) = conf_knn_total(r, c) + 1;
        end
        
        % Custom Quadratic Logistic Regression
        [w_fold, mu_fold, sigma_fold] = train_logistic_regression(X_train, y_train, 0.1);
        probs_lr = predict_logistic_regression(X_test, w_fold, mu_fold, sigma_fold);
        pred_lr = (probs_lr >= 0.5);
        acc_lr(fold) = sum(pred_lr == y_test) / length(y_test);
        
        for i = 1:length(y_test)
            r = y_test(i) + 1;
            c = double(pred_lr(i)) + 1;
            conf_lr_total(r, c) = conf_lr_total(r, c) + 1;
        end
        
        % Custom Random Forest
        forest_fold = fit_forest(X_train, y_train, 15, 3);
        probs_rf = predict_forest(forest_fold, X_test);
        pred_rf = (probs_rf >= 0.5);
        acc_rf(fold) = sum(pred_rf == y_test) / length(y_test);
        
        for i = 1:length(y_test)
            r = y_test(i) + 1;
            c = double(pred_rf(i)) + 1;
            conf_rf_total(r, c) = conf_rf_total(r, c) + 1;
        end
    end
    
    fprintf('\n--- KNN Performance Summary ---\n');
    fprintf('KNN (K=5) 5-Fold CV Accuracy: %.2f%%\n', mean(acc_knn) * 100);
    tp_knn = conf_knn_total(2, 2);
    fp_knn = conf_knn_total(1, 2);
    fn_knn = conf_knn_total(2, 1);
    precision_knn = tp_knn / (tp_knn + fp_knn + eps);
    recall_knn = tp_knn / (tp_knn + fn_knn + eps);
    f1_knn = 2 * (precision_knn * recall_knn) / (precision_knn + recall_knn + eps);
    fprintf('  F1-Score: %.2f%%\n', f1_knn * 100);
    
    fprintf('\n--- Quadratic Logistic Regression (LogReg) Performance Summary ---\n');
    fprintf('LogReg 5-Fold CV Accuracy: %.2f%%\n', mean(acc_lr) * 100);
    tp_lr = conf_lr_total(2, 2);
    fp_lr = conf_lr_total(1, 2);
    fn_lr = conf_lr_total(2, 1);
    precision_lr = tp_lr / (tp_lr + fp_lr + eps);
    recall_lr = tp_lr / (tp_lr + fn_lr + eps);
    f1_lr = 2 * (precision_lr * recall_lr) / (precision_lr + recall_lr + eps);
    fprintf('  F1-Score: %.2f%%\n', f1_lr * 100);
    
    fprintf('\n--- Random Forest (RF) Performance Summary ---\n');
    fprintf('RF 5-Fold CV Accuracy: %.2f%%\n', mean(acc_rf) * 100);
    tp_rf = conf_rf_total(2, 2);
    fp_rf = conf_rf_total(1, 2);
    fn_rf = conf_rf_total(2, 1);
    precision_rf = tp_rf / (tp_rf + fp_rf + eps);
    recall_rf = tp_rf / (tp_rf + fn_rf + eps);
    f1_rf = 2 * (precision_rf * recall_rf) / (precision_rf + recall_rf + eps);
    fprintf('  F1-Score: %.2f%%\n', f1_rf * 100);
    
    % Compute Feature Importance using Fisher Score
    imp = zeros(size(X, 2), 1);
    for j = 1:size(X, 2)
        x_class0 = X(y == 0, j);
        x_class1 = X(y == 1, j);
        imp(j) = (mean(x_class0) - mean(x_class1))^2 / (var(x_class0) + var(x_class1) + eps);
    end
    
    % Save Feature Importance Plot
    fig1 = figure('Visible', 'off', 'Position', [100, 100, 800, 500]);
    bar(imp, 'FaceColor', '#0072BD');
    set(gca, 'XTickLabel', feature_names, 'XTick', 1:length(feature_names));
    title('Fisher Score Feature Importance');
    xlabel('Feature');
    ylabel('Fisher Score (Discriminability)');
    grid on;
    saveas(fig1, fullfile(artifact_dir, 'vessel_feature_importance.png'));
    close(fig1);
    
    % Find top 2 features for 2D Boundary Plot
    [~, sorted_idx] = sort(imp, 'descend');
    feat1_idx = sorted_idx(1);
    feat2_idx = sorted_idx(2);
    
    X_top2 = X(:, [feat1_idx, feat2_idx]);
    mu_top2 = mean(X_top2);
    sigma_top2 = std(X_top2);
    X_top2_norm = (X_top2 - mu_top2) ./ sigma_top2;
    
    x1range = min(X_top2_norm(:, 1))-0.5 : 0.05 : max(X_top2_norm(:, 1))+0.5;
    x2range = min(X_top2_norm(:, 2))-0.5 : 0.05 : max(X_top2_norm(:, 2))+0.5;
    [XX1, XX2] = meshgrid(x1range, x2range);
    XGrid = [XX1(:), XX2(:)];
    
    % Plot 2D Classification Boundary (KNN)
    fig2 = figure('Visible', 'off', 'Position', [100, 100, 900, 750]);
    hold on;
    grid_preds_knn = knn_classify(X_top2_norm, y, XGrid, 5);
    contourf(XX1, XX2, reshape(grid_preds_knn, size(XX1)), 'LineColor', 'none');
    colormap([1 0.85 0.85; 0.85 1 0.85]);
    h1 = scatter(X_top2_norm(y==0, 1), X_top2_norm(y==0, 2), 60, 'r', 'filled', 'MarkerFaceAlpha', 0.6, 'DisplayName', 'Underwater (Croatia DVP)');
    h2 = scatter(X_top2_norm(y==1, 1), X_top2_norm(y==1, 2), 60, 'g', 'filled', 'MarkerFaceAlpha', 0.6, 'DisplayName', 'Surface (Garda Boat)');
    title('Vessel Classification Boundary (KNN)', 'FontSize', 12);
    xlabel(sprintf('%s (Normalized)', feature_names{feat1_idx}));
    ylabel(sprintf('%s (Normalized)', feature_names{feat2_idx}));
    legend([h1, h2], 'Location', 'best');
    grid on;
    saveas(fig2, fullfile(artifact_dir, 'vessel_classification_boundary.png'));
    close(fig2);
    
    % Plot 2D Classification Boundary (Quadratic Logistic Regression)
    fig3 = figure('Visible', 'off', 'Position', [100, 100, 900, 750]);
    hold on;
    [w_lr_top2, ~, ~] = train_logistic_regression(X_top2, y, 0.1);
    XGrid_unnorm = XGrid .* sigma_top2 + mu_top2;
    grid_preds_lr = (predict_logistic_regression(XGrid_unnorm, w_lr_top2, mu_top2, sigma_top2) >= 0.5);
    contourf(XX1, XX2, reshape(grid_preds_lr, size(XX1)), 'LineColor', 'none');
    colormap([1 0.85 0.85; 0.85 1 0.85]);
    h1 = scatter(X_top2_norm(y==0, 1), X_top2_norm(y==0, 2), 60, 'r', 'filled', 'MarkerFaceAlpha', 0.6, 'DisplayName', 'Underwater (Croatia DVP)');
    h2 = scatter(X_top2_norm(y==1, 1), X_top2_norm(y==1, 2), 60, 'g', 'filled', 'MarkerFaceAlpha', 0.6, 'DisplayName', 'Surface (Garda Boat)');
    title('Vessel Classification Boundary (Quadratic Logistic Regression)', 'FontSize', 12);
    xlabel(sprintf('%s (Normalized)', feature_names{feat1_idx}));
    ylabel(sprintf('%s (Normalized)', feature_names{feat2_idx}));
    legend([h1, h2], 'Location', 'best');
    grid on;
    saveas(fig3, fullfile(artifact_dir, 'vessel_logreg_boundary.png'));
    close(fig3);
    
    % Plot 2D Classification Boundary (Random Forest)
    fig4 = figure('Visible', 'off', 'Position', [100, 100, 900, 750]);
    hold on;
    forest_top2 = fit_forest(X_top2, y, 15, 3);
    grid_preds_rf = (predict_forest(forest_top2, XGrid_unnorm) >= 0.5);
    contourf(XX1, XX2, reshape(grid_preds_rf, size(XX1)), 'LineColor', 'none');
    colormap([1 0.85 0.85; 0.85 1 0.85]);
    h1 = scatter(X_top2_norm(y==0, 1), X_top2_norm(y==0, 2), 60, 'r', 'filled', 'MarkerFaceAlpha', 0.6, 'DisplayName', 'Underwater (Croatia DVP)');
    h2 = scatter(X_top2_norm(y==1, 1), X_top2_norm(y==1, 2), 60, 'g', 'filled', 'MarkerFaceAlpha', 0.6, 'DisplayName', 'Surface (Garda Boat)');
    title('Vessel Classification Boundary (Random Forest)', 'FontSize', 12);
    xlabel(sprintf('%s (Normalized)', feature_names{feat1_idx}));
    ylabel(sprintf('%s (Normalized)', feature_names{feat2_idx}));
    legend([h1, h2], 'Location', 'best');
    grid on;
    saveas(fig4, fullfile(artifact_dir, 'vessel_rf_boundary.png'));
    close(fig4);
    
    % Train final models
    [w_lr, mu_lr, sigma_lr] = train_logistic_regression(X, y, 0.1);
    forest_model = fit_forest(X, y, 15, 3);
    
    save(fullfile(artifact_dir, 'vessel_classifier_model.mat'), 'X', 'y', 'w_lr', 'mu_lr', 'sigma_lr', 'forest_model');
    fprintf('\nSaved Feature Importance, LogReg/KNN/RF Boundary plots, and model data.\n');
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

function val = percentile(x, p)
    x_sorted = sort(x);
    n = length(x);
    idx = max(1, round(n * p / 100));
    val = x_sorted(idx);
end

function [w, mu, sigma] = train_logistic_regression(X, y, lambda)
    % Z-score normalize X
    mu = mean(X);
    sigma = std(X);
    sigma(sigma == 0) = 1;
    X_norm = (X - mu) ./ sigma;
    
    % Expand features to quadratic: [x1, x2, x1^2, x2^2, x1*x2]
    X_poly = [X_norm, X_norm.^2, X_norm(:, 1) .* X_norm(:, 2)];
    X_bias = [ones(size(X_poly, 1), 1), X_poly];
    
    [N, D] = size(X_bias);
    w = zeros(D, 1);
    alpha = 0.5; % Learning rate
    for iter = 1:5000
        h = 1 ./ (1 + exp(-X_bias * w));
        grad = (1/N) * (X_bias' * (h - y)) + (lambda/N) * [0; w(2:end)];
        w = w - alpha * grad;
    end
end

function prob = predict_logistic_regression(X, w, mu, sigma)
    X_norm = (X - mu) ./ sigma;
    X_poly = [X_norm, X_norm.^2, X_norm(:, 1) .* X_norm(:, 2)];
    X_bias = [ones(size(X_poly, 1), 1), X_poly];
    prob = 1 ./ (1 + exp(-X_bias * w));
end

function forest = fit_forest(X, y, num_trees, max_depth)
    forest = cell(num_trees, 1);
    N = size(X, 1);
    for b = 1:num_trees
        % Bootstrap sample with replacement
        idx = randi(N, N, 1);
        forest{b} = fit_tree(X(idx, :), y(idx), max_depth);
    end
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

function node = fit_tree(X, y, max_depth, depth)
    if nargin < 4, depth = 0; end
    num_samples = size(X, 1);
    num_classes = length(unique(y));
    
    % Base cases: maximum depth reached, too few samples, or pure node
    if depth >= max_depth || num_samples < 5 || num_classes == 1
        node.is_leaf = true;
        node.class = mode(y);
        return;
    end
    
    node.is_leaf = false;
    best_gini = 1;
    best_feat = 1;
    best_thresh = 0;
    
    [N, D] = size(X);
    for d = 1:D
        vals = unique(X(:, d))';
        for val = vals
            left_mask = X(:, d) <= val;
            right_mask = ~left_mask;
            if sum(left_mask) == 0 || sum(right_mask) == 0, continue; end
            
            p_l = sum(y(left_mask) == 1) / sum(left_mask);
            gini_l = 1 - p_l^2 - (1 - p_l)^2;
            
            p_r = sum(y(right_mask) == 1) / sum(right_mask);
            gini_r = 1 - p_r^2 - (1 - p_r)^2;
            
            gini = (sum(left_mask)/N)*gini_l + (sum(right_mask)/N)*gini_r;
            if gini < best_gini
                best_gini = gini;
                best_feat = d;
                best_thresh = val;
            end
        end
    end
    
    if best_gini == 1
        node.is_leaf = true;
        node.class = mode(y);
        return;
    end
    
    node.feat = best_feat;
    node.thresh = best_thresh;
    left_idx = X(:, best_feat) <= best_thresh;
    node.left = fit_tree(X(left_idx, :), y(left_idx), max_depth, depth + 1);
    node.right = fit_tree(X(~left_idx, :), y(~left_idx), max_depth, depth + 1);
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
