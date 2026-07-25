"""Build coarse-layer region-mean daily forcing from local CAMELS-US (no download).

Coarse layer v0 INPUT side. A "region" is a TILE_DEG-degree lat/lon grid cell.
Each CAMELS-US basin is assigned to the cell containing its gauge (lat, lon).
Region-mean forcing = simple mean over member basins' Daymet basin-mean forcing.

This is a v0 proxy: the intended coarse forcing is the spatial mean of a gridded
field (e.g. ERA5-Land) over the region. Averaging member-basin series is biased to
gauged locations, but it is zero-download and enough to stand up the input->state
plumbing. Swap in gridded-field means later behind the same output interface.

Outputs (under results/25_global_flood_hierarchy/coarse_v0/region_forcing/):
  region_forcing.nc      xarray Dataset dims (region, time), one var per forcing field
  region_membership.csv  gauge_id, tile, lat, lon, n_basins_in_tile
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
import xarray as xr

REPO = Path(__file__).resolve().parents[3]
CAMELS = REPO / "data" / "camels_us"
FORCING_ROOT = CAMELS / "basin_mean_forcing" / "daymet"
TOPO = CAMELS / "camels_attributes_v2.0" / "camels_topo.txt"
OUT = REPO / "results" / "25_global_flood_hierarchy" / "coarse_v0" / "region_forcing"

TILE_DEG = 2.0
# Daymet basin-mean forcing columns kept for the coarse water-balance state.
FORCING_VARS = ["prcp(mm/day)", "srad(W/m2)", "swe(mm)", "tmax(C)", "tmin(C)", "vp(Pa)"]


def tile_id(lat: float, lon: float, deg: float = TILE_DEG) -> str:
    """Grid-cell id from the cell's lower-left corner in `deg`-degree steps."""
    row = int(np.floor(lat / deg))
    col = int(np.floor(lon / deg))
    return f"lat{row * int(deg):+04d}_lon{col * int(deg):+04d}"


def read_topo() -> pd.DataFrame:
    df = pd.read_csv(TOPO, sep=";", dtype={"gauge_id": str})
    df["gauge_id"] = df["gauge_id"].str.zfill(8)
    return df[["gauge_id", "gauge_lat", "gauge_lon"]].dropna()


def read_basin_forcing(gauge_id: str) -> pd.DataFrame | None:
    matches = list(FORCING_ROOT.glob(f"*/{gauge_id}_*_forcing_leap.txt"))
    if not matches:
        return None
    df = pd.read_csv(matches[0], sep=r"\s+", skiprows=3)
    df["date"] = pd.to_datetime(dict(year=df["Year"], month=df["Mnth"], day=df["Day"]))
    keep = [v for v in FORCING_VARS if v in df.columns]
    return df.set_index("date")[keep].sort_index()


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    topo = read_topo()
    topo["tile"] = [tile_id(la, lo) for la, lo in zip(topo["gauge_lat"], topo["gauge_lon"])]

    # Load every basin's forcing, tag with its tile.
    frames: dict[str, list[pd.DataFrame]] = {}
    missing = []
    for _, row in topo.iterrows():
        f = read_basin_forcing(row["gauge_id"])
        if f is None:
            missing.append(row["gauge_id"])
            continue
        frames.setdefault(row["tile"], []).append(f)

    # Region-mean = mean over member basins, aligned on the union of dates.
    region_da = {}
    for tile, dfs in frames.items():
        stacked = pd.concat(dfs, axis=0).groupby(level=0).mean()
        region_da[tile] = stacked

    regions = sorted(region_da)
    all_dates = sorted(set().union(*[set(df.index) for df in region_da.values()]))
    time_index = pd.DatetimeIndex(all_dates)

    ds = xr.Dataset(
        {
            var.split("(")[0]: (
                ("region", "time"),
                np.stack([region_da[r].reindex(time_index)[var].to_numpy() for r in regions]),
            )
            for var in FORCING_VARS
        },
        coords={"region": regions, "time": time_index},
    )
    ds.to_netcdf(OUT / "region_forcing.nc")

    counts = topo[~topo["gauge_id"].isin(missing)].groupby("tile").size()
    membership = topo.copy()
    membership["n_basins_in_tile"] = membership["tile"].map(counts).fillna(0).astype(int)
    membership.to_csv(OUT / "region_membership.csv", index=False)

    # --- sanity checks + summary (self-verifying) ---
    prcp = ds["prcp"]
    ann_mean = float(prcp.mean().item()) * 365.25  # mm/yr, grand mean
    assert len(regions) >= 10, f"suspiciously few regions: {len(regions)}"
    assert 100 < ann_mean < 3000, f"region-mean annual precip out of range: {ann_mean:.0f} mm/yr"

    print(f"basins used     : {len(topo) - len(missing)} / {len(topo)}  (missing forcing: {len(missing)})")
    print(f"regions (2deg)  : {len(regions)}")
    print(f"basins/region   : min {counts.min()}  median {int(counts.median())}  max {counts.max()}")
    print(f"date range      : {time_index.min().date()} .. {time_index.max().date()}  ({len(time_index)} days)")
    print(f"grand-mean prcp : {ann_mean:.0f} mm/yr   (sanity 100..3000)")
    big = counts.sort_values(ascending=False).head(3)
    print(f"largest regions : " + ", ".join(f"{t}({n})" for t, n in big.items()))
    print(f"written         : {OUT / 'region_forcing.nc'}")
    print(f"                  {OUT / 'region_membership.csv'}")


if __name__ == "__main__":
    main()
