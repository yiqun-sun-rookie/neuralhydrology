"""
Generate publication-ready plots for CUDA-LSTM baseline (reproduce_531_nse074)
"""
import re
import matplotlib.pyplot as plt
import numpy as np
from pathlib import Path

# Set style for publication
plt.style.use('seaborn-v0_8-whitegrid')
plt.rcParams.update({
    'font.family': 'DejaVu Sans',
    'font.size': 12,
    'axes.titlesize': 14,
    'axes.labelsize': 12,
    'xtick.labelsize': 10,
    'ytick.labelsize': 10,
    'legend.fontsize': 10,
    'figure.dpi': 150,
    'savefig.dpi': 300,
    'savefig.bbox': 'tight',
    'axes.spines.top': False,
    'axes.spines.right': False,
})

# Color palette
COLORS = {
    'train': '#2E86AB',      # Blue
    'val': '#E94F37',        # Red  
    'nse': '#1B998B',        # Teal
    'highlight': '#F4A261',  # Orange
}

def parse_log(log_path):
    """Parse training log to extract metrics"""
    epochs = []
    train_loss = []
    val_loss = []
    val_nse = []
    
    with open(log_path, 'r') as f:
        content = f.read()
    
    # Parse training loss
    train_pattern = r'Epoch (\d+) average loss: avg_loss: ([\d.]+)'
    for match in re.finditer(train_pattern, content):
        epoch = int(match.group(1))
        loss = float(match.group(2))
        epochs.append(epoch)
        train_loss.append(loss)
    
    # Parse validation metrics
    val_pattern = r'Epoch (\d+) average validation loss: ([\d.]+) -- Median validation metrics: avg_loss: [\d.]+, NSE: ([\d.]+)'
    val_epochs = []
    for match in re.finditer(val_pattern, content):
        epoch = int(match.group(1))
        v_loss = float(match.group(2))
        nse = float(match.group(3))
        val_epochs.append(epoch)
        val_loss.append(v_loss)
        val_nse.append(nse)
    
    return {
        'epochs': epochs,
        'train_loss': train_loss,
        'val_epochs': val_epochs,
        'val_loss': val_loss,
        'val_nse': val_nse,
    }

def plot_training_curves(data, output_dir):
    """Plot 1: Training and Validation Loss"""
    fig, ax = plt.subplots(figsize=(10, 6))
    
    ax.plot(data['epochs'], data['train_loss'], 
            color=COLORS['train'], linewidth=2, label='Training Loss', marker='o', markersize=4)
    ax.plot(data['val_epochs'], data['val_loss'], 
            color=COLORS['val'], linewidth=2, label='Validation Loss', marker='s', markersize=5)
    
    ax.set_xlabel('Epoch')
    ax.set_ylabel('NSE Loss')
    ax.set_title('CUDA-LSTM Training Progress (531 Basins)')
    ax.legend(loc='upper right')
    ax.set_xlim(0, 31)
    
    # Add learning rate change annotations
    ax.axvline(x=10, color='gray', linestyle='--', alpha=0.5, linewidth=1)
    ax.axvline(x=20, color='gray', linestyle='--', alpha=0.5, linewidth=1)
    ax.text(10.5, ax.get_ylim()[1]*0.95, 'LR: 0.001', fontsize=9, color='gray')
    ax.text(20.5, ax.get_ylim()[1]*0.95, 'LR: 0.0005', fontsize=9, color='gray')
    
    plt.tight_layout()
    plt.savefig(output_dir / 'fig1_training_loss.png')
    plt.savefig(output_dir / 'fig1_training_loss.pdf')
    print(f"Saved: fig1_training_loss.png/pdf")
    plt.close()

def plot_nse_curve(data, output_dir):
    """Plot 2: Validation NSE over epochs"""
    fig, ax = plt.subplots(figsize=(10, 6))
    
    ax.plot(data['val_epochs'], data['val_nse'], 
            color=COLORS['nse'], linewidth=2.5, marker='o', markersize=6)
    
    # Highlight best epoch
    best_idx = np.argmax(data['val_nse'])
    best_epoch = data['val_epochs'][best_idx]
    best_nse = data['val_nse'][best_idx]
    
    ax.scatter([best_epoch], [best_nse], color=COLORS['highlight'], 
               s=150, zorder=5, edgecolors='black', linewidths=1.5)
    ax.annotate(f'Best: NSE={best_nse:.3f}\n(Epoch {best_epoch})', 
                xy=(best_epoch, best_nse), 
                xytext=(best_epoch+3, best_nse-0.02),
                fontsize=11, fontweight='bold',
                arrowprops=dict(arrowstyle='->', color='black', lw=1.5))
    
    ax.set_xlabel('Epoch')
    ax.set_ylabel('Median Validation NSE')
    ax.set_title('CUDA-LSTM Validation Performance (531 Basins)')
    ax.set_xlim(0, 31)
    ax.set_ylim(0.6, 0.78)
    
    # Add horizontal reference lines
    ax.axhline(y=0.7, color='gray', linestyle=':', alpha=0.5)
    ax.text(1, 0.702, 'NSE = 0.7', fontsize=9, color='gray')
    
    plt.tight_layout()
    plt.savefig(output_dir / 'fig2_validation_nse.png')
    plt.savefig(output_dir / 'fig2_validation_nse.pdf')
    print(f"Saved: fig2_validation_nse.png/pdf")
    plt.close()

def plot_combined(data, output_dir):
    """Plot 3: Combined dual-axis plot"""
    fig, ax1 = plt.subplots(figsize=(12, 6))
    
    # Loss on left axis
    ln1 = ax1.plot(data['epochs'], data['train_loss'], 
                   color=COLORS['train'], linewidth=2, label='Training Loss', alpha=0.8)
    ln2 = ax1.plot(data['val_epochs'], data['val_loss'], 
                   color=COLORS['val'], linewidth=2, label='Validation Loss', alpha=0.8)
    ax1.set_xlabel('Epoch')
    ax1.set_ylabel('NSE Loss', color='black')
    ax1.tick_params(axis='y', labelcolor='black')
    ax1.set_xlim(0, 31)
    
    # NSE on right axis
    ax2 = ax1.twinx()
    ln3 = ax2.plot(data['val_epochs'], data['val_nse'], 
                   color=COLORS['nse'], linewidth=2.5, label='Validation NSE', 
                   marker='D', markersize=5)
    ax2.set_ylabel('Median Validation NSE', color=COLORS['nse'])
    ax2.tick_params(axis='y', labelcolor=COLORS['nse'])
    ax2.set_ylim(0.55, 0.80)
    
    # Highlight best
    best_idx = np.argmax(data['val_nse'])
    best_epoch = data['val_epochs'][best_idx]
    best_nse = data['val_nse'][best_idx]
    ax2.scatter([best_epoch], [best_nse], color=COLORS['highlight'], 
                s=120, zorder=5, edgecolors='black', linewidths=1.5)
    
    # Combined legend
    lns = ln1 + ln2 + ln3
    labs = [l.get_label() for l in lns]
    ax1.legend(lns, labs, loc='center right')
    
    ax1.set_title('CUDA-LSTM Training Overview (531 CAMELS-US Basins)')
    
    # Learning rate annotations
    ax1.axvline(x=10, color='gray', linestyle='--', alpha=0.4, linewidth=1)
    ax1.axvline(x=20, color='gray', linestyle='--', alpha=0.4, linewidth=1)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'fig3_combined_overview.png')
    plt.savefig(output_dir / 'fig3_combined_overview.pdf')
    print(f"Saved: fig3_combined_overview.png/pdf")
    plt.close()

def plot_loss_bar(data, output_dir):
    """Plot 4: Final epoch comparison bar chart"""
    fig, ax = plt.subplots(figsize=(8, 5))
    
    metrics = ['Train Loss\n(Epoch 30)', 'Val Loss\n(Epoch 30)', 'Best Val NSE\n(Epoch 22)']
    values = [data['train_loss'][-1], data['val_loss'][-1], max(data['val_nse'])]
    colors = [COLORS['train'], COLORS['val'], COLORS['nse']]
    
    bars = ax.bar(metrics, values, color=colors, edgecolor='black', linewidth=1.2)
    
    # Add value labels on bars
    for bar, val in zip(bars, values):
        height = bar.get_height()
        ax.text(bar.get_x() + bar.get_width()/2., height + 0.01,
                f'{val:.4f}', ha='center', va='bottom', fontsize=11, fontweight='bold')
    
    ax.set_ylabel('Value')
    ax.set_title('CUDA-LSTM Final Performance Metrics')
    ax.set_ylim(0, max(values) * 1.15)
    
    plt.tight_layout()
    plt.savefig(output_dir / 'fig4_final_metrics.png')
    plt.savefig(output_dir / 'fig4_final_metrics.pdf')
    print(f"Saved: fig4_final_metrics.png/pdf")
    plt.close()

def main():
    # Paths
    project_root = Path(__file__).parent.parent
    log_path = project_root / 'runs' / 'reproduce_531_nse074_2025_1129_2145_ep30' / 'output.log'
    # Store figures in the Project B documentation folder (single source of truth)
    output_dir = project_root / 'docs' / 'projects' / 'project_b_full531' / 'results'
    output_dir.mkdir(parents=True, exist_ok=True)
    
    print(f"Reading log: {log_path}")
    print(f"Output dir: {output_dir}")
    print("-" * 50)
    
    # Parse and plot
    data = parse_log(log_path)
    
    print(f"Parsed {len(data['epochs'])} training epochs")
    print(f"Parsed {len(data['val_epochs'])} validation epochs")
    print(f"Best validation NSE: {max(data['val_nse']):.4f} at epoch {data['val_epochs'][np.argmax(data['val_nse'])]}")
    print("-" * 50)
    
    # Generate all plots
    plot_training_curves(data, output_dir)
    plot_nse_curve(data, output_dir)
    plot_combined(data, output_dir)
    plot_loss_bar(data, output_dir)
    
    print("-" * 50)
    print(f"All figures saved to: {output_dir}")

if __name__ == '__main__':
    main()

