"""Clip GloFAS NetCDF files to a basin polygon, with bbox fallback.

Example:
    python src/haihe_river/pipelines/glofas/clip_glofas.py \
        --config configs/glofas/haihe_clip.yaml
"""

from __future__ import annotations

import argparse
import logging
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Optional

import yaml

try:
    import geopandas as gpd
except ImportError as exc:
    raise ImportError(
        "geopandas is required. Install via `pip install geopandas`."
    ) from exc

try:
    import xarray as xr
except ImportError as exc:
    raise ImportError(
        "xarray is required. Install via `pip install xarray`."
    ) from exc

try:
    import rioxarray  # noqa: F401
except ImportError as exc:
    raise ImportError(
        "rioxarray is required. Install via `pip install rioxarray`."
    ) from exc


LOG_FORMAT = "%(asctime)s | %(levelname)s | %(message)s"


@dataclass
class ClipConfig:
    input_dir: Path
    input_glob: str
    output_dir: Path
    basin_boundary: Path
    logs_dir: Optional[Path] = None
    lon_name: str = "lon"
    lat_name: str = "lat"
    convert_longitudes: bool = True
    buffer_deg: float = 0.0
    drop_history: bool = True
    overwrite: bool = False
    dry_run: bool = False
    metadata: dict = field(default_factory=dict)


def load_config(path: Path) -> ClipConfig:
    with path.open("r", encoding="utf-8") as fp:
        raw = yaml.safe_load(fp)

    return ClipConfig(
        input_dir=Path(raw["input_dir"]),
        input_glob=raw.get("input_glob", "*.nc"),
        output_dir=Path(raw["output_dir"]),
        basin_boundary=Path(raw["basin_boundary"]),
        logs_dir=Path(raw["logs_dir"]) if raw.get("logs_dir") else None,
        lon_name=raw.get("lon_name", "lon"),
        lat_name=raw.get("lat_name", "lat"),
        convert_longitudes=bool(raw.get("convert_longitudes", True)),
        buffer_deg=float(raw.get("buffer_deg", 0.0)),
        drop_history=bool(raw.get("drop_history", True)),
        overwrite=bool(raw.get("overwrite", False)),
        dry_run=bool(raw.get("dry_run", False)),
        metadata=raw.get("metadata", {}) or {},
    )


def configure_logging(logs_dir: Optional[Path]) -> None:
    handlers = [logging.StreamHandler(sys.stdout)]
    if logs_dir:
        logs_dir.mkdir(parents=True, exist_ok=True)
        log_file = logs_dir / "clip.log"
        handlers.append(logging.FileHandler(log_file, encoding="utf-8"))

    logging.basicConfig(level=logging.INFO, handlers=handlers, format=LOG_FORMAT)


def load_geometry(basin_path: Path, buffer_deg: float = 0.0):
    gdf = gpd.read_file(basin_path)
    if gdf.empty:
        raise ValueError(f"Basin boundary `{basin_path}` is empty.")
    geom = gdf.to_crs("EPSG:4326").unary_union
    if buffer_deg:
        geom = geom.buffer(buffer_deg)
    return geom


def ensure_crs(ds: xr.Dataset, epsg: str = "EPSG:4326") -> xr.Dataset:
    if not ds.rio.crs:
        ds = ds.rio.write_crs(epsg)
    return ds


def convert_longitudes_if_needed(
    ds: xr.Dataset, lon_name: str
) -> xr.Dataset:
    lon = ds[lon_name]
    if lon.max() <= 180:
        return ds
    logging.info("Converting longitudes from 0-360 to -180-180.")
    lon_360 = lon.where(lon <= 180, lon - 360)
    ds = ds.assign_coords({lon_name: lon_360})
    ds = ds.sortby(lon_name)
    return ds


def clip_dataset(
    ds: xr.Dataset,
    geometry,
    lon_name: str,
    lat_name: str,
) -> xr.Dataset:
    ds = ensure_crs(ds)
    try:
        clipped = ds.rio.clip([geometry], drop=True)
        logging.info("Polygon clip succeeded.")
        return clipped
    except Exception as exc:  # noqa: BLE001
        logging.warning("Polygon clip failed (%s). Falling back to bbox slice.", exc)
        minx, miny, maxx, maxy = geometry.bounds
        lat_slice = slice(maxy, miny) if ds[lat_name][0] > ds[lat_name][-1] else slice(miny, maxy)
        lon_slice = slice(minx, maxx)
        return ds.sel({lat_name: lat_slice, lon_name: lon_slice})


def drop_history_attributes(ds: xr.Dataset) -> xr.Dataset:
    attrs = dict(ds.attrs)
    if "history" in attrs:
        attrs.pop("history")
    ds.attrs = attrs
    return ds


def build_output_path(config: ClipConfig, source: Path) -> Path:
    return config.output_dir / source.name.replace(".nc", "_clip.nc")


def process_file(
    path: Path,
    config: ClipConfig,
    geometry,
) -> None:
    target = build_output_path(config, path)

    if target.exists() and not config.overwrite:
        logging.info("Skipping existing file: %s", target)
        return

    logging.info("Opening %s", path)
    ds = xr.open_dataset(path)
    if config.convert_longitudes and config.lon_name in ds.coords:
        ds = convert_longitudes_if_needed(ds, config.lon_name)

    clipped = clip_dataset(ds, geometry, config.lon_name, config.lat_name)
    if config.drop_history:
        clipped = drop_history_attributes(clipped)

    for key, value in config.metadata.items():
        clipped.attrs.setdefault(key, value)

    target.parent.mkdir(parents=True, exist_ok=True)
    logging.info("Writing %s", target)
    if config.dry_run:
        logging.info("Dry-run enabled; skipping write.")
        return
    clipped.to_netcdf(target)


def iterate_files(config: ClipConfig) -> Iterable[Path]:
    yield from sorted(config.input_dir.glob(config.input_glob))


def run_clip(config: ClipConfig) -> None:
    configure_logging(config.logs_dir)
    geometry = load_geometry(config.basin_boundary, config.buffer_deg)

    for path in iterate_files(config):
        process_file(path, config, geometry)

    logging.info("Clipping finished.")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Clip GloFAS NetCDF to basin.")
    parser.add_argument(
        "--config",
        type=Path,
        required=True,
        help="Path to YAML configuration file.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    config = load_config(args.config)
    run_clip(config)


if __name__ == "__main__":
    main()

