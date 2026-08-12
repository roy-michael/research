function train_toolbox_models()
    artifact_dir = 'C:\Users\Roy\.gemini\antigravity-ide\brain\80253fc1-2f58-4f2e-ba60-1b773092b2dc';
    mat_file = fullfile(artifact_dir, 'vessel_classifier_model.mat');
    
    if ~exist(mat_file, 'file')
        error('Could not find cached features in %s', mat_file);
    end
    
    load(mat_file, 'X', 'y', 'w_lr', 'mu_lr', 'sigma_lr', 'forest_model');
    
    N = size(X, 1);
    rng(42);
    indices = randperm(N);
    fold_sizes = floor(N / 5);
    
    acc_svm = zeros(5, 1);
    conf_svm_total = zeros(2, 2);
    
    acc_nn = zeros(5, 1);
    conf_nn_total = zeros(2, 2);
    
    fprintf('\n=== Training Toolbox Models (SVM & Neural Network) ===\n');
    
    for fold = 1:5
        test_idx = indices((fold-1)*fold_sizes + 1 : fold*fold_sizes);
        train_mask = true(N, 1);
        train_mask(test_idx) = false;
        
        X_train = X(train_mask, :);
        y_train = y(train_mask);
        X_test = X(test_idx, :);
        y_test = y(test_idx);
        
        % MATLAB Toolbox: Support Vector Machine (RBF Kernel)
        svm_fold = fitcsvm(X_train, y_train, 'KernelFunction', 'rbf', 'Standardize', true);
        pred_svm = predict(svm_fold, X_test);
        acc_svm(fold) = sum(pred_svm == y_test) / length(y_test);
        for i = 1:length(y_test)
            conf_svm_total(y_test(i)+1, double(pred_svm(i))+1) = conf_svm_total(y_test(i)+1, double(pred_svm(i))+1) + 1;
        end
        
        % MATLAB Toolbox: Neural Network (MLP)
        nn_fold = fitcnet(X_train, y_train, 'LayerSizes', [10, 5], 'Standardize', true);
        pred_nn = predict(nn_fold, X_test);
        acc_nn(fold) = sum(pred_nn == y_test) / length(y_test);
        for i = 1:length(y_test)
            conf_nn_total(y_test(i)+1, double(pred_nn(i))+1) = conf_nn_total(y_test(i)+1, double(pred_nn(i))+1) + 1;
        end
    end
    
    fprintf('\n--- SVM (RBF Kernel) Performance Summary ---\n');
    fprintf('SVM 5-Fold CV Accuracy: %.2f%%\n', mean(acc_svm) * 100);
    tp = conf_svm_total(2, 2); fp = conf_svm_total(1, 2); fn = conf_svm_total(2, 1);
    f1 = 2 * (tp / (tp + fp + eps) * tp / (tp + fn + eps)) / (tp / (tp + fp + eps) + tp / (tp + fn + eps) + eps);
    fprintf('  F1-Score: %.2f%%\n', f1 * 100);
    
    fprintf('\n--- Neural Network (MLP) Performance Summary ---\n');
    fprintf('NN 5-Fold CV Accuracy: %.2f%%\n', mean(acc_nn) * 100);
    tp = conf_nn_total(2, 2); fp = conf_nn_total(1, 2); fn = conf_nn_total(2, 1);
    f1 = 2 * (tp / (tp + fp + eps) * tp / (tp + fn + eps)) / (tp / (tp + fp + eps) + tp / (tp + fn + eps) + eps);
    fprintf('  F1-Score: %.2f%%\n', f1 * 100);
    
    svm_model = fitcsvm(X, y, 'KernelFunction', 'rbf', 'Standardize', true);
    nn_model = fitcnet(X, y, 'LayerSizes', [10, 5], 'Standardize', true);
    
    save(mat_file, 'X', 'y', 'w_lr', 'mu_lr', 'sigma_lr', 'forest_model', 'svm_model', 'nn_model');
    fprintf('\nSaved new models to %s\n', mat_file);
end
