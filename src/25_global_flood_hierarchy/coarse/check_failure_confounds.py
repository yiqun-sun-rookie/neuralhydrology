"""Stress-test the 'arid regions are intrinsically unlearnable' reading of B.

Two confounds that would change the story, both computable from the saved npz:

1. DROUGHT-EXTRAPOLATION. Validation is 2011-2014, which contains the 2011 Texas
   and 2012-2014 California/Southwest droughts: a large, monotonic GRACE drawdown
   concentrated in exactly the failing (southwestern) regions. If the failures are
   the model flattening a downward trend it never saw in 2002-2010 training, that is
   out-of-distribution extrapolation, not an intrinsic arid-region limit. Test: do
   failing regions have a strong negative obs trend that the model fails to follow
   (obs slope << pred slope)?

2. BIAS vs DYNAMICS. NSE penalizes a wrong mean level (bias) and a wrong shape
   (centered error) together. If failing-region MSE is bias-dominated, the model
   tracks the shape but sits at the wrong level (more fixable) rather than being
   unable to track storage at all. Test: bias^2 / total MSE for fail vs pass.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
import pandas as pd

REPO = Path(__file__).resolve().parents[3]
OUT = REPO / "results" / "25_global_flood_hierarchy" / "coarse_v0"
NPZ = OUT / "coarse_v0_pred.npz"


def slope_per_year(months: pd.DatetimeIndex, y: np.ndarray) -> float:
    """OLS slope of y (cm) vs time in years; NaN-safe."""
    m = np.isfinite(y)
    if m.sum() < 5:
        return np.nan
    t = (months[m] - months[m][0]).days.to_numpy() / 365.25
    return float(np.polyfit(t, y[m], 1)[0])


def main() -> None:
    d = np.load(NPZ, allow_pickle=True)
    regions = [str(r) for r in d["regions"]]
    months = pd.to_datetime([str(m) for m in d["months"]])
    obs, pred = d["obs"], d["pred"]
    targets = [str(t) for t in d["targets"]]
    val = d["val_mask"].astype(bool)
    gi = targets.index("grace_lwe")
    vmonths = months[val]

    rows = []
    for i in range(len(regions)):
        o, p = obs[i, val, gi], pred[i, val, gi]
        m = np.isfinite(o) & np.isfinite(p)
        if m.sum() < 5:
            continue
        oo, pp = o[m], p[m]
        denom = np.sum((oo - oo.mean()) ** 2)
        nse = 1 - np.sum((oo - pp) ** 2) / denom if denom > 0 else np.nan
        bias = float(np.mean(pp - oo))
        resid = (pp - oo) - bias
        crmse = float(np.sqrt(np.mean(resid ** 2)))  # centered RMSE (shape error)
        mse = float(np.mean((pp - oo) ** 2))
        bias_frac = bias ** 2 / mse if mse > 0 else np.nan
        nse_debias = 1 - crmse ** 2 / (denom / m.sum()) if denom > 0 else np.nan  # NSE if level were right
        rows.append(dict(
            region=regions[i], nse=nse, nse_debias=nse_debias, bias=bias, crmse=crmse, bias_frac=bias_frac,
            obs_slope=slope_per_year(vmonths[m] if m.sum() == len(o) else vmonths[np.isfinite(o)], oo)
            if m.sum() == len(o) else slope_per_year(vmonths, o),
            pred_slope=slope_per_year(vmonths, p),
        ))
    df = pd.DataFrame(rows)
    # recompute slopes cleanly on the aligned val series (avoid the messy inline guard)
    df["obs_slope"] = [slope_per_year(vmonths, obs[regions.index(r), val, gi]) for r in df["region"]]
    df["pred_slope"] = [slope_per_year(vmonths, pred[regions.index(r), val, gi]) for r in df["region"]]
    df["slope_gap"] = df["obs_slope"] - df["pred_slope"]  # how much drawdown the model misses

    fail = df["nse"] < 0
    F, P = df[fail], df[~fail]

    def med(g, c):
        return float(np.nanmedian(g[c]))

    print(f"val window               : {vmonths.min().date()} .. {vmonths.max().date()}")
    print(f"regions                  : fail {len(F)}   pass {len(P)}")
    print()
    print("=== confound 1: drought-trend extrapolation ===")
    print(f"median obs slope (cm/yr) : pass {med(P,'obs_slope'):+.2f}   fail {med(F,'obs_slope'):+.2f}"
          "   (negative = storage draining over 2011-2014)")
    print(f"median pred slope        : pass {med(P,'pred_slope'):+.2f}   fail {med(F,'pred_slope'):+.2f}")
    print(f"median slope gap (o-p)   : pass {med(P,'slope_gap'):+.2f}   fail {med(F,'slope_gap'):+.2f}"
          "   (large negative = model misses a real drawdown)")
    strong_draw = (F["obs_slope"] < -1.0)
    print(f"fail regions draining hard(obs slope < -1 cm/yr): {int(strong_draw.sum())}/{len(F)}")
    print()
    print("=== confound 2: bias vs dynamics ===")
    print(f"median |bias| (cm)       : pass {med(P,'bias').__abs__():.2f}   "
          f"fail {abs(med(F,'bias')):.2f}")
    print(f"median centered RMSE     : pass {med(P,'crmse'):.2f}   fail {med(F,'crmse'):.2f}"
          "   (shape error; large = truly can't track)")
    print(f"median bias^2 / MSE      : pass {med(P,'bias_frac'):.2f}   fail {med(F,'bias_frac'):.2f}"
          "   (near 1 = failure is wrong LEVEL; near 0 = wrong SHAPE)")
    db_pass = int((P["nse_debias"] > 0).sum())
    db_fail = int((F["nse_debias"] > 0).sum())
    print(f"median NSE if level fixed: pass {med(P,'nse_debias'):+.2f}   fail {med(F,'nse_debias'):+.2f}"
          "   (debiased: shape-only skill)")
    print(f"fail regions that FLIP to NSE>0 once bias removed : {db_fail}/{len(F)}")


if __name__ == "__main__":
    main()
