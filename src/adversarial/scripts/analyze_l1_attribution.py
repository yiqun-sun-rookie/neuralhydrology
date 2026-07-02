"""L1 analysis: does the attack's per-forcing-variable attribution shift by regime?
Hypothesis: in snow catchments the attack rides the TEMPERATURE channel (mistiming
snowmelt); in rain catchments it rides PRECIPITATION.

Reads exp_l1l2_summary (leave-one-out channel attribution per basin), joins CAMELS
frac_snow, and reports Spearman + partial-Spearman (control clean NSE) of temp_share
vs snow, plus a snow-vs-rain group contrast. Works on whatever basins are done so far.

    python src/adversarial/scripts/analyze_l1_attribution.py
"""
import json
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import spearmanr, pearsonr, rankdata

REPO = Path(__file__).resolve().parents[3]
RES = REPO / "results" / "05_adversarial_robustness" / "id18_s100"
DATA_DIR = REPO / "data" / "camels_us"
from neuralhydrology.datasetzoo.camelsus import load_camels_us_attributes


def partial_spearman(x, y, z):
    rx, ry, rz = rankdata(x), rankdata(y), rankdata(z)
    def resid(a, b):
        B = np.vstack([b, np.ones_like(b)]).T
        c, *_ = np.linalg.lstsq(B, a, rcond=None)
        return a - B @ c
    return pearsonr(resid(rx, rz), resid(ry, rz))


s = json.load(open(RES / "exp_l1l2_summary_eps0.1.json"))
df = pd.DataFrame(s).T.rename_axis("basin").reset_index()
df["basin"] = df["basin"].astype(str).str.zfill(8)
for c in ["D_nse", "nse_clean", "precip_att", "temp_att", "srad_att", "vp_att"]:
    df[c] = df[c].astype(float)
tot = df[["precip_att", "temp_att", "srad_att", "vp_att"]].sum(axis=1).clip(lower=1e-9)
df["temp_share"] = df["temp_att"] / tot
df["precip_share"] = df["precip_att"] / tot

attrs = load_camels_us_attributes(DATA_DIR, basins=df["basin"].tolist())
attrs.index = attrs.index.astype(str).str.zfill(8)
df = df.merge(attrs[["frac_snow", "aridity", "hfd_mean", "baseflow_index"]],
              left_on="basin", right_index=True, how="left")

n = len(df)
print(f"basins analyzed: {n}")
print(f"temp_share  median {df.temp_share.median():.3f}  range [{df.temp_share.min():.2f}, {df.temp_share.max():.2f}]")
print(f"precip_share median {df.precip_share.median():.3f}")

r_raw, p_raw = spearmanr(df.temp_share, df.frac_snow)
r_par, p_par = partial_spearman(df.temp_share.values, df.frac_snow.values, df.nse_clean.values)
print(f"\ntemp_share vs frac_snow : Spearman {r_raw:+.3f} (p={p_raw:.1e}) | "
      f"partial|cleanNSE {r_par:+.3f} (p={p_par:.1e})")
rp_raw, _ = spearmanr(df.precip_share, df.frac_snow)
print(f"precip_share vs frac_snow: Spearman {rp_raw:+.3f}")

snow = df["frac_snow"] > 0.2
print(f"\n=== snow (frac_snow>0.2, n={int(snow.sum())}) vs rain (n={int((~snow).sum())}) ===")
print(f"temp_share   snow {df.loc[snow,'temp_share'].median():.3f}  vs rain {df.loc[~snow,'temp_share'].median():.3f}")
print(f"precip_share snow {df.loc[snow,'precip_share'].median():.3f}  vs rain {df.loc[~snow,'precip_share'].median():.3f}")
print(f"temp>precip? snow: {int((df.loc[snow,'temp_share']>df.loc[snow,'precip_share']).sum())}/{int(snow.sum())} basins | "
      f"rain: {int((df.loc[~snow,'temp_share']>df.loc[~snow,'precip_share']).sum())}/{int((~snow).sum())} basins")

df[["basin", "frac_snow", "nse_clean", "D_nse", "temp_share", "precip_share"]].to_csv(
    RES / "l1_attribution_summary.csv", index=False)
print(f"\nsaved -> {RES / 'l1_attribution_summary.csv'}")
