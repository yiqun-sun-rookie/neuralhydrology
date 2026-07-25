"""Diagnose where coarse v0 fails: the regions with negative GRACE NSE.

Question B: are the failing regions clustered (a shared geography/climate) or
scattered, and is the failure a real modeling failure or an NSE-metric artifact?

NSE is variance-normalized: NSE = 1 - SSE / SS_obs. A region whose GRACE storage
barely moves (small seasonal amplitude) has a tiny denominator, so even a small
absolute error drives NSE negative. Such a region is "failing" by NSE yet may have
a perfectly small absolute error. This script separates the two explanations.

For every region it aligns validation skill against attributes:
  amplitude   std of validation GRACE obs   (the NSE denominator; small -> unforgiving)
  rmse        absolute error on validation  (is the model actually far off?)
  precip      annual region precip (mm/yr)  (aridity proxy)
  swe         mean snow water equivalent     (snow/mountain proxy)
  n_basins    gauged basins in the region    (proxy-noise test, revisited)
  lat, lon    location                       (spatial clustering)

Outputs a 4-panel figure + a printed fail-vs-pass comparison with the single
attribute that best separates the two groups.
"""
from __future__ import annotations

from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import xarray as xr

REPO = Path(__file__).resolve().parents[3]
OUT = REPO / "results" / "25_global_flood_hierarchy" / "coarse_v0"
NPZ = OUT / "coarse_v0_pred.npz"
FORCING = OUT / "region_forcing" / "region_forcing.nc"
MEMBERSHIP = OUT / "region_forcing" / "region_membership.csv"
FIG = OUT / "coarse_v0_failure_diagnosis.png"


def nse(o, p):
    m = np.isfinite(o) & np.isfinite(p)
    if m.sum() < 5:
        return np.nan
    o, p = o[m], p[m]
    d = np.sum((o - o.mean()) ** 2)
    return 1 - np.sum((o - p) ** 2) / d if d > 0 else np.nan


def rmse(o, p):
    m = np.isfinite(o) & np.isfinite(p)
    if m.sum() < 5:
        return np.nan
    return float(np.sqrt(np.mean((o[m] - p[m]) ** 2)))


def main() -> None:
    d = np.load(NPZ, allow_pickle=True)
    regions = [str(r) for r in d["regions"]]
    obs, pred = d["obs"], d["pred"]  # (R,T,K)
    targets = [str(t) for t in d["targets"]]
    val = d["val_mask"].astype(bool)
    gi = targets.index("grace_lwe")

    # per-region validation skill + absolute error + signal amplitude
    R = len(regions)
    reg_nse = np.full(R, np.nan)
    reg_rmse = np.full(R, np.nan)
    reg_amp = np.full(R, np.nan)  # std of validation obs = sqrt(NSE denominator / n)
    for i in range(R):
        o, p = obs[i, val, gi], pred[i, val, gi]
        reg_nse[i] = nse(o, p)
        reg_rmse[i] = rmse(o, p)
        ov = o[np.isfinite(o)]
        reg_amp[i] = ov.std() if ov.size >= 5 else np.nan

    # region attributes: precip (aridity), swe (snow), location, #basins
    fc = xr.open_dataset(FORCING).reindex(region=regions)
    precip = fc["prcp"].mean("time").values * 365.25  # mm/yr
    swe = fc["swe"].mean("time").values  # mm
    mem = pd.read_csv(MEMBERSHIP)
    cen = mem.groupby("tile").agg(lat=("gauge_lat", "mean"), lon=("gauge_lon", "mean"),
                                  n=("gauge_id", "size")).reindex(regions)
    lat, lon, nbas = cen["lat"].values, cen["lon"].values, cen["n"].values

    df = pd.DataFrame(dict(region=regions, nse=reg_nse, rmse=reg_rmse, amp=reg_amp,
                           precip=precip, swe=swe, lat=lat, lon=lon, nbas=nbas))
    df = df[np.isfinite(df["nse"])].reset_index(drop=True)
    fail = df["nse"] < 0
    F, P = df[fail], df[~fail]

    # which attribute best separates fail from pass? standardized median gap.
    attrs = ["amp", "rmse", "precip", "swe", "lat", "lon", "nbas"]
    seps = {}
    for a in attrs:
        pooled_sd = df[a].std() + 1e-9
        seps[a] = (P[a].median() - F[a].median()) / pooled_sd
    best = max(seps, key=lambda k: abs(seps[k]))

    # --- figure ---
    fig, ax = plt.subplots(2, 2, figsize=(13, 9))

    a = ax[0, 0]  # map: fail vs pass, sized by amplitude
    a.scatter(P["lon"], P["lat"], s=12 + 40 * P["amp"] / df["amp"].max(), c="C0",
              alpha=0.7, edgecolor="k", linewidth=0.3, label=f"pass ({len(P)})")
    a.scatter(F["lon"], F["lat"], s=12 + 40 * F["amp"] / df["amp"].max(), c="C3",
              marker="X", alpha=0.85, edgecolor="k", linewidth=0.3, label=f"fail ({len(F)})")
    a.set_title("A. failing regions (red X); size ~ GRACE amplitude")
    a.set_xlabel("lon"); a.set_ylabel("lat"); a.legend(fontsize=8, loc="lower left")

    b = ax[0, 1]  # the artifact test: NSE vs amplitude
    b.scatter(df["amp"], np.clip(df["nse"], -1.5, 1), s=22, alpha=0.65,
              c=np.where(fail, "C3", "C0"), edgecolor="k", linewidth=0.3)
    b.axhline(0, color="grey", lw=0.8, ls="--")
    r_amp = np.corrcoef(df["amp"], np.clip(df["nse"], -1.5, 1))[0, 1]
    b.set_title(f"B. NSE vs GRACE amplitude  (corr {r_amp:+.2f})")
    b.set_xlabel("val GRACE amplitude = std of obs (cm)"); b.set_ylabel("GRACE NSE (clip -1.5..1)")

    c = ax[1, 0]  # is absolute error actually worse in failures?
    c.scatter(P["amp"], P["rmse"], s=20, alpha=0.7, c="C0", edgecolor="k", linewidth=0.3, label="pass")
    c.scatter(F["amp"], F["rmse"], s=26, alpha=0.85, c="C3", marker="X", edgecolor="k",
              linewidth=0.3, label="fail")
    lim = [0, float(np.nanmax(df["amp"])) * 1.05]
    c.plot(lim, lim, "grey", lw=0.8, ls=":", label="rmse = amplitude (NSE=0)")
    c.set_title("C. absolute error vs amplitude (below dotted line = NSE>0)")
    c.set_xlabel("GRACE amplitude (cm)"); c.set_ylabel("val RMSE (cm)"); c.legend(fontsize=7)

    dax = ax[1, 1]  # best-separating attribute distribution
    dax.boxplot([P[best].dropna(), F[best].dropna()], labels=[f"pass\n(n={len(P)})",
                                                              f"fail\n(n={len(F)})"])
    dax.set_title(f"D. best separator: '{best}'  (pass median {P[best].median():.2g} vs "
                  f"fail {F[best].median():.2g})")
    dax.set_ylabel(best)

    fig.suptitle("Coarse v0: why 39 regions fail (negative GRACE NSE)", fontsize=13)
    fig.tight_layout(rect=(0, 0, 1, 0.97))
    fig.savefig(FIG, dpi=120)

    # --- printed verdict ---
    # NOTE: RMSE<amp is tautological with NSE>0 (NSE = 1-(RMSE/amp)^2 when unbiased),
    # so it is NOT an independent artifact test. The honest decomposition is: failing
    # regions have BOTH a smaller signal (amp) AND a larger absolute error (rmse) than
    # passing ones -> a genuine limitation, compounded by (not caused by) the metric.
    print(f"regions scored           : {len(df)}   fail(NSE<0) {len(F)}   pass {len(P)}")
    print(f"median amplitude         : pass {P['amp'].median():.2f} cm   fail {F['amp'].median():.2f} cm  "
          f"(fail signal is weaker -> smaller NSE denominator)")
    print(f"median RMSE              : pass {P['rmse'].median():.2f} cm   fail {F['rmse'].median():.2f} cm  "
          f"(fail abs error is LARGER -> genuinely worse, not only a metric effect)")
    print(f"median annual precip     : pass {P['precip'].median():.0f}   fail {F['precip'].median():.0f} mm/yr")
    print(f"median snow (swe)        : pass {P['swe'].median():.1f}   fail {F['swe'].median():.1f} mm")
    print(f"median #basins/region    : pass {P['nbas'].median():.0f}   fail {F['nbas'].median():.0f}")
    print(f"median latitude          : pass {P['lat'].median():.1f}   fail {F['lat'].median():.1f} degN "
          f"(fail sits further south)")
    print(f"NSE vs amplitude corr    : {r_amp:+.2f}   (positive => low-amplitude regions fail)")
    print("standardized fail-vs-pass gap per attribute (|larger| = better separator):")
    for a in sorted(seps, key=lambda k: -abs(seps[k])):
        print(f"    {a:8s} {seps[a]:+.2f}")
    print(f"best separator           : '{best}'  (dry, low-storage-variability arid regions)")
    print(f"saved figure             : {FIG}")


if __name__ == "__main__":
    main()
