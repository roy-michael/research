import numpy as np

def plot_divergence_heatmap(ax, keys, matrix, title):
    im = ax.imshow(matrix, cmap='YlGnBu')
    ax.set_xticks(np.arange(len(keys)))
    ax.set_yticks(np.arange(len(keys)))
    ax.set_xticklabels(keys, rotation=25, ha="right")
    ax.set_yticklabels(keys)

    for i in range(len(keys)):
        for j in range(len(keys)):
            val = matrix[i, j]
            text_color = "w" if val > matrix.max() / 2 else "black"
            if i == j:
                ax.text(j, i, "-", ha="center", va="center", color=text_color)
            else:
                ax.text(j, i, f"{val:.4f}", ha="center", va="center", color=text_color, fontsize=8)

    ax.set_title(title)
    ax.set_ylabel("Dataset 1")
    ax.set_xlabel("Dataset 2")

def plot_histogram(ax, data1, data2, data3, data4, bins, labels, colors, title, xlabel):
    weights1 = np.ones_like(data1) / len(data1) if len(data1) > 0 else []
    weights2 = np.ones_like(data2) / len(data2) if len(data2) > 0 else []
    counts1, _, patches1 = ax.hist(data1, bins=bins, alpha=0.6, label=labels[0], color=colors[0], weights=weights1)
    counts2, _, patches2 = ax.hist(data2, bins=bins, alpha=0.6, label=labels[1], color=colors[1], weights=weights2)
    
    if data3:
        weights3 = np.ones_like(data3) / len(data3)
        counts3, _, patches3 = ax.hist(data3, bins=bins, alpha=0.6, label=labels[2], color=colors[2], weights=weights3)
    else:
        counts3, patches3 = [], []
        
    if data4:
        weights4 = np.ones_like(data4) / len(data4)
        counts4, _, patches4 = ax.hist(data4, bins=bins, alpha=0.6, label=labels[3], color=colors[3], weights=weights4)
    else:
        counts4, patches4 = [], []
        
    for counts, patches, color in zip([counts1, counts2, counts3, counts4], [patches1, patches2, patches3, patches4], ['navy', 'darkred', 'darkgreen', 'indigo']):
        for count, patch in zip(counts, patches):
            if count > 0.02: 
                ax.text(patch.get_x() + patch.get_width()/2, patch.get_height(), f"{count:.2f}", ha='center', va='bottom', fontsize=6, color=color)
                
    ax.set_title(title)
    ax.set_xlabel(xlabel)
    ax.set_ylabel("Probability")
    ax.legend()
    ax.grid(True, alpha=0.5)
    return counts1, counts2, counts3, counts4

def plot_single_histogram(ax, data, bins, label, color, title, xlabel):
    if len(data) == 0:
        ax.set_title(f"{title} - {label} (No Data)")
        return np.zeros(len(bins)-1)
        
    weights = np.ones_like(data) / len(data)
    counts, _, patches = ax.hist(data, bins=bins, alpha=0.7, label=label, color=color, weights=weights)
    
    for count, patch in zip(counts, patches):
        if count > 0.05: 
            ax.text(patch.get_x() + patch.get_width()/2, patch.get_height(), f"{count:.2f}", ha='center', va='bottom', fontsize=8, color='black')
            
    ax.set_title(f"{title}")
    ax.set_xlabel(xlabel)
    ax.set_ylabel("Probability")
    ax.grid(True, alpha=0.5)
    return counts
