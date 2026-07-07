"""Round 2 analysis: does OPTIMIZER-FREE temperature dependence rise with snow, controlling for
total input dependence? (the decisive test for the channel-identity survivor from Round 1)

    python src/adversarial/scripts/analyze_occlusion_channel.py
"""
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import spearmanr, pearsonr, rankdata

REPO = Path(__file__).resolve().parents[3]
RES = REPO / "results/05_adversarial_robustness/id18_s100"


def partial(x, y, Z):
    x, y, Z = np.asarray(x, float), np.asarray(y, float), np.asarray(Z, float)
    rx, ry = rankdata(x), rankdata(y)
    B = np.column_stack([np.column_stack([rankdata(z) for z in Z.T]), np.ones(len(rx))]) if Z.size else np.ones((len(rx), 1))
    res = lambda a: a - B @ np.linalg.lstsq(B, a, rcond=None)[0]
    return pearsonr(res(rx), res(ry))


# shuffle-mode occlusion is the manuscript's method (temporal permutation, in-distribution);
# occlusion_importance.csv is the deprecated set-to-mean variant kept only for comparison.
occ = pd.read_csv(RES / "occlusion_importance_shuffle.csv", dtype={"basin": str})
occ["basin"] = occ["basin"].str.zfill(8)
vul = pd.read_csv(RES / "hydro_vulnerability_summary.csv", dtype={"basin": str})
vul["basin"] = vul["basin"].str.zfill(8)
df = occ.merge(vul[["basin", "frac_snow", "aridity", "nse_clean", "q_mean"]], on="basin", suffixes=("", "_v"))
print(f"n = {len(df)} basins")


def rep(y, ctrl, label):
    d = df[[y, "frac_snow"] + ctrl].dropna()
    if ctrl:
        r, p = partial(d["frac_snow"], d[y], d[ctrl].values)
    else:
        r, p = spearmanr(d["frac_snow"], d[y])
    print(f"{label:54s}: rho = {r:+.3f} (p={p:.1e}, n={len(d)})")


print("\n=== OPTIMIZER-FREE temperature dependence share ~ snow (n=531) ===")
rep("temp_share", [], "temp_share ~ snow (raw)")
rep("temp_share", ["nse_clean"], "| clean NSE")
rep("temp_share", ["nse_clean", "total_dep"], "| clean NSE + total_dep  *** KEY (magnitude-free)")
rep("temp_share", ["nse_clean", "total_dep", "q_mean"], "| clean NSE + total_dep + q_mean")
rep("precip_share", ["nse_clean", "total_dep"], "precip_share ~ snow | clean NSE + total_dep")
print("\n-- is temp_share orthogonal to how attackable the basin is? --")
rep("total_dep", ["nse_clean"], "total_dep ~ snow | clean NSE (does snow just depend more overall?)")
print(f"temp_share vs total_dep Spearman: {spearmanr(df.temp_share, df.total_dep).statistic:+.3f}")

g = pd.Series("humid", index=df.index)
g[df["aridity"] > 1.5] = "dry"
g[df["frac_snow"] > 0.2] = "snow"
print("\n=== group medians (dry/humid/snow) ===")
for c in ["temp_share", "precip_share", "total_dep", "imp_temp", "imp_precip"]:
    print(f"  {c:12s}: " + " | ".join(f"{r} {df.loc[g == r, c].median():+.3f}" for r in ["dry", "humid", "snow"]))
sn = df["frac_snow"] > 0.2
print(f"\ntemp leads precip (imp_temp>imp_precip): snow {int((df.loc[sn,'imp_temp']>df.loc[sn,'imp_precip']).sum())}/{int(sn.sum())}"
      f" | non-snow {int((df.loc[~sn,'imp_temp']>df.loc[~sn,'imp_precip']).sum())}/{int((~sn).sum())}")

# cross-check vs the attack-derived attribution (107 subset): do they agree in direction?
l1 = RES / "l1_attribution_summary.csv"
if l1.exists():
    a = pd.read_csv(l1, dtype={"basin": str})
    a["basin"] = a["basin"].str.zfill(8)
    m = df.merge(a[["basin", "temp_share"]].rename(columns={"temp_share": "temp_share_attack"}), on="basin")
    r = spearmanr(m.temp_share, m.temp_share_attack)
    print(f"\nocclusion temp_share vs ATTACK-derived temp_share (n={len(m)}): Spearman {r.statistic:+.3f} (p={r.pvalue:.1e})")
