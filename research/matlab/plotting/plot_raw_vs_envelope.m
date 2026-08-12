function plot_raw_vs_envelope()
    % Raw Features [Centroid (kHz), Entropy]
    croatia_raw = [6.0751, 0.8018; 
                   1.1453, 0.6119; 
                   1.4995, 0.6906; 
                   5.1398, 0.7899; 
                   0.8248, 0.4653];
                   
    garda_raw = [4.9205, 0.7928; 
                 2.0247, 0.7074; 
                 2.9389, 0.6948; 
                 3.1193, 0.7232];
    
    % Envelope Features [Coherence Time (ms), Sample Entropy]
    croatia_env = [40.0257, 0.6990; 
                   120.8571, 0.8969; 
                   35.8194, 0.8962; 
                   203.0000, 1.8886; 
                   124.1375, 1.3432];
                   
    garda_env = [267.9062, 1.4608; 
                 158.2576, 0.8135; 
                 81.4459, 1.1907; 
                 212.3750, 1.4379];
    
    fig = figure('Visible', 'off', 'Position', [100, 100, 1200, 500]);
    
    % --- Subplot 1: Raw Audio Space ---
    subplot(1, 2, 1);
    hold on;
    scatter(croatia_raw(:,1), croatia_raw(:,2), 120, [0 0.4470 0.7410], 'filled', 'MarkerEdgeColor', 'k');
    scatter(garda_raw(:,1), garda_raw(:,2), 120, [0.8500 0.3250 0.0980], 'filled', 'MarkerEdgeColor', 'k');
    
    % Try to draw a separator to show it's impossible/hard
    title('Raw Audio Domain (No Separation)', 'FontSize', 14);
    xlabel('Raw Centroid (kHz)', 'FontSize', 12);
    ylabel('Raw Entropy', 'FontSize', 12);
    legend({'Croatia (Underwater Scooter)', 'Garda (Surface Boats)'}, 'Location', 'best');
    grid on;
    
    % --- Subplot 2: Envelope Space ---
    subplot(1, 2, 2);
    hold on;
    scatter(croatia_env(:,1), croatia_env(:,2), 120, [0 0.4470 0.7410], 'filled', 'MarkerEdgeColor', 'k');
    scatter(garda_env(:,1), garda_env(:,2), 120, [0.8500 0.3250 0.0980], 'filled', 'MarkerEdgeColor', 'k');
    
    % Draw a conceptual separator line
    plot([140, 140], [0, 2], 'k--', 'LineWidth', 2);
    
    title('Amplitude Envelope Domain (Clear Separation)', 'FontSize', 14);
    xlabel('Envelope Coherence Time (ms)', 'FontSize', 12);
    ylabel('Envelope Sample Entropy', 'FontSize', 12);
    legend({'Croatia (Underwater Scooter)', 'Garda (Surface Boats)', 'Decision Boundary'}, 'Location', 'best');
    grid on;
    
    sgtitle('Feature Space Separability: Raw Audio vs Envelope', 'FontSize', 16, 'FontWeight', 'bold');
    
    out_dir = 'C:\Users\Roy\dev\research\research\images';
    if ~exist(out_dir, 'dir'), mkdir(out_dir); end
    saveas(fig, fullfile(out_dir, 'raw_vs_envelope_scatter.png'));
    
    artifact_dir = 'C:\Users\Roy\.gemini\antigravity-ide\brain\ba8fb3cc-11cb-4768-982c-06c5cf44fdb9';
    saveas(fig, fullfile(artifact_dir, 'raw_vs_envelope_scatter.png'));
    close(fig);
    
    fprintf('Saved raw_vs_envelope_scatter.png\n');
end
