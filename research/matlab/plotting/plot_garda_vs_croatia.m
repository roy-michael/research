function plot_garda_vs_croatia()
    % Using the previously extracted features to instantly plot
    % the comparison without having to re-process the raw audio files.
    
    croatia_names = {'2307 Free', '2407_1 600m', '2407_2 Snake', '2507_1 1k', '2507_2 Joint'};
    garda_names = {'Shallow Elec', 'Shallow Pet', 'Deep Elec', 'Deep Pet'};
    
    % Feature 1: Raw Centroid (kHz)
    c_cent = [6.0751, 1.1453, 1.4995, 5.1398, 0.8248];
    g_cent = [4.9205, 2.0247, 2.9389, 3.1193];
    
    % Feature 2: Raw Entropy
    c_ent = [0.8018, 0.6119, 0.6906, 0.7899, 0.4653];
    g_ent = [0.7928, 0.7074, 0.6948, 0.7232];
    
    % Feature 3: Envelope Sample Entropy
    c_sampen = [0.6990, 0.8969, 0.8962, 1.8886, 1.3432];
    g_sampen = [1.4608, 0.8135, 1.1907, 1.4379];
    
    % Feature 4: Envelope Coherence Time (ms)
    c_coh = [40.0257, 120.8571, 35.8194, 203.0000, 124.1375];
    g_coh = [267.9062, 158.2576, 81.4459, 212.3750];
    
    fig = figure('Visible', 'off', 'Position', [100, 100, 1200, 800]);
    
    features = { ...
        {c_cent, g_cent, 'Raw Centroid (kHz)'}, ...
        {c_ent, g_ent, 'Raw Entropy'}, ...
        {c_sampen, g_sampen, 'Env Sample Entropy'}, ...
        {c_coh, g_coh, 'Env Coherence Time (ms)'} ...
    };
    
    for i = 1:4
        subplot(2, 2, i);
        hold on;
        
        c_val = features{i}{1};
        g_val = features{i}{2};
        name = features{i}{3};
        
        % Plot mean and std error bars
        errorbar(1, mean(c_val), std(c_val), 'k', 'LineWidth', 2, 'CapSize', 15);
        errorbar(2, mean(g_val), std(g_val), 'k', 'LineWidth', 2, 'CapSize', 15);
        plot([0.8, 1.2], [mean(c_val), mean(c_val)], 'k', 'LineWidth', 2);
        plot([1.8, 2.2], [mean(g_val), mean(g_val)], 'k', 'LineWidth', 2);
        
        % Overlay data points
        scatter(ones(1, 5), c_val, 80, [0, 0.4470, 0.7410], 'filled', 'MarkerEdgeColor', 'k', 'Jitter', 'on', 'JitterAmount', 0.1);
        scatter(2*ones(1, 4), g_val, 80, [0.8500, 0.3250, 0.0980], 'filled', 'MarkerEdgeColor', 'k', 'Jitter', 'on', 'JitterAmount', 0.1);
        
        set(gca, 'XTick', [1, 2], 'XTickLabel', {'Croatia', 'Garda'}, 'XLim', [0.5, 2.5], 'FontSize', 12);
        
        ylabel(name, 'FontWeight', 'bold');
        title(sprintf('Distribution: %s', name), 'FontSize', 14);
        grid on;
    end
    
    sgtitle('Feature Distribution Comparison: Croatia vs Garda', 'FontSize', 16, 'FontWeight', 'bold');
    
    out_dir = 'C:\Users\Roy\dev\research\research\images';
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end
    saveas(fig, fullfile(out_dir, 'garda_vs_croatia_all_features.png'));
    
    artifact_dir = 'C:\Users\Roy\.gemini\antigravity-ide\brain\ba8fb3cc-11cb-4768-982c-06c5cf44fdb9';
    saveas(fig, fullfile(artifact_dir, 'garda_vs_croatia_all_features.png'));
    close(fig);
    
    fprintf('All features plot generated and saved successfully.\n');
end
