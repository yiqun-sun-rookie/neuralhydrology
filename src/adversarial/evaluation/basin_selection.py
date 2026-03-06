"""Select representative basins from CAMELS-US using k-medoids clustering."""
from __future__ import annotations

import os
# Prevent sklearn/OpenBLAS deadlock on Windows
os.environ.setdefault("OMP_NUM_THREADS", "1")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")

from pathlib import Path
from typing import List

import numpy as np
import pandas as pd


def select_representative_basins(
    attr_file: Path,
    n_basins: int = 15,
    random_state: int = 42,
) -> List[str]:
    """Select representative basins via KMeans on static attributes.

    Args:
        attr_file: Path to CSV with basin attributes (must have 'gauge_id' column).
        n_basins: Number of basins to select.
        random_state: Random seed for reproducibility.

    Returns:
        List of gauge_id strings.
    """
    df = pd.read_csv(attr_file, dtype={"gauge_id": str})

    # Select clustering features
    cluster_cols = [
        "gauge_elev_mean", "gauge_slope_mean", "area",
        "p_mean", "aridity", "frac_snow", "frac_forest",
        "soil_depth_pelletier",
    ]
    available = [c for c in cluster_cols if c in df.columns]
    if len(available) < 3:
        available = df.select_dtypes(include=[np.number]).columns.tolist()[:8]

    features = df[available].copy()
    features = features.fillna(features.median())

    # Normalize
    features = (features - features.mean()) / features.std().clip(lower=1e-8)
    X = features.values

    from sklearn.cluster import KMeans
    km = KMeans(n_clusters=n_basins, random_state=random_state, n_init=10)
    labels = km.fit_predict(X)

    # For each cluster, pick the basin closest to centroid
    selected = []
    gauge_ids = df["gauge_id"].values
    for k in range(n_basins):
        mask = labels == k
        cluster_points = X[mask]
        dists = np.linalg.norm(cluster_points - km.cluster_centers_[k], axis=1)
        idx_in_cluster = dists.argmin()
        global_idx = np.where(mask)[0][idx_in_cluster]
        selected.append(str(gauge_ids[global_idx]).zfill(8))

    return selected
