"""Component usage analysis for HydroAgent experiment results.

Scans basin experiment directories, identifies the best iteration (highest
calib NSE), extracts which SuperflexPy components were used in that
structure, and outputs:
  - component_frequency.csv   (basin x component matrix)
  - component_heatmap.png     (visual heatmap)
  - summary print to stdout

Usage:
    python src/hydroagent/scripts/analyze_structures.py \
        --results-dir results/07_hydroagent/v2_split_deepseek
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

import matplotlib
matplotlib.use('Agg')  # non-interactive backend
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

# ---------------------------------------------------------------------------
# Full component and lag registries (mirrors environment.py)
# ---------------------------------------------------------------------------

ALL_COMPONENTS: List[str] = [
    'UnsaturatedReservoir',
    'UpperZone',
    'ProductionStore',
    'InterceptionFilter',
    'SnowReservoir',
    'PowerReservoir',
    'LinearReservoir',
    'RoutingStore',
    'DeepGroundwater',
    'ConveyanceLoss',
    'InterceptionBucket',
    'ThresholdReservoir',
    'PercolationStore',
    'SaturationAreaStore',
]

ALL_LAGS: List[str] = [
    'HalfTriangularLag',
    'UnitHydrograph1',
    'UnitHydrograph2',
]

ALL_TYPES: List[str] = ALL_COMPONENTS + ALL_LAGS


# ---------------------------------------------------------------------------
# Data loading helpers
# ---------------------------------------------------------------------------


def _load_iterations(basin_dir: Path) -> Optional[pd.DataFrame]:
    """Load iterations.csv from a basin experiment directory."""
    csv_path = basin_dir / 'iterations.csv'
    if not csv_path.exists():
        return None
    try:
        df = pd.read_csv(csv_path)
        return df
    except Exception:
        return None


def _load_structures(basin_dir: Path) -> Dict[int, Dict[str, Any]]:
    """Load structures.jsonl — returns dict keyed by iteration number."""
    jsonl_path = basin_dir / 'structures.jsonl'
    if not jsonl_path.exists():
        return {}
    result: Dict[int, Dict[str, Any]] = {}
    with open(jsonl_path, 'r', encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                it_num = record['iteration']
                result[it_num] = record['structure']
            except (json.JSONDecodeError, KeyError):
                continue
    return result


def _load_meta(basin_dir: Path) -> Optional[Dict[str, Any]]:
    """Load meta.json from a basin experiment directory."""
    meta_path = basin_dir / 'meta.json'
    if not meta_path.exists():
        return None
    try:
        with open(meta_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception:
        return None


def _extract_basin_id(dirname: str) -> str:
    """Extract the basin ID (first token before '_') from directory name.

    Example: '01022500_deepseek_default_20260308_220718' -> '01022500'
    """
    return dirname.split('_')[0]


def _extract_components(structure: Dict[str, Any]) -> Set[str]:
    """Extract the set of component type names from a structure dict.

    Includes both layer types and lag function types.
    """
    types: Set[str] = set()
    for layer in structure.get('layers', []):
        ltype = layer.get('type', '')
        if ltype:
            types.add(ltype)
    for lag in structure.get('lag_functions', []):
        ltype = lag.get('type', '')
        if ltype:
            types.add(ltype)
    return types


# ---------------------------------------------------------------------------
# Main analysis
# ---------------------------------------------------------------------------


def analyze_results(results_dir: Path) -> Tuple[pd.DataFrame, pd.DataFrame]:
    """Scan basin subdirectories and extract component usage for best iteration.

    Returns:
        (detail_df, summary_df) where:
        - detail_df: columns [basin_id, component_type, used] — one row per
          basin x component combination
        - summary_df: columns [basin_id, best_iteration, best_nse, converged,
          model_name, components_used] — one row per basin
    """
    detail_rows: List[Dict[str, Any]] = []
    summary_rows: List[Dict[str, Any]] = []

    # Discover basin subdirectories (skip files like summary.csv)
    subdirs = sorted([
        d for d in results_dir.iterdir()
        if d.is_dir() and (d / 'iterations.csv').exists()
    ])

    if not subdirs:
        print(f"No basin experiment directories found in {results_dir}")
        return pd.DataFrame(), pd.DataFrame()

    for basin_dir in subdirs:
        dirname = basin_dir.name
        basin_id = _extract_basin_id(dirname)

        # Load data
        iter_df = _load_iterations(basin_dir)
        structures = _load_structures(basin_dir)
        meta = _load_meta(basin_dir)

        if iter_df is None or iter_df.empty:
            print(f"  [SKIP] {basin_id}: no iterations.csv data")
            continue

        # Find best iteration (highest NSE in calib)
        best_idx = iter_df['NSE'].idxmax()
        best_row = iter_df.loc[best_idx]
        best_iter = int(best_row['iteration'])
        best_nse = float(best_row['NSE'])
        model_name = str(best_row.get('model_name', ''))

        converged = meta.get('converged', False) if meta else False

        # Get the structure for the best iteration
        if best_iter not in structures:
            print(f"  [WARN] {basin_id}: best iteration {best_iter} not in structures.jsonl")
            continue

        best_structure = structures[best_iter]
        used_components = _extract_components(best_structure)

        # Build detail rows (one per component type)
        for comp in ALL_TYPES:
            detail_rows.append({
                'basin_id': basin_id,
                'component_type': comp,
                'used': 1 if comp in used_components else 0,
            })

        # Build summary row
        summary_rows.append({
            'basin_id': basin_id,
            'best_iteration': best_iter,
            'best_nse': round(best_nse, 4),
            'converged': converged,
            'model_name': model_name,
            'components_used': ', '.join(sorted(used_components)),
        })

    detail_df = pd.DataFrame(detail_rows)
    summary_df = pd.DataFrame(summary_rows)
    return detail_df, summary_df


def print_summary(summary_df: pd.DataFrame):
    """Print a human-readable summary table to stdout."""
    if summary_df.empty:
        print("No results to display.")
        return

    print("\n" + "=" * 100)
    print("COMPONENT USAGE SUMMARY (best iteration per basin)")
    print("=" * 100)

    header = f"{'Basin':<12} {'Iter':>4} {'NSE':>8} {'Conv':>5} {'Model':<25} {'Components'}"
    print(header)
    print("-" * 100)

    for _, row in summary_df.iterrows():
        nse_str = f"{row['best_nse']:.4f}"
        conv_str = 'Y' if row['converged'] else 'N'
        model_str = (row['model_name'] or '')[:25]
        comp_str = row['components_used']
        print(f"{row['basin_id']:<12} {row['best_iteration']:>4} {nse_str:>8} "
              f"{conv_str:>5} {model_str:<25} {comp_str}")

    print("-" * 100)

    # Component frequency summary
    print("\nCOMPONENT FREQUENCY:")
    n_basins = len(summary_df)
    for comp in ALL_TYPES:
        count = sum(1 for _, r in summary_df.iterrows() if comp in r['components_used'].split(', '))
        if count > 0:
            pct = 100.0 * count / n_basins
            bar = '#' * int(pct / 2)
            print(f"  {comp:<25} {count:>3}/{n_basins}  ({pct:5.1f}%)  {bar}")

    # Components never used
    never_used = [comp for comp in ALL_TYPES
                  if not any(comp in r['components_used'] for _, r in summary_df.iterrows())]
    if never_used:
        print(f"\n  Never used: {', '.join(never_used)}")


def plot_heatmap(detail_df: pd.DataFrame, output_path: Path):
    """Create and save a heatmap of component usage across basins."""
    if detail_df.empty:
        print("No data for heatmap.")
        return

    # Pivot to matrix: basins (rows) x components (columns)
    pivot = detail_df.pivot_table(
        index='basin_id', columns='component_type', values='used', aggfunc='max'
    )
    # Reorder columns to match ALL_TYPES ordering (only those present)
    ordered_cols = [c for c in ALL_TYPES if c in pivot.columns]
    pivot = pivot[ordered_cols]

    # Drop columns that are all zeros (never used by any basin)
    used_cols = pivot.columns[pivot.sum(axis=0) > 0].tolist()
    # Keep unused ones too but at the end, dimmed — actually just show all for completeness
    # but let's at least order used-first
    unused_cols = [c for c in ordered_cols if c not in used_cols]
    pivot = pivot[used_cols + unused_cols]

    fig, ax = plt.subplots(figsize=(max(10, len(pivot.columns) * 0.7), max(6, len(pivot) * 0.4)))

    # Color map: 0=white, 1=colored
    cmap = matplotlib.colormaps.get_cmap('YlOrRd').resampled(2)
    im = ax.imshow(pivot.values, cmap=cmap, aspect='auto', vmin=0, vmax=1, interpolation='nearest')

    # Labels
    ax.set_xticks(range(len(pivot.columns)))
    ax.set_xticklabels(pivot.columns, rotation=45, ha='right', fontsize=9)
    ax.set_yticks(range(len(pivot.index)))
    ax.set_yticklabels(pivot.index, fontsize=9)

    ax.set_xlabel('Component Type', fontsize=11)
    ax.set_ylabel('Basin ID', fontsize=11)
    ax.set_title('Component Usage in Best Iteration per Basin', fontsize=13, fontweight='bold')

    # Add text annotations (1 or 0)
    for i in range(len(pivot.index)):
        for j in range(len(pivot.columns)):
            val = int(pivot.values[i, j])
            color = 'white' if val == 1 else 'lightgray'
            ax.text(j, i, str(val), ha='center', va='center', fontsize=8, color=color)

    # Grid lines
    ax.set_xticks(np.arange(-0.5, len(pivot.columns), 1), minor=True)
    ax.set_yticks(np.arange(-0.5, len(pivot.index), 1), minor=True)
    ax.grid(which='minor', color='white', linewidth=1.5)
    ax.tick_params(which='minor', size=0)

    # Colorbar
    cbar = plt.colorbar(im, ax=ax, shrink=0.6, ticks=[0, 1])
    cbar.set_ticklabels(['Not used', 'Used'])

    plt.tight_layout()
    fig.savefig(output_path, dpi=150, bbox_inches='tight')
    plt.close(fig)
    print(f"\nHeatmap saved to {output_path}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(
        description='Analyze component usage in HydroAgent experiment results',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument('--results-dir', type=str,
                        default='results/07_hydroagent/v2_split_deepseek',
                        help='Directory containing basin experiment subdirs '
                             '(default: results/07_hydroagent/v2_split_deepseek)')
    parser.add_argument('--output-dir', type=str, default=None,
                        help='Output directory for CSV and heatmap '
                             '(default: same as results-dir)')
    args = parser.parse_args()

    results_dir = Path(args.results_dir)
    output_dir = Path(args.output_dir) if args.output_dir else results_dir

    if not results_dir.exists():
        print(f"Error: results directory does not exist: {results_dir}")
        sys.exit(1)

    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"Scanning {results_dir} ...")
    detail_df, summary_df = analyze_results(results_dir)

    if detail_df.empty:
        print("No data found. Exiting.")
        sys.exit(1)

    # Save CSV
    csv_path = output_dir / 'component_frequency.csv'
    detail_df.to_csv(csv_path, index=False)
    print(f"Component frequency CSV saved to {csv_path}")

    # Print summary
    print_summary(summary_df)

    # Save heatmap
    heatmap_path = output_dir / 'component_heatmap.png'
    plot_heatmap(detail_df, heatmap_path)

    # Also save summary CSV
    summary_csv_path = output_dir / 'component_summary.csv'
    summary_df.to_csv(summary_csv_path, index=False)
    print(f"Summary CSV saved to {summary_csv_path}")


if __name__ == '__main__':
    main()
