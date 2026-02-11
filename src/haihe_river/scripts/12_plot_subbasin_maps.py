#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Generate GIS-style maps (choropleths) for key subbasin indicators.

Inputs
------
- Subbasin geometry (GeoPackage/GeoJSON/Shapefile)
- Per-basin statistics CSV (output of 11_subbasin_quick_healthcheck.py)

Outputs
-------
- Individual PNG maps for each requested indicator (default: area, mean elevation,
  mean slope, relief range) stored in the specified output directory.
"""
from __future__ import annotations

import argparse
from pathlib import Path
from typing import Dict, Optional

import geopandas as gpd
import matplotlib.pyplot as plt
import matplotlib.colors as colors
import numpy as np
import pandas as pd

# same metadata as 11_subbasin_quick_healthcheck.py to keep labels/units consistent
COLUMN_METADATA: Dict[str, Dict[str, Optional[str]]] = {
    "area_km2": {"label": "Area", "unit": "km^2"},
    "elev_mean": {"label": "Mean elevation", "unit": "m"},
    "elev_median": {"label": "Median elevation", "unit": "m"},
    "elev_min": {"label": "Min elevation", "unit": "m"},
    "elev_max": {"label": "Max elevation", "unit": "m"},
    "elev_std": {"label": "Elevation stdev", "unit": "m"},
    "slope_mean": {"label": "Mean slope", "unit": "deg"},
    "slope_median": {"label": "Median slope", "unit": "deg"},
    "slope_std": {"label": "Slope stdev", "unit": "deg"},
    "relief_range": {"label": "Relief (max-min)", "unit": "m"},
    "relief_std": {"label": "Relief stdev", "unit": "m"},
}

DEFAULT_COLUMNS = ["area_km2", "elev_mean", "slope_mean", "relief_range"]


def load_data(basin_path: Path, layer: Optional[str], stats_path: Path, id_field: str) -> gpd.GeoDataFrame:
    basins = gpd.read_file(basin_path, layer=layer) if layer else gpd.read_file(basin_path)
    if basins.crs is None:
        raise ValueError(f"Basins file {basin_path} lacks CRS information.")
    stats = pd.read_csv(stats_path)
    if id_field not in basins.columns:
        raise KeyError(f"{id_field} not found in basin file columns: {basins.columns.tolist()}")
    if id_field not in stats.columns:
        raise KeyError(f"{id_field} not found in stats file columns: {stats.columns.tolist()}")
    merged = basins.merge(stats, on=id_field, how="left")
    return merged


def display_name(column: str) -> str:
    meta = COLUMN_METADATA.get(column, {})
    label = meta.get("label", column)
    unit = meta.get("unit")
    return f"{label} ({unit})" if unit else label


def plot_indicator(gdf: gpd.GeoDataFrame, column: str, out_dir: Path, cmap: str = "viridis") -> Optional[Path]:
    if column not in gdf.columns:
        print(f"[skip] Column '{column}' missing.")
        return None
    series = gdf[column]
    valid = series.replace([np.inf, -np.inf], np.nan).dropna()
    if valid.empty:
        print(f"[skip] Column '{column}' has no valid data.")
        return None

    q02, q98 = valid.quantile([0.02, 0.98])
    vmin = float(q02)
    vmax = float(q98)
    if np.isclose(vmin, vmax):
        vmin = float(valid.min())
        vmax = float(valid.max())
    if np.isclose(vmin, vmax):
        vmax = vmin + 1.0

    norm = colors.Normalize(vmin=vmin, vmax=vmax)
    fig, ax = plt.subplots(figsize=(8, 7))
    gdf.plot(
        column=column,
        ax=ax,
        cmap=cmap,
        linewidth=0.1,
        edgecolor="black",
        norm=norm,
        missing_kwds={"color": "#d9d9d9", "edgecolor": "black", "label": "No data"},
    )
    ax.set_xticks([])
    ax.set_yticks([])
    ax.set_axis_off()
    title = display_name(column)
    ax.set_title(title, fontsize=14, fontweight="bold")

    sm = plt.cm.ScalarMappable(norm=norm, cmap=cmap)
    sm._A = []  # required for matplotlib < 3.8
    cbar = fig.colorbar(sm, ax=ax, fraction=0.028, pad=0.02)
    cbar.ax.set_ylabel(display_name(column), rotation=270, labelpad=15)

    output = out_dir / f"{column}_map.png"
    fig.savefig(output, dpi=200, bbox_inches="tight")
    plt.close(fig)
    print(f"[saved] {output}")
    return output


def main():
    parser = argparse.ArgumentParser(description="Plot GIS-style subbasin indicator maps.")
    parser.add_argument("--basins", required=True, help="Subbasin geometry file (GeoPackage/GeoJSON/Shapefile)")
    parser.add_argument("--layer", default=None, help="Optional layer name for GeoPackage input")
    parser.add_argument("--stats", required=True, help="Per-basin statistics CSV produced by health check script")
    parser.add_argument("--id-field", default="basin_id", help="Join key present in both geometry and stats (default: basin_id)")
    parser.add_argument(
        "--columns",
        nargs="+",
        default=DEFAULT_COLUMNS,
        help=f"Indicator columns to visualize (default: {DEFAULT_COLUMNS})",
    )
    parser.add_argument("--outdir", required=True, help="Output directory for generated maps")
    parser.add_argument("--cmap", default="viridis", help="Matplotlib colormap (default: viridis)")
    args = parser.parse_args()

    basin_path = Path(args.basins)
    stats_path = Path(args.stats)
    out_dir = Path(args.outdir)
    out_dir.mkdir(parents=True, exist_ok=True)

    gdf = load_data(basin_path, args.layer, stats_path, args.id_field)
    for column in args.columns:
        try:
            plot_indicator(gdf, column, out_dir, cmap=args.cmap)
        except Exception as exc:  # safeguard to continue other columns
            print(f"[error] Failed to plot {column}: {exc}")


if __name__ == "__main__":
    main()

