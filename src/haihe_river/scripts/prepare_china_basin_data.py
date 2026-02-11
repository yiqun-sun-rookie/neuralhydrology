#!/usr/bin/env python3
"""Automate ERA5-Land forcing preparation for Chinese basins.

This script downloads hourly ERA5-Land reanalysis fields for a target basin, clips the
covering grid to the basin polygon, performs areal averaging, derives the daily CAMELS
forcing variables required by ``simple_train.py`` and stores them in the expected
``_forcing_leap.txt`` format.

Prerequisites
-------------
1. CDS API account: https://cds.climate.copernicus.eu/api-how-to
   Create ``~/.cdsapirc`` with your key before running this script.
2. Python dependencies (conda-forge recommended):

   .. code-block:: bash

       conda install -c conda-forge cdsapi geopandas rioxarray xarray numpy pandas tqdm pyproj

Usage
-----

.. code-block:: bash

    python prepare_china_basin_data.py \
        --basin-shapefile data/china_basins.shp \
        --basin-id 0001 \
        --start-date 1999-10-01 \
        --end-date 2014-09-30 \
        --output-root data/china_era5 \
        --overwrite

The resulting forcing file will live at
``<output-root>/basin_mean_forcing/era5land/<basin_id>_lump_era5land_forcing_leap.txt``
and can be picked up by ``simple_train.py`` once you set ``DATA_DIR`` to the same root.
"""
from __future__ import annotations

import argparse
import calendar
import logging
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable, List, Sequence

import numpy as np
import pandas as pd
import xarray as xr

try:  # pragma: no cover - purely import guard
    import cdsapi
except ImportError as exc:  # pragma: no cover - user-facing hint
    raise SystemExit(
        "Missing dependency 'cdsapi'. Install it via 'pip install cdsapi' or "
        "'conda install -c conda-forge cdsapi'."
    ) from exc

try:  # pragma: no cover
    import geopandas as gpd
except ImportError as exc:
    raise SystemExit(
        "Missing dependency 'geopandas'. Install it via 'conda install -c conda-forge geopandas'."
    ) from exc

try:  # pragma: no cover
    import rioxarray  # noqa: F401 - registers the .rio accessor
except ImportError as exc:
    raise SystemExit(
        "Missing dependency 'rioxarray'. Install it via 'conda install -c conda-forge rioxarray'."
    ) from exc

from pyproj import Geod
from shapely.geometry import Polygon
from shapely.geometry.base import BaseGeometry
from tqdm import tqdm

LOGGER = logging.getLogger("prepare_china_basin_data")
HOURLY_TIMES = [f"{hour:02d}:00" for hour in range(24)]
ERA5_VARIABLES = [
    "total_precipitation",  # metres
    "surface_solar_radiation_downwards",  # J m-2
    "2m_temperature",  # Kelvin
    "2m_dewpoint_temperature",  # Kelvin
]


@dataclass(frozen=True)
class BasinContext:
    """Simple container for basin metadata."""

    basin_id: str
    geometry: BaseGeometry
    centroid_lat: float
    centroid_lon: float
    area_m2: float


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    parser.add_argument("--basin-shapefile", type=Path, required=True, help="Path to basin shapefile/geojson.")
    parser.add_argument("--basin-id", type=str, required=True, help="Unique basin identifier (used for filenames).")
    parser.add_argument(
        "--id-field",
        type=str,
        default=None,
        help="Name of the attribute column that stores basin ids. If omitted, the first feature is used.",
    )
    parser.add_argument(
        "--start-date",
        type=lambda v: datetime.strptime(v, "%Y-%m-%d"),
        default=datetime(1999, 10, 1),
        help="Start date (inclusive).",
    )
    parser.add_argument(
        "--end-date",
        type=lambda v: datetime.strptime(v, "%Y-%m-%d"),
        default=datetime(2014, 9, 30),
        help="End date (inclusive).",
    )
    parser.add_argument(
        "--output-root",
        type=Path,
        default=Path("data/china_era5"),
        help="Root directory to mirror CAMELS folder structure into.",
    )
    parser.add_argument(
        "--download-cache",
        type=Path,
        default=None,
        help="Optional directory to cache raw ERA5-Land NetCDF files (defaults to <output-root>/raw/era5_land).",
    )
    parser.add_argument(
        "--keep-downloads",
        action="store_true",
        help="Do not delete downloaded ERA5 files after aggregation.",
    )
    parser.add_argument(
        "--overwrite",
        action="store_true",
        help="Overwrite existing forcing files instead of skipping.",
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"],
        help="Logging verbosity.",
    )
    return parser.parse_args()


def setup_logging(level: str) -> None:
    logging.basicConfig(
        level=getattr(logging, level.upper()),
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )


def load_basin(args: argparse.Namespace) -> BasinContext:
    basin_path = args.basin_shapefile
    if not basin_path.exists():
        raise FileNotFoundError(f"Basin geometry not found: {basin_path}")

    gdf = gpd.read_file(basin_path)
    if gdf.empty:
        raise ValueError(f"No geometries found in {basin_path}")

    if args.id_field:
        if args.id_field not in gdf.columns:
            raise ValueError(f"ID field '{args.id_field}' not present in shapefile columns: {gdf.columns.tolist()}")
        matches = gdf[gdf[args.id_field].astype(str) == args.basin_id]
        if matches.empty:
            raise ValueError(f"No feature with id_field == {args.basin_id} in {basin_path}")
        geometry = matches.geometry.iloc[0]
    else:
        geometry = gdf.geometry.iloc[0]

    if not isinstance(geometry, Polygon):
        geometry = geometry.unary_union
        if not isinstance(geometry, Polygon):
            raise ValueError("Expected polygon geometry for basin boundary.")

    centroid = geometry.centroid
    geod = Geod(ellps="WGS84")
    area, _ = geod.geometry_area_perimeter(geometry)

    return BasinContext(
        basin_id=args.basin_id,
        geometry=geometry,
        centroid_lat=float(centroid.y),
        centroid_lon=float(centroid.x),
        area_m2=abs(area),
    )


def month_iter(start: datetime, end: datetime) -> Iterable[tuple[int, int]]:
    current = datetime(start.year, start.month, 1)
    final = datetime(end.year, end.month, 1)
    while current <= final:
        yield current.year, current.month
        if current.month == 12:
            current = datetime(current.year + 1, 1, 1)
        else:
            current = datetime(current.year, current.month + 1, 1)


def expand_bbox(geometry: BaseGeometry, buffer_deg: float = 0.5) -> tuple[float, float, float, float]:
    minx, miny, maxx, maxy = geometry.bounds
    return (maxy + buffer_deg, minx - buffer_deg, miny - buffer_deg, maxx + buffer_deg)


def ensure_directory(path: Path) -> Path:
    path.mkdir(parents=True, exist_ok=True)
    return path


def download_era5_month(
    client: cdsapi.Client,
    cache_dir: Path,
    year: int,
    month: int,
    bbox: tuple[float, float, float, float],
    overwrite: bool,
) -> Path:
    ensure_directory(cache_dir)
    target = cache_dir / f"era5land_{year}_{month:02d}.nc"
    if target.exists() and not overwrite:
        LOGGER.debug("Using cached ERA5 file: %s", target)
        return target

    days_in_month = calendar.monthrange(year, month)[1]
    LOGGER.info("Downloading ERA5-Land %04d-%02d (%d days)", year, month, days_in_month)
    request = {
        "format": "netcdf",
        "product_type": "reanalysis",
        "variable": ERA5_VARIABLES,
        "year": f"{year}",
        "month": f"{month:02d}",
        "day": [f"{d:02d}" for d in range(1, days_in_month + 1)],
        "time": HOURLY_TIMES,
        # CDS expects [North, West, South, East]
        "area": [bbox[0], bbox[1], bbox[2], bbox[3]],
    }
    client.retrieve("reanalysis-era5-land", request, target.as_posix())
    return target


def load_and_clip(dataset_paths: Sequence[Path], geometry: BaseGeometry) -> xr.Dataset:
    LOGGER.info("Loading %d ERA5 files into memory", len(dataset_paths))
    ds = xr.open_mfdataset([p.as_posix() for p in dataset_paths], combine="by_coords")
    ds = ds.sortby("latitude", ascending=True)
    ds = ds.rio.write_crs(4326)
    ds = ds.rio.set_spatial_dims(x_dim="longitude", y_dim="latitude", inplace=True)
    clipped = ds.rio.clip([geometry.__geo_interface__], drop=True)
    return clipped.load()


def build_cell_weights(template: xr.DataArray) -> xr.DataArray:
    lat_radians = np.deg2rad(template["latitude"])
    weights = xr.ones_like(template)
    weights = weights * np.cos(lat_radians)
    weights = weights.where(~np.isnan(template))
    total = weights.sum()
    if float(total) == 0:
        raise RuntimeError("Computed zero total weight; check basin geometry overlap with ERA5 grid.")
    return weights / total


def weighted_daily_mean(data: xr.DataArray, weights: xr.DataArray, how: str) -> xr.DataArray:
    if how == "sum":
        resampled = data.resample(time="1D").sum()
    elif how == "max":
        resampled = data.resample(time="1D").max()
    elif how == "min":
        resampled = data.resample(time="1D").min()
    else:
        resampled = data.resample(time="1D").mean()
    return resampled.weighted(weights).mean(dim=("latitude", "longitude"))


def dewpoint_to_vapor_pressure(temp_c: xr.DataArray) -> xr.DataArray:
    # Magnus formula (Pa)
    return 610.94 * np.exp((17.625 * temp_c) / (243.04 + temp_c))


def daylength_seconds(latitude_deg: float, dates: pd.DatetimeIndex) -> np.ndarray:
    lat_rad = np.deg2rad(latitude_deg)
    declination = np.deg2rad(23.44) * np.sin(np.deg2rad((360 / 365.0) * (dates.dayofyear - 81)))
    cos_omega = -np.tan(lat_rad) * np.tan(declination)
    cos_omega = np.clip(cos_omega, -1.0, 1.0)
    omega = np.arccos(cos_omega)
    day_hours = (24.0 / np.pi) * omega
    return (day_hours * 3600).astype(float)


def compute_forcings_dataset(ds: xr.Dataset, basin: BasinContext, start: datetime, end: datetime) -> pd.DataFrame:
    template = ds["t2m"].isel(time=0, drop=True)
    weights = build_cell_weights(template)

    tp_mm = weighted_daily_mean(ds["tp"], weights, how="sum") * 1000.0
    ssrd_wm2 = weighted_daily_mean(ds["ssrd"], weights, how="sum") / 86400.0

    t2m_c = ds["t2m"] - 273.15
    tmax_c = weighted_daily_mean(t2m_c, weights, how="max")
    tmin_c = weighted_daily_mean(t2m_c, weights, how="min")

    d2m_c = ds["d2m"] - 273.15
    vp_pa = weighted_daily_mean(dewpoint_to_vapor_pressure(d2m_c), weights, how="mean")

    forcings = pd.DataFrame(
        {
            "date": tp_mm["time"].to_index(),
            "prcp(mm/day)": tp_mm.to_numpy(),
            "srad(W/m2)": ssrd_wm2.to_numpy(),
            "tmax(C)": tmax_c.to_numpy(),
            "tmin(C)": tmin_c.to_numpy(),
            "vp(Pa)": vp_pa.to_numpy(),
        }
    )
    forcings = forcings[(forcings["date"] >= pd.Timestamp(start)) & (forcings["date"] <= pd.Timestamp(end))]
    forcings = forcings.sort_values("date")
    forcings["Year"] = forcings["date"].dt.year
    forcings["Mnth"] = forcings["date"].dt.month
    forcings["Day"] = forcings["date"].dt.day
    forcings["Hr"] = 12
    forcings["dayl(s)"] = daylength_seconds(basin.centroid_lat, forcings["date"].dt)
    forcings["swe(mm)"] = 0.0
    cols = ["Year", "Mnth", "Day", "Hr", "dayl(s)", "prcp(mm/day)", "srad(W/m2)", "swe(mm)", "tmax(C)", "tmin(C)", "vp(Pa)"]
    return forcings[cols]


def write_camels_forcing_file(forcings: pd.DataFrame, basin: BasinContext, output_path: Path, overwrite: bool) -> None:
    if output_path.exists() and not overwrite:
        LOGGER.warning("Forcing file already exists and --overwrite not set: %s", output_path)
        return

    ensure_directory(output_path.parent)
    with output_path.open("w", encoding="utf-8") as fp:
        fp.write(f"{basin.centroid_lat:.4f}\n")
        fp.write(f"{basin.centroid_lon:.4f}\n")
        fp.write(f"{int(round(basin.area_m2))}\n")
        fp.write("Year Mnth Day Hr dayl(s) prcp(mm/day) srad(W/m2) swe(mm) tmax(C) tmin(C) vp(Pa)\n")
        forcings.to_csv(fp, sep="\t", index=False, float_format="%.4f")
    LOGGER.info("Forcing file written to %s", output_path)


def write_basic_attributes(basin: BasinContext, output_root: Path) -> None:
    attr_dir = ensure_directory(output_root / "basin_attributes")
    attr_path = attr_dir / f"{basin.basin_id}.csv"
    df = pd.DataFrame(
        {
            "basin_id": [basin.basin_id],
            "centroid_lat": [basin.centroid_lat],
            "centroid_lon": [basin.centroid_lon],
            "area_km2": [basin.area_m2 / 1e6],
        }
    )
    df.to_csv(attr_path, index=False)
    LOGGER.info("Wrote basic attribute file to %s", attr_path)


def cleanup(downloads: Sequence[Path]) -> None:
    for path in downloads:
        try:
            path.unlink()
            LOGGER.debug("Deleted %s", path)
        except OSError:
            LOGGER.warning("Could not delete %s", path)


def main() -> None:
    args = parse_args()
    setup_logging(args.log_level)
    basin = load_basin(args)
    bbox = expand_bbox(basin.geometry)

    client = cdsapi.Client()

    cache_dir = args.download_cache or (args.output_root / "raw" / "era5_land")
    download_paths: List[Path] = []
    for year, month in tqdm(list(month_iter(args.start_date, args.end_date)), desc="ERA5 months"):
        path = download_era5_month(client, cache_dir, year, month, bbox, overwrite=args.overwrite)
        download_paths.append(path)

    dataset = load_and_clip(download_paths, basin.geometry)
    forcings = compute_forcings_dataset(dataset, basin, args.start_date, args.end_date)
    dataset.close()

    forcing_dir = ensure_directory(args.output_root / "basin_mean_forcing" / "era5land")
    forcing_path = forcing_dir / f"{basin.basin_id}_lump_era5land_forcing_leap.txt"
    write_camels_forcing_file(forcings, basin, forcing_path, overwrite=args.overwrite)

    write_basic_attributes(basin, args.output_root)

    if not args.keep_downloads:
        cleanup(download_paths)

    LOGGER.info("Done. Update simple_train.py with DATA_DIR=%s and forcings=['era5land'].", args.output_root)


if __name__ == "__main__":
    main()
