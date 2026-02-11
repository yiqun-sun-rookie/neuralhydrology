#!/usr/bin/env python3
"""
Mamba vs LSTM Performance Analysis Script

This script analyzes and compares results from Mamba and LSTM experiments
on CAMELS-H hourly data.

Usage:
    python src/mamba_camelsh/scripts/analyze_results.py \
        --mamba_results results/03_mamba_camelsh/camelsh_mamba_mini_benchmark \
        --lstm_results results/03_mamba_camelsh/camelsh_lstm_mini_benchmark_*
"""

import argparse
import json
import os
from pathlib import Path
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from scipy import stats

# Set style
sns.set_style("whitegrid")
plt.rcParams['figure.figsize'] = (12, 8)
plt.rcParams['font.size'] = 12


def load_metrics(run_dir):
    """Load metrics from a NeuralHydrology run directory."""
    metrics_file = Path(run_dir) / "metrics" / "test" / "model_metrics.json"
    
    if not metrics_file.exists():
        print(f"Warning: {metrics_file} not found")
        return None
    
    with open(metrics_file, 'r') as f:
        metrics = json.load(f)
    
    return metrics


def extract_basin_metrics(run_dir):
    """Extract per-basin metrics from test results."""
    test_dir = Path(run_dir) / "test"
    
    if not test_dir.exists():
        print(f"Warning: {test_dir} not found")
        return None
    
    basin_metrics = []
    
    # Look for basin-specific result files
    for basin_file in test_dir.glob("*.csv"):
        basin_id = basin_file.stem
        df = pd.read_csv(basin_file)
        
        # Calculate metrics if not present
        if 'NSE' not in df.columns:
            # Calculate NSE and KGE from predictions
            # This is a placeholder - adjust based on actual file format
            continue
        
        metrics = {
            'basin_id': basin_id,
            'NSE': df['NSE'].iloc[0] if 'NSE' in df.columns else np.nan,
            'KGE': df['KGE'].iloc[0] if 'KGE' in df.columns else np.nan,
        }
        basin_metrics.append(metrics)
    
    if not basin_metrics:
        # Try alternative: read from summary file
        summary_file = test_dir / "model_metrics.json"
        if summary_file.exists():
            with open(summary_file, 'r') as f:
                summary = json.load(f)
                # Extract per-basin if available
                pass
    
    return pd.DataFrame(basin_metrics) if basin_metrics else None


def compare_models(mamba_results, lstm_results, output_dir):
    """Compare Mamba and LSTM results."""
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Load metrics
    mamba_metrics = load_metrics(mamba_results)
    lstm_metrics = load_metrics(lstm_results)
    
    # Extract per-basin metrics
    mamba_basins = extract_basin_metrics(mamba_results)
    lstm_basins = extract_basin_metrics(lstm_results)
    
    # Create comparison table
    comparison = {
        'Model': ['Mamba', 'LSTM'],
        'Mean NSE': [
            mamba_metrics.get('NSE', {}).get('mean', np.nan) if mamba_metrics else np.nan,
            lstm_metrics.get('NSE', {}).get('mean', np.nan) if lstm_metrics else np.nan,
        ],
        'Median NSE': [
            mamba_metrics.get('NSE', {}).get('median', np.nan) if mamba_metrics else np.nan,
            lstm_metrics.get('NSE', {}).get('median', np.nan) if lstm_metrics else np.nan,
        ],
        'Mean KGE': [
            mamba_metrics.get('KGE', {}).get('mean', np.nan) if mamba_metrics else np.nan,
            lstm_metrics.get('KGE', {}).get('mean', np.nan) if lstm_metrics else np.nan,
        ],
    }
    
    comparison_df = pd.DataFrame(comparison)
    comparison_df.to_csv(output_dir / "model_comparison.csv", index=False)
    print("\nModel Comparison:")
    print(comparison_df.to_string(index=False))
    
    # Statistical test (if per-basin data available)
    if mamba_basins is not None and lstm_basins is not None:
        # Merge on basin_id
        merged = mamba_basins.merge(
            lstm_basins, 
            on='basin_id', 
            suffixes=('_mamba', '_lstm')
        )
        
        # Paired t-test for NSE
        if 'NSE_mamba' in merged.columns and 'NSE_lstm' in merged.columns:
            t_stat, p_value = stats.ttest_rel(
                merged['NSE_mamba'].dropna(),
                merged['NSE_lstm'].dropna()
            )
            print(f"\nPaired t-test (NSE):")
            print(f"  t-statistic: {t_stat:.4f}")
            print(f"  p-value: {p_value:.4f}")
            print(f"  Significant: {'Yes' if p_value < 0.05 else 'No'}")
        
        # Create comparison plots
        create_comparison_plots(merged, output_dir)
    
    return comparison_df


def create_comparison_plots(merged_df, output_dir):
    """Create visualization plots."""
    # 1. Scatter plot: Mamba vs LSTM NSE
    fig, axes = plt.subplots(1, 2, figsize=(14, 6))
    
    # NSE scatter
    axes[0].scatter(merged_df['NSE_lstm'], merged_df['NSE_mamba'], alpha=0.6)
    axes[0].plot([0, 1], [0, 1], 'r--', label='1:1 line')
    axes[0].set_xlabel('LSTM NSE')
    axes[0].set_ylabel('Mamba NSE')
    axes[0].set_title('NSE Comparison: Mamba vs LSTM')
    axes[0].legend()
    axes[0].grid(True, alpha=0.3)
    
    # KGE scatter
    axes[1].scatter(merged_df['KGE_lstm'], merged_df['KGE_mamba'], alpha=0.6)
    axes[1].plot([0, 1], [0, 1], 'r--', label='1:1 line')
    axes[1].set_xlabel('LSTM KGE')
    axes[1].set_ylabel('Mamba KGE')
    axes[1].set_title('KGE Comparison: Mamba vs LSTM')
    axes[1].legend()
    axes[1].grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(output_dir / "mamba_vs_lstm_scatter.png", dpi=300, bbox_inches='tight')
    plt.close()
    
    # 2. Box plot comparison
    fig, axes = plt.subplots(1, 2, figsize=(14, 6))
    
    # NSE box plot
    data_nse = [merged_df['NSE_lstm'].dropna(), merged_df['NSE_mamba'].dropna()]
    axes[0].boxplot(data_nse, labels=['LSTM', 'Mamba'])
    axes[0].set_ylabel('NSE')
    axes[0].set_title('NSE Distribution Comparison')
    axes[0].grid(True, alpha=0.3)
    
    # KGE box plot
    data_kge = [merged_df['KGE_lstm'].dropna(), merged_df['KGE_mamba'].dropna()]
    axes[1].boxplot(data_kge, labels=['LSTM', 'Mamba'])
    axes[1].set_ylabel('KGE')
    axes[1].set_title('KGE Distribution Comparison')
    axes[1].grid(True, alpha=0.3)
    
    plt.tight_layout()
    plt.savefig(output_dir / "mamba_vs_lstm_boxplot.png", dpi=300, bbox_inches='tight')
    plt.close()
    
    print(f"\nPlots saved to {output_dir}")


def main():
    parser = argparse.ArgumentParser(
        description="Analyze and compare Mamba vs LSTM results"
    )
    parser.add_argument(
        "--mamba_results",
        type=str,
        required=True,
        help="Path to Mamba experiment results directory"
    )
    parser.add_argument(
        "--lstm_results",
        type=str,
        required=True,
        help="Path to LSTM experiment results directory"
    )
    parser.add_argument(
        "--output_dir",
        type=str,
        default="results/03_mamba_camelsh/analysis",
        help="Output directory for analysis results"
    )
    
    args = parser.parse_args()
    
    print("=" * 60)
    print("Mamba vs LSTM Performance Analysis")
    print("=" * 60)
    print(f"Mamba results: {args.mamba_results}")
    print(f"LSTM results: {args.lstm_results}")
    print(f"Output directory: {args.output_dir}")
    print("=" * 60)
    
    comparison_df = compare_models(
        args.mamba_results,
        args.lstm_results,
        args.output_dir
    )
    
    print("\nAnalysis complete!")


if __name__ == "__main__":
    main()
