"""
Generate spatial distribution plot of test NSE results for 531 CAMELS-US basins
"""
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path
from matplotlib.colors import TwoSlopeNorm
import matplotlib.patches as mpatches

# Set style
plt.style.use('seaborn-v0_8-whitegrid')
plt.rcParams.update({
    'font.family': 'DejaVu Sans',
    'font.size': 11,
    'axes.titlesize': 14,
    'axes.labelsize': 12,
    'figure.dpi': 150,
    'savefig.dpi': 300,
    'savefig.bbox': 'tight',
})

def load_data(project_root):
    """Load test metrics and basin locations"""
    # Load test results
    metrics_path = project_root / 'runs' / 'reproduce_531_nse074_2025_1129_2145_ep30' / 'test' / 'model_epoch020' / 'test_metrics.csv'
    metrics_df = pd.read_csv(metrics_path)
    metrics_df['basin'] = metrics_df['basin'].astype(str).str.zfill(8)
    
    # Load basin locations
    topo_path = project_root / 'data' / 'camels_us' / 'full' / 'camels_attributes_v2.0' / 'camels_topo.txt'
    topo_df = pd.read_csv(topo_path, sep=';')
    topo_df['gauge_id'] = topo_df['gauge_id'].astype(str).str.zfill(8)
    
    # Merge
    merged = metrics_df.merge(topo_df, left_on='basin', right_on='gauge_id', how='left')
    
    return merged

def plot_spatial_nse(data, output_dir):
    """Plot 1: Spatial distribution of NSE with diverging colormap"""
    fig, ax = plt.subplots(figsize=(14, 9))
    
    # Create diverging norm centered at 0.7
    norm = TwoSlopeNorm(vmin=-0.5, vcenter=0.5, vmax=1.0)
    
    # Scatter plot
    scatter = ax.scatter(
        data['gauge_lon'], 
        data['gauge_lat'],
        c=data['NSE'],
        cmap='RdYlGn',
        norm=norm,
        s=25,
        alpha=0.8,
        edgecolors='black',
        linewidths=0.3
    )
    
    # Colorbar
    cbar = plt.colorbar(scatter, ax=ax, shrink=0.8, pad=0.02)
    cbar.set_label('Test NSE (Epoch 20)', fontsize=12)
    
    # Labels
    ax.set_xlabel('Longitude')
    ax.set_ylabel('Latitude')
    ax.set_title('CUDA-LSTM Test Performance: Spatial Distribution (531 CAMELS-US Basins)')
    
    # Add statistics annotation
    median_nse = data['NSE'].median()
    mean_nse = data['NSE'].mean()
    good_pct = (data['NSE'] >= 0.7).sum() / len(data) * 100
    
    stats_text = f'Median NSE: {median_nse:.3f}\nMean NSE: {mean_nse:.3f}\nNSE >= 0.7: {good_pct:.1f}%'
    ax.text(0.02, 0.98, stats_text, transform=ax.transAxes, fontsize=10,
            verticalalignment='top', bbox=dict(boxstyle='round', facecolor='white', alpha=0.8))
    
    plt.tight_layout()
    plt.savefig(output_dir / 'fig5_spatial_nse.png')
    plt.savefig(output_dir / 'fig5_spatial_nse.pdf')
    print(f"Saved: fig5_spatial_nse.png/pdf")
    plt.close()

def plot_spatial_categories(data, output_dir):
    """Plot 2: Spatial distribution with performance categories"""
    fig, ax = plt.subplots(figsize=(14, 9))
    
    # Define categories
    def categorize(nse):
        if nse >= 0.8:
            return 'Excellent (>=0.8)'
        elif nse >= 0.7:
            return 'Good (0.7-0.8)'
        elif nse >= 0.5:
            return 'Acceptable (0.5-0.7)'
        elif nse >= 0:
            return 'Poor (0-0.5)'
        else:
            return 'Unsatisfactory (<0)'
    
    data['category'] = data['NSE'].apply(categorize)
    
    # Colors for each category
    colors = {
        'Excellent (>=0.8)': '#1a9850',
        'Good (0.7-0.8)': '#91cf60',
        'Acceptable (0.5-0.7)': '#fee08b',
        'Poor (0-0.5)': '#fc8d59',
        'Unsatisfactory (<0)': '#d73027'
    }
    
    # Plot each category
    for cat in ['Unsatisfactory (<0)', 'Poor (0-0.5)', 'Acceptable (0.5-0.7)', 'Good (0.7-0.8)', 'Excellent (>=0.8)']:
        subset = data[data['category'] == cat]
        if len(subset) > 0:
            ax.scatter(
                subset['gauge_lon'], 
                subset['gauge_lat'],
                c=colors[cat],
                s=30,
                alpha=0.8,
                edgecolors='black',
                linewidths=0.3,
                label=f'{cat} (n={len(subset)})'
            )
    
    ax.set_xlabel('Longitude')
    ax.set_ylabel('Latitude')
    ax.set_title('CUDA-LSTM Test Performance Categories (531 CAMELS-US Basins)')
    ax.legend(loc='lower left', fontsize=9)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'fig6_spatial_categories.png')
    plt.savefig(output_dir / 'fig6_spatial_categories.pdf')
    print(f"Saved: fig6_spatial_categories.png/pdf")
    plt.close()

def plot_nse_histogram(data, output_dir):
    """Plot 3: Histogram of NSE distribution"""
    fig, ax = plt.subplots(figsize=(10, 6))
    
    # Filter for reasonable range
    nse_values = data['NSE'].clip(-1, 1)
    
    # Create histogram
    bins = np.linspace(-1, 1, 41)
    n, bins_edges, patches = ax.hist(nse_values, bins=bins, edgecolor='black', linewidth=0.5)
    
    # Color bars based on value
    for i, (patch, left_edge) in enumerate(zip(patches, bins_edges[:-1])):
        if left_edge >= 0.8:
            patch.set_facecolor('#1a9850')
        elif left_edge >= 0.7:
            patch.set_facecolor('#91cf60')
        elif left_edge >= 0.5:
            patch.set_facecolor('#fee08b')
        elif left_edge >= 0:
            patch.set_facecolor('#fc8d59')
        else:
            patch.set_facecolor('#d73027')
    
    # Add reference lines
    ax.axvline(x=0.7, color='black', linestyle='--', linewidth=1.5, label='NSE = 0.7')
    ax.axvline(x=data['NSE'].median(), color='blue', linestyle='-', linewidth=2, label=f'Median = {data["NSE"].median():.3f}')
    
    ax.set_xlabel('Test NSE')
    ax.set_ylabel('Number of Basins')
    ax.set_title('Distribution of Test NSE across 531 CAMELS-US Basins')
    ax.legend(loc='upper left')
    ax.set_xlim(-1, 1)
    
    # Add count annotation
    excellent = (data['NSE'] >= 0.8).sum()
    good = ((data['NSE'] >= 0.7) & (data['NSE'] < 0.8)).sum()
    acceptable = ((data['NSE'] >= 0.5) & (data['NSE'] < 0.7)).sum()
    poor = ((data['NSE'] >= 0) & (data['NSE'] < 0.5)).sum()
    bad = (data['NSE'] < 0).sum()
    
    summary = f'Excellent: {excellent}\nGood: {good}\nAcceptable: {acceptable}\nPoor: {poor}\nUnsatisfactory: {bad}'
    ax.text(0.98, 0.98, summary, transform=ax.transAxes, fontsize=10,
            verticalalignment='top', horizontalalignment='right',
            bbox=dict(boxstyle='round', facecolor='white', alpha=0.8))
    
    plt.tight_layout()
    plt.savefig(output_dir / 'fig7_nse_histogram.png')
    plt.savefig(output_dir / 'fig7_nse_histogram.pdf')
    print(f"Saved: fig7_nse_histogram.png/pdf")
    plt.close()

def plot_regional_boxplot(data, output_dir):
    """Plot 4: Regional boxplot of NSE by HUC-02 region"""
    fig, ax = plt.subplots(figsize=(14, 6))
    
    # Extract HUC-02 region from basin ID (first 2 digits)
    data['huc02'] = data['basin'].str[:2]
    
    # Get regions with data
    regions = sorted(data['huc02'].unique())
    
    # Create boxplot data
    boxplot_data = [data[data['huc02'] == r]['NSE'].values for r in regions]
    
    # Create boxplot
    bp = ax.boxplot(boxplot_data, labels=regions, patch_artist=True)
    
    # Color boxes
    colors = plt.cm.tab20(np.linspace(0, 1, len(regions)))
    for patch, color in zip(bp['boxes'], colors):
        patch.set_facecolor(color)
        patch.set_alpha(0.7)
    
    # Add reference line
    ax.axhline(y=0.7, color='red', linestyle='--', linewidth=1, label='NSE = 0.7')
    ax.axhline(y=data['NSE'].median(), color='blue', linestyle='-', linewidth=1.5, label=f'Overall Median = {data["NSE"].median():.3f}')
    
    ax.set_xlabel('HUC-02 Region')
    ax.set_ylabel('Test NSE')
    ax.set_title('Test NSE Distribution by HUC-02 Hydrologic Region')
    ax.legend(loc='lower right')
    ax.set_ylim(-1.5, 1.1)
    
    # Add count per region
    for i, r in enumerate(regions):
        count = len(data[data['huc02'] == r])
        ax.text(i + 1, -1.4, f'n={count}', ha='center', fontsize=8)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'fig8_regional_boxplot.png')
    plt.savefig(output_dir / 'fig8_regional_boxplot.pdf')
    print(f"Saved: fig8_regional_boxplot.png/pdf")
    plt.close()

def plot_test_summary(data, output_dir):
    """Plot: Test results summary with key metrics"""
    fig, axes = plt.subplots(1, 3, figsize=(15, 5))
    
    # 1. CDF plot
    ax1 = axes[0]
    sorted_nse = np.sort(data['NSE'].values)
    cdf = np.arange(1, len(sorted_nse) + 1) / len(sorted_nse)
    ax1.plot(sorted_nse, cdf, color='#2E86AB', linewidth=2)
    ax1.axvline(x=0.7, color='red', linestyle='--', label='NSE = 0.7')
    ax1.axvline(x=data['NSE'].median(), color='green', linestyle='-', linewidth=2, 
                label=f'Median = {data["NSE"].median():.3f}')
    ax1.axhline(y=0.5, color='gray', linestyle=':', alpha=0.5)
    ax1.set_xlabel('Test NSE')
    ax1.set_ylabel('Cumulative Probability')
    ax1.set_title('(a) CDF of Test NSE')
    ax1.set_xlim(-0.5, 1)
    ax1.legend(loc='upper left')
    ax1.grid(True, alpha=0.3)
    
    # 2. Top/Bottom basins
    ax2 = axes[1]
    top10 = data.nlargest(10, 'NSE')[['basin', 'NSE']]
    bottom10 = data.nsmallest(10, 'NSE')[['basin', 'NSE']]
    
    y_pos = np.arange(10)
    ax2.barh(y_pos + 0.2, top10['NSE'].values, height=0.35, color='#1a9850', label='Top 10')
    ax2.barh(y_pos - 0.2, bottom10['NSE'].values, height=0.35, color='#d73027', label='Bottom 10')
    
    # Add basin labels
    for i, (t_basin, t_nse) in enumerate(zip(top10['basin'], top10['NSE'])):
        ax2.text(t_nse + 0.02, i + 0.2, f'{t_basin}', va='center', fontsize=8)
    for i, (b_basin, b_nse) in enumerate(zip(bottom10['basin'], bottom10['NSE'])):
        ax2.text(max(b_nse, -0.3) + 0.02, i - 0.2, f'{b_basin}', va='center', fontsize=8)
    
    ax2.axvline(x=0, color='black', linewidth=0.5)
    ax2.set_xlabel('Test NSE')
    ax2.set_ylabel('Basin Rank')
    ax2.set_title('(b) Top 10 vs Bottom 10 Basins')
    ax2.set_xlim(-1.8, 1.1)
    ax2.legend(loc='lower right')
    
    # 3. Performance pie chart
    ax3 = axes[2]
    categories = ['Excellent\n(>=0.8)', 'Good\n(0.7-0.8)', 'Acceptable\n(0.5-0.7)', 
                  'Poor\n(0-0.5)', 'Unsatisfactory\n(<0)']
    counts = [
        (data['NSE'] >= 0.8).sum(),
        ((data['NSE'] >= 0.7) & (data['NSE'] < 0.8)).sum(),
        ((data['NSE'] >= 0.5) & (data['NSE'] < 0.7)).sum(),
        ((data['NSE'] >= 0) & (data['NSE'] < 0.5)).sum(),
        (data['NSE'] < 0).sum()
    ]
    colors = ['#1a9850', '#91cf60', '#fee08b', '#fc8d59', '#d73027']
    
    wedges, texts, autotexts = ax3.pie(counts, labels=categories, autopct='%1.1f%%',
                                        colors=colors, startangle=90,
                                        textprops={'fontsize': 9})
    ax3.set_title('(c) Performance Distribution')
    
    # Add center text
    centre_circle = plt.Circle((0, 0), 0.5, fc='white')
    ax3.add_patch(centre_circle)
    ax3.text(0, 0, f'n=531\nMedian\n{data["NSE"].median():.3f}', 
             ha='center', va='center', fontsize=11, fontweight='bold')
    
    plt.suptitle('CUDA-LSTM Test Results Summary (Epoch 20)', fontsize=14, fontweight='bold', y=1.02)
    plt.tight_layout()
    plt.savefig(output_dir / 'fig9_test_summary.png')
    plt.savefig(output_dir / 'fig9_test_summary.pdf')
    print(f"Saved: fig9_test_summary.png/pdf")
    plt.close()

def main():
    project_root = Path(__file__).parent.parent
    # Store figures in the Project B documentation folder (single source of truth)
    output_dir = project_root / 'docs' / 'projects' / 'project_b_full531' / 'results'
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print("Loading data...")
    data = load_data(project_root)
    print(f"Loaded {len(data)} basins with coordinates")
    print(f"NSE range: [{data['NSE'].min():.3f}, {data['NSE'].max():.3f}]")
    print(f"Median NSE: {data['NSE'].median():.3f}")
    print("-" * 50)
    
    # Generate plots
    plot_spatial_nse(data, output_dir)
    plot_spatial_categories(data, output_dir)
    plot_nse_histogram(data, output_dir)
    plot_regional_boxplot(data, output_dir)
    plot_test_summary(data, output_dir)  # NEW: Test summary figure
    
    print("-" * 50)
    print(f"All spatial figures saved to: {output_dir}")

if __name__ == '__main__':
    main()

