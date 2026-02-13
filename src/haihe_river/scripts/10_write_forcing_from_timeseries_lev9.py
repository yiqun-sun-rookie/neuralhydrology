#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""将单流域时序 CSV 写入 NeuralHydrology 可用�?CAMELS 风格 forcing 文本�?

功能摘要
--------
- 读取 `results/06_haihe_river/per_basin_timeseries_lev9/<basin_id>.csv`
- 按日期升序整理，并根据需要对指定列做非负截断
- 可选地从对�?GeoJSON 估算质心经纬度与面积（m²），写入 forcing 文件前三�?
- 产出 `data/haihe/forcing/<basin_id>.txt`

使用示例
--------
```
python src/haihe_river/scripts/10_write_forcing_from_timeseries_lev9.py \
  --src results/06_haihe_river/per_basin_timeseries_lev9 \
  --dst data/haihe/forcing \
  --geojson-dir data/haihe/basins_individual \
  --clamp-nonnegative total_precipitation_sum,potential_evaporation_sum,snow_depth_water_equivalent \
  --basin-list data/haihe/basins_individual/basin_list.txt
```

备注
----
- forcing 文件采用 CAMELS US 风格：前三行为纬度、经度、面积（m²），其后为以空格分隔�?Year/Mnth/Day 及气象列
- 如果缺少 GeoJSON，可写入 NaN/0 作为占位；后续可通过 `--skip-geo` 跳过
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

import numpy as np
import pandas as pd

from neuralhydrology.utils.era5l_hourly_processing import assemble_camels_daily_features


# Windows/conda �?pyproj 可能找不�?PROJ 数据库，这里自动补充一�?
if "PROJ_LIB" not in os.environ:
    exe = Path(sys.executable)
    cand = exe.parent / "Library" / "share" / "proj"
    if cand.exists():
        os.environ["PROJ_LIB"] = str(cand)

try:  # shapely/pyproj �?conda 环境中常驻，如无则降级为占位写入
    from shapely.geometry import shape
    from pyproj import Geod

    _GEOD = Geod(ellps="WGS84")
except Exception:  # pragma: no cover - 容错
    shape = None  # type: ignore
    _GEOD = None  # type: ignore


LEGACY_COLUMNS: Sequence[str] = (
    "total_precipitation_sum",
    "surface_net_solar_radiation_sum",
    "surface_net_thermal_radiation_sum",
    "potential_evaporation_sum",
    "temperature_2m",
    "surface_pressure",
    "u_component_of_wind_10m",
    "v_component_of_wind_10m",
    "snow_depth_water_equivalent",
)


@dataclass
class BasinMeta:
    lat: float
    lon: float
    area_m2: float


def read_basin_list(src: Path, basin_list: Optional[Path]) -> List[str]:
    if basin_list is None:
        return sorted(fp.stem for fp in src.glob("*.csv"))

    ids: List[str] = []
    with basin_list.open("r", encoding="utf-8") as f:
        for line in f:
            basin_id = line.strip()
            if basin_id:
                ids.append(basin_id)
    return ids


def parse_clamp_columns(expr: str) -> List[str]:
    if not expr:
        return []
    return [item.strip() for item in expr.split(",") if item.strip()]


def load_metadata(basin_id: str, geojson_dir: Optional[Path]) -> Optional[BasinMeta]:
    if geojson_dir is None:
        return None

    fp = geojson_dir / f"{basin_id}.geojson"
    if not fp.exists():
        return None

    if shape is None or _GEOD is None:
        return None

    with fp.open("r", encoding="utf-8") as f:
        gj = json.load(f)

    features = gj.get("features", [])
    if not features:
        return None

    geom = shape(features[0]["geometry"])  # type: ignore[index]
    if geom.is_empty:
        return None

    centroid = geom.centroid
    area, _ = _GEOD.geometry_area_perimeter(geom)
    return BasinMeta(lat=float(centroid.y), lon=float(centroid.x), area_m2=abs(float(area)))


def ensure_columns(df: pd.DataFrame, required: Iterable[str]) -> None:
    missing = [col for col in required if col not in df.columns]
    if missing:
        raise ValueError(f"缺少必要�? {missing}")


def clamp_nonnegative(df: pd.DataFrame, columns: Sequence[str]) -> Dict[str, int]:
    stats: Dict[str, int] = {}
    for col in columns:
        if col not in df.columns:
            continue
        series = pd.to_numeric(df[col], errors="coerce")
        negatives = series < 0
        stats[col] = int(negatives.sum())
        df.loc[negatives, col] = 0.0
    return stats


def reindex_and_interpolate(df: pd.DataFrame) -> Tuple[pd.DataFrame, int]:
    df = df.copy()
    df["date"] = pd.to_datetime(df["date"], format="%Y-%m-%d")
    df = df.sort_values("date")
    original_len = len(df)

    df = df.set_index("date")
    full_index = pd.date_range(df.index.min(), df.index.max(), freq="D")
    df = df.reindex(full_index)
    gap_count = len(full_index) - original_len

    numeric_cols = [col for col in df.columns if col in LEGACY_COLUMNS]
    if numeric_cols:
        df[numeric_cols] = df[numeric_cols].interpolate(method="time", limit_direction="both")

    df.index.name = "date"
    df = df.reset_index()
    return df, gap_count


def reindex_daily(df: pd.DataFrame) -> Tuple[pd.DataFrame, int]:
    """Ensure daily dataframe covers continuous date range (no interpolation)."""
    df = df.copy()
    df.index = pd.to_datetime(df.index)
    df = df.sort_index()
    full_index = pd.date_range(df.index.min(), df.index.max(), freq="D")
    gap_count = len(full_index) - len(df)
    df = df.reindex(full_index)
    return df, gap_count


def write_forcing_file(
    df: pd.DataFrame,
    meta: Optional[BasinMeta],
    dst_fp: Path,
    float_format: str,
) -> None:
    dst_fp.parent.mkdir(parents=True, exist_ok=True)

    lat = f"{meta.lat:.6f}" if meta else "nan"
    lon = f"{meta.lon:.6f}" if meta else "nan"
    area_line = (
        f"{int(round(meta.area_m2))}"
        if meta and np.isfinite(meta.area_m2)
        else "0"
    )

    with dst_fp.open("w", encoding="utf-8", newline="\n") as f:
        f.write(f"{lat}\n")
        f.write(f"{lon}\n")
        f.write(f"{area_line}\n")
    df.to_csv(f, sep=" ", index=False, float_format=float_format)


def process_basin_legacy(
    basin_id: str,
    csv_dir: Path,
    dst_dir: Path,
    geojson_dir: Optional[Path],
    clamp_cols: Sequence[str],
    overwrite: bool,
    float_format: str,
) -> Tuple[int, Dict[str, int], int, List[str]]:
    csv_fp = csv_dir / f"{basin_id}.csv"
    if not csv_fp.exists():
        raise FileNotFoundError(f"CSV 不存�? {csv_fp}")

    dst_fp = dst_dir / f"{basin_id}.txt"
    if dst_fp.exists() and not overwrite:
        raise FileExistsError(f"输出已存在，请使�?--overwrite：{dst_fp}")

    df = pd.read_csv(csv_fp)
    ensure_columns(df, ["date", *LEGACY_COLUMNS])

    df, gap_count = reindex_and_interpolate(df)

    clamp_stats = clamp_nonnegative(df, clamp_cols)

    df["Year"] = df["date"].dt.year
    df["Mnth"] = df["date"].dt.month
    df["Day"] = df["date"].dt.day
    df = df[["Year", "Mnth", "Day", *LEGACY_COLUMNS]]

    missing_cols = [col for col in LEGACY_COLUMNS if df[col].isna().any()]

    meta = load_metadata(basin_id, geojson_dir)
    write_forcing_file(df, meta, dst_fp, float_format=float_format)

    return len(df), clamp_stats, gap_count, missing_cols


def process_basin_camels(
    basin_id: str,
    csv_dir: Path,
    dst_dir: Path,
    geojson_dir: Optional[Path],
    clamp_cols: Sequence[str],
    overwrite: bool,
    float_format: str,
) -> Tuple[int, Dict[str, int], int, List[str]]:
    csv_fp = csv_dir / f"{basin_id}.csv"
    if not csv_fp.exists():
        raise FileNotFoundError(f"CSV 不存�? {csv_fp}")

    dst_fp = dst_dir / f"{basin_id}.txt"
    if dst_fp.exists() and not overwrite:
        raise FileExistsError(f"输出已存在，请使�?--overwrite：{dst_fp}")

    df = pd.read_csv(csv_fp)
    if "date" not in df.columns:
        raise ValueError(f"{csv_fp} 缺少 'date' 列，请先运行 hourly 聚合脚本")
    df["date"] = pd.to_datetime(df["date"], format="%Y-%m-%d")
    df = df.set_index("date").sort_index()

    df, gap_count = reindex_daily(df)
    camels_df = assemble_camels_daily_features(df)

    clamp_stats = clamp_nonnegative(camels_df, clamp_cols)
    value_cols = [c for c in camels_df.columns if c not in {"Year", "Mnth", "Day"}]
    missing_cols = [col for col in value_cols if camels_df[col].isna().any()]

    meta = load_metadata(basin_id, geojson_dir)
    write_forcing_file(camels_df, meta, dst_fp, float_format=float_format)

    return len(camels_df), clamp_stats, gap_count, missing_cols


def main():
    ap = argparse.ArgumentParser(description="Write per-basin CSV files to CAMELS-style forcing format")
    ap.add_argument("--src", required=True, type=Path, help="Directory containing per-basin CSV files")
    ap.add_argument("--dst", required=True, type=Path, help="forcing 输出目录")
    ap.add_argument("--geojson-dir", type=Path, default=None, help="GeoJSON 目录，用于写入质心与面积")
    ap.add_argument("--basin-list", type=Path, default=None, help="Optional basin_id allow-list")
    ap.add_argument("--clamp-nonnegative", default="", help="Comma-separated columns to clamp at zero")
    ap.add_argument("--overwrite", action="store_true", help="允许覆盖已存在的 forcing 文件")
    ap.add_argument("--limit", type=int, default=None, help="Only process first N basins (debug)")
    ap.add_argument("--float-format", default="%.6f", help="Floating point output format")
    ap.add_argument("--schema", choices=["legacy", "camels"], default="legacy",
                    help="Input CSV schema: legacy for old daily aggregate, camels for hourly->daily CAMELS aggregate")
    args = ap.parse_args()

    csv_dir: Path = args.src
    dst_dir: Path = args.dst
    geojson_dir: Optional[Path] = args.geojson_dir
    basin_list = args.basin_list
    clamp_cols = parse_clamp_columns(args.clamp_nonnegative)
    if not clamp_cols:
        if args.schema == "camels":
            clamp_cols = ["prcp(mm/day)", "pet(mm/day)", "snowfall(mm/day)"]
        else:
            clamp_cols = [
                "total_precipitation_sum",
                "potential_evaporation_sum",
                "snow_depth_water_equivalent",
            ]

    if not csv_dir.exists():
        raise SystemExit(f"输入目录不存�? {csv_dir}")

    basins = read_basin_list(csv_dir, basin_list)
    if args.limit is not None:
        basins = basins[: args.limit]

    processed = 0
    total_rows = 0
    total_gap_days = 0
    agg_clamp: Dict[str, int] = {col: 0 for col in clamp_cols}
    basins_with_missing: List[Tuple[str, List[str]]] = []

    processor = process_basin_legacy if args.schema == "legacy" else process_basin_camels

    for basin_id in basins:
        rows, stats, gap_count, missing_cols = processor(
            basin_id=basin_id,
            csv_dir=csv_dir,
            dst_dir=dst_dir,
            geojson_dir=geojson_dir,
            clamp_cols=clamp_cols,
            overwrite=args.overwrite,
            float_format=args.float_format,
        )
        processed += 1
        total_rows += rows
        total_gap_days += gap_count
        for col, cnt in stats.items():
            agg_clamp[col] = agg_clamp.get(col, 0) + cnt
        if missing_cols:
            basins_with_missing.append((basin_id, missing_cols))

    if processed == 0:
        print("[WARN] 未处理任�?basin")
        return

    print(f"[OK] forcing 写入完成: {processed} basins, {total_rows} rows")
    if total_gap_days:
        print(f"[INFO] 补齐缺失日期: {total_gap_days}")
    if agg_clamp:
        print("[INFO] Non-negative clamp counts:")
        for col, cnt in agg_clamp.items():
            print(f"  {col}: {cnt}")
    if basins_with_missing:
        print("[WARN] The following basins still contain NaN values and need follow-up processing:")
        for bid, cols in basins_with_missing:
            print(f"  {bid}: {', '.join(cols)}")


if __name__ == "__main__":
    main()


