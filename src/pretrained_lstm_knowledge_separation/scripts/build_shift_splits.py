"""Attribute-based shift split builder for knowledge separation experiments.

Computes Mahalanobis distance from source distribution center to select
low-shift and high-shift target basin groups.
"""
import argparse
from pathlib import Path
from typing import List, Tuple

import numpy as np
import pandas as pd
from scipy.spatial.distance import mahalanobis

DEFAULT_DESCRIPTOR_COLS = [
    "aridity",
    "frac_snow",
    "elev_mean",
    "slope_mean",
    "soil_depth_pelletier",
    "soil_porosity",
    "frac_forest",
    "p_mean",
]


def compute_shift_distances(
    attributes: pd.DataFrame,
    source_basins: List[str],
    descriptor_cols: List[str] = None,
) -> pd.Series:
    """Compute Mahalanobis distance of each basin from the source distribution center.

    Parameters
    ----------
    attributes : pd.DataFrame
        Basin-indexed DataFrame with attribute columns.
    source_basins : list of str
        Basin IDs that form the source distribution.
    descriptor_cols : list of str, optional
        Columns to use for distance computation. Defaults to DEFAULT_DESCRIPTOR_COLS.

    Returns
    -------
    pd.Series
        Mahalanobis distance for every basin in ``attributes``.
    """
    if descriptor_cols is None:
        descriptor_cols = DEFAULT_DESCRIPTOR_COLS

    X = attributes[descriptor_cols].copy()
    X_source = X.loc[source_basins]

    mean = X_source.mean().values
    cov = np.cov(X_source.values, rowvar=False)
    # regularize to avoid singular covariance
    cov += np.eye(cov.shape[0]) * 1e-6
    cov_inv = np.linalg.inv(cov)

    distances = X.apply(lambda row: mahalanobis(row.values, mean, cov_inv), axis=1)
    distances.name = "shift_distance"
    return distances.astype(np.float64)


def select_shift_groups(
    distances: pd.Series,
    source_basins: List[str],
    n_per_group: int = 50,
) -> Tuple[List[str], List[str]]:
    """Select low-shift and high-shift target groups from non-source basins.

    Parameters
    ----------
    distances : pd.Series
        Shift distance for every basin.
    source_basins : list of str
        Basins to exclude from target groups.
    n_per_group : int
        Number of basins per group.

    Returns
    -------
    (low_shift, high_shift) : tuple of list[str]
        Basin IDs for each group.
    """
    target = distances.drop(labels=source_basins, errors="ignore").sort_values()
    low_shift = target.head(n_per_group).index.tolist()
    high_shift = target.tail(n_per_group).index.tolist()
    return low_shift, high_shift


def main():
    parser = argparse.ArgumentParser(description="Build low/high shift basin splits from CAMELS-US attributes.")
    parser.add_argument("--data-dir", type=Path, required=True, help="Path to CAMELS-US data directory")
    parser.add_argument("--source-basin-file", type=Path, required=True, help="Text file with source basin IDs")
    parser.add_argument("--output-dir", type=Path, default=Path("src/pretrained_lstm_knowledge_separation/data"))
    parser.add_argument("--n-per-group", type=int, default=50)
    args = parser.parse_args()

    from neuralhydrology.datasetzoo.camelsus import load_camels_us_attributes

    source_basins = args.source_basin_file.read_text().strip().splitlines()
    attributes = load_camels_us_attributes(args.data_dir, basins=[])

    distances = compute_shift_distances(attributes, source_basins)
    low_shift, high_shift = select_shift_groups(distances, source_basins, n_per_group=args.n_per_group)

    args.output_dir.mkdir(parents=True, exist_ok=True)

    (args.output_dir / "low_shift_basins.txt").write_text("\n".join(low_shift) + "\n")
    (args.output_dir / "high_shift_basins.txt").write_text("\n".join(high_shift) + "\n")

    summary = distances.to_frame()
    summary["group"] = "none"
    summary.loc[source_basins, "group"] = "source"
    summary.loc[low_shift, "group"] = "low_shift"
    summary.loc[high_shift, "group"] = "high_shift"
    summary.to_csv(args.output_dir / "shift_summary.csv")

    print(f"Low-shift basins ({len(low_shift)}): mean dist = {distances.loc[low_shift].mean():.3f}")
    print(f"High-shift basins ({len(high_shift)}): mean dist = {distances.loc[high_shift].mean():.3f}")
    print(f"Saved to {args.output_dir}")


if __name__ == "__main__":
    main()
