"""Select GloFAS representative outlet grid points for each subbasin.

This script reads a YAML configuration with paths to preprocessed GloFAS
discharge NetCDF files, the static upstream area raster, and HydroBASINS
subbasin polygons. It computes long-term mean discharge, filters candidate
grid cells by thresholds, and writes the selected outlet points as GeoJSON.
It also exports the discharge time series for each selected grid cell.

Example usage:
    python src/haihe_river/pipelines/glofas/select_subbasin_outlets.py \
        --config configs/glofas/haihe_outlets.yaml
"""

from __future__ import annotations

import argparse
import logging
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Optional

import geopandas as gpd
import pandas as pd
import xarray as xr
import yaml
from shapely.geometry import Point

LOG_FORMAT = "%(asctime)s | %(levelname)s | %(message)s"


@dataclass
class OutletConfig:
    discharge_files: List[Path]
    upstream_file: Path
    subbasin_file: Path
    subbasin_id_field: str
    output_geojson: Path
    timeseries_dir: Path
    ua_threshold_km2: float = 500.0
    mean_dis_threshold_m3s: float = 1.0
    search_buffer_deg: float = 0.0
    allow_empty_threshold: bool = True
    append_mean_to_geojson: bool = True


def load_config(path: Path) -> OutletConfig:
    with path.open("r", encoding="utf-8") as fp:
        raw = yaml.safe_load(fp)

    discharge_files = [Path(p) for p in raw["discharge_files"]]
    upstream_file = Path(raw["upstream_file"])
    subbasin_file = Path(raw["subbasin_file"])
    output_geojson = Path(raw["output_geojson"])
    timeseries_dir = Path(raw["timeseries_dir"])

    return OutletConfig(
        discharge_files=discharge_files,
        upstream_file=upstream_file,
        subbasin_file=subbasin_file,
        subbasin_id_field=raw.get("subbasin_id_field", "PFAF_ID"),
        output_geojson=output_geojson,
        timeseries_dir=timeseries_dir,
        ua_threshold_km2=float(raw.get("ua_threshold_km2", 500.0)),
        mean_dis_threshold_m3s=float(raw.get("mean_dis_threshold_m3s", 1.0)),
        search_buffer_deg=float(raw.get("search_buffer_deg", 0.0)),
        allow_empty_threshold=bool(raw.get("allow_empty_threshold", True)),
        append_mean_to_geojson=bool(raw.get("append_mean_to_geojson", True)),
    )


def configure_logging() -> None:
    logging.basicConfig(level=logging.INFO, format=LOG_FORMAT, stream=sys.stdout)


def open_discharge_dataset(files: Iterable[Path]) -> xr.Dataset:
    datasets = []
    for file in files:
        logging.info("Opening discharge file: %s", file)
        ds = xr.open_dataset(file)
        if "dis24" not in ds:
            raise KeyError(f"'dis24' variable not found in {file}")
        datasets.append(ds)

    combined = xr.concat(datasets, dim="valid_time")
    combined = combined.sortby("valid_time")
    return combined


def compute_grid_stats(
    discharge_ds: xr.Dataset,
    upstream_ds: xr.Dataset,
) -> gpd.GeoDataFrame:
    mean_discharge = discharge_ds["dis24"].mean(dim="valid_time", skipna=True)
    upstream_area = upstream_ds["uparea"]
    if tuple(upstream_area.dims) != ("latitude", "longitude"):
        upstream_area = upstream_area.transpose("latitude", "longitude")

    if upstream_area.shape != mean_discharge.shape:
        upstream_area = upstream_area.interp(
            latitude=mean_discharge["latitude"],
            longitude=mean_discharge["longitude"],
            method="nearest",
        )

    lat_grid, lon_grid = xr.broadcast(mean_discharge["latitude"], mean_discharge["longitude"])
    pdf = pd.DataFrame(
        {
            "latitude": lat_grid.values.ravel(),
            "longitude": lon_grid.values.ravel(),
            "mean_discharge": mean_discharge.values.ravel(),
            "upstream_area_km2": (upstream_area.values / 1_000_000.0).ravel(),
        }
    )
    pdf = pdf.dropna(subset=["upstream_area_km2"])

    geometry = gpd.points_from_xy(pdf["longitude"], pdf["latitude"])
    gdf = gpd.GeoDataFrame(pdf, geometry=geometry, crs="EPSG:4326")
    return gdf


def subset_points_by_geometry(
    points: gpd.GeoDataFrame,
    geometry,
) -> gpd.GeoDataFrame:
    minx, miny, maxx, maxy = geometry.bounds
    bbox_mask = (
        (points["longitude"] >= minx)
        & (points["longitude"] <= maxx)
        & (points["latitude"] >= miny)
        & (points["latitude"] <= maxy)
    )
    bbox_subset = points.loc[bbox_mask]
    if bbox_subset.empty:
        return bbox_subset
    mask = bbox_subset.geometry.apply(
        lambda geom: geometry.contains(geom) or geometry.touches(geom)
    )
    return bbox_subset.loc[mask]


def select_outlet_for_subbasin(
    sub_row,
    points: gpd.GeoDataFrame,
    config: OutletConfig,
) -> Optional[pd.Series]:
    geom = sub_row.geometry
    if config.search_buffer_deg > 0.0:
        geom = geom.buffer(config.search_buffer_deg)

    candidate_points = subset_points_by_geometry(points, geom)
    if candidate_points.empty:
        logging.warning(
            "No grid points intersect subbasin %s; skipping.",
            sub_row[config.subbasin_id_field],
        )
        return None

    filtered = candidate_points[
        (candidate_points["upstream_area_km2"] >= config.ua_threshold_km2)
        & (candidate_points["mean_discharge"] >= config.mean_dis_threshold_m3s)
    ]

    if filtered.empty:
        if not config.allow_empty_threshold:
            logging.warning(
                "No candidate meets thresholds for subbasin %s; skipping.",
                sub_row[config.subbasin_id_field],
            )
            return None
        selected_pool = candidate_points
        threshold_flag = False
    else:
        selected_pool = filtered
        threshold_flag = True

    selected = selected_pool.sort_values(
        ["upstream_area_km2", "mean_discharge"],
        ascending=[False, False],
    ).iloc[0]

    selected = selected.copy()
    selected["threshold_passed"] = threshold_flag
    selected["candidate_count"] = len(candidate_points)
    selected["threshold_count"] = len(filtered)
    return selected


def export_timeseries(
    discharge_ds: xr.Dataset,
    lat: float,
    lon: float,
    output_path: Path,
) -> None:
    sel = discharge_ds["dis24"].sel(
        latitude=lat,
        longitude=lon,
        method="nearest",
    )
    df = sel.to_dataframe(name="discharge_m3s").reset_index()
    df = df.rename(columns={"valid_time": "time"})
    df.to_csv(output_path, index=False)


def run(config: OutletConfig) -> None:
    configure_logging()
    config.timeseries_dir.mkdir(parents=True, exist_ok=True)
    config.output_geojson.parent.mkdir(parents=True, exist_ok=True)

    discharge_ds = open_discharge_dataset(config.discharge_files)
    upstream_ds = xr.open_dataset(config.upstream_file)

    points_gdf = compute_grid_stats(discharge_ds, upstream_ds)
    points_gdf = points_gdf.reset_index(drop=True)

    subbasins = gpd.read_file(config.subbasin_file)
    if config.subbasin_id_field not in subbasins.columns:
        raise KeyError(
            f"Subbasin ID field '{config.subbasin_id_field}' "
            f"not found in {config.subbasin_file}"
        )
    if subbasins.crs is None:
        raise ValueError("Subbasin file lacks CRS information.")
    if subbasins.crs.to_epsg() != 4326:
        subbasins = subbasins.to_crs("EPSG:4326")

    outlets = []
    for _, row in subbasins.iterrows():
        sub_id = row[config.subbasin_id_field]
        selected = select_outlet_for_subbasin(row, points_gdf, config)
        if selected is None:
            continue

        geometry = Point(selected["longitude"], selected["latitude"])
        record = {
            "SUB_ID": str(sub_id),
            "lon": float(selected["longitude"]),
            "lat": float(selected["latitude"]),
            "ua_km2": float(selected["upstream_area_km2"]),
            "mean_dis": float(selected["mean_discharge"]),
            "threshold_passed": bool(selected["threshold_passed"]),
            "candidate_count": int(selected["candidate_count"]),
            "threshold_count": int(selected["threshold_count"]),
            "geometry": geometry,
        }
        outlets.append(record)

        ts_path = config.timeseries_dir / f"sub_{sub_id}_discharge.csv"
        export_timeseries(discharge_ds, record["lat"], record["lon"], ts_path)
        logging.info("Exported time series: %s", ts_path)

    if not outlets:
        logging.error("No outlets were selected; check thresholds or input data.")
        return

    outlets_gdf = gpd.GeoDataFrame(outlets, geometry="geometry", crs="EPSG:4326")
    if not config.append_mean_to_geojson:
        outlets_gdf = outlets_gdf.drop(columns=["mean_dis"], errors="ignore")

    outlets_gdf.to_file(config.output_geojson, driver="GeoJSON")
    logging.info("Saved outlets GeoJSON: %s", config.output_geojson)

    summary_csv = config.output_geojson.with_suffix(".csv")
    outlets_gdf.drop(columns="geometry").to_csv(summary_csv, index=False)
    logging.info("Saved outlets summary CSV: %s", summary_csv)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Select GloFAS outlet points for each subbasin."
    )
    parser.add_argument(
        "--config", required=True, type=Path, help="Path to YAML configuration file."
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    config = load_config(args.config)
    run(config)


if __name__ == "__main__":
    main()

