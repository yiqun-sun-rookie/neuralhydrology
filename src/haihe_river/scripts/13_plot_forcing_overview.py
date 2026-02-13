#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Plot overview figures for Haihe lev9 forcing and static attributes."""

from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd
import seaborn as sns


def main():
    ap = argparse.ArgumentParser(description="绘制 forcing 与静态属性概览图")
    ap.add_argument("--summary", default="results/06_haihe_river/reports/forcing_summary_lev9.csv")
    ap.add_argument("--attributes", default="data/haihe/attributes/attributes.csv")
    ap.add_argument("--out", default="results/06_haihe_river/reports/forcing_attributes_overview.png")
    args = ap.parse_args()

    df_summary = pd.read_csv(args.summary)
    df_attrs = pd.read_csv(args.attributes)

    df = df_attrs.merge(df_summary, on="basin_id", suffixes=("", "_summary"))

    sns.set_theme(style="whitegrid")
    fig, axes = plt.subplots(1, 2, figsize=(12, 5))

    sns.histplot(df["area_km2_geod"], bins=40, color="#2a9d8f", ax=axes[0])
    axes[0].set_title("流域面积分布 (km²)")
    axes[0].set_xlabel("面积 (km²)")
    axes[0].set_ylabel("频数")

    scatter = axes[1].scatter(df["centroid_lon"], df["centroid_lat"],
                               c=df["area_km2_geod"], cmap="viridis", s=12)
    axes[1].set_title("Centroid locations and area")
    axes[1].set_xlabel("经度")
    axes[1].set_ylabel("纬度")
    plt.colorbar(scatter, ax=axes[1], label="面积 (km²)")

    fig.suptitle(f"Haihe lev9 forcing and attributes overview (n={len(df)})", fontsize=14)
    fig.tight_layout(rect=[0, 0, 1, 0.96])

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, dpi=200)
    print(f"[OK] Saved figure: {out_path}")


if __name__ == "__main__":
    main()

