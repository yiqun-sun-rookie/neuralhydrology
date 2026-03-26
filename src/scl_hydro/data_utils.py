"""Data utilities for loading CAMELS-US data into SCLDataset format."""
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np
import pandas as pd

from neuralhydrology.datasetzoo.camelsus import load_camels_us_forcings, load_camels_us_discharge


def load_camels_basins(
    data_dir: Path,
    basins: List[str],
    features: List[str],
    target: str = "QObs(mm/d)",
    start_date: str = None,
    end_date: str = None,
    forcings: str = "daymet",
) -> Dict[str, pd.DataFrame]:
    """Load CAMELS-US basin data into dict format for SCLDataset.

    Returns dict mapping basin_id -> DataFrame with features + target columns,
    date-indexed, float32.
    """
    data_dir = Path(data_dir)
    data = {}
    for basin in basins:
        df_forcing, area = load_camels_us_forcings(data_dir, basin, forcings)
        q = load_camels_us_discharge(data_dir, basin, area)
        df = df_forcing.copy()
        df[target] = q

        # Filter date range
        if start_date:
            df = df[df.index >= start_date]
        if end_date:
            df = df[df.index <= end_date]

        # Keep only requested features + target, drop Year/Mnth/Day/Hr if present
        cols = [c for c in features if c in df.columns] + [target]
        df = df[cols].astype(np.float32)

        # Replace negative Q with NaN
        df.loc[df[target] < 0, target] = np.nan

        data[basin] = df

    return data


def compute_scaler(data: Dict[str, pd.DataFrame]) -> Dict[str, Tuple[float, float]]:
    """Compute per-feature (mean, std) from training data for z-score normalization."""
    all_data = pd.concat(data.values(), axis=0)
    scaler = {}
    for col in all_data.columns:
        mean = float(all_data[col].mean())
        std = float(all_data[col].std())
        if std < 1e-10:
            std = 1.0
        scaler[col] = (mean, std)
    return scaler


def apply_scaler(
    data: Dict[str, pd.DataFrame],
    scaler: Dict[str, Tuple[float, float]],
) -> Dict[str, pd.DataFrame]:
    """Apply z-score normalization using precomputed scaler."""
    normalized = {}
    for basin_id, df in data.items():
        df_norm = df.copy()
        for col in df.columns:
            if col in scaler:
                mean, std = scaler[col]
                df_norm[col] = (df[col] - mean) / std
        normalized[basin_id] = df_norm
    return normalized
