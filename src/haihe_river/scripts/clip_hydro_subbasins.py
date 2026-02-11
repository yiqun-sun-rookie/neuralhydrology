#!/usr/bin/env python3
"""Clip HydroBASINS/HydroRIVERS to a custom large-basin boundary.

This helper script extracts ready-to-use sub-basins and river network segments for a
user-specified macro basin. It is meant to simplify the workflow before preparing
meteorological forcings (e.g. via ``prepare_china_basin_data.py``).

HydroBASINS and HydroRIVERS are part of WWF's HydroSHEDS suite and can be
downloaded from https://www.hydrosheds.org/. HydroBASINS is distributed in tiled
shapefiles by Pfafstetter level (1–12). HydroRIVERS contains the global river
network as polylines. Both products are in EPSG:4326 (WGS84), so we keep the same
CRS throughout the script.

Example
-------

.. code-block:: bash

    python clip_hydro_subbasins.py \
        --macro-basins data/macro_basin.shp \
        --hydrobasins data/HydroBASINS/asi/asi_l06.shp \
        --hydrorivers data/HydroRIVERS/HydroRIVERS_v10_na.shp \
        --id-field HYBAS_ID \
        --min-overlap-ratio 0.02 \
        --output-dir data/china_era5/basin_boundaries

Outputs
-------

``<output-dir>/subbasins.geojson``
    Clipped sub-basin polygons with original attributes and an
    ``intersection_ratio`` column (share of the sub-basin area inside the macro
    basin).

``<output-dir>/rivers.geojson`` (optional)
    River polylines clipped to the macro basin. Only written if
    ``--hydrorivers`` is provided.

Dependencies
------------
- geopandas
- shapely (>=2.0)
- pyproj
- tqdm (progress bar)

Install via conda-forge (recommended):

.. code-block:: bash

    conda install -c conda-forge geopandas shapely pyproj tqdm
"""
from __future__ import annotations

import argparse
import logging
from pathlib import Path
from typing import Optional

import geopandas as gpd
import pandas as pd
from pyproj import Geod
from shapely.geometry import GeometryCollection, MultiPolygon, Polygon
from shapely.ops import unary_union
from tqdm import tqdm

LOGGER = logging.getLogger("clip_hydro_subbasins")
GEOD = Geod(ellps="WGS84")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument("--macro-basins", type=Path, required=True, help="Shapefile/GeoJSON of the large basin boundary/boundaries.")
    parser.add_argument("--hydrobasins", type=Path, required=True, help="HydroBASINS shapefile for the region/level of interest.")
    parser.add_argument("--hydrorivers", type=Path, default=None, help="Optional HydroRIVERS shapefile to clip.")
    parser.add_argument("--id-field", type=str, default="HYBAS_ID", help="Column in HydroBASINS containing unique basin identifiers.")
    parser.add_argument("--min-overlap-ratio", type=float, default=0.01, help="Minimum intersection ratio (0-1) required to keep a sub-basin.")
    parser.add_argument("--output-dir", type=Path, required=True, help="Directory to store clipped GeoJSON layers.")
    parser.add_argument("--log-level", default="INFO", choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"], help="Logging verbosity.")
    return parser.parse_args()


def setup_logging(level: str) -> None:
    logging.basicConfig(
        level=getattr(logging, level.upper()),
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )


def load_macro_geometry(path: Path) -> Polygon:
    gdf = gpd.read_file(path)
    if gdf.empty:
        raise ValueError(f"Macro basin file {path} is empty")
    geoms = gdf.geometry.dropna().tolist()
    merged = unary_union(geoms)
    if isinstance(merged, (Polygon, MultiPolygon)):
        if isinstance(merged, MultiPolygon):
            merged = max(merged.geoms, key=lambda geom: abs(GEOD.geometry_area_perimeter(geom)[0]))
        return merged
    if isinstance(merged, GeometryCollection):
        polygons = [geom for geom in merged.geoms if isinstance(geom, Polygon)]
        if not polygons:
            raise ValueError("Macro basin geometry contains no polygons")
        return max(polygons, key=lambda geom: abs(GEOD.geometry_area_perimeter(geom)[0]))
    raise ValueError("Unexpected geometry type for macro basin")


def calc_area(geom: Polygon) -> float:
    area, _ = GEOD.geometry_area_perimeter(geom)
    return abs(area)


def clip_hydrobasins(
    macro_geom: Polygon,
    hydro_path: Path,
    id_field: str,
    min_ratio: float,
) -> gpd.GeoDataFrame:
    hydro = gpd.read_file(hydro_path)
    if hydro.empty:
        raise ValueError(f"HydroBASINS file {hydro_path} is empty")
    if id_field not in hydro.columns:
        raise ValueError(f"HydroBASINS file lacks id field '{id_field}'. Available columns: {hydro.columns.tolist()}")

    hydro = hydro.to_crs(4326)
    macro_gdf = gpd.GeoDataFrame(geometry=[macro_geom], crs="EPSG:4326")

    clipped_rows = []
    for _, row in tqdm(hydro.iterrows(), total=len(hydro), desc="sub-basins"):
        geom = row.geometry
        if geom is None:
            continue
        if not geom.intersects(macro_geom):
            continue
        intersection = geom.intersection(macro_geom)
        if intersection.is_empty:
            continue
        original_area = calc_area(geom)
        intersect_area = calc_area(intersection)
        ratio = intersect_area / original_area if original_area > 0 else 0
        if ratio < min_ratio:
            continue
        data = row.to_dict()
        data["geometry"] = intersection
        data["intersection_ratio"] = ratio
        data["original_area_km2"] = original_area / 1e6
        data["intersect_area_km2"] = intersect_area / 1e6
        clipped_rows.append(data)

    if not clipped_rows:
        raise RuntimeError("No sub-basins survived clipping. Consider lowering --min-overlap-ratio or using another HydroBASINS level.")

    result = gpd.GeoDataFrame(clipped_rows, crs="EPSG:4326")
    result = result.reset_index(drop=True)
    LOGGER.info("Selected %d sub-basins covering %.1f%% of the macro basin area", len(result), 100.0 * calc_area(result.unary_union) / calc_area(macro_geom))
    return result


def clip_rivers(macro_geom: Polygon, rivers_path: Path) -> gpd.GeoDataFrame:
    rivers = gpd.read_file(rivers_path)
    if rivers.empty:
        raise ValueError(f"HydroRIVERS file {rivers_path} is empty")

    rivers = rivers.to_crs(4326)
    clipped = gpd.overlay(rivers, gpd.GeoDataFrame(geometry=[macro_geom], crs="EPSG:4326"), how="intersection")
    clipped = clipped.reset_index(drop=True)
    LOGGER.info("Clipped %d river segments", len(clipped))
    return clipped


def write_layer(gdf: gpd.GeoDataFrame, target: Path) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    gdf.to_file(target, driver="GeoJSON")
    LOGGER.info("Wrote %s", target)


def summarize(gdf: gpd.GeoDataFrame, id_field: str) -> pd.DataFrame:
    attrs = gdf[[id_field, "intersect_area_km2", "intersection_ratio"]].copy()
    attrs = attrs.sort_values("intersect_area_km2", ascending=False).reset_index(drop=True)
    return attrs


def main() -> None:
    args = parse_args()
    setup_logging(args.log_level)

    macro_geom = load_macro_geometry(args.macro_basins)
    LOGGER.info("Loaded macro basin geometry (%.2f km^2)", calc_area(macro_geom) / 1e6)

    subbasins = clip_hydrobasins(macro_geom, args.hydrobasins, args.id_field, args.min_overlap_ratio)
    write_layer(subbasins, args.output_dir / "subbasins.geojson")

    summary = summarize(subbasins, args.id_field)
    summary_path = args.output_dir / "subbasin_summary.csv"
    summary.to_csv(summary_path, index=False)
    LOGGER.info("Saved summary metrics to %s", summary_path)

    if args.hydrorivers:
        rivers = clip_rivers(macro_geom, args.hydrorivers)
        write_layer(rivers, args.output_dir / "rivers.geojson")

    LOGGER.info("Done. The resulting sub-basins can now feed prepare_china_basin_data.py for forcing extraction.")


if __name__ == "__main__":
    main()
