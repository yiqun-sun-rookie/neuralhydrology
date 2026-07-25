"""Probe what the coarse v0 GRU learned: where it works, and whether its hidden
state encodes storage. Produces a 4-panel figure.

A  per-region GRACE NSE on validation, mapped over CONUS
B  per-region GRACE NSE vs number of gauged basins in the region (proxy-noise test)
C  example region time series: GRACE obs vs model prediction (validation shaded)
D  the single hidden unit most correlated with GRACE obs -> did the state learn storage
"""
from __future__ import annotations

from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

REPO = Path(__file__).resolve().parents[3]
OUT = REPO / "results" / "25_global_flood_hierarchy" / "coarse_v0"
NPZ = OUT / "coarse_v0_pred.npz"
MEMBERSHIP = OUT / "region_forcing" / "region_membership.csv"
FIG = OUT / "coarse_v0_what_learned.png"


def nse(o, p):
    m = np.isfinite(o) & np.isfinite(p)
    if m.sum() < 5:
        return np.nan
    o, p = o[m], p[m]
    d = np.sum((o - o.mean()) ** 2)
    return 1 - np.sum((o - p) ** 2) / d if d > 0 else np.nan


def main() -> None:
    d = np.load(NPZ, allow_pickle=True)
    regions = [str(r) for r in d["regions"]]
    months = pd.to_datetime([str(m) for m in d["months"]])
    obs, pred, hidden = d["obs"], d["pred"], d["hidden"]  # (R,T,K),(R,T,K),(R,T,H)
    targets = [str(t) for t in d["targets"]]
    val = d["val_mask"].astype(bool)
    gi = targets.index("grace_lwe")

    mem = pd.read_csv(MEMBERSHIP)
    cen = mem.groupby("tile").agg(lat=("gauge_lat", "mean"), lon=("gauge_lon", "mean"),
                                  n=("gauge_id", "size")).reset_index()
    cen = cen.set_index("tile").reindex(regions)

    # per-region GRACE NSE on validation
    reg_nse = np.array([nse(obs[i, val, gi], pred[i, val, gi]) for i in range(len(regions))])

    fig, ax = plt.subplots(2, 2, figsize=(13, 9))

    # A: map
    a = ax[0, 0]
    sc = a.scatter(cen["lon"], cen["lat"], c=np.clip(reg_nse, -0.5, 1), s=18 + 4 * cen["n"],
                   cmap="RdYlBu", vmin=-0.5, vmax=1, edgecolor="k", linewidth=0.3)
    fig.colorbar(sc, ax=a, label="GRACE NSE (val)")
    a.set_title(f"A. per-region GRACE skill  (median NSE {np.nanmedian(reg_nse):.2f})")
    a.set_xlabel("lon"); a.set_ylabel("lat")

    # B: skill vs basins-per-region
    b = ax[0, 1]
    b.scatter(cen["n"], reg_nse, s=20, alpha=0.6, edgecolor="k", linewidth=0.3)
    b.axhline(0, color="grey", lw=0.8, ls="--")
    r = np.corrcoef(cen["n"], np.nan_to_num(reg_nse, nan=np.nanmedian(reg_nse)))[0, 1]
    b.set_title(f"B. skill vs #basins/region  (corr {r:+.2f})")
    b.set_xlabel("# gauged basins in region"); b.set_ylabel("GRACE NSE (val)")

    # C: example time series (best + a weak region)
    c = ax[1, 0]
    order = np.argsort(np.where(np.isfinite(reg_nse), reg_nse, -9))
    best, weak = order[-1], order[len(order) // 4]
    for idx, lab, col in [(best, f"best {regions[best]} (NSE {reg_nse[best]:.2f})", "C0"),
                          (weak, f"weak {regions[weak]} (NSE {reg_nse[weak]:.2f})", "C3")]:
        c.plot(months, obs[idx, :, gi], col, lw=1.4, label=f"obs {lab}")
        c.plot(months, pred[idx, :, gi], col, lw=1.0, ls="--", alpha=0.8)
    c.axvspan(months[val][0], months[val][-1], color="grey", alpha=0.12)
    c.set_title("C. GRACE obs (solid) vs model (dashed); val shaded")
    c.set_ylabel("lwe anomaly (cm)"); c.legend(fontsize=7, loc="upper left")

    # D: does the hidden state encode storage?
    dax = ax[1, 1]
    H = hidden.shape[-1]
    o_flat = obs[:, :, gi].ravel()
    corrs = []
    for h in range(H):
        hv = hidden[:, :, h].ravel()
        m = np.isfinite(o_flat) & np.isfinite(hv)
        corrs.append(np.corrcoef(o_flat[m], hv[m])[0, 1] if m.sum() > 10 else 0.0)
    corrs = np.array(corrs)
    hbest = int(np.argmax(np.abs(corrs)))
    hv = hidden[:, :, hbest].ravel()
    m = np.isfinite(o_flat) & np.isfinite(hv)
    dax.scatter(hv[m], o_flat[m], s=4, alpha=0.15)
    dax.set_title(f"D. best hidden unit #{hbest} vs GRACE  (corr {corrs[hbest]:+.2f})")
    dax.set_xlabel(f"hidden unit {hbest} activation"); dax.set_ylabel("GRACE lwe (cm)")

    fig.suptitle("Coarse v0: what the region GRU learned", fontsize=13)
    fig.tight_layout(rect=(0, 0, 1, 0.97))
    fig.savefig(FIG, dpi=120)
    print(f"regions with NSE>0        : {int(np.nansum(reg_nse > 0))}/{len(regions)}")
    print(f"regions beating clim(NSE>0.345 grand): median region NSE {np.nanmedian(reg_nse):.3f}")
    print(f"skill vs #basins corr     : {r:+.2f}")
    print(f"max |hidden-GRACE corr|   : unit {hbest}, corr {corrs[hbest]:+.2f}")
    print(f"saved figure              : {FIG}")


if __name__ == "__main__":
    main()
