"""Figure fig7: process attribution (L1) + hydrological consequence (L2).
(a) attack's temperature-channel attribution share vs snow fraction (L1).
(b) predicted flood-peak magnitude change, snow vs rain (L2).
"""
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

REPO = Path(__file__).resolve().parents[3]
RES = REPO / "results" / "05_adversarial_robustness" / "id18_s100"
FIGDIR = REPO / "draft" / "papers" / "05_adversarial_latex" / "figures"

l1 = pd.read_csv(RES / "l1_attribution_summary.csv")
l2 = pd.read_csv(RES / "l2_signatures_summary.csv")
for d in (l1, l2):
    d["basin"] = d["basin"].astype(str).str.zfill(8)
df = l1.merge(l2[["basin", "peak_mag_rel"]], on="basin")
snow = df["frac_snow"] > 0.2

fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 4.3))

sc = ax1.scatter(df["frac_snow"], df["temp_share"], c=df["nse_clean"], cmap="viridis",
                 s=26, alpha=0.85, edgecolor="none")
ax1.axhline(0.5, ls=":", c="grey", lw=1)
ax1.set_xlabel("Snow fraction of precipitation")
ax1.set_ylabel("Temperature share of attack damage")
ax1.set_title("(a) attack gains temperature leverage with snow\npartial Spearman = +0.68 (control clean NSE)", fontsize=9.5)
cb = fig.colorbar(sc, ax=ax1); cb.set_label("clean NSE", fontsize=9)

data = [df.loc[~snow, "peak_mag_rel"].dropna() * 100, df.loc[snow, "peak_mag_rel"].dropna() * 100]
ax2.boxplot(data, labels=[f"rain\n(n={int((~snow).sum())})", f"snow\n(n={int(snow.sum())})"], showfliers=False)
ax2.axhline(0, ls="--", c="grey", lw=1)
ax2.set_ylabel("Predicted flood-peak magnitude change (%)")
ax2.set_title("(b) snow flood peaks suppressed more\nmedian -18% (snow) vs -7% (rain)", fontsize=9.5)

fig.tight_layout()
for ext in ("pdf", "png"):
    fig.savefig(FIGDIR / f"fig7_process_attribution.{ext}", dpi=200, bbox_inches="tight")
print("saved ->", FIGDIR / "fig7_process_attribution.pdf")
