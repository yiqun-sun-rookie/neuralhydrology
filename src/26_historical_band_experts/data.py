"""Allowed-input data assembly for the fixed historical-band pilot."""
from __future__ import annotations

from dataclasses import dataclass
import hashlib
from pathlib import Path
from typing import Mapping, Sequence

import numpy as np
import pandas as pd


_REPO = Path(__file__).resolve().parents[2]
DEFAULT_STATICS_FILE = _REPO / "src/fair_benchmark/frozen/bundle/track0_statics.csv"

DYNAMIC_COLUMNS = (
    "PRCP(mm/day)",
    "Tmin(C)",
    "Tmax(C)",
    "SRAD(W/m2)",
    "Vp(Pa)",
)
STATIC_COLUMNS = (
    "p_mean",
    "pet_mean",
    "aridity",
    "p_seasonality",
    "frac_snow",
    "high_prec_freq",
    "high_prec_dur",
    "low_prec_freq",
    "low_prec_dur",
    "elev_mean",
    "slope_mean",
    "area_gages2",
    "frac_forest",
    "lai_max",
    "lai_diff",
    "gvf_max",
    "gvf_diff",
    "soil_depth_pelletier",
    "soil_depth_statsgo",
    "soil_porosity",
    "soil_conductivity",
    "max_water_content",
    "sand_frac",
    "silt_frac",
    "clay_frac",
    "carbonate_rocks_frac",
    "geol_permeability",
)


@dataclass(frozen=True)
class Periods:
    history_start: pd.Timestamp
    train_start: pd.Timestamp
    train_end: pd.Timestamp
    validation_start: pd.Timestamp
    validation_end: pd.Timestamp


@dataclass
class DataPack:
    basins: tuple[str, ...]
    dates: pd.DatetimeIndex
    forcing: np.ndarray
    discharge: np.ndarray
    statics: np.ndarray


def default_periods() -> Periods:
    train_start = pd.Timestamp("1999-10-01")
    return Periods(
        history_start=train_start - pd.Timedelta(days=3649),
        train_start=train_start,
        train_end=pd.Timestamp("2006-09-30"),
        validation_start=pd.Timestamp("2006-10-01"),
        validation_end=pd.Timestamp("2008-09-30"),
    )


def split_target_indices(
    dates: pd.DatetimeIndex,
    discharge: np.ndarray,
    split: str,
) -> tuple[np.ndarray, np.ndarray]:
    """Return finite target coordinates for the frozen training or validation split."""
    periods = default_periods()
    if split == "train":
        start, end = periods.train_start, periods.train_end
    elif split == "validation":
        start, end = periods.validation_start, periods.validation_end
    else:
        raise ValueError("split must be 'train' or 'validation'")
    if discharge.ndim != 2 or discharge.shape[1] != len(dates):
        raise ValueError("discharge must have shape [basin,time] aligned with dates")
    date_mask = np.asarray((dates >= start) & (dates <= end))
    valid = np.isfinite(discharge) & date_mask[None, :]
    basin_indices, target_indices = np.nonzero(valid)
    if len(target_indices) and int(target_indices.min()) < 3649:
        raise ValueError("a selected target lacks the required 3649 lag days")
    return basin_indices.astype(np.int64), target_indices.astype(np.int64)


def compute_scaler(
    forcing: np.ndarray,
    discharge: np.ndarray,
    statics: np.ndarray,
    dates: pd.DatetimeIndex,
) -> dict[str, np.ndarray | float]:
    """Compute normalization and loss statistics from training target dates only."""
    periods = default_periods()
    train_mask = np.asarray((dates >= periods.train_start) & (dates <= periods.train_end))
    dynamic_values = forcing[:, train_mask, :].reshape(-1, forcing.shape[-1])
    target_values = discharge[:, train_mask]
    dynamic_center = np.nanmean(dynamic_values, axis=0)
    dynamic_scale = np.nanstd(dynamic_values, axis=0)
    dynamic_scale[dynamic_scale < 1e-8] = 1.0
    q_center = float(np.nanmean(target_values))
    q_scale = float(np.nanstd(target_values))
    if q_scale < 1e-8:
        q_scale = 1.0
    static_center = np.nanmean(statics, axis=0)
    static_scale = np.nanstd(statics, axis=0)
    static_scale[static_scale < 1e-8] = 1.0
    per_basin_q_std = np.nanstd(target_values, axis=1)
    return {
        "dynamic_center": dynamic_center.astype(np.float32),
        "dynamic_scale": dynamic_scale.astype(np.float32),
        "q_center": q_center,
        "q_scale": q_scale,
        "static_center": static_center.astype(np.float32),
        "static_scale": static_scale.astype(np.float32),
        "per_basin_q_std": per_basin_q_std.astype(np.float32),
    }


def normalize_pack(
    pack: DataPack,
    scaler: Mapping[str, np.ndarray | float],
) -> DataPack:
    forcing = (
        pack.forcing - np.asarray(scaler["dynamic_center"], dtype=np.float32)
    ) / np.asarray(scaler["dynamic_scale"], dtype=np.float32)
    forcing = np.nan_to_num(forcing, nan=0.0, posinf=0.0, neginf=0.0).astype(np.float32)
    statics = (
        pack.statics - np.asarray(scaler["static_center"], dtype=np.float32)
    ) / np.asarray(scaler["static_scale"], dtype=np.float32)
    discharge = (
        pack.discharge - float(scaler["q_center"])
    ) / float(scaler["q_scale"])
    return DataPack(
        basins=pack.basins,
        dates=pack.dates,
        forcing=forcing,
        discharge=discharge.astype(np.float32),
        statics=statics.astype(np.float32),
    )


def model_input_arrays(pack: DataPack) -> dict[str, np.ndarray]:
    """Return model inputs without exposing the supervised discharge target."""
    return {"forcing": pack.forcing, "statics": pack.statics}


def load_basin_ids(path: str | Path) -> tuple[str, ...]:
    return tuple(
        line.strip().zfill(8)
        for line in Path(path).read_text(encoding="utf-8").splitlines()
        if line.strip()
    )


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_target_bundle(
    targets_file: str | Path,
    expected_sha256: str,
    basins: Sequence[str],
) -> pd.DataFrame:
    """Validate and return the target-only bundle for the frozen allowed dates."""
    targets_file = Path(targets_file)
    actual_sha256 = _sha256(targets_file)
    if actual_sha256.lower() != str(expected_sha256).lower():
        raise ValueError(
            f"target bundle SHA-256 mismatch: expected {expected_sha256}, got {actual_sha256}"
        )
    frame = pd.read_csv(targets_file, dtype={"basin": str})
    required = {"basin", "date", "qobs"}
    if set(frame.columns) != required:
        raise ValueError(f"target bundle columns must be exactly {sorted(required)}")
    frame["basin"] = frame["basin"].str.zfill(8)
    frame["date"] = pd.to_datetime(frame["date"], errors="raise")
    frame["qobs"] = pd.to_numeric(frame["qobs"], errors="raise")
    if frame.duplicated(["basin", "date"]).any():
        raise ValueError("target bundle contains a duplicate basin-date key")

    basin_ids = tuple(str(basin).zfill(8) for basin in basins)
    if set(frame["basin"]) != set(basin_ids):
        raise ValueError("target bundle basin set does not match the frozen basin list")
    periods = default_periods()
    if frame["date"].min() != periods.train_start or frame["date"].max() != periods.validation_end:
        raise ValueError("target bundle date range does not match the frozen allowed period")
    values = frame["qobs"].to_numpy(dtype=np.float64)
    if not np.isfinite(values).all() or np.any(values < 0):
        raise ValueError("target bundle contains non-finite or negative discharge")

    expected_dates = pd.date_range(periods.train_start, periods.validation_end, freq="D")
    expected_index = pd.MultiIndex.from_product(
        [tuple(sorted(basin_ids)), expected_dates], names=["basin", "date"]
    )
    ordered = frame.sort_values(["basin", "date"]).reset_index(drop=True)
    actual_index = pd.MultiIndex.from_frame(ordered[["basin", "date"]])
    if not actual_index.equals(expected_index):
        raise ValueError("target bundle is missing or contains unexpected basin-date keys")
    return ordered


def load_data_pack(
    data_dir: str | Path,
    basins: Sequence[str],
    targets_file: str | Path,
    expected_targets_sha256: str,
    statics_file: str | Path = DEFAULT_STATICS_FILE,
) -> DataPack:
    """Load allowed forcing, static attributes, and the target-only bundle."""
    from neuralhydrology.datasetzoo.camelsus import load_camels_us_forcings

    periods = default_periods()
    dates = pd.date_range(periods.history_start, periods.validation_end, freq="D")
    basin_ids = tuple(str(basin).zfill(8) for basin in basins)
    target_frame = load_target_bundle(targets_file, expected_targets_sha256, basin_ids)
    forcing = np.full((len(basin_ids), len(dates), len(DYNAMIC_COLUMNS)), np.nan, dtype=np.float32)
    discharge = np.full((len(basin_ids), len(dates)), np.nan, dtype=np.float32)
    data_dir = Path(data_dir)

    for basin_index, basin in enumerate(basin_ids):
        basin_forcing, _area = load_camels_us_forcings(data_dir, basin, "maurer")
        basin_forcing = basin_forcing.reindex(dates)
        forcing[basin_index] = basin_forcing[list(DYNAMIC_COLUMNS)].to_numpy(dtype=np.float32)
        basin_targets = target_frame.loc[target_frame["basin"] == basin].set_index("date")["qobs"]
        discharge[basin_index] = basin_targets.reindex(dates).to_numpy(dtype=np.float32)

    static_frame = pd.read_csv(statics_file, dtype={"gauge_id": str})
    static_frame["gauge_id"] = static_frame["gauge_id"].str.zfill(8)
    static_frame = static_frame.set_index("gauge_id").loc[list(basin_ids), list(STATIC_COLUMNS)]
    statics = static_frame.to_numpy(dtype=np.float32)
    return DataPack(
        basins=basin_ids,
        dates=dates,
        forcing=forcing,
        discharge=discharge,
        statics=statics,
    )