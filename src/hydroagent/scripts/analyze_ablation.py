"""Ablation analysis script for HydroAgent Paper 3.

Loads summary.csv files from multiple ablation runs, computes pivot tables,
and performs Wilcoxon signed-rank tests vs the 'full' variant.

Usage:
    python src/hydroagent/scripts/analyze_ablation.py --results-dir results/07_hydroagent
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Dict, List, Optional

import numpy as np
import pandas as pd

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))


def load_all_summaries(results_dir: Path) -> pd.DataFrame:
    """Glob all summary.csv files under results_dir and merge into one DataFrame."""
    csv_files = list(results_dir.rglob('summary.csv'))
    if not csv_files:
        raise FileNotFoundError(f"No summary.csv files found under {results_dir}")

    frames = []
    for f in csv_files:
        df = pd.read_csv(f)
        df['source_file'] = str(f)
        frames.append(df)

    merged = pd.concat(frames, ignore_index=True)
    # Deduplicate: keep last run per (basin_id, backend, ablation)
    if 'ablation' in merged.columns:
        merged = merged.drop_duplicates(
            subset=['basin_id', 'backend', 'ablation'], keep='last'
        )
    return merged


def compute_ablation_table(df: pd.DataFrame) -> pd.DataFrame:
    """Create pivot table: ablation variant × basin → NSE.

    Returns a DataFrame with ablation variants as rows and basin IDs as columns.
    """
    if 'ablation' not in df.columns or df['ablation'].isna().all():
        print("Warning: No ablation column found. Returning raw data.")
        return df

    pivot = df.pivot_table(
        index='ablation', columns='basin_id', values='best_nse', aggfunc='mean'
    )
    # Add mean column
    pivot['mean_NSE'] = pivot.mean(axis=1)
    pivot = pivot.sort_values('mean_NSE', ascending=False)
    return pivot


def statistical_tests(df: pd.DataFrame, baseline: str = 'full') -> pd.DataFrame:
    """Wilcoxon signed-rank test for each ablation variant vs baseline.

    Returns DataFrame with columns: variant, mean_nse, delta_nse, p_value, n_basins.
    """
    from scipy.stats import wilcoxon

    if 'ablation' not in df.columns:
        return pd.DataFrame()

    variants = [v for v in df['ablation'].unique() if v != baseline and pd.notna(v) and v != '']
    base_df = df[df['ablation'] == baseline].set_index('basin_id')['best_nse']

    rows = []
    for variant in variants:
        var_df = df[df['ablation'] == variant].set_index('basin_id')['best_nse']
        common = base_df.index.intersection(var_df.index)
        if len(common) < 5:
            rows.append({
                'variant': variant,
                'mean_nse': var_df.mean(),
                'delta_nse': float('nan'),
                'p_value': float('nan'),
                'n_basins': len(common),
            })
            continue

        base_vals = base_df.loc[common].values
        var_vals = var_df.loc[common].values

        # Filter pairs where both are finite
        mask = np.isfinite(base_vals) & np.isfinite(var_vals)
        b = base_vals[mask]
        v = var_vals[mask]

        if len(b) < 5:
            p_val = float('nan')
        else:
            try:
                _, p_val = wilcoxon(b, v)
            except ValueError:
                p_val = float('nan')

        rows.append({
            'variant': variant,
            'mean_nse': float(np.nanmean(var_vals)),
            'delta_nse': float(np.nanmean(var_vals) - np.nanmean(base_vals)),
            'p_value': float(p_val),
            'n_basins': int(np.sum(mask)),
        })

    result = pd.DataFrame(rows)
    if not result.empty:
        result = result.sort_values('delta_nse', ascending=False)
    return result


def print_paper_table(pivot: pd.DataFrame, stats: pd.DataFrame):
    """Print formatted Table 2 for the paper."""
    print("\n" + "=" * 80)
    print("Table 2: Ablation Study — NSE by Variant")
    print("=" * 80)

    if not pivot.empty:
        print(pivot.round(4).to_string())

    if not stats.empty:
        print("\n--- Statistical Significance (vs 'full') ---")
        print(stats.round(4).to_string(index=False))
    print()


def main():
    parser = argparse.ArgumentParser(description='Analyze HydroAgent ablation experiments')
    parser.add_argument('--results-dir', type=str, default='results/07_hydroagent',
                        help='Root directory containing summary.csv files')
    parser.add_argument('--output', type=str, default=None,
                        help='Output CSV path for the ablation table')
    args = parser.parse_args()

    results_dir = Path(args.results_dir)
    print(f"Loading summaries from {results_dir}...")

    df = load_all_summaries(results_dir)
    print(f"Loaded {len(df)} experiment rows from {df['source_file'].nunique()} files")

    pivot = compute_ablation_table(df)
    stats = statistical_tests(df)
    print_paper_table(pivot, stats)

    if args.output:
        out_path = Path(args.output)
        pivot.to_csv(out_path)
        print(f"Ablation table saved to {out_path}")

        stats_path = out_path.parent / (out_path.stem + '_stats.csv')
        stats.to_csv(stats_path, index=False)
        print(f"Statistical tests saved to {stats_path}")


if __name__ == '__main__':
    main()
