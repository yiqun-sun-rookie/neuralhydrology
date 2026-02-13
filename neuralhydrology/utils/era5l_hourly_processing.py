from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Tuple

import numpy as np
import pandas as pd
from shapely.geometry import shape
try:
    from timezonefinder import TimezoneFinder
except Exception:  # pragma: no cover
    try:
        from timezonefinderL import TimezoneFinder  # type: ignore
    except Exception:
        TimezoneFinder = None  # type: ignore
from pytz import timezone, utc


@dataclass(frozen=True)
class BasinMeta:
    basin_id: str
    lat: float
    lon: float


def load_basin_metadata(basins_dir: Path) -> Dict[str, BasinMeta]:
    """Load basin centroids (lat/lon) from GeoJSON files."""
    metadata: Dict[str, BasinMeta] = {}
    for fp in basins_dir.glob("*.geojson"):
        with fp.open("r", encoding="utf-8") as f:
            data = json.load(f)
        if data.get("type") == "FeatureCollection":
            features = data.get("features", [])
            if not features:
                continue
            geom = features[0]["geometry"]
            props = features[0].get("properties", {}) or {}
        elif data.get("type") == "Feature":
            geom = data["geometry"]
            props = data.get("properties", {}) or {}
        else:
            geom = data
            props = {}
        basin_id = str(props.get("basin_id", fp.stem))
        centroid = shape(geom).centroid
        metadata[basin_id] = BasinMeta(basin_id=basin_id, lat=float(centroid.y), lon=float(centroid.x))
    if not metadata:
        raise RuntimeError(f"未能从 {basins_dir} 中解析任何 basin 元数据")
    return metadata


def _get_timezone_offset(lat: float, lon: float) -> float:
    """Return UTC offset (hours) for given lat/lon using standard time (non-DST)."""
    if TimezoneFinder is None:
        # fallback approximation
        return round(lon / 15.0)
    tf = TimezoneFinder()
    tz_name = tf.timezone_at(lat=lat, lng=lon)
    if tz_name is None:
        return round(lon / 15.0)
    tz = timezone(tz_name)
    # use typical summer/winter dates depending on hemisphere to avoid DST
    date = utc.localize(pd.Timestamp("2020-07-01") if lat >= 0 else pd.Timestamp("2020-01-01"))
    offset = tz.utcoffset(date)
    if offset is None:
        return 0.0
    return offset.total_seconds() / 3600.0


def disaggregate_accumulations(df: pd.DataFrame, accumulated_cols: Iterable[str]) -> pd.DataFrame:
    """Convert ERA5-Land accumulated hourly variables to hourly increments."""
    cols = [c for c in accumulated_cols if c in df.columns]
    if not cols:
        return df
    diff = df[cols].diff(1)
    # replace values at 01:00 with original data (accumulated 00->01)
    diff.loc[diff.index.hour == 1] = df[cols].loc[df.index.hour == 1].values
    # first row fallback
    diff.iloc[0] = df[cols].iloc[0]
    df.loc[:, cols] = diff
    return df


def convert_units(df: pd.DataFrame) -> pd.DataFrame:
    """Convert ERA5-Land units to hydrological conventions."""
    for col in df.columns:
        if col in {"temperature_2m", "temperature_2m_max", "temperature_2m_min", "dewpoint_temperature_2m"}:
            df[col] = df[col] - 273.15
        elif col == "surface_pressure":
            df[col] = df[col] / 1000.0  # Pa -> kPa
        elif col in {"total_precipitation", "potential_evaporation", "snowfall_water_equivalent", "snowfall"}:
            df[col] = df[col] * 1000.0  # m -> mm
        elif col in {"surface_net_solar_radiation", "surface_net_thermal_radiation"}:
            df[col] = df[col] / 3600.0  # J/m2 -> W/m2
    return df


def _restrict_full_days(df: pd.DataFrame) -> pd.DataFrame:
    """Restrict dataframe to full days with 24 hourly values (1..24)."""
    first = df.loc[df.index.hour == 1].index.min()
    last = df.loc[df.index.hour == 0].index.max()
    if pd.isna(first) or pd.isna(last):
        return df
    return df.loc[first:last]


def aggregate_to_daily(
    df: pd.DataFrame,
    sum_cols: Iterable[str],
    mean_cols: Iterable[str],
    min_cols: Iterable[str],
    max_cols: Iterable[str],
) -> pd.DataFrame:
    """Aggregate hourly data (assumed local time) to daily resolution."""
    df = _restrict_full_days(df)
    pieces = []
    if sum_cols:
        sums = df[list(sum_cols)].resample("1D", offset=pd.Timedelta(hours=1)).sum()
        sums = sums.rename(columns={c: f"{c}_sum" for c in sums.columns})
        pieces.append(sums)
    if mean_cols:
        means = df[list(mean_cols)].resample("1D", offset=pd.Timedelta(hours=1)).mean()
        means = means.rename(columns={c: f"{c}_mean" for c in means.columns})
        pieces.append(means)
    if min_cols:
        mins = df[list(min_cols)].resample("1D", offset=pd.Timedelta(hours=1)).min()
        mins = mins.rename(columns={c: f"{c}_min" for c in mins.columns})
        pieces.append(mins)
    if max_cols:
        maxs = df[list(max_cols)].resample("1D", offset=pd.Timedelta(hours=1)).max()
        maxs = maxs.rename(columns={c: f"{c}_max" for c in maxs.columns})
        pieces.append(maxs)
    if not pieces:
        raise ValueError("至少需要指定一个聚合列集合")
    daily = pd.concat(pieces, axis=1)
    daily.index = daily.index.normalize()
    daily = daily.sort_index()
    return daily


def compute_vapor_pressure(tdew_c: pd.Series) -> pd.Series:
    """Compute vapor pressure (Pa) from dew point temperature (°C)."""
    # Magnus formula: e (hPa) = 6.112 * exp((17.67 * Td)/(Td + 243.5))
    e_hpa = 6.112 * np.exp((17.67 * tdew_c) / (tdew_c + 243.5))
    return e_hpa * 100.0  # Pa


def convert_utc_to_local(df: pd.DataFrame, lat: float, lon: float) -> pd.DataFrame:
    """Shift timezone from UTC to local standard time based on lat/lon."""
    offset = _get_timezone_offset(lat, lon)
    if offset != 0.0:
        df = df.copy()
        df.index = df.index + pd.to_timedelta(offset, unit="h")
    return df


def build_hourly_dataframe(hourly_files: List[Path], date_format: str) -> pd.DataFrame:
    """Combine hourly CSV files into a single dataframe indexed by datetime for all basins."""
    frames = []
    for fp in hourly_files:
        df = pd.read_csv(fp)
        if df.empty:
            continue
        if "system_index" not in df.columns or "basin_id" not in df.columns:
            raise ValueError(f"{fp} 缺少 system_index 或 basin_id 列")
        df["datetime"] = pd.to_datetime(df["system_index"], format=date_format)
        frames.append(df)
    if not frames:
        raise RuntimeError("未读取到任何 hourly CSV 数据")
    combined = pd.concat(frames, axis=0, ignore_index=True)
    combined = combined.sort_values(["basin_id", "datetime"])
    return combined


def split_by_basin(df: pd.DataFrame, bands: List[str]) -> Dict[str, pd.DataFrame]:
    """Split combined dataframe into basin-indexed hourly data (UTC)."""
    keep_cols = ["datetime", "basin_id", *bands]
    basin_groups: Dict[str, List[pd.DataFrame]] = {}
    for basin_id, grp in df[keep_cols].groupby("basin_id"):
        grp = grp.drop(columns=["basin_id"]).set_index("datetime")
        basin_groups[basin_id] = grp
    return basin_groups


CAMELS_REQUIRED_COLUMNS = [
    "total_precipitation_sum",
    "surface_net_solar_radiation_sum",
    "temperature_2m_max",
    "temperature_2m_min",
    "temperature_2m_mean",
    "vp(Pa)",
]


def assemble_camels_daily_features(daily: pd.DataFrame) -> pd.DataFrame:
    """Map daily ERA5-Land aggregates to CAMELS-style variable names.

    Parameters
    ----------
    daily : pd.DataFrame
        Daily dataframe produced by :func:`aggregate_to_daily`. Index must be datetime-like.

    Returns
    -------
    pd.DataFrame
        DataFrame containing columns Year/Mnth/Day plus CAMELS variables.
    """

    missing = [c for c in CAMELS_REQUIRED_COLUMNS if c not in daily.columns]
    if missing:
        raise ValueError(f"日尺度数据缺少生成 CAMELS 变量所需的列: {missing}")

    df = pd.DataFrame(index=daily.index.copy())
    df["prcp(mm/day)"] = daily["total_precipitation_sum"]
    df["srad(W/m2)"] = daily["surface_net_solar_radiation_sum"]
    df["tmax(C)"] = daily["temperature_2m_max"]
    df["tmin(C)"] = daily["temperature_2m_min"]
    df["tmean(C)"] = daily["temperature_2m_mean"]
    df["vp(Pa)"] = daily["vp(Pa)"]

    if "potential_evaporation_sum" in daily.columns:
        df["pet(mm/day)"] = daily["potential_evaporation_sum"]
    if "surface_net_thermal_radiation_sum" in daily.columns:
        df["str(W/m2)"] = daily["surface_net_thermal_radiation_sum"]
    if "snowfall_water_equivalent_sum" in daily.columns:
        df["snowfall(mm/day)"] = daily["snowfall_water_equivalent_sum"]
    elif "snowfall_sum" in daily.columns:
        df["snowfall(mm/day)"] = daily["snowfall_sum"]
    if "surface_pressure_mean" in daily.columns:
        df["surface_pressure(kPa)"] = daily["surface_pressure_mean"]
    if "u_component_of_wind_10m_mean" in daily.columns:
        df["u_component_of_wind_10m(m/s)"] = daily["u_component_of_wind_10m_mean"]
    if "v_component_of_wind_10m_mean" in daily.columns:
        df["v_component_of_wind_10m(m/s)"] = daily["v_component_of_wind_10m_mean"]

    df = df.reset_index()
    df["Year"] = df["index"].dt.year
    df["Mnth"] = df["index"].dt.month
    df["Day"] = df["index"].dt.day
    df = df.drop(columns=["index"])
    ordered_cols = ["Year", "Mnth", "Day"] + [c for c in df.columns if c not in {"Year", "Mnth", "Day"}]
    df = df[ordered_cols]
    return df


