#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
验证新的 ERA5-Land 日聚合流程与 Caravan 官方后处理结果是否一致�?

流程�?
1. 读取 `03_ee_export_era5l.py --mode hourly` 导出的小时级 CSV�?
2. 使用本项目新增的聚合逻辑生成 CAMELS 风格的日尺度 forcing�?
3. 使用 Caravan 官方 `caravan_utils` 中的函数对相同数据进行处理�?
4. 对比两者输出，检查误差是否低于给定阈值�?

用法示例�?
    python projects/haihe/scripts/10a_verify_caravan_alignment.py \
        --hourly-dir data/Caravan_Haihe_ERA5L_lev9_hourly \
        --basins-dir data/haihe/basins_individual \
        --basin-id HB4090006920
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path
from typing import Dict, List

import numpy as np
import pandas as pd
import types

try:
    import timezonefinder  # type: ignore  # noqa: F401
except Exception:  # pragma: no cover
    try:
        from timezonefinderL import TimezoneFinder as _TF  # type: ignore
        module = types.ModuleType("timezonefinder")
        module.TimezoneFinder = _TF  # type: ignore[attr-defined]
        sys.modules["timezonefinder"] = module
    except Exception:
        pass

from neuralhydrology.utils.era5l_export import get_export_config
from neuralhydrology.utils.era5l_hourly_processing import (
    assemble_camels_daily_features,
    build_hourly_dataframe,
    compute_vapor_pressure,
    convert_units,
    convert_utc_to_local,
    disaggregate_accumulations,
    load_basin_metadata,
    aggregate_to_daily,
    split_by_basin,
)

# 导入 Caravan 官方工具
CARAVAN_CODE_DIR = Path(__file__).resolve().parents[2] / "external" / "Caravan" / "code"
if CARAVAN_CODE_DIR.exists():
    sys.path.append(str(CARAVAN_CODE_DIR))
try:
    from caravan_utils import (  # type: ignore
        aggregate_df_to_daily as caravan_aggregate_df_to_daily,
        disaggregate_features as caravan_disaggregate_features,
        era5l_unit_conversion as caravan_unit_conversion,
    )
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "Failed to import Caravan official utilities. Ensure external/Caravan is initialized."
    ) from exc


CAMELS_COMPARE_COLUMNS = [
    "prcp(mm/day)",
    "srad(W/m2)",
    "tmax(C)",
    "tmin(C)",
    "tmean(C)",
    "vp(Pa)",
    "pet(mm/day)",
    "snowfall(mm/day)",
    "surface_pressure(kPa)",
    "u_component_of_wind_10m(m/s)",
    "v_component_of_wind_10m(m/s)",
    "str(W/m2)",
]


def parse_args():
    parser = argparse.ArgumentParser(description="Verify ERA5-Land daily aggregation against Caravan reference outputs")
    parser.add_argument("--hourly-dir", required=True, help="Directory containing era5l_hourly_*.csv files")
    parser.add_argument("--basins-dir", required=True, help="Directory with per-basin GeoJSON files for centroid metadata")
    parser.add_argument("--basin-id", required=True, help="待验证的 basin_id")
    parser.add_argument("--tolerance", type=float, default=1e-6, help="Maximum allowed absolute error")
    parser.add_argument("--print-cols", action="store_true", help="Print comparable column names")
    return parser.parse_args()


def prepare_our_daily(df_hourly: pd.DataFrame, lat: float, lon: float) -> pd.DataFrame:
    config = get_export_config("hourly")
    df_hourly = disaggregate_accumulations(df_hourly, config.accumulated_bands)
    df_hourly = convert_units(df_hourly)
    df_local = convert_utc_to_local(df_hourly, lat=lat, lon=lon)
    daily = aggregate_to_daily(
        df_local,
        sum_cols=[
            "total_precipitation",
            "surface_net_solar_radiation",
            "surface_net_thermal_radiation",
            "potential_evaporation",
            "snowfall_water_equivalent",
        ],
        mean_cols=[
            "temperature_2m",
            "dewpoint_temperature_2m",
            "surface_pressure",
            "u_component_of_wind_10m",
            "v_component_of_wind_10m",
        ],
        min_cols=["temperature_2m"],
        max_cols=["temperature_2m"],
    )
    if "dewpoint_temperature_2m_mean" in daily.columns:
        daily["vp(Pa)"] = compute_vapor_pressure(daily["dewpoint_temperature_2m_mean"])
    camels_df = assemble_camels_daily_features(daily)
    return camels_df


def prepare_caravan_daily(df_hourly: pd.DataFrame, lat: float, lon: float) -> pd.DataFrame:
    df_hourly = caravan_disaggregate_features(df_hourly.copy())
    df_hourly = caravan_unit_conversion(df_hourly)
    daily = caravan_aggregate_df_to_daily(
        df=df_hourly,
        gauge_lat=lat,
        gauge_lon=lon,
        mean_vars=[
            "temperature_2m",
            "dewpoint_temperature_2m",
            "surface_pressure",
            "u_component_of_wind_10m",
            "v_component_of_wind_10m",
        ],
        min_vars=["temperature_2m"],
        max_vars=["temperature_2m"],
        sum_vars=[
            "total_precipitation",
            "surface_net_solar_radiation",
            "surface_net_thermal_radiation",
            "potential_evaporation",
            "snowfall_water_equivalent",
        ],
    )
    if "dewpoint_temperature_2m_mean" in daily.columns:
        daily["vp(Pa)"] = compute_vapor_pressure(daily["dewpoint_temperature_2m_mean"])

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
    cols = ["Year", "Mnth", "Day"] + [c for c in df.columns if c not in {"Year", "Mnth", "Day"}]
    df = df[cols]
    return df


def main():
    args = parse_args()

    hourly_dir = Path(args.hourly_dir)
    basins_dir = Path(args.basins_dir)
    basin_id = args.basin_id

    config = get_export_config("hourly")
    metadata = load_basin_metadata(basins_dir)
    if basin_id not in metadata:
        raise SystemExit(f"�?{basins_dir} 中未找到 {basin_id} �?GeoJSON")

    hourly_files = sorted(hourly_dir.glob("*.csv"))
    if not hourly_files:
        raise SystemExit(f"{hourly_dir} 中未发现任何 CSV 文件")

    combined = build_hourly_dataframe(hourly_files, date_format=config.date_format)
    grouped = split_by_basin(combined, config.bands)
    if basin_id not in grouped:
        raise SystemExit(f"hourly 数据集中未找�?basin {basin_id}")

    df_utc = grouped[basin_id].sort_index()
    meta = metadata[basin_id]

    ours = prepare_our_daily(df_utc.copy(), lat=meta.lat, lon=meta.lon)
    caravan = prepare_caravan_daily(df_utc.copy(), lat=meta.lat, lon=meta.lon)

    common_cols = [
        col for col in CAMELS_COMPARE_COLUMNS if col in ours.columns and col in caravan.columns
    ]
    if args.print_cols:
        print("Comparable columns:", common_cols)

    ours_cmp = ours.set_index(["Year", "Mnth", "Day"])[common_cols]
    caravan_cmp = caravan.set_index(["Year", "Mnth", "Day"])[common_cols]

    if ours_cmp.shape != caravan_cmp.shape or not ours_cmp.index.equals(caravan_cmp.index):
        raise SystemExit("Row count or date index does not match Caravan output; cannot compare.")

    diff = (ours_cmp - caravan_cmp).abs()
    max_diff = diff.max()
    failing = max_diff[max_diff > args.tolerance]

    if failing.empty:
        print(f"[OK] {basin_id} 通过验证。最大绝对误差：\n{max_diff}")
    else:
        print(f"[WARN] {basin_id} has columns exceeding tolerance {args.tolerance}")
        print(failing)
        print("最大绝对误差：")
        print(max_diff)
        sys.exit(1)


if __name__ == "__main__":
    main()


