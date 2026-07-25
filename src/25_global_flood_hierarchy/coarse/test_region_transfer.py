"""Do static region attributes transfer to regions the model never saw?

test_input_design.py found static attributes are the single biggest input change
(median val NSE 0.495 -> 0.602, arid regions 0.123 -> 0.344). But that test splits
in TIME only: every region appears in training, so the network can reach the same
score by memorising each region's offset and amplitude from its attribute vector.
Memorisation would not transfer, and transfer is the entire point of the coarse
layer -- it exists to carry a regional state into places without gauges.

Spatial holdout settles it. Regions are split into three longitude bands; the model
trains on two bands and is scored on the third, which it has never seen. Same
temporal split inside the training regions.

  B  spin-up, 6 meteorological features   (no region descriptor at all)
  S  spin-up + 4 static attributes        (the arm under test)

If S still beats B on held-out regions, the attributes carry transferable climate
information. If S collapses to B or below, the gain in the time-split test was
region memorisation and must not be trusted for ungauged use.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd
import torch
import xarray as xr

from test_input_design import (LABEL_START, SPINUP_START, TRAIN_END, VAL_END, VAL_START, CoarseGRU,
                               EPOCHS, HIDDEN, LR, SEEDS, add_features, load, nse, standardise)

REPO = Path(__file__).resolve().parents[3]
OUT = REPO / "results" / "25_global_flood_hierarchy" / "coarse_v0"
MEMBERSHIP = OUT / "region_forcing" / "region_membership.csv"


def fit_predict(X: np.ndarray, Y: np.ndarray, months: pd.DatetimeIndex, tr_reg: np.ndarray,
                seed: int) -> np.ndarray:
    """Train on tr_reg regions only; return predictions for every region."""
    torch.manual_seed(seed)
    np.random.seed(seed)
    keep = months >= SPINUP_START
    Xs, Ys, ms = X[:, keep], Y[:, keep], months[keep]
    train_m = ms <= TRAIN_END

    # standardise on training regions x training months only
    Xz, Yz, tmu, tsd = standardise(Xs[tr_reg], Ys[tr_reg], train_m)
    fmu = np.nanmean(Xs[tr_reg][:, train_m], axis=(0, 1))
    fsd = np.nanstd(Xs[tr_reg][:, train_m], axis=(0, 1)) + 1e-6
    Xz_all = np.nan_to_num((Xs - fmu) / fsd, nan=0.0)
    Yz_all = (Ys - tmu) / tsd

    dev = "cuda" if torch.cuda.is_available() else "cpu"
    xt = torch.tensor(Xz_all, dtype=torch.float32, device=dev)
    yt = torch.tensor(Yz_all, dtype=torch.float32, device=dev)
    mask = torch.tensor(np.isfinite(Yz_all), dtype=torch.float32, device=dev)
    ymask = yt.clone()
    ymask[mask == 0] = 0.0
    tr_m = torch.tensor(train_m, device=dev)
    tr_r = torch.tensor(tr_reg, device=dev)

    model = CoarseGRU(Xs.shape[-1], HIDDEN, Ys.shape[-1]).to(dev)
    opt = torch.optim.Adam(model.parameters(), lr=LR)
    for _ in range(EPOCHS):
        opt.zero_grad()
        se = (model(xt) - ymask) ** 2 * mask
        sel = se[tr_r][:, tr_m]
        (sel.sum() / mask[tr_r][:, tr_m].sum().clamp(min=1)).backward()
        opt.step()
    model.eval()
    with torch.no_grad():
        pred = model(xt).cpu().numpy() * tsd + tmu
    full = np.full(Y.shape, np.nan)
    full[:, keep] = pred
    return full


def score(pred: np.ndarray, Y: np.ndarray, months: pd.DatetimeIndex, gi: int,
          regs: np.ndarray, window: tuple[str, str]) -> np.ndarray:
    sel = (months >= window[0]) & (months <= window[1])
    o, p = Y[regs][:, sel, gi], pred[regs][:, sel, gi]
    return np.array([nse(o[i], p[i]) for i in range(o.shape[0])])


def main() -> None:
    regions, months, X0, Y, targets, feats = load()
    gi = targets.index("grace_lwe")
    train_m_full = (months >= LABEL_START) & (months <= TRAIN_END)
    X_st, _ = add_features(X0, months, feats, train_m_full, acc=False, static=True)

    mem = pd.read_csv(MEMBERSHIP)
    lon = mem.groupby("tile")["gauge_lon"].mean().reindex(regions).to_numpy()
    edges = np.nanpercentile(lon, [33.3, 66.7])
    band = np.digitize(lon, edges)  # 0 = west, 1 = central, 2 = east

    print(f"regions {len(regions)}  longitude bands at {edges[0]:.1f} / {edges[1]:.1f} degE "
          f"-> n = {[int((band == b).sum()) for b in range(3)]}")
    print("held-out regions are never seen in training; scored on 2011-2014 and on all "
          "labelled months 2002-2014")
    print()
    hdr = (f"{'fold (held-out band)':22s} {'arm':10s} {'val median':>11s} {'val NSE>0':>10s} "
           f"{'all-lab median':>15s}")
    print(hdr)
    print("-" * len(hdr))

    agg = {"B base": [], "S +static": []}
    agg_all = {"B base": [], "S +static": []}
    for b in range(3):
        te = band == b
        tr = ~te
        for arm, Xa in [("B base", X0), ("S +static", X_st)]:
            med, npos, med_all = [], [], []
            for s in SEEDS:
                pred = fit_predict(Xa, Y, months, tr, s)
                per = score(pred, Y, months, gi, te, (VAL_START, VAL_END))
                med.append(np.nanmedian(per))
                npos.append(int(np.nansum(per > 0)))
                med_all.append(np.nanmedian(score(pred, Y, months, gi, te,
                                                  (LABEL_START, VAL_END))))
            m, n, ma = float(np.median(med)), int(np.median(npos)), float(np.median(med_all))
            agg[arm].append(m)
            agg_all[arm].append(ma)
            print(f"{['west', 'central', 'east'][b]:22s} {arm:10s} {m:11.3f} "
                  f"{n:6d}/{int(te.sum()):<3d} {ma:15.3f}")
        print()

    print("=== mean over the three held-out bands ===")
    for arm in agg:
        print(f"  {arm:10s} val median {np.mean(agg[arm]):+.3f}   "
              f"all-labelled median {np.mean(agg_all[arm]):+.3f}")
    d = np.mean(agg["S +static"]) - np.mean(agg["B base"])
    d_all = np.mean(agg_all["S +static"]) - np.mean(agg_all["B base"])
    print(f"  static-attribute effect on UNSEEN regions: {d:+.3f} (val)  {d_all:+.3f} (all labelled)")
    print("  compare with +0.108 on seen regions (test_input_design.py). A much smaller or "
          "negative number here means the seen-region gain was memorisation.")


if __name__ == "__main__":
    main()
