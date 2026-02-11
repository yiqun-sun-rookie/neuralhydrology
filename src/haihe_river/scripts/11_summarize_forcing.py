#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""汇�?NH forcing 文本的基础质量信息并导出报告�?

输出：`reports/forcing_summary_lev9.csv`（可通过参数调整），包含每个流域�?
- 起止日期、总天�?
- 任意缺失值数量（按列�?
- 负值计数（按列�?
- 非单调日�?重复日期检�?
- 文件首三行给出的纬度、经度与面积

示例�?
```
python projects/haihe/scripts/11_summarize_forcing.py \
  --dir data/haihe/forcing \
  --out reports/forcing_summary_lev9.csv \
  --check-negative total_precipitation_sum,potential_evaporation_sum,snow_depth_water_equivalent
```
"""

from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Sequence

import numpy as np
import pandas as pd


@dataclass
class ForcingSummary:
    basin_id: str
    rows: int
    date_start: str
    date_end: str
    has_duplicate_dates: bool
    has_gap: bool
    lat: float
    lon: float
    area_m2: float
    na_counts: Dict[str, int]
    negative_counts: Dict[str, int]


def parse_front_matter(fp: Path) -> Dict[str, float]:
    with fp.open("r", encoding="utf-8") as f:
        lat_line = f.readline().strip()
        lon_line = f.readline().strip()
        area_line = f.readline().strip()

    def _parse(value: str) -> float:
        if value.lower() in {"nan", ""}:
            return float("nan")
        try:
            return float(value)
        except ValueError:
            return float("nan")

    return {
        "lat": _parse(lat_line),
        "lon": _parse(lon_line),
        "area_m2": _parse(area_line),
    }


def load_forcing_table(fp: Path) -> pd.DataFrame:
    df = pd.read_csv(fp, sep=r"\s+", skiprows=3)
    df = df.dropna(how="all")  # 防守：若末尾空行
    df["date"] = pd.to_datetime(dict(year=df["Year"], month=df["Mnth"], day=df["Day"]))
    return df


def detect_gap(dates: pd.Series) -> bool:
    if dates.empty:
        return False
    expected = pd.date_range(dates.iloc[0], dates.iloc[-1], freq="D")
    return len(expected) != len(dates)


def summarize_forcing(
    fp: Path,
    check_negative_cols: Sequence[str],
) -> ForcingSummary:
    meta = parse_front_matter(fp)
    df = load_forcing_table(fp)

    basin_id = fp.stem
    rows = len(df)
    if rows == 0:
        date_start = date_end = ""
        has_duplicate = False
        has_gap = False
    else:
        df = df.sort_values("date")
        has_duplicate = df["date"].duplicated().any()
        has_gap = detect_gap(df["date"].reset_index(drop=True))
        date_start = df["date"].iloc[0].strftime("%Y-%m-%d")
        date_end = df["date"].iloc[-1].strftime("%Y-%m-%d")

    numeric_cols = [c for c in df.columns if c not in {"Year", "Mnth", "Day", "date"}]
    na_counts = {col: int(df[col].isna().sum()) for col in numeric_cols}

    negative_counts: Dict[str, int] = {}
    for col in check_negative_cols:
        if col in df.columns:
            negative_counts[col] = int((df[col] < 0).sum())

    return ForcingSummary(
        basin_id=basin_id,
        rows=rows,
        date_start=date_start,
        date_end=date_end,
        has_duplicate_dates=has_duplicate,
        has_gap=has_gap,
        lat=meta["lat"],
        lon=meta["lon"],
        area_m2=meta["area_m2"],
        na_counts=na_counts,
        negative_counts=negative_counts,
    )


def read_basin_list(root: Path, basin_list: Optional[Path]) -> List[str]:
    if basin_list is None:
        return sorted(fp.stem for fp in root.glob("*.txt"))

    ids: List[str] = []
    with basin_list.open("r", encoding="utf-8") as f:
        for line in f:
            basin_id = line.strip()
            if basin_id:
                ids.append(basin_id)
    return ids


def to_dataframe(records: List[ForcingSummary]) -> pd.DataFrame:
    rows: List[Dict[str, object]] = []
    for rec in records:
        base = {
            "basin_id": rec.basin_id,
            "rows": rec.rows,
            "date_start": rec.date_start,
            "date_end": rec.date_end,
            "has_duplicate_dates": rec.has_duplicate_dates,
            "has_gap": rec.has_gap,
            "lat": rec.lat,
            "lon": rec.lon,
            "area_m2": rec.area_m2,
        }

        for col, cnt in rec.na_counts.items():
            base[f"na_{col}"] = cnt

        for col, cnt in rec.negative_counts.items():
            base[f"neg_{col}"] = cnt

        rows.append(base)

    df = pd.DataFrame(rows).set_index("basin_id").sort_index()
    return df


def main():
    ap = argparse.ArgumentParser(description="汇�?forcing 文本质量信息")
    ap.add_argument("--dir", required=True, type=Path, help="forcing 文本目录")
    ap.add_argument("--out", required=True, type=Path, help="输出 CSV 路径")
    ap.add_argument("--basin-list", type=Path, default=None, help="可选：限定 basin id 列表")
    ap.add_argument(
        "--check-negative",
        default="",
        help="需要检查负值的列名，逗号分隔",
    )
    args = ap.parse_args()

    root: Path = args.dir
    if not root.exists():
        raise SystemExit(f"输入目录不存在：{root}")

    check_negative_cols: Sequence[str] = [
        col.strip() for col in args.check_negative.split(",") if col.strip()
    ]

    basins = read_basin_list(root, args.basin_list)
    records: List[ForcingSummary] = []
    for basin_id in basins:
        fp = root / f"{basin_id}.txt"
        if not fp.exists():
            print(f"[WARN] 找不�?forcing 文件：{fp}")
            continue
        summary = summarize_forcing(fp, check_negative_cols)
        records.append(summary)

    if not records:
        raise SystemExit("No forcing summary records were generated.")

    df = to_dataframe(records)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(args.out)

    duplicates = df[df["has_duplicate_dates"]].shape[0]
    gaps = df[df["has_gap"]].shape[0]
    print(f"[OK] 汇总完成：{len(df)} basins -> {args.out}")
    print(f"[INFO] 含重复日�? {duplicates}")
    print(f"[INFO] 含缺口日�? {gaps}")

    if check_negative_cols:
        for col in check_negative_cols:
            neg_col = f"neg_{col}"
            if neg_col in df.columns:
                total_neg = int(df[neg_col].fillna(0).sum())
                print(f"[INFO] {col} 负值计数总和: {total_neg}")


if __name__ == "__main__":
    main()


