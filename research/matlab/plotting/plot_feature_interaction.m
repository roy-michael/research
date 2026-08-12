function plot_feature_interaction()
    artifact_dir = 'C:\Users\Roy\.gemini\antigravity-ide\brain\80253fc1-2f58-4f2e-ba60-1b773092b2dc';
    mat_file = fullfile(artifact_dir, 'vessel_classifier_model.mat');
    
    if ~exist(mat_file, 'file')
        fprintf('Error: Model file not found at %s\n', mat_file);
        return;
    end
    
    load(mat_file, 'X', 'y', 'forest_model', 'svm_model', 'nn_model');
    
    % X(:,1) = Sample Entropy, X(:,2) = Coherence Time
    x1_min = min(X(:, 1)); x1_max = max(X(:, 1));
    x2_min = min(X(:, 2)); x2_max = max(X(:, 2));
    
    % Create a dense grid for smooth probability mapping
    x1_range = linspace(x1_min*0.8, x1_max*1.1, 150);
    x2_range = linspace(max(0, x2_min*0.8), x2_max*1.1, 150);
    [XX1, XX2] = meshgrid(x1_range, x2_range);
    XGrid = [XX1(:), XX2(:)];
    
    % Predict probabilities for RF
    probs_rf = predict_forest(forest_model, XGrid);
    ProbGrid_rf = reshape(probs_rf, size(XX1));
    
    % Predict probabilities for SVM
    [~, scores_svm] = predict(svm_model, XGrid);
    % Map SVM distance scores to a 0-1 pseudo-probability using Sigmoid for heatmap
    probs_svm = 1 ./ (1 + exp(-scores_svm(:, 2))); 
    ProbGrid_svm = reshape(probs_svm, size(XX1));
    
    % Predict probabilities for NN
    [~, probs_nn] = predict(nn_model, XGrid);
    ProbGrid_nn = reshape(probs_nn(:, 2), size(XX1));
    
    fig = figure('Visible', 'off', 'Position', [100, 100, 1600, 500]);
    cmap = custom_colormap();
    
    % --- Plot Random Forest ---
    subplot(1, 3, 1);
    contourf(XX1, XX2, ProbGrid_rf, 50, 'LineColor', 'none');
    colormap(cmap); caxis([0, 1]); hold on;
    scatter(X(y==0, 1), X(y==0, 2), 30, 'w', 'filled', 'MarkerEdgeColor', 'k');
    scatter(X(y==1, 1), X(y==1, 2), 30, 'k', 'filled', 'MarkerEdgeColor', 'w');
    contour(XX1, XX2, ProbGrid_rf, [0.5, 0.5], 'k-', 'LineWidth', 2);
    title('Random Forest (Custom)', 'FontSize', 14);
    xlabel('Envelope Sample Entropy'); ylabel('Envelope Coherence Time (ms)'); grid on;
    
    % --- Plot SVM (RBF Kernel) ---
    subplot(1, 3, 2);
    contourf(XX1, XX2, ProbGrid_svm, 50, 'LineColor', 'none');
    colormap(cmap); caxis([0, 1]); hold on;
    scatter(X(y==0, 1), X(y==0, 2), 30, 'w', 'filled', 'MarkerEdgeColor', 'k');
    scatter(X(y==1, 1), X(y==1, 2), 30, 'k', 'filled', 'MarkerEdgeColor', 'w');
    contour(XX1, XX2, ProbGrid_svm, [0.5, 0.5], 'k-', 'LineWidth', 2);
    title('Support Vector Machine (RBF)', 'FontSize', 14);
    xlabel('Envelope Sample Entropy'); grid on;
    
    % --- Plot Neural Network (MLP) ---
    subplot(1, 3, 3);
    contourf(XX1, XX2, ProbGrid_nn, 50, 'LineColor', 'none');
    colormap(cmap); caxis([0, 1]); hold on;
    scatter(X(y==0, 1), X(y==0, 2), 30, 'w', 'filled', 'MarkerEdgeColor', 'k');
    scatter(X(y==1, 1), X(y==1, 2), 30, 'k', 'filled', 'MarkerEdgeColor', 'w');
    contour(XX1, XX2, ProbGrid_nn, [0.5, 0.5], 'k-', 'LineWidth', 2);
    title('Neural Network (MLP)', 'FontSize', 14);
    xlabel('Envelope Sample Entropy'); grid on;
    
    % Add a single colorbar for all
    cb = colorbar('Position', [0.93, 0.15, 0.015, 0.7]);
    cb.Label.String = 'Probability of Surface Boat';
    cb.Label.FontSize = 12;
    
    sgtitle('Classifier Probability Heatmap Comparison', 'FontSize', 18, 'FontWeight', 'bold');
    
    out_dir = 'C:\Users\Roy\dev\research\research\images';
    saveas(fig, fullfile(out_dir, 'feature_interaction_toolbox.png'));
    
    artifact_dir_new = 'C:\Users\Roy\.gemini\antigravity-ide\brain\ba8fb3cc-11cb-4768-982c-06c5cf44fdb9';
    saveas(fig, fullfile(artifact_dir_new, 'feature_interaction_toolbox.png'));
    close(fig);
    fprintf('Saved feature_interaction_toolbox.png\n');
end

function cmap = custom_colormap()
    % Blue (0) to White (0.5) to Red (1)
    c1 = [0, 0.4470, 0.7410]; % Blue
    c2 = [1, 1, 1]; % White
    c3 = [0.8500, 0.3250, 0.0980]; % Red
    
    n = 256;
    n1 = floor(n/2);
    n2 = n - n1;
    
    r = [linspace(c1(1), c2(1), n1), linspace(c2(1), c3(1), n2)]';
    g = [linspace(c1(2), c2(2), n1), linspace(c2(2), c3(2), n2)]';
    b = [linspace(c1(3), c2(3), n1), linspace(c2(3), c3(3), n2)]';
    cmap = [r, g, b];
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
