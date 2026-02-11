#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Quick health check for a subbasin collection.

Metrics
-------
- Always: sample size, area distribution (extremes + quantiles)
- With DEM + slope rasters: mean/median elevation & slope, relief (max-min and std)

Inputs
------
- Subbasin polygons (GeoPackage/GeoJSON/Shapefile, preferably EPSG:4326)
- DEM GeoTIFF (required) providing elevation in meters
- Slope GeoTIFF (required) providing slope (degrees or percent, consistent with the raster)

Outputs
-------
- per-basin CSV with all metrics
- summary Markdown with extremes and quantiles
- tables/ directory: summary stats, quantiles, top/bottom rankings (CSV + Markdown)
- figures/ directory: histograms, boxplots, ECDF plots (English labels)

Example
-------
python projects/haihe/scripts/11_subbasin_quick_healthcheck.py ^
  --basins data/haihe/hydrobasins/lev12/haihe_hydrobasins_lev12.gpkg ^
  --layer basins ^
  --dem data/haihe/dem/haihe_srtm_dem.tif ^
  --slope data/haihe/dem/haihe_srtm_slope.tif ^
  --outdir outputs/haihe_healthcheck
"""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path
from typing import Optional, Sequence, Dict, Any

import geopandas as gpd
import numpy as np
import pandas as pd
import rasterio
from pyproj import Geod
from shapely.geometry import Polygon, MultiPolygon
from tqdm import tqdm

try:
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
except Exception:
    matplotlib = None
    plt = None

try:
    from rasterstats import zonal_stats
except Exception:
    zonal_stats = None  # allow area-only stats when rasterstats is missing


GEOD = Geod(ellps="WGS84")

SUMMARY_QUANTILES = [0.0, 0.05, 0.25, 0.5, 0.75, 0.95, 1.0]

DEFAULT_BASINS = Path("data/haihe/hydrobasins/lev12/haihe_hydrobasins_lev12.gpkg")
DEFAULT_LAYER = "basins"
DEFAULT_ID_FIELD = "basin_id"
DEFAULT_DEM = Path("data/haihe/dem/haihe_srtm_dem.tif")
DEFAULT_SLOPE = Path("data/haihe/dem/haihe_srtm_slope.tif")
DEFAULT_OUTDIR = Path("outputs/haihe_healthcheck")

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

RANK_VARIABLES = ["area_km2", "slope_mean", "relief_range"]


@dataclass
class PerBasinStats:
    basin_id: Optional[str]
    area_km2: float
    elev_mean: Optional[float] = None
    elev_median: Optional[float] = None
    elev_min: Optional[float] = None
    elev_max: Optional[float] = None
    elev_std: Optional[float] = None
    slope_mean: Optional[float] = None
    slope_median: Optional[float] = None
    slope_std: Optional[float] = None
    relief_range: Optional[float] = None  # max - min
    relief_std: Optional[float] = None    # std of elevation


def read_basins(path: Path, layer: Optional[str]) -> gpd.GeoDataFrame:
    gdf = gpd.read_file(path, layer=layer) if layer else gpd.read_file(path)
    # convert to WGS84 to leverage geodesic area
    if gdf.crs is None or gdf.crs.to_epsg() != 4326:
        gdf = gdf.to_crs(4326)
    # drop invalid geometries
    gdf = gdf[~gdf.geometry.is_empty & gdf.geometry.notna()].copy()
    gdf = gdf.reset_index(drop=True)
    return gdf


def geodesic_area_sq_m(geom: Polygon | MultiPolygon) -> float:
    area, _ = GEOD.geometry_area_perimeter(geom)
    return abs(area)


def calc_area_km2(gdf: gpd.GeoDataFrame) -> np.ndarray:
    areas = []
    for geom in gdf.geometry.values:
        areas.append(geodesic_area_sq_m(geom) / 1e6)
    return np.asarray(areas, dtype=float)


def compute_zonal(
    gdf: gpd.GeoDataFrame,
    raster_path: Optional[Path],
    stats: Sequence[str],
    fallback_nodata: Optional[float] = None,
) -> Optional[list[Dict[str, Any]]]:
    if raster_path is None:
        return None
    if zonal_stats is None:
        raise RuntimeError("rasterstats is required for DEM/slope zonal statistics. Install via 'pip install rasterstats'.")
    if not Path(raster_path).exists():
        raise FileNotFoundError(f"Raster not found: {raster_path}")
    with rasterio.open(raster_path) as src:
        nodata_val = src.nodata if src.nodata is not None else fallback_nodata
    # use all_touched=False to avoid overly generous inclusion, honour raster nodata
    zs = zonal_stats(
        vectors=gdf.geometry,
        raster=str(raster_path),
        stats=list(stats),
        all_touched=False,
        nodata=nodata_val,
        geojson_out=False
    )
    return zs


def to_quantile_series(values: pd.Series, q: Sequence[float]) -> pd.Series:
    return values.quantile(q=q).rename(index=lambda x: f"p{int(x*100):02d}")


def build_summary(df: pd.DataFrame) -> str:
    lines: list[str] = []
    lines.append("# Subbasin health check report")
    lines.append("")
    lines.append(f"- Sample size: {len(df)}")
    lines.append("")

    def section(title: str, series: pd.Series):
        nonlocal lines
        series = series.dropna()
        if series.empty:
            return
        q = to_quantile_series(series, q=SUMMARY_QUANTILES)
        lines.append(f"## {title}")
        lines.append("")
        lines.append(f"- Min: {series.min():.3f}")
        lines.append(f"- Max: {series.max():.3f}")
        lines.append(f"- Mean: {series.mean():.3f}")
        lines.append(f"- Median: {series.median():.3f}")
        lines.append("")
        lines.append("Quantiles:")
        lines.append("")
        lines.append("| Quantile | Value |")
        lines.append("|---|---:|")
        for idx, val in q.items():
            lines.append(f"| {idx} | {val:.3f} |")
        lines.append("")

    section("Area (km^2)", df["area_km2"])
    if "elev_mean" in df.columns:
        section("Mean elevation (m)", df["elev_mean"])
    if "elev_median" in df.columns:
        section("Median elevation (m)", df["elev_median"])
    if "slope_mean" in df.columns:
        section("Mean slope", df["slope_mean"])
    if "slope_median" in df.columns:
        section("Median slope", df["slope_median"])
    if "relief_range" in df.columns:
        section("Relief (max-min, m)", df["relief_range"])
    if "relief_std" in df.columns:
        section("Relief stdev (m)", df["relief_std"])
    return "\n".join(lines)


def build_summary_table(df: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for col, meta in COLUMN_METADATA.items():
        if col not in df.columns:
            continue
        series = df[col].dropna()
        if series.empty:
            continue
        rows.append(
            {
                "column": col,
                "label": meta.get("label", col),
                "unit": meta.get("unit") or "",
                "count": int(len(series)),
                "min": float(series.min()),
                "p05": float(series.quantile(0.05)),
                "p25": float(series.quantile(0.25)),
                "median": float(series.median()),
                "p75": float(series.quantile(0.75)),
                "p95": float(series.quantile(0.95)),
                "max": float(series.max()),
                "mean": float(series.mean()),
                "std": float(series.std(ddof=1)) if len(series) >= 2 else np.nan,
            }
        )
    return pd.DataFrame(rows)


def build_quantiles_table(df: pd.DataFrame) -> pd.DataFrame:
    index = [f"p{int(q * 100):02d}" for q in SUMMARY_QUANTILES]
    quantiles_df = pd.DataFrame(index=index)
    for col, meta in COLUMN_METADATA.items():
        if col not in df.columns:
            continue
        series = df[col].dropna()
        if series.empty:
            continue
        quantiles_df[col] = [float(series.quantile(q)) for q in SUMMARY_QUANTILES]
    return quantiles_df


def _format_value(val) -> str:
    if isinstance(val, (float, np.floating)):
        if np.isnan(val):
            return ""
        return f"{val:.3f}"
    if pd.isna(val):
        return ""
    return str(val)


def save_markdown_table(df: pd.DataFrame, path: Path) -> Optional[Path]:
    if df.empty:
        return None
    df = df.copy()
    if df.index.name or df.index.tolist() != list(range(len(df))):
        df = df.reset_index().rename(columns={"index": df.index.name or "index"})
    headers = list(df.columns)
    lines = []
    lines.append("| " + " | ".join(headers) + " |")
    lines.append("| " + " | ".join(["---"] * len(headers)) + " |")
    for _, row in df.iterrows():
        values = [_format_value(row[col]) for col in headers]
        lines.append("| " + " | ".join(values) + " |")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return path


def _display_name(column: str) -> str:
    meta = COLUMN_METADATA.get(column, {})
    label = meta.get("label", column)
    unit = meta.get("unit")
    return f"{label} ({unit})" if unit else label


def generate_rank_tables(df: pd.DataFrame, tables_dir: Path, basin_col: str = "basin_id", top_n: int = 20) -> list[Path]:
    generated: list[Path] = []
    if basin_col not in df.columns:
        return generated
    for col in RANK_VARIABLES:
        if col not in df.columns:
            continue
        subset = df[[basin_col, col]].dropna()
        if subset.empty:
            continue
        display = _display_name(col)
        subset = subset.rename(columns={basin_col: "basin_id", col: display})
        top = subset.nlargest(top_n, display)
        bottom = subset.nsmallest(top_n, display)
        top_path = tables_dir / f"top{top_n}_{col}.csv"
        bottom_path = tables_dir / f"bottom{top_n}_{col}.csv"
        top.to_csv(top_path, index=False, encoding="utf-8-sig", float_format="%.3f")
        bottom.to_csv(bottom_path, index=False, encoding="utf-8-sig", float_format="%.3f")
        generated.extend([top_path, bottom_path])
        save_markdown_table(top, tables_dir / f"top{top_n}_{col}.md")
        save_markdown_table(bottom, tables_dir / f"bottom{top_n}_{col}.md")
    return generated


def generate_additional_tables(df: pd.DataFrame, tables_dir: Path) -> list[Path]:
    tables_dir.mkdir(parents=True, exist_ok=True)
    generated: list[Path] = []

    summary_table = build_summary_table(df)
    if not summary_table.empty:
        summary_csv = tables_dir / "summary_stats.csv"
        summary_table.to_csv(summary_csv, index=False, encoding="utf-8-sig", float_format="%.3f")
        generated.append(summary_csv)
        md_path = tables_dir / "summary_stats.md"
        saved = save_markdown_table(summary_table, md_path)
        if saved:
            generated.append(saved)

    quantiles_table = build_quantiles_table(df)
    if not quantiles_table.empty:
        quantiles_csv = tables_dir / "summary_quantiles.csv"
        quantiles_table.to_csv(quantiles_csv, encoding="utf-8-sig", float_format="%.3f")
        generated.append(quantiles_csv)
        quantiles_md_df = quantiles_table.copy()
        quantiles_md_df.insert(0, "quantile", quantiles_md_df.index)
        quantiles_md = tables_dir / "summary_quantiles.md"
        saved = save_markdown_table(quantiles_md_df.reset_index(drop=True), quantiles_md)
        if saved:
            generated.append(saved)

    generated.extend(generate_rank_tables(df, tables_dir))
    return generated


def plot_hist_box(series: pd.Series, meta: Dict[str, Optional[str]], path: Path, log_scale: bool = False) -> Optional[Path]:
    if plt is None:
        return None
    data = series.dropna()
    if data.empty:
        return None
    if log_scale:
        data = data[data > 0]
        if data.empty:
            return None
    bins = min(50, max(10, int(np.sqrt(len(data)))))
    fig, axes = plt.subplots(1, 2, figsize=(11, 4.5))
    axes[0].hist(data, bins=bins, color="#1f77b4", alpha=0.78, edgecolor="white")
    axes[0].set_ylabel("Count")
    if log_scale:
        axes[0].set_xscale("log")
        axes[0].set_title(f"{meta.get('label', '')} distribution (log scale)")
    else:
        axes[0].set_title(f"{meta.get('label', '')} distribution")
    axes[0].set_xlabel(_display_name_from_meta(meta))
    axes[0].grid(alpha=0.3, linestyle="--")

    axes[1].boxplot(data, vert=True, patch_artist=True, boxprops=dict(facecolor="#ff7f0e", alpha=0.6))
    axes[1].set_ylabel(_display_name_from_meta(meta))
    axes[1].set_xticks([])
    axes[1].set_title("Boxplot")

    fig.tight_layout()
    fig.savefig(path, dpi=180)
    plt.close(fig)
    return path


def plot_ecdf(series: pd.Series, meta: Dict[str, Optional[str]], path: Path, log_scale: bool = False) -> Optional[Path]:
    if plt is None:
        return None
    data = series.dropna()
    if data.empty:
        return None
    if log_scale:
        data = data[data > 0]
        if data.empty:
            return None
    data = np.sort(data.to_numpy())
    y = (np.arange(len(data)) + 1) / len(data)
    fig, ax = plt.subplots(figsize=(6.5, 4.5))
    ax.step(data, y, where="post", color="#2ca02c")
    if log_scale:
        ax.set_xscale("log")
        ax.set_title(f"{meta.get('label', '')} ECDF (log scale)")
    else:
        ax.set_title(f"{meta.get('label', '')} ECDF")
    ax.set_xlabel(_display_name_from_meta(meta))
    ax.set_ylabel("Cumulative probability")
    ax.grid(alpha=0.3, linestyle="--")
    fig.tight_layout()
    fig.savefig(path, dpi=180)
    plt.close(fig)
    return path


def _display_name_from_meta(meta: Dict[str, Optional[str]]) -> str:
    label = meta.get("label", "")
    unit = meta.get("unit")
    return f"{label} ({unit})" if unit else label


def generate_figures(df: pd.DataFrame, figures_dir: Path) -> list[Path]:
    if plt is None:
        print("Warning: matplotlib not available. Skipping figure generation. Install via 'pip install matplotlib'.")
        return []
    figures_dir.mkdir(parents=True, exist_ok=True)
    generated: list[Path] = []
    for col, meta in COLUMN_METADATA.items():
        if col not in df.columns:
            continue
        data = df[col].dropna()
        if data.empty:
            continue
        hist_path = figures_dir / f"{col}_hist_box.png"
        saved = plot_hist_box(data, meta, hist_path, log_scale=False)
        if saved:
            generated.append(saved)
        if col == "area_km2":
            positive = data[data > 0]
            if len(positive) > 0 and positive.max() / positive.min() > 50:
                log_path = figures_dir / f"{col}_hist_box_log.png"
                saved_log = plot_hist_box(positive, meta, log_path, log_scale=True)
                if saved_log:
                    generated.append(saved_log)
        ecdf_path = figures_dir / f"{col}_ecdf.png"
        saved_ecdf = plot_ecdf(data, meta, ecdf_path, log_scale=(col == "area_km2"))
        if saved_ecdf:
            generated.append(saved_ecdf)
    return generated


def main():
    ap = argparse.ArgumentParser(description="Subbasin collection quick health check")
    ap.add_argument(
        "--basins",
        default=str(DEFAULT_BASINS),
        help=f"Subbasin boundary file (.gpkg/.geojson/.shp etc.) [default: {DEFAULT_BASINS}]",
    )
    ap.add_argument(
        "--layer",
        default=DEFAULT_LAYER,
        help=f"Optional layer name (e.g. for GeoPackage) [default: {DEFAULT_LAYER}]",
    )
    ap.add_argument(
        "--id-field",
        default=DEFAULT_ID_FIELD,
        help=f"Column to use as basin_id (e.g. HYBAS_ID/basin_id) [default: {DEFAULT_ID_FIELD}]",
    )
    ap.add_argument(
        "--dem",
        default=str(DEFAULT_DEM),
        help=f"DEM GeoTIFF path (meters) [default: {DEFAULT_DEM}]",
    )
    ap.add_argument(
        "--slope",
        default=str(DEFAULT_SLOPE),
        help=f"Slope GeoTIFF path (degrees or percent) [default: {DEFAULT_SLOPE}]",
    )
    ap.add_argument(
        "--outdir",
        default=str(DEFAULT_OUTDIR),
        help=f"Output directory [default: {DEFAULT_OUTDIR}]",
    )
    args = ap.parse_args()

    basins_path = Path(args.basins)
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    if not basins_path.exists():
        raise FileNotFoundError(f"Basins file not found: {basins_path}")

    dem_path = Path(args.dem)
    slope_path = Path(args.slope)

    if not dem_path.exists():
        raise FileNotFoundError(
            f"DEM not found: {dem_path}. Run projects/haihe/scripts/00_prepare_haihe_srtm.py first."
        )
    if not slope_path.exists():
        raise FileNotFoundError(
            f"Slope raster not found: {slope_path}. Run projects/haihe/scripts/00_prepare_haihe_srtm.py first."
        )

    gdf = read_basins(basins_path, layer=args.layer)
    area_km2 = calc_area_km2(gdf)

    # determine basin_id column if available
    candidate_ids = [args.id_field] if args.id_field else []
    candidate_ids += ["basin_id", "HYBAS_ID", "hybas_id", "sub_id", "id", "BASIN_ID"]
    basin_id_field = None
    for col in candidate_ids:
        if col and col in gdf.columns:
            basin_id_field = col
            break
    if basin_id_field:
        raw_ids = gdf[basin_id_field]
        basin_ids = [
            str(v) if pd.notna(v) else None
            for v in raw_ids
        ]
    else:
        basin_ids = [None] * len(gdf)

    dem_stats = compute_zonal(gdf, dem_path, stats=["min", "max", "mean", "median", "std"], fallback_nodata=-32768.0)
    slope_stats = compute_zonal(gdf, slope_path, stats=["mean", "median", "std"], fallback_nodata=-9999.0)

    rows: list[PerBasinStats] = []
    for idx in tqdm(range(len(gdf)), desc="aggregating per-basin stats"):
        elev_mean = elev_median = elev_min = elev_max = elev_std = None
        slope_mean = slope_median = slope_std = None
        relief_range = relief_std = None

        if dem_stats is not None:
            ds = dem_stats[idx]
            elev_min = _safe_float(ds.get("min"))
            elev_max = _safe_float(ds.get("max"))
            elev_mean = _safe_float(ds.get("mean"))
            elev_median = _safe_float(ds.get("median"))
            elev_std = _safe_float(ds.get("std"))
            if elev_min is not None and elev_max is not None:
                relief_range = elev_max - elev_min
            if elev_std is not None:
                relief_std = elev_std

        if slope_stats is not None:
            ss = slope_stats[idx]
            slope_mean = _safe_float(ss.get("mean"))
            slope_median = _safe_float(ss.get("median"))
            slope_std = _safe_float(ss.get("std"))

        rows.append(
            PerBasinStats(
                basin_id=basin_ids[idx],
                area_km2=float(area_km2[idx]),
                elev_mean=elev_mean,
                elev_median=elev_median,
                elev_min=elev_min,
                elev_max=elev_max,
                elev_std=elev_std,
                slope_mean=slope_mean,
                slope_median=slope_median,
                slope_std=slope_std,
                relief_range=relief_range,
                relief_std=relief_std,
            )
        )

    df = pd.DataFrame([r.__dict__ for r in rows])
    # friendly column order
    preferred_order = [
        "basin_id", "area_km2",
        "elev_mean", "elev_median", "elev_min", "elev_max", "elev_std",
        "slope_mean", "slope_median", "slope_std",
        "relief_range", "relief_std"
    ]
    df = df[[c for c in preferred_order if c in df.columns]]

    per_basin_csv = outdir / "subbasin_stats.csv"
    df.to_csv(per_basin_csv, index=False, encoding="utf-8-sig")

    summary_md_path = outdir / "summary.md"
    summary_md = build_summary(df)
    summary_md_path.write_text(summary_md, encoding="utf-8")

    tables_dir = outdir / "tables"
    figures_dir = outdir / "figures"
    generated_tables = generate_additional_tables(df, tables_dir)
    generated_figures = generate_figures(df, figures_dir)

    print("=" * 60)
    print("Subbasin health check complete!")
    print(f"- Sample size: {len(df)}")
    print(f"- Detail CSV: {per_basin_csv}")
    print(f"- Summary Markdown: {summary_md_path}")
    if generated_tables:
        print(f"- Tables ({len(generated_tables)} files): {tables_dir}")
    if generated_figures:
        print(f"- Figures ({len(generated_figures)} files): {figures_dir}")


def _safe_float(v) -> Optional[float]:
    try:
        if v is None:
            return None
        f = float(v)
        if np.isnan(f):
            return None
        return f
    except Exception:
        return None


if __name__ == "__main__":
    main()


