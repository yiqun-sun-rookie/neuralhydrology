"""Build coarse-layer region-mean monthly labels (GRACE storage + soil moisture).

For each 2-degree region defined by build_region_forcing.py, take the spatial mean
of each gridded label over the region's lat/lon box, monthly. Produces the coarse
layer's supervision targets, aligned to the same regions as the region forcing.

Labels (v0):
  grace_lwe   CSR GRACE/-FO mascon liquid water equivalent thickness anomaly (cm).
              Monthly, 0.25deg, 0..360 longitude, gaps during instrument outages.
  soil        TerraClimate total-column soil moisture end-of-month (mm), 1/24deg.

Missing labels stay NaN (multi-task masking happens at training time). TerraClimate
is optional here: if its files are absent the script still writes the GRACE column.

Output: results/25_global_flood_hierarchy/coarse_v0/region_labels.nc
        dims (region, time), monthly; data_vars grace_lwe, soil (soil if available).
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
import xarray as xr

REPO = Path(__file__).resolve().parents[3]
OUT = REPO / "results" / "25_global_flood_hierarchy" / "coarse_v0"
MEMBERSHIP = OUT / "region_forcing" / "region_membership.csv"
GRACE = REPO / "data" / "grace_csr" / "CSR_GRACE_GRACE-FO_RL0603_Mascons_all-corrections.nc"
TERRA_DIR = REPO / "data" / "terraclimate_soil"

TILE_DEG = 2.0


def tile_box(tile: str) -> tuple[float, float, float, float]:
    """Return (lat0, lat1, lon0, lon1) for a tile id 'lat+038_lon-080' (lower-left corner)."""
    lat0 = float(tile.split("_")[0].replace("lat", ""))
    lon0 = float(tile.split("_")[1].replace("lon", ""))
    return lat0, lat0 + TILE_DEG, lon0, lon0 + TILE_DEG


def region_tiles() -> list[str]:
    df = pd.read_csv(MEMBERSHIP)
    return sorted(df["tile"].unique())


def grace_region_means(tiles: list[str]) -> tuple[pd.DatetimeIndex, dict[str, np.ndarray]]:
    ds = xr.open_dataset(GRACE, decode_times=False)
    units = ds["time"].attrs.get("units", "days since 2002-01-01")
    origin = pd.Timestamp(units.split("since")[-1].strip())
    time = origin + pd.to_timedelta(ds["time"].values, unit="D")
    time = pd.DatetimeIndex(time).to_period("M").to_timestamp()  # snap to month start
    lwe = ds["lwe_thickness"]  # (time, lat, lon), lon 0..360
    lat = ds["lat"].values
    lon = ds["lon"].values

    out = {}
    for t in tiles:
        lat0, lat1, lon0, lon1 = tile_box(t)
        lo0, lo1 = (lon0 % 360), (lon1 % 360)
        lat_m = (lat >= lat0) & (lat < lat1)
        lon_m = (lon >= lo0) & (lon < lo1)
        if not lat_m.any() or not lon_m.any():
            out[t] = np.full(len(time), np.nan)
            continue
        sub = lwe.values[:, lat_m][:, :, lon_m]
        out[t] = np.nanmean(sub, axis=(1, 2))
    return time, out


# CONUS bounding box (deg): keeps the loaded array to ~0.5 GB instead of the
# ~23 GB global 4 km field. Widen when the fine layer expands beyond CONUS.
CONUS_BOX = (24.0, 51.0, -125.0, -66.0)  # lat0, lat1, lon0, lon1


def terra_region_means(tiles: list[str]) -> tuple[pd.DatetimeIndex, dict[str, np.ndarray]] | None:
    files = sorted(TERRA_DIR.glob("TerraClimate_soil_*.nc"))
    if not files:
        return None
    ds = xr.open_mfdataset(files, combine="by_coords")
    lat = ds["lat"].values
    lon = ds["lon"].values
    time = pd.DatetimeIndex(ds["time"].values).to_period("M").to_timestamp()

    # Subset to CONUS *before* materializing values (avoids loading the global field).
    la0, la1, lo0, lo1 = CONUS_BOX
    lat_idx = np.where((lat >= la0) & (lat <= la1))[0]
    lon_idx = np.where((lon >= lo0) & (lon <= lo1))[0]
    soil = ds["soil"].isel(lat=lat_idx, lon=lon_idx).values  # (time, latC, lonC), ~0.5 GB
    latc = lat[lat_idx]
    lonc = lon[lon_idx]

    out = {}
    for t in tiles:
        lat0, lat1, lon0, lon1 = tile_box(t)
        lat_m = (latc >= lat0) & (latc < lat1)
        lon_m = (lonc >= lon0) & (lonc < lon1)
        if not lat_m.any() or not lon_m.any():
            out[t] = np.full(len(time), np.nan)
            continue
        sub = soil[:, lat_m][:, :, lon_m]
        out[t] = np.nanmean(sub, axis=(1, 2))
    return time, out


def main() -> None:
    tiles = region_tiles()
    g_time, g_means = grace_region_means(tiles)

    # GRACE can carry two solutions in one calendar month; collapse to one per month.
    g_df = pd.DataFrame({t: g_means[t] for t in tiles}, index=g_time).groupby(level=0).mean()
    g_time = pd.DatetimeIndex(g_df.index)
    g_means = {t: g_df[t].to_numpy() for t in tiles}

    data = {"grace_lwe": (("region", "time"), np.stack([g_means[t] for t in tiles]))}
    coords = {"region": tiles, "time": g_time}

    terra = terra_region_means(tiles)
    if terra is not None:
        s_time, s_means = terra
        # align soil onto the GRACE monthly axis (union), reindex both
        all_time = pd.DatetimeIndex(sorted(set(g_time) | set(s_time)))
        g_re = np.stack([pd.Series(g_means[t], index=g_time).reindex(all_time).to_numpy() for t in tiles])
        s_re = np.stack([pd.Series(s_means[t], index=s_time).reindex(all_time).to_numpy() for t in tiles])
        data = {"grace_lwe": (("region", "time"), g_re), "soil": (("region", "time"), s_re)}
        coords = {"region": tiles, "time": all_time}

    ds = xr.Dataset(data, coords=coords)
    ds.to_netcdf(OUT / "region_labels.nc")

    # --- summary ---
    print(f"regions          : {len(tiles)}")
    print(f"GRACE months     : {g_time.min().date()} .. {g_time.max().date()}  (n={len(g_time)})")
    g = ds["grace_lwe"]
    cov_g = float((~np.isnan(g)).mean()) * 100
    print(f"GRACE coverage   : {cov_g:.0f}% non-NaN;  value range {float(g.min()):.1f}..{float(g.max()):.1f} cm")
    if "soil" in ds:
        s = ds["soil"]
        cov_s = float((~np.isnan(s)).mean()) * 100
        print(f"soil months      : n={ds.sizes['time']} (merged axis)")
        print(f"soil coverage    : {cov_s:.0f}% non-NaN;  value range {float(np.nanmin(s)):.0f}..{float(np.nanmax(s)):.0f} mm")
    else:
        print("soil             : TerraClimate files not present yet (GRACE-only labels written)")
    print(f"written          : {OUT / 'region_labels.nc'}")


if __name__ == "__main__":
    main()
