"""Prepare HydroBASINS sub-basins for the GloFAS pipeline."""

from __future__ import annotations

import argparse
import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import geopandas as gpd
import pandas as pd
import yaml
from pyproj import Geod
from shapely.geometry import Polygon
from shapely.ops import unary_union
from tqdm import tqdm

LOG_FORMAT = "%(asctime)s | %(levelname)s | %(message)s"
GEOD = Geod(ellps="WGS84")


@dataclass
class SubbasinConfig:
    macro_basin: Path
    hydrobasins: Path
    output_file: Path
    output_layer: str = "basins"
    list_csv: Optional[Path] = None
    id_field: str = "HYBAS_ID"
    sub_id_field: str = "SUB_ID"
    min_overlap_ratio: float = 0.02


def load_config(path: Path) -> SubbasinConfig:
    with path.open("r", encoding="utf-8") as fp:
        raw = yaml.safe_load(fp)

    if raw is None:
        raise ValueError("Subbasin config cannot be empty.")

    return SubbasinConfig(
        macro_basin=Path(raw["macro_basin"]),
        hydrobasins=Path(raw["hydrobasins"]),
        output_file=Path(raw["output_file"]),
        output_layer=raw.get("output_layer", "basins"),
        list_csv=Path(raw["list_csv"]) if raw.get("list_csv") else None,
        id_field=raw.get("id_field", "HYBAS_ID"),
        sub_id_field=raw.get("sub_id_field", raw.get("id_field", "HYBAS_ID")),
        min_overlap_ratio=float(raw.get("min_overlap_ratio", 0.02)),
    )


def configure_logging() -> None:
    logging.basicConfig(level=logging.INFO, format=LOG_FORMAT)


def ensure_epsg4326(gdf: gpd.GeoDataFrame) -> gpd.GeoDataFrame:
    if gdf.crs is None:
        raise ValueError("Input data lacks CRS information.")
    if gdf.crs.to_epsg() != 4326:
        gdf = gdf.to_crs("EPSG:4326")
    return gdf


def dissolve_macro(path: Path) -> Polygon:
    gdf = gpd.read_file(path)
    gdf = ensure_epsg4326(gdf)
    geom = unary_union(gdf.geometry.dropna())
    if geom.is_empty:
        raise ValueError(f"Macro basin geometry from {path} is empty.")
    return geom


def load_hydrobasins(path: Path) -> gpd.GeoDataFrame:
    hydro = gpd.read_file(path)
    if hydro.empty:
        raise ValueError(f"HydroBASINS file {path} is empty.")
    hydro = ensure_epsg4326(hydro)
    hydro = hydro[hydro.geometry.notna()].copy()
    return hydro


def select_subbasins(
    macro_geom,
    hydro: gpd.GeoDataFrame,
    id_field: str,
    min_overlap: float,
) -> gpd.GeoDataFrame:
    if id_field not in hydro.columns:
        raise KeyError(f"HydroBASINS data lacks '{id_field}' column.")

    selected_rows = []

    try:
        sindex = hydro.sindex
        candidate_idx = list(sindex.query(macro_geom, predicate="intersects"))
        iterable = hydro.iloc[candidate_idx].iterrows()
        total = len(candidate_idx)
    except Exception:  # noqa: BLE001
        iterable = hydro.iterrows()
        total = len(hydro)

    for _, row in tqdm(iterable, total=total, desc="subbasins"):
        geom = row.geometry
        if geom is None or geom.is_empty:
            continue
        if not geom.intersects(macro_geom):
            continue
        intersection = geom.intersection(macro_geom)
        if intersection.is_empty:
            continue
        orig_area = abs(GEOD.geometry_area_perimeter(geom)[0]) / 1e6
        inter_area = abs(GEOD.geometry_area_perimeter(intersection)[0]) / 1e6
        ratio = inter_area / orig_area if orig_area > 0 else 0.0
        if ratio < min_overlap:
            continue
        record = row.to_dict()
        record["geometry"] = intersection
        record["intersection_ratio"] = ratio
        record["intersect_area_km2"] = inter_area
        record["original_area_km2"] = orig_area
        selected_rows.append(record)

    if not selected_rows:
        raise RuntimeError("No sub-basins satisfied the overlap criteria.")

    result = gpd.GeoDataFrame(selected_rows, crs="EPSG:4326")
    return result.reset_index(drop=True)


def add_sub_ids(gdf: gpd.GeoDataFrame, config: SubbasinConfig) -> gpd.GeoDataFrame:
    if config.sub_id_field in gdf.columns:
        gdf[config.sub_id_field] = gdf[config.sub_id_field].astype(str)
        return gdf

    if config.id_field not in gdf.columns:
        raise KeyError(
            f"Cannot derive {config.sub_id_field}; missing `{config.id_field}` column."
        )
    gdf = gdf.copy()
    gdf[config.sub_id_field] = gdf[config.id_field].astype(str)
    return gdf


def write_outputs(gdf: gpd.GeoDataFrame, config: SubbasinConfig) -> None:
    config.output_file.parent.mkdir(parents=True, exist_ok=True)
    gdf.to_file(config.output_file, layer=config.output_layer, driver="GPKG")
    logging.info("Saved sub-basins to %s (layer=%s)", config.output_file, config.output_layer)

    if config.list_csv:
        list_csv = config.list_csv
    else:
        list_csv = config.output_file.with_name(f"{config.output_file.stem}_list.csv")
    summary_cols = [
        config.sub_id_field,
        config.id_field,
        "intersection_ratio",
        "intersect_area_km2",
    ]
    available_cols = [col for col in summary_cols if col in gdf.columns]
    list_csv.parent.mkdir(parents=True, exist_ok=True)
    pd.DataFrame(gdf[available_cols]).to_csv(list_csv, index=False, encoding="utf-8")
    logging.info("Saved summary CSV to %s", list_csv)


def run(config: SubbasinConfig) -> None:
    configure_logging()
    macro_geom = dissolve_macro(config.macro_basin)
    hydro = load_hydrobasins(config.hydrobasins)
    selected = select_subbasins(macro_geom, hydro, config.id_field, config.min_overlap_ratio)
    selected = add_sub_ids(selected, config)
    write_outputs(selected, config)
    logging.info("Subbasin preparation finished. %d features retained.", len(selected))


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--config", type=Path, required=True, help="Path to subbasin preparation YAML config."
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    config = load_config(args.config)
    run(config)


if __name__ == "__main__":
    main()

