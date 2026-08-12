function plot_training_verification()
    % Load extracted features and labels
    artifact_dir = 'C:\Users\Roy\.gemini\antigravity-ide\brain\80253fc1-2f58-4f2e-ba60-1b773092b2dc';
    mat_file = fullfile(artifact_dir, 'vessel_classifier_model.mat');
    
    if ~exist(mat_file, 'file')
        fprintf('Error: Model file not found at %s\n', mat_file);
        return;
    end
    
    load(mat_file, 'X', 'y');
    
    out_dir = 'C:\Users\Roy\dev\research\research\images';
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end
    
    %% --- 1. Training Process (Logistic Regression Loss Curve) ---
    % We retrain the logistic regression specifically to capture the loss history
    [~, ~, ~, loss_history] = train_logistic_regression_with_loss(X, y, 0.1);
    
    fig1 = figure('Visible', 'off', 'Position', [100, 100, 800, 500]);
    plot(1:length(loss_history), loss_history, 'LineWidth', 2, 'Color', '#D95319');
    title('Logistic Regression Training Process (Gradient Descent)', 'FontSize', 14);
    xlabel('Iteration', 'FontSize', 12);
    ylabel('Binary Cross-Entropy Loss', 'FontSize', 12);
    grid on;
    
    loss_plot_path = fullfile(out_dir, 'training_loss_curve.png');
    saveas(fig1, loss_plot_path);
    close(fig1);
    
    %% --- 2. Level of Verification (5-Fold CV Confusion Matrix for Random Forest) ---
    N = size(X, 1);
    rng(42); % Fixed seed for reproducibility
    indices = randperm(N);
    fold_sizes = floor(N / 5);
    
    conf_rf = zeros(2, 2); % [Actual 0, Actual 1; Predicted 0, Predicted 1]
    
    for fold = 1:5
        test_idx = indices((fold-1)*fold_sizes + 1 : fold*fold_sizes);
        train_mask = true(N, 1);
        train_mask(test_idx) = false;
        
        X_train = X(train_mask, :);
        y_train = y(train_mask);
        X_test = X(test_idx, :);
        y_test = y(test_idx);
        
        forest_fold = fit_forest(X_train, y_train, 15, 3);
        probs_rf = predict_forest(forest_fold, X_test);
        pred_rf = (probs_rf >= 0.5);
        
        for i = 1:length(y_test)
            r = y_test(i) + 1; % Actual class + 1 (1 for 0, 2 for 1)
            c = double(pred_rf(i)) + 1; % Predicted class + 1
            conf_rf(r, c) = conf_rf(r, c) + 1;
        end
    end
    
    % Plot custom confusion matrix using imagesc
    fig2 = figure('Visible', 'off', 'Position', [100, 100, 700, 600]);
    imagesc(conf_rf);
    colormap(flipud(hot)); % Bright colors for high values
    colorbar;
    
    title('Random Forest Verification (5-Fold CV Confusion Matrix)', 'FontSize', 14);
    set(gca, 'XTick', [1 2], 'XTickLabel', {'Predicted: Underwater', 'Predicted: Surface'}, 'FontSize', 12);
    set(gca, 'YTick', [1 2], 'YTickLabel', {'Actual: Underwater', 'Actual: Surface'}, 'FontSize', 12);
    
    % Add text annotations inside the matrix cells
    for r = 1:2
        for c = 1:2
            text(c, r, num2str(conf_rf(r, c)), 'HorizontalAlignment', 'center', ...
                 'VerticalAlignment', 'middle', 'FontSize', 24, 'FontWeight', 'bold', 'Color', 'k');
        end
    end
    
    cm_plot_path = fullfile(out_dir, 'rf_confusion_matrix.png');
    saveas(fig2, cm_plot_path);
    close(fig2);
    
    % Copy files to current artifact dir for display
    current_artifact_dir = 'C:\Users\Roy\.gemini\antigravity-ide\brain\ba8fb3cc-11cb-4768-982c-06c5cf44fdb9';
    if exist(current_artifact_dir, 'dir')
        copyfile(loss_plot_path, fullfile(current_artifact_dir, 'training_loss_curve.png'));
        copyfile(cm_plot_path, fullfile(current_artifact_dir, 'rf_confusion_matrix.png'));
    end
    
    fprintf('Saved training_loss_curve.png and rf_confusion_matrix.png\n');
end

% --- Modified Logistic Regression to track Loss ---
function [w, mu, sigma, loss_history] = train_logistic_regression_with_loss(X, y, lambda)
    mu = mean(X);
    sigma = std(X);
    sigma(sigma == 0) = 1;
    X_norm = (X - mu) ./ sigma;
    
    X_poly = [X_norm, X_norm.^2, X_norm(:, 1) .* X_norm(:, 2)];
    X_bias = [ones(size(X_poly, 1), 1), X_poly];
    
    [N, D] = size(X_bias);
    w = zeros(D, 1);
    alpha = 0.5;
    
    loss_history = zeros(5000, 1);
    
    for iter = 1:5000
        h = 1 ./ (1 + exp(-X_bias * w));
        
        % Calculate binary cross-entropy loss (with L2 regularization)
        epsilon = 1e-15; % Prevent log(0)
        h = max(epsilon, min(1 - epsilon, h));
        loss = -(1/N) * sum(y .* log(h) + (1 - y) .* log(1 - h)) + (lambda/(2*N)) * sum(w(2:end).^2);
        loss_history(iter) = loss;
        
        grad = (1/N) * (X_bias' * (h - y)) + (lambda/N) * [0; w(2:end)];
        w = w - alpha * grad;
    end
end

% --- Random Forest functions ---
function forest = fit_forest(X, y, num_trees, max_depth)
    forest = cell(num_trees, 1);
    N = size(X, 1);
    for b = 1:num_trees
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
