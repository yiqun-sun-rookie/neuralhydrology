#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Download Copernicus DEM tiles for the Haihe basin, mosaic them, clip to the basin
boundary, and derive a slope raster.

Outputs
-------
- data/haihe/dem/haihe_srtm_dem.tif
- data/haihe/dem/haihe_srtm_slope.tif
"""
from __future__ import annotations

import math
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import urlopen

import geopandas as gpd
import numpy as np
import rasterio
from rasterio.merge import merge
from rasterio.mask import mask
from shapely.geometry import mapping

BASE_DIR = Path("data/haihe/dem")
RAW_DIR = BASE_DIR / "copernicus_raw"
RAW_DIR.mkdir(parents=True, exist_ok=True)

BASIN_PATH = Path("data/haihe/hydrobasins/lev12/haihe_hydrobasins_lev12.gpkg")
BASIN_LAYER = "basins"

DEM_OUTPUT = BASE_DIR / "haihe_srtm_dem.tif"
SLOPE_OUTPUT = BASE_DIR / "haihe_srtm_slope.tif"

BASE_URL = "https://copernicus-dem-90m.s3.amazonaws.com"


def iter_tiles() -> list[tuple[int, int]]:
    basins = gpd.read_file(BASIN_PATH, layer=BASIN_LAYER).to_crs(4326)
    minx, miny, maxx, maxy = basins.total_bounds
    lon_start = math.floor(minx)
    lon_end = math.ceil(maxx)
    lat_start = math.floor(miny)
    lat_end = math.ceil(maxy)
    tiles = []
    for lat in range(lat_start, lat_end):
        for lon in range(lon_start, lon_end):
            tiles.append((lat, lon))
    return tiles


def tile_url(lat: int, lon: int) -> tuple[str, str]:
    lat_prefix = "N" if lat >= 0 else "S"
    lon_prefix = "E" if lon >= 0 else "W"
    lat_id = f"{lat_prefix}{abs(lat):02d}_00"
    lon_id = f"{lon_prefix}{abs(lon):03d}_00"
    tile_id = f"Copernicus_DSM_COG_30_{lat_id}_{lon_id}_DEM"
    url = f"{BASE_URL}/{tile_id}/{tile_id}.tif"
    return tile_id, url


def download_tiles() -> list[Path]:
    tiles: list[Path] = []
    for lat, lon in iter_tiles():
        tile_id, url = tile_url(lat, lon)
        tif_path = RAW_DIR / f"{tile_id}.tif"

        if tif_path.exists():
            tiles.append(tif_path)
            continue

        try:
            with urlopen(url) as resp, open(tif_path, "wb") as dst:
                expected = resp.length if hasattr(resp, "length") else None
                bytes_read = 0
                while True:
                    chunk = resp.read(1 << 20)
                    if not chunk:
                        break
                    dst.write(chunk)
                    bytes_read += len(chunk)
            if expected is not None and bytes_read != expected:
                raise IOError(f"incomplete download {bytes_read}/{expected} bytes")
            print(f"[downloaded] {url}")
            tiles.append(tif_path)
        except HTTPError as exc:
            print(f"[missing] {url} ({exc.code})")
            if tif_path.exists():
                tif_path.unlink()
            continue
        except Exception as exc:
            print(f"[error] downloading {url}: {exc}")
            if tif_path.exists():
                tif_path.unlink()
            continue

    if not tiles:
        raise RuntimeError("No Copernicus tiles were downloaded. Cannot continue.")
    return tiles


def build_dem(tiles: list[Path]) -> Path:
    datasets = [rasterio.open(tile) for tile in tiles]
    try:
        mosaic, transform = merge(datasets, nodata=-32768)
        profile = datasets[0].profile
        profile.update(
            height=mosaic.shape[1],
            width=mosaic.shape[2],
            transform=transform,
            nodata=profile.get("nodata", -32768),
            compress="deflate",
        )

        tmp_path = BASE_DIR / "haihe_dem_raw.tif"
        with rasterio.open(tmp_path, "w", **profile) as dst:
            dst.write(mosaic.astype(profile["dtype"]))
    finally:
        for ds in datasets:
            ds.close()

    # clip to basin extent
    basins = gpd.read_file(BASIN_PATH, layer=BASIN_LAYER).to_crs(4326)
    geom = [mapping(basins.geometry.unary_union)]

    with rasterio.open(tmp_path) as src:
        clipped, clipped_transform = mask(src, geom, crop=True, nodata=-32768)
        clip_profile = src.profile
        clip_profile.update(
            height=clipped.shape[1],
            width=clipped.shape[2],
            transform=clipped_transform,
            compress="deflate",
        )
        with rasterio.open(DEM_OUTPUT, "w", **clip_profile) as dst:
            dst.write(clipped.astype(np.int16))

    tmp_path.unlink(missing_ok=True)
    return DEM_OUTPUT


def derive_slope(dem_path: Path) -> Path:
    with rasterio.open(dem_path) as src:
        dem = src.read(1).astype(np.float32)
        nodata = src.nodata
        if nodata is not None:
            dem = np.where(dem == nodata, np.nan, dem)

        xres = abs(src.transform.a)
        yres = abs(src.transform.e)

        # guard against zero resolution
        if math.isclose(xres, 0.0) or math.isclose(yres, 0.0):
            raise ValueError("Invalid pixel size encountered in DEM.")

        dz_dy, dz_dx = np.gradient(dem, yres, xres)
        slope_rad = np.arctan(np.sqrt(dz_dx**2 + dz_dy**2))
        slope_deg = np.degrees(slope_rad)

        slope_nodata = -9999.0
        slope_deg = np.where(np.isnan(dem), slope_nodata, slope_deg)

        profile = src.profile
        profile.update(
            dtype="float32",
            nodata=slope_nodata,
            compress="deflate",
        )

        with rasterio.open(SLOPE_OUTPUT, "w", **profile) as dst:
            dst.write(slope_deg.astype(np.float32), 1)

    return SLOPE_OUTPUT


def main():
    tiles = download_tiles()
    dem_path = build_dem(tiles)
    slope_path = derive_slope(dem_path)
    print(f"[done] DEM saved to {dem_path}")
    print(f"[done] Slope saved to {slope_path}")


if __name__ == "__main__":
    main()

