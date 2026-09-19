"""Stage 0b-1 extraction for the precip-input-da line (runs on the HPC login node, single thread, seconds).

Inputs : <dst>/base/C4/validation/model_epoch030/validation_results.p  (seed-100 C4 validation, both water years)
         <parquet>                                                      (track0 Maurer forcing, all 531 basins)
Outputs: <dst>/exports/c4_s100_tune_year_sim_obs.npz   TUNING YEAR ONLY (2006-10-01..2007-09-30), sim + obs per basin
         <dst>/exports/track0_forcing_4basins.csv      four basins, full record, for a local byte check vs data/camels_us
The exam year (2007-10-01..2008-09-30) is deliberately NOT written anywhere outside the cluster (plan v1.1 section 1).
No backslash literals in this file (mailbox heredoc rule).
"""
import pickle
import sys
from pathlib import Path

import numpy as np
import pandas as pd

TUNE_START, TUNE_END = "2006-10-01", "2007-09-30"
FOUR_BASINS = ["01022500", "01547700", "02064000", "03015500"]


def main(dst: Path, parquet: Path) -> None:
    out = dst / "exports"
    out.mkdir(parents=True, exist_ok=True)

    # ---- 1. seed-100 validation results -> tuning-year sim/obs ---------------------------------------------------
    pkl = dst / "base" / "C4" / "validation" / "model_epoch030" / "validation_results.p"
    with open(pkl, "rb") as fh:
        res = pickle.load(fh)
    basins = sorted(res)
    print(f"validation_results.p: {len(basins)} basins; first={basins[0]} last={basins[-1]}")
    first = res[basins[0]]
    print(f"top-level keys of first basin: {list(first.keys())}")
    xr0 = first["1D"]["xr"]
    print(f"xr dims={dict(xr0.sizes)} vars={list(xr0.data_vars)}")
    print(f"xr date range: {pd.to_datetime(xr0['date'].values).min().date()} .. "
          f"{pd.to_datetime(xr0['date'].values).max().date()} (full validation period, stays on cluster)")

    dates = pd.date_range(TUNE_START, TUNE_END, freq="D")
    sim = np.full((len(basins), len(dates)), np.nan, dtype=np.float32)
    obs = np.full((len(basins), len(dates)), np.nan, dtype=np.float32)
    for i, b in enumerate(basins):
        xr = res[b]["1D"]["xr"]
        if "time_step" in xr.dims:
            xr = xr.isel(time_step=-1)
        s = xr["QObs(mm/d)_sim"].to_series()
        o = xr["QObs(mm/d)_obs"].to_series()
        s.index = pd.to_datetime(s.index)
        o.index = pd.to_datetime(o.index)
        sim[i] = s.reindex(dates).to_numpy(dtype=np.float32)
        obs[i] = o.reindex(dates).to_numpy(dtype=np.float32)

    np.savez_compressed(out / "c4_s100_tune_year_sim_obs.npz",
                        basins=np.array(basins),
                        dates=dates.values.astype("datetime64[D]"),
                        sim=sim,
                        obs=obs)
    # sanity: tuning-year NSE median (not a registered number, just to prove the arrays are aligned)
    nse = []
    for i in range(len(basins)):
        m = np.isfinite(sim[i]) & np.isfinite(obs[i])
        if m.sum() < 30:
            continue
        o_, s_ = obs[i][m], sim[i][m]
        nse.append(1.0 - float(np.sum((s_ - o_) ** 2)) / float(np.sum((o_ - o_.mean()) ** 2)))
    print(f"tuning-year sanity: n_basins_with_data={len(nse)} median_NSE={np.median(nse):.4f} "
          f"nan_frac_sim={np.mean(~np.isfinite(sim)):.4f} nan_frac_obs={np.mean(~np.isfinite(obs)):.4f}")

    # ---- 2. four-basin slice of the track0 Maurer parquet ----------------------------------------------------------
    df = pd.read_parquet(parquet, filters=[("gauge_id", "in", FOUR_BASINS)])
    df["gauge_id"] = df["gauge_id"].astype(str).str.zfill(8)
    df = df.sort_values(["gauge_id", "date"])
    df.to_csv(out / "track0_forcing_4basins.csv", index=False)
    print(f"parquet slice: rows={len(df)} basins={sorted(df['gauge_id'].unique())} cols={list(df.columns)} "
          f"date range {pd.to_datetime(df['date']).min().date()} .. {pd.to_datetime(df['date']).max().date()}")


if __name__ == "__main__":
    main(Path(sys.argv[1]), Path(sys.argv[2]))
