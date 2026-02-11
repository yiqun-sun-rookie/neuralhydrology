#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""根据 forcing 汇总与 HydroBASINS 列表生成基础静态属性表�?

输出：`data/haihe/attributes/attributes.csv`

列说明：
- `hybas_id`: HydroBASINS ID�?
- `area_km2_geod`: 根据 GeoJSON 质心/面积计算的面积（km²）�?
- `area_km2_sub`: HydroBASINS `SUB_AREA`（km²），供对照�?
- `centroid_lat`/`centroid_lon`: forcing 文件首行写入的质心坐标�?
- `forcing_rows`: forcing 行数（天数）�?
- `forcing_missing_any`: 是否仍存在缺失值�?
- `forcing_missing_columns`: 存在缺失的列名（逗号分隔，若无则为空）�?
- `forcing_all_nan`: 所�?forcing 列是否全为缺失（用于标记需剔除的流域）�?

依赖�?
- 在执行本脚本前，应先运行 `10_write_forcing_from_timeseries_lev9.py` �?
  `11_summarize_forcing.py`，保�?`reports/forcing_summary_lev9.csv` 为最新�?
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import List

import pandas as pd


def collect_missing_columns(row: pd.Series, na_prefix: str = "na_") -> List[str]:
    cols = []
    for col, value in row.items():
        if col.startswith(na_prefix) and value > 0:
            cols.append(col[len(na_prefix):])
    return cols


def main():
    ap = argparse.ArgumentParser(description="生成海河 lev9 静态属性表")
    ap.add_argument("--summary", default="reports/forcing_summary_lev9.csv", help="forcing 汇�?CSV 路径")
    ap.add_argument("--hybas", default="data/haihe/hydrobasins/lev9/haihe_hybas_lev9_list.csv", help="HydroBASINS 列表")
    ap.add_argument("--out-dir", default="data/haihe/attributes", help="输出目录")
    args = ap.parse_args()

    summary_path = Path(args.summary)
    hybas_path = Path(args.hybas)
    out_dir = Path(args.out_dir)

    if not summary_path.exists():
        raise SystemExit(f"未找�?forcing 汇总文件：{summary_path}")
    if not hybas_path.exists():
        raise SystemExit(f"未找�?HydroBASINS 列表：{hybas_path}")

    df_summary = pd.read_csv(summary_path)
    df_hybas = pd.read_csv(hybas_path)

    df_summary = df_summary.set_index("basin_id")
    df_hybas = df_hybas.set_index("basin_id")

    df = df_summary.join(df_hybas, how="left")

    if df["HYBAS_ID"].isna().any():
        missing = df[df["HYBAS_ID"].isna()].index.tolist()
        print(f"[WARN] {len(missing)} 个流域缺�?HYBAS_ID: {missing[:10]}")

    na_cols = df.filter(like="na_").columns

    df_out = pd.DataFrame(index=df.index)
    df_out["hybas_id"] = df["HYBAS_ID"].astype("Int64")
    df_out["area_km2_geod"] = df["area_m2"] / 1e6
    df_out["area_km2_sub"] = df["SUB_AREA"]
    df_out["centroid_lat"] = df["lat"]
    df_out["centroid_lon"] = df["lon"]
    df_out["forcing_rows"] = df["rows"].astype(int)

    missing_lists = df.apply(lambda row: collect_missing_columns(row[na_cols]), axis=1)
    df_out["forcing_missing_any"] = missing_lists.map(lambda lst: len(lst) > 0)
    df_out["forcing_missing_columns"] = missing_lists.map(lambda lst: ",".join(lst))
    df_out["forcing_all_nan"] = df_out["forcing_missing_any"] & (df_out["forcing_missing_columns"].map(lambda s: set(s.split(",")) if s else set()) == set([col[len("na_"):] for col in na_cols]))

    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "attributes.csv"
    df_out.to_csv(out_path)
    print(f"[OK] 静态属性已写入: {out_path}")


if __name__ == "__main__":
    main()


