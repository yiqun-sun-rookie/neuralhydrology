"""Test A (anti-tautology / confound): is snow-basin adversarial fragility a REAL finding,
or just a restatement of "snow output depends more on inputs -> more attack surface"?

The cleanest control for a basin's intrinsic input-sensitivity that is NOT derived from the
adversarial optimizer is the best-of-100 RANDOM-sign damage D_rs100 (isotropic input
sensitivity); secondarily the single-step FGSM damage D_FGSM (gradient-aligned local
sensitivity), and flow scale q_mean / flashiness slope_fdc.

Logic: "more input-dependence -> more attackable" predicts random damage rises with snow too,
so it would show up in D_rs100. If that is ALL that is going on, then (i) D_APGD~snow collapses
once we control D_rs100, and (ii) amp = D_APGD/D_rs100 (the coordination premium) is flat across
regimes. If snow SURVIVES controlling D_rs100 (and amp is elevated in snow), the coordinated
attack exploits something snow-specific beyond raw sensitivity -> NON-tautological.

    python src/adversarial/scripts/analyze_tautology_confound.py
"""
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import spearmanr, pearsonr, rankdata

REPO = Path(__file__).resolve().parents[3]
CSV = REPO / "results/05_adversarial_robustness/id18_s100/hydro_vulnerability_summary.csv"


def partial(x, y, Z):
    x, y = np.asarray(x, float), np.asarray(y, float)
    Z = np.asarray(Z, float)
    rx, ry = rankdata(x), rankdata(y)
    if Z.size:
        B = np.column_stack([np.column_stack([rankdata(z) for z in Z.T]), np.ones(len(rx))])
    else:
        B = np.ones((len(rx), 1))
    res = lambda a: a - B @ np.linalg.lstsq(B, a, rcond=None)[0]
    return pearsonr(res(rx), res(ry))


df = pd.read_csv(CSV, dtype={"basin": str})
df["basin"] = df["basin"].str.zfill(8)
df["amp"] = df["D_APGD"] / df["D_rs100"].clip(lower=1e-3)


def rep(y, ctrl, label):
    d = df[[y, "frac_snow"] + ctrl].dropna()
    if ctrl:
        r, p = partial(d["frac_snow"], d[y], d[ctrl].values)
    else:
        r, p = spearmanr(d["frac_snow"], d[y])
    print(f"{label:56s}: rho = {r:+.3f} (p={p:.1e}, n={len(d)})")


print("=== D_APGD ~ snow_frac, progressive controls (n=531) ===")
rep("D_APGD", [], "raw (no control)")
rep("D_APGD", ["nse_clean"], "| clean NSE   [established baseline]")
rep("D_APGD", ["nse_clean", "D_rs100"], "| clean NSE + D_rs100 (raw sensitivity)  *** KEY TEST")
rep("D_APGD", ["nse_clean", "D_FGSM"], "| clean NSE + D_FGSM (gradient sensitivity)")
rep("D_APGD", ["nse_clean", "q_mean"], "| clean NSE + q_mean (flow scale)")
rep("D_APGD", ["nse_clean", "slope_fdc"], "| clean NSE + slope_fdc (flashiness)")
rep("D_APGD", ["nse_clean", "D_rs100", "q_mean"], "| clean NSE + D_rs100 + q_mean")

print("\n=== is the snow signal already in the RAW random sensitivity? ===")
rep("D_rs100", ["nse_clean"], "D_rs100 ~ snow | clean NSE")
rep("D_FGSM", ["nse_clean"], "D_FGSM ~ snow | clean NSE")
rep("amp", ["nse_clean"], "amp (=D_APGD/D_rs100) ~ snow | clean NSE  *** coordination premium")
rep("amp", ["nse_clean", "q_mean"], "amp ~ snow | clean NSE + q_mean")

g = pd.Series("humid", index=df.index)
g[df["aridity"] > 1.5] = "dry"
g[df["frac_snow"] > 0.2] = "snow"
print("\n=== group medians by regime ===")
for c in ["D_APGD", "D_rs100", "D_FGSM", "amp", "nse_clean"]:
    cells = " | ".join(f"{r} {df.loc[g == r, c].median():.3f}" for r in ["dry", "humid", "snow"])
    print(f"  {c:9s}: {cells}")

# how much of snow's D_APGD is 'predicted' by its D_rs100 (raw sensitivity)?
sn = df["frac_snow"] > 0.2
print(f"\nsnow (n={int(sn.sum())}): median D_APGD {df.loc[sn,'D_APGD'].median():.3f}, "
      f"median D_rs100 {df.loc[sn,'D_rs100'].median():.3f}, ratio(amp med) {df.loc[sn,'amp'].median():.1f}")
print(f"non-snow (n={int((~sn).sum())}): median D_APGD {df.loc[~sn,'D_APGD'].median():.3f}, "
      f"median D_rs100 {df.loc[~sn,'D_rs100'].median():.4f}, ratio(amp med) {df.loc[~sn,'amp'].median():.1f}")
