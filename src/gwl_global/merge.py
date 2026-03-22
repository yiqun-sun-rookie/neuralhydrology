"""Merge GWL time series with KNMI weather data."""
import json
import logging
from pathlib import Path
from typing import Optional

import numpy as np
import pandas as pd

from src.gwl_global.config import data_dir, knmi_station_for_coord

logger = logging.getLogger(__name__)


def interpolate_short_gaps(series: pd.Series, max_gap: int = 5) -> pd.Series:
    """Linearly interpolate NaN gaps of <= max_gap consecutive days."""
    result = series.copy()
    mask = result.isna()
    if not mask.any():
        return result

    # Identify gap groups: consecutive NaN blocks get the same group id
    not_nan = ~mask
    gap_id = not_nan.cumsum()
    gap_sizes = mask.groupby(gap_id).transform("sum")

    # Interpolate everything, then restore long gaps
    interpolated = result.interpolate(method="linear")
    long_gap_mask = mask & (gap_sizes > max_gap)
    interpolated[long_gap_mask] = np.nan

    return interpolated


def merge_single_well(
    bro_id: str,
    knmi_stn: int,
    base_dir: Path,
    save: bool = False,
) -> Optional[pd.DataFrame]:
    """Merge a single well's GWL with KNMI weather data.

    Args:
        bro_id: BRO well/GLD identifier
        knmi_stn: KNMI station number
        base_dir: directory containing timeseries/ and meteo/
        save: if True, write merged CSV

    Returns:
        Merged DataFrame or None if insufficient overlap.
    """
    gwl_path = base_dir / "timeseries" / f"{bro_id}_gwl.csv"
    knmi_path = base_dir / "meteo" / f"knmi_{knmi_stn}_daily.csv"

    if not gwl_path.exists() or not knmi_path.exists():
        logger.warning("Missing files for %s (knmi %d)", bro_id, knmi_stn)
        return None

    gwl = pd.read_csv(gwl_path, parse_dates=["date"], index_col="date")
    knmi = pd.read_csv(knmi_path, parse_dates=["date"], index_col="date")

    # Resample GWL to daily (in case of sub-daily observations)
    gwl_daily = gwl["gwl_m_nap"].resample("D").mean()

    # Interpolate short gaps
    gwl_daily = interpolate_short_gaps(gwl_daily, max_gap=14)

    # Inner join
    merged = pd.DataFrame({"gwl_m_nap": gwl_daily})
    knmi_cols = [c for c in ["P_mm", "ET_mm", "T_degC"] if c in knmi.columns]
    merged = merged.join(knmi[knmi_cols], how="inner")

    # Require at least 365 days of overlap
    if len(merged) < 365:
        logger.warning("%s: only %d overlapping days, skipping.", bro_id, len(merged))
        return None

    if save:
        out_dir = base_dir / "merged"
        out_dir.mkdir(parents=True, exist_ok=True)
        merged.to_csv(out_dir / f"{bro_id}_merged.csv", index_label="date")

    return merged


def run_merge(output_dir: Optional[Path] = None) -> dict:
    """Merge all QC-passed wells with their nearest KNMI station.

    Reads wells.csv for coordinates, quality_check.csv for QC pass list.

    Returns:
        Summary dict.
    """
    output_dir = output_dir or data_dir()

    wells = pd.read_csv(output_dir / "wells.csv")
    qc = pd.read_csv(output_dir / "quality_check.csv")
    gld_index = pd.read_csv(output_dir / "gld_index.csv")

    passed = qc[qc["passed"]]["bro_id"].tolist()
    logger.info("%d wells passed QC.", len(passed))

    n_merged = 0
    for bro_id in passed:
        # Find coordinates from gld_index or wells
        row = gld_index[gld_index["gld_bro_id"] == bro_id]
        if row.empty:
            row = wells[wells["bro_id"] == bro_id]
        if row.empty:
            continue

        lat = row.iloc[0].get("lat", None)
        lon = row.iloc[0].get("lon", None)
        if lat is None or lon is None or pd.isna(lat) or pd.isna(lon):
            continue

        stn = knmi_station_for_coord(lat, lon)
        result = merge_single_well(bro_id, stn, output_dir, save=True)
        if result is not None:
            n_merged += 1

    # Write summary
    summary = {
        "total_wells_found": len(wells),
        "total_gld_records": len(gld_index),
        "wells_passed_qc": len(passed),
        "wells_with_merged_data": n_merged,
    }
    with open(output_dir / "summary.json", "w") as f:
        json.dump(summary, f, indent=2)

    logger.info("Merge complete: %s", summary)
    return summary
