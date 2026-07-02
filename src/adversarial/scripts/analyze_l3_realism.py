"""L3 physical realism: is the adversarial budget eps=0.1 within the real disagreement
between gridded forcing products?

Compares eps in physical units (precip +/-0.70 mm/d, mean-temp +/-1.07 C at eps=0.1)
to the day-to-day spread between Daymet / Maurer / NLDAS at the same basins/dates over
the test period. ratio = eps / inter-product spread; ratio<=1 => the harmful perturbation
is within real forcing uncertainty (reachable), ratio>1 => it exceeds typical real errors.

    python src/adversarial/scripts/analyze_l3_realism.py
"""
from pathlib import Path
import numpy as np
import pandas as pd

REPO = Path(__file__).resolve().parents[3]
DATA_DIR = REPO / "data" / "camels_us"
BASIN_FILE = REPO / "src" / "adversarial" / "data" / "531_basins.txt"
RES = REPO / "results" / "05_adversarial_robustness" / "id18_s100"
from neuralhydrology.datasetzoo.camelsus import load_camels_us_forcings

EPS_PRCP, EPS_TEMP = 0.70, 1.07          # eps=0.1 in physical units (Table 2, Maurer sigma)
TEST0, TEST1 = "1989-10-01", "1999-09-30"


def cols(df):
    lc = {c.lower(): c for c in df.columns}
    def find(key):
        for k, orig in lc.items():
            if key in k:
                return orig
        return None
    return find("prcp"), find("tmax"), find("tmin")


basins = [b.strip() for b in open(BASIN_FILE) if b.strip()]
rows, fail = [], 0
for basin in basins:
    try:
        prods = {}
        for p in ("daymet", "maurer", "nldas"):
            df, _ = load_camels_us_forcings(DATA_DIR, basin, p)
            df = df.loc[TEST0:TEST1]
            cp, cx, cn = cols(df)
            prods[p] = pd.DataFrame({"prcp": df[cp], "tmean": (df[cx] + df[cn]) / 2.0})
        idx = prods["daymet"].index
        for p in prods:
            idx = idx.intersection(prods[p].index)
        P = np.stack([prods[p].loc[idx, "prcp"].to_numpy() for p in prods])     # [3, T]
        Tm = np.stack([prods[p].loc[idx, "tmean"].to_numpy() for p in prods])
        ok = np.isfinite(P).all(0) & np.isfinite(Tm).all(0)
        P, Tm = P[:, ok], Tm[:, ok]
        p_std, t_std = P.std(0), Tm.std(0)                                      # per-day inter-product std
        p_rng, t_rng = P.max(0) - P.min(0), Tm.max(0) - Tm.min(0)
        rows.append(dict(
            basin=basin,
            prcp_spread=float(p_std.mean()), temp_spread=float(t_std.mean()),
            prcp_exceed=float((p_rng > EPS_PRCP).mean()),   # frac days product range > eps
            temp_exceed=float((t_rng > EPS_TEMP).mean()),
        ))
    except Exception as e:  # noqa: BLE001
        fail += 1

df = pd.DataFrame(rows)
print(f"basins: {len(df)} ok, {fail} failed")
print(f"\neps physical: precip +/-{EPS_PRCP} mm/d | mean-temp +/-{EPS_TEMP} C")
print(f"median inter-product spread (mean daily std): "
      f"precip {df.prcp_spread.median():.3f} mm/d | temp {df.temp_spread.median():.3f} C")
print(f"ratio eps / spread: precip {EPS_PRCP/df.prcp_spread.median():.2f} | temp {EPS_TEMP/df.temp_spread.median():.2f}")
print(f"\nfrac of days the 3-product RANGE exceeds eps (median over basins): "
      f"precip {df.prcp_exceed.median():.3f} | temp {df.temp_exceed.median():.3f}")
print(f"basins where median product spread >= eps: "
      f"precip {int((df.prcp_spread >= EPS_PRCP).sum())}/{len(df)} | "
      f"temp {int((df.temp_spread >= EPS_TEMP).sum())}/{len(df)}")
df.to_csv(RES / "l3_realism_summary.csv", index=False)
print(f"\nsaved -> {RES / 'l3_realism_summary.csv'}")
