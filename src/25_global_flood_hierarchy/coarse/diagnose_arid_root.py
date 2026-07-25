"""Root-cause diagnostic for the arid-third weakness (Step 1.1 follow-up, zero cost).

After per-region loss standardisation (train_coarse_v2.py) failed to move the arid
third (0.344 -> 0.341), this asks whether the arid weakness is a MODEL failure or an
INFORMATION limit, using the discriminator: per-region last-month-persistence NSE by
aridity band.

  arid persistence HIGH, model LOW  -> signal exists, model can't track -> capacity/structure
  arid persistence LOW  (both low)  -> storage genuinely hard -> new inputs, not capacity

Also reports lag-1 autocorrelation (predictability proxy) and the trend share of the
validation-window variance (human-water / drought signature that meteo forcing cannot see).

Reads only what already exists: coarse_v2_pred.npz (obs, months, val_mask) plus
region_forcing.nc for the annual-precip banding, recomputed exactly as the training
scripts do. No training, no download.

Result (2026-07-25):
  band   n   model  persist   clim   ac1  trend%
  arid  60   0.341   0.700  -0.354  0.85   0.35
  mid   60   0.620   0.725   0.316  0.80   0.09
  wet   60   0.749   0.717   0.573  0.79   0.04
Arid storage is highly persistent (ac1 0.85) and NOT seasonal (climatology NSE < 0);
35% of its validation variance is a linear trend the forcing has no information about.
The model captures roughly half the learnable part -> forcing-only arid ceiling ~0.6-0.65,
not persistence's 0.70 (which rides the trend by copying last month but is unusable where
the coarse state is meant to go).
"""
from pathlib import Path

import numpy as np
import pandas as pd
import xarray as xr

REPO = Path(__file__).resolve().parents[3]
OUT = REPO / "results" / "25_global_flood_hierarchy" / "coarse_v0"
NPZ = OUT / "coarse_v2_pred.npz"
FORCING = OUT / "region_forcing" / "region_forcing.nc"
LABEL_START, TRAIN_END = "2002-01-01", "2010-12-31"


def nse(o: np.ndarray, p: np.ndarray) -> float:
    m = np.isfinite(o) & np.isfinite(p)
    if m.sum() < 5:
        return np.nan
    o, p = o[m], p[m]
    d = np.sum((o - o.mean()) ** 2)
    return 1.0 - np.sum((o - p) ** 2) / d if d > 0 else np.nan


def ac1(x: np.ndarray) -> float:
    x = x[np.isfinite(x)]
    if x.size < 12:
        return np.nan
    x = x - x.mean()
    return np.sum(x[1:] * x[:-1]) / np.sum(x * x)


def trend_share(x: np.ndarray, t: np.ndarray) -> float:
    m = np.isfinite(x)
    if m.sum() < 6:
        return np.nan
    x, t = x[m], t[m]
    fit = np.polyval(np.polyfit(t, x, 1), t)
    v = np.var(x)
    return np.var(fit) / v if v > 0 else np.nan


def main() -> None:
    d = np.load(NPZ, allow_pickle=True)
    obs = d["obs"]
    pred = d["pred"]
    months = pd.DatetimeIndex(d["months"].astype(str))
    val_m = d["val_mask"].astype(bool)
    targets = [str(t) for t in d["targets"]]
    gi = targets.index("grace_lwe")
    R = obs.shape[0]

    ds = xr.open_dataset(FORCING)
    prcp_m = ds["prcp"].resample(time="MS").sum()
    mt = pd.DatetimeIndex(prcp_m["time"].values)
    tr_forcing = (mt >= LABEL_START) & (mt <= TRAIN_END)
    ann = np.nanmean(prcp_m.values[:, tr_forcing], axis=1) * 12.0
    q1, q2 = np.nanpercentile(ann, [33.3, 66.7])
    grp = np.where(ann <= q1, 0, np.where(ann <= q2, 1, 2))
    names = {0: "arid", 1: "mid", 2: "wet"}

    persist = np.full_like(obs, np.nan)
    persist[:, 1:, :] = obs[:, :-1, :]
    clim = np.full_like(obs, np.nan)
    cal = months.month
    tr_lab = (months >= LABEL_START) & (months <= TRAIN_END)
    for mo in range(1, 13):
        sel = tr_lab & (cal == mo)
        if sel.sum():
            clim[:, cal == mo, gi] = np.nanmean(obs[:, sel, gi], axis=1, keepdims=True)

    m_nse = np.array([nse(obs[i, val_m, gi], pred[i, val_m, gi]) for i in range(R)])
    p_nse = np.array([nse(obs[i, val_m, gi], persist[i, val_m, gi]) for i in range(R)])
    c_nse = np.array([nse(obs[i, val_m, gi], clim[i, val_m, gi]) for i in range(R)])
    ac = np.array([ac1(obs[i, months >= LABEL_START, gi]) for i in range(R)])
    tt = np.arange(int(val_m.sum()))
    tshare = np.array([trend_share(obs[i, val_m, gi], tt) for i in range(R)])

    print(f"regions {R}   arid<= {q1:.0f} mm/yr   wet> {q2:.0f} mm/yr   (val = {int(val_m.sum())} months)\n")
    print(f"{'band':5s} {'n':>4s} {'model':>7s} {'persist':>8s} {'clim':>7s} {'ac1':>6s} {'trend%':>7s}")
    for g in (0, 1, 2):
        s = grp == g
        print(f"{names[g]:5s} {int(s.sum()):4d} "
              f"{np.nanmedian(m_nse[s]):7.3f} {np.nanmedian(p_nse[s]):8.3f} "
              f"{np.nanmedian(c_nse[s]):7.3f} {np.nanmedian(ac[s]):6.2f} {np.nanmedian(tshare[s]):7.2f}")
    print(f"{'ALL':5s} {R:4d} {np.nanmedian(m_nse):7.3f} {np.nanmedian(p_nse):8.3f} "
          f"{np.nanmedian(c_nse):7.3f} {np.nanmedian(ac):6.2f} {np.nanmedian(tshare):7.2f}")


if __name__ == "__main__":
    main()
