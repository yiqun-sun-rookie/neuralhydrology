#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
�?ERA5-Land 小时级导出数据聚合为日尺�?CAMELS 变量�?

功能�?
- 读取 `03_ee_export_era5l.py --mode hourly` 导出�?CSV
- 针对每个流域：累积量差分、单位转换、按本地时区聚合
- 生成包含日总量/日均/日最�?日最�?水汽压等列的 CSV

使用示例�?
    python projects/haihe/scripts/09_convert_hourly_to_daily.py \
        --hourly-dir data/Caravan_Haihe_ERA5L_lev9_hourly \
        --basins-dir data/haihe/basins_individual \
        --out outputs/haihe/per_basin_timeseries_era5l_hourly
"""

from __future__ import annotations

import argparse
from collections import defaultdict
from pathlib import Path
from typing import Dict, List

import pandas as pd
from tqdm import tqdm

from neuralhydrology.utils.era5l_export import get_export_config
from neuralhydrology.utils.era5l_hourly_processing import (
    BasinMeta,
    aggregate_to_daily,
    compute_vapor_pressure,
    convert_units,
    convert_utc_to_local,
    disaggregate_accumulations,
    load_basin_metadata,
    split_by_basin,
    build_hourly_dataframe,
)


def parse_args():
    parser = argparse.ArgumentParser(description="Aggregate ERA5-Land hourly CSV files to daily CAMELS-style variables")
    parser.add_argument("--hourly-dir", required=True, help="Directory containing era5l_hourly_*.csv files")
    parser.add_argument("--basins-dir", required=True, help="单体流域 GeoJSON 目录（获取质心坐标）")
    parser.add_argument("--out", required=True, help="Output directory (one CSV per basin)")
    parser.add_argument("--overwrite", action="store_true", help="若目标文件存在则覆盖")
    return parser.parse_args()


def ensure_output_dir(out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)


def process_basin(
    basin_id: str,
    df_utc: pd.DataFrame,
    meta: BasinMeta,
    accumulated_cols: List[str],
    out_dir: Path,
    overwrite: bool,
):
    out_fp = out_dir / f"{basin_id}.csv"
    if out_fp.exists() and not overwrite:
        return

    df_utc = df_utc.sort_index()
    df_utc = disaggregate_accumulations(df_utc.copy(), accumulated_cols)
    df_utc = convert_units(df_utc)

    df_local = convert_utc_to_local(df_utc, lat=meta.lat, lon=meta.lon)

    sum_cols = [
        "total_precipitation",
        "surface_net_solar_radiation",
        "surface_net_thermal_radiation",
        "potential_evaporation",
        "snowfall",
    ]
    mean_cols = [
        "temperature_2m",
        "dewpoint_temperature_2m",
        "surface_pressure",
        "u_component_of_wind_10m",
        "v_component_of_wind_10m",
    ]
    min_cols = ["temperature_2m"]
    max_cols = ["temperature_2m"]

    daily = aggregate_to_daily(
        df_local,
        sum_cols=[c for c in sum_cols if c in df_local.columns],
        mean_cols=[c for c in mean_cols if c in df_local.columns],
        min_cols=[c for c in min_cols if c in df_local.columns],
        max_cols=[c for c in max_cols if c in df_local.columns],
    )

    # 衍生变量
    if "dewpoint_temperature_2m_mean" in daily.columns:
        daily["vp(Pa)"] = compute_vapor_pressure(daily["dewpoint_temperature_2m_mean"])

    rename_map = {
        "total_precipitation_sum": "total_precipitation_sum",  # 先保留原�?
        "surface_net_solar_radiation_sum": "surface_net_solar_radiation_sum",
        "surface_net_thermal_radiation_sum": "surface_net_thermal_radiation_sum",
        "potential_evaporation_sum": "potential_evaporation_sum",
        "snowfall_water_equivalent_sum": "snowfall_water_equivalent_sum",
        "temperature_2m_mean": "temperature_2m_mean",
        "temperature_2m_min": "temperature_2m_min",
        "temperature_2m_max": "temperature_2m_max",
        "dewpoint_temperature_2m_mean": "dewpoint_temperature_2m_mean",
        "surface_pressure_mean": "surface_pressure_mean",
        "u_component_of_wind_10m_mean": "u_component_of_wind_10m_mean",
        "v_component_of_wind_10m_mean": "v_component_of_wind_10m_mean",
    }
    daily = daily.rename(columns=rename_map)

    daily.insert(0, "date", daily.index.strftime("%Y-%m-%d"))
    daily.to_csv(out_fp, index=False)


def main():
    args = parse_args()

    hourly_dir = Path(args.hourly_dir)
    basins_dir = Path(args.basins_dir)
    out_dir = Path(args.out)
    ensure_output_dir(out_dir)

    config = get_export_config("hourly")
    metadata = load_basin_metadata(basins_dir)

    hourly_files = sorted(hourly_dir.glob("*.csv"))
    if not hourly_files:
        raise SystemExit(f"目录 {hourly_dir} 未找到任�?CSV 文件")

    combined = build_hourly_dataframe(hourly_files, date_format=config.date_format)
    grouped = split_by_basin(combined, bands=config.bands)

    missing_meta = sorted(set(grouped.keys()) - set(metadata.keys()))
    if missing_meta:
        raise SystemExit(f"以下 basin 缺少 GeoJSON 元数据：{missing_meta[:5]}...")

    for basin_id in tqdm(grouped.keys(), desc="Aggregate to daily", ncols=100):
        process_basin(
            basin_id=basin_id,
            df_utc=grouped[basin_id],
            meta=metadata[basin_id],
            accumulated_cols=config.accumulated_bands,
            out_dir=out_dir,
            overwrite=args.overwrite,
        )

    print(f"[OK] 已生�?{len(grouped)} 个流域的日尺�?ERA5-Land 聚合数据，输出目录：{out_dir}")


if __name__ == "__main__":
    main()


