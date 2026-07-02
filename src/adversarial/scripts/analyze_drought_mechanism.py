"""Drought-axis mechanism check (offline go/no-go for the 'runoff extractability' two-axis framing).

The snow axis is nailed: delayed signal -> attack switches to the temperature channel -> peaks
suppressed harder. This script asks whether the DRY end (arid / low runoff-ratio basins, where
runoff is a small residual of P minus ET) has a comparably nailable mechanism, using ONLY
already-recorded artifacts (no GPU, no new attacks):

  (A) 531 basins (hydro_vulnerability_summary.csv): where does dry-basin vulnerability live?
      - D_APGD vs aridity / p_mean / runoff_ratio, partial Spearman controlling BOTH
        frac_snow and clean NSE (so it is not a snow story or a skill story in disguise).
      - Is the paper's headline 'lowflow-targeted attacks are much weaker' an exception in dry
        basins? Test D_lowflow / D_APGD vs aridity.
  (B) 107 basins (exp_l1l2_summary_eps0.1.json): does the attack change CHANNEL in dry basins
      (like it does in snow), or stay on precipitation?
  (C) 107 basins (l1l2_records/*.npz): what does the attack DO to dry-basin hydrographs?
      - net flow bias (fabricating water vs shaving it),
      - phantom flow added on low-flow days (normalized by mean flow),
      - fraction of low-flow days where predicted flow at least doubles,
      - peak magnitude change (from l2_signatures_summary.csv) by aridity group.

Groups: snow = frac_snow > 0.2; among non-snow, dry = aridity > 1.5, humid = the rest.
Honest caveat printed alongside: the 107 subset holds only a handful of dry non-snow basins,
so (B)/(C) are direction checks, not publishable estimates.

    python src/adversarial/scripts/analyze_drought_mechanism.py
"""
import json
from pathlib import Path

import numpy as np
import pandas as pd
from scipy.stats import spearmanr, pearsonr, rankdata

REPO = Path(__file__).resolve().parents[3]
RES = REPO / "results" / "05_adversarial_robustness" / "id18_s100"
REC = RES / "l1l2_records"

SNOW_THR = 0.2
ARID_THR = 1.5
LOWQ_QUANTILE = 0.3     # 'low-flow days' = clean prediction below its own 30th percentile
MIN_Q_EPS = 1e-3        # mm/d floor for flow denominators


def partial_spearman(x, y, Z):
    """Spearman(x, y) after regressing the (rank-transformed) covariate matrix Z out of both."""
    x, y, Z = np.asarray(x, float), np.asarray(y, float), np.asarray(Z, float)
    rx, ry = rankdata(x), rankdata(y)
    B = np.column_stack([np.column_stack([rankdata(z) for z in Z.T]), np.ones(len(rx))])

    def resid(a):
        c, *_ = np.linalg.lstsq(B, a, rcond=None)
        return a - B @ c

    return pearsonr(resid(rx), resid(ry))


def report(df, ycol, xcol, zcols, label=None):
    d = df[[ycol, xcol] + zcols].dropna()
    r_raw, p_raw = spearmanr(d[xcol], d[ycol])
    r_par, p_par = partial_spearman(d[xcol].values, d[ycol].values, d[zcols].values)
    print(f"{label or ycol + ' vs ' + xcol:44s}: Spearman {r_raw:+.3f} (p={p_raw:.1e}) | "
          f"partial|{'+'.join(zcols)} {r_par:+.3f} (p={p_par:.1e})  [n={len(d)}]")


def med3(df, col, grp):
    return " | ".join(f"{g} {df.loc[grp == g, col].median():+.3f} (n={int(df.loc[grp == g, col].notna().sum())})"
                      for g in ["dry", "humid", "snow"])


def regime(df):
    g = pd.Series("humid", index=df.index)
    g[df["aridity"] > ARID_THR] = "dry"
    g[df["frac_snow"] > SNOW_THR] = "snow"    # snow wins ties so 'dry' is dry AND non-snow
    return g


CTRL = ["frac_snow", "nse_clean"]

# ---------------- (A) 531: where dry-basin vulnerability lives ----------------
df = pd.read_csv(RES / "hydro_vulnerability_summary.csv", dtype={"basin": str})
df["basin"] = df["basin"].str.zfill(8)
grp = regime(df)
print(f"=== (A) 531 basins | dry(n={int((grp=='dry').sum())}) humid(n={int((grp=='humid').sum())}) "
      f"snow(n={int((grp=='snow').sum())}) ===")
for x in ["aridity", "p_mean", "runoff_ratio", "q_mean", "baseflow_index"]:
    report(df, "D_APGD", x, CTRL)
print(f"D_APGD    medians: {med3(df, 'D_APGD', grp)}")
print(f"nse_clean medians: {med3(df, 'nse_clean', grp)}")

df["lowflow_share"] = df["D_lowflow"] / df["D_APGD"].clip(lower=1e-3)
print("\n-- is 'lowflow-targeted attacks are weak' an exception in dry basins? --")
report(df, "lowflow_share", "aridity", CTRL, "D_lowflow/D_APGD vs aridity")
report(df, "D_lowflow", "aridity", CTRL)
print(f"lowflow_share medians: {med3(df, 'lowflow_share', grp)}")
report(df, "amp", "aridity", CTRL, "amp (=D_APGD/D_rs100) vs aridity")

# ---------------- (B) 107: channel attribution in dry basins ----------------
s = json.load(open(RES / "exp_l1l2_summary_eps0.1.json"))
l1 = pd.DataFrame(s).T.rename_axis("basin").reset_index()
l1["basin"] = l1["basin"].astype(str).str.zfill(8)
for c in ["D_nse", "nse_clean", "precip_att", "temp_att", "srad_att", "vp_att"]:
    l1[c] = l1[c].astype(float)
tot = l1[["precip_att", "temp_att", "srad_att", "vp_att"]].sum(axis=1).clip(lower=1e-9)
l1["precip_share"], l1["temp_share"] = l1["precip_att"] / tot, l1["temp_att"] / tot
l1 = l1.drop(columns=["nse_clean"]).merge(
    df[["basin", "nse_clean", "frac_snow", "aridity", "p_mean", "runoff_ratio", "q_mean"]], on="basin")
g1 = regime(l1)
print(f"\n=== (B) {len(l1)} basins, leave-one-out channel attribution | dry(n={int((g1=='dry').sum())}) "
      f"humid(n={int((g1=='humid').sum())}) snow(n={int((g1=='snow').sum())}) ===")
for y in ["precip_share", "temp_share"]:
    report(l1, y, "aridity", CTRL)
    print(f"  {y} medians: {med3(l1, y, g1)}")
for y in ["precip_att", "temp_att"]:
    print(f"  {y} (absolute) medians: {med3(l1, y, g1)}")

# ---------------- (C) 107: hydrograph consequences in dry basins ----------------
rows = []
for f in sorted(REC.glob("*.npz")):
    z = np.load(f, allow_pickle=True)
    qc, qa = z["q_clean"].astype(float), z["q_adv"].astype(float)
    mq = max(float(qc.mean()), MIN_Q_EPS)
    low = qc <= np.quantile(qc, LOWQ_QUANTILE)
    rows.append(dict(
        basin=f.stem,
        bias_rel=float((qa.mean() - qc.mean()) / mq),
        phantom_low=float(np.clip(qa - qc, 0, None)[low].mean() / mq),
        double_frac_low=float((qa[low] > 2 * np.clip(qc[low], 0.01, None)).mean()),
        nse_clean_npz=float(z["nse_clean"]),
    ))
c = pd.DataFrame(rows)
c["basin"] = c["basin"].astype(str).str.zfill(8)
l2 = pd.read_csv(RES / "l2_signatures_summary.csv", dtype={"basin": str})
l2["basin"] = l2["basin"].str.zfill(8)
c = (c.merge(l2[["basin", "peak_mag_rel", "peak_timing_abs"]], on="basin")
      .merge(df[["basin", "nse_clean", "frac_snow", "aridity", "p_mean", "runoff_ratio", "q_mean"]], on="basin"))
gc = regime(c)
print(f"\n=== (C) {len(c)} basins, hydrograph consequences | dry(n={int((gc=='dry').sum())}) "
      f"humid(n={int((gc=='humid').sum())}) snow(n={int((gc=='snow').sum())}) ===")
for y, lab in [("bias_rel", "net flow bias (adv-clean)/mean_clean"),
               ("phantom_low", "phantom flow on low-flow days / mean_clean"),
               ("double_frac_low", "frac low-flow days with flow >= doubled"),
               ("peak_mag_rel", "peak magnitude change")]:
    report(c, y, "aridity", CTRL, f"{lab} vs aridity")
    print(f"  medians: {med3(c, y, gc)}")
ampl = c[c.peak_mag_rel > 0]
print(f"peak-AMPLIFIED basins: {len(ampl)}/{len(c)} | their aridity median {ampl.aridity.median():.2f} "
      f"vs suppressed {c.loc[c.peak_mag_rel <= 0, 'aridity'].median():.2f}")

# ---------------- (D) identifiability / robustness checks quoted in the manuscript ----------------
print("\n=== (D) identifiability / robustness ===")
cols = ["aridity", "p_mean", "runoff_ratio", "q_mean"]
print("attribute inter-correlations (Spearman):")
print(df[cols].corr(method="spearman").round(3).to_string())
report(df, "D_APGD", "aridity", CTRL + ["q_mean"], "D_APGD vs aridity (adding q_mean control)")
report(df, "amp", "aridity", CTRL + ["q_mean"], "amp vs aridity (adding q_mean control)")
print(f"amp medians by regime (raw group contrast REVERSES the conditional +0.23): {med3(df, 'amp', grp)}")
ns = l1[g1 != "snow"]
report(ns, "precip_share", "aridity", CTRL, "precip_share vs aridity, NON-SNOW basins only")

# p_mean attenuation from adding the snow control (sources the -0.37 -> -0.26 note in the text)
report(df, "D_APGD", "p_mean", ["nse_clean"], "D_APGD vs p_mean (skill-only control)")
report(df, "D_APGD", "p_mean", CTRL, "D_APGD vs p_mean (skill + snow control)")

# dry-end flood-peak / low-flow signature tests, scoped to the NON-SNOW population (n=71)
print("\n-- dry-end signature nulls, evaluated WITHIN non-snow basins --")
cns = c[gc != "snow"]
report(cns, "peak_mag_rel", "aridity", CTRL, "peak_mag_rel vs aridity, NON-SNOW only (n=71)")
dfns = df[df["basin"].isin(l1["basin"]) & (df["frac_snow"] <= SNOW_THR)].copy()  # non-snow of the 107 subset
report(dfns, "lowflow_share", "aridity", CTRL, "lowflow_share vs aridity, NON-SNOW only (n=71)")
print(f"full-107 (snow-leakage) peak_mag_rel~aridity partial and D_lowflow/D_APGD~aridity partial "
      f"are the SIGNIFICANT ones already printed above; scope the manuscript null to non-snow.")

out = RES / "drought_mechanism_summary.csv"
c["regime"] = gc
c.to_csv(out, index=False)
print(f"\nsaved -> {out}")
print(f"\nCAVEAT: dry non-snow n={int((gc == 'dry').sum())} in the 107 subset -> (B)/(C) are direction "
      f"checks only; a publishable drought-mechanism section needs the ~43 dry non-snow basins of the 531 run.")
