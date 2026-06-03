"""Generate 5 paper-grade figures for HBV-lite CAMELS-US 531 results.

Output: figures/hbv_lite_camels531/{fig1..5}.{png,pdf}
"""
from pathlib import Path
import sys

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib as mpl

mpl.rcParams.update({
    "font.size": 11,
    "axes.titlesize": 12,
    "axes.labelsize": 11,
    "legend.fontsize": 10,
    "xtick.labelsize": 10,
    "ytick.labelsize": 10,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "figure.dpi": 120,
    "savefig.dpi": 200,
    "savefig.bbox": "tight",
})

OUT = Path("figures/hbv_lite_camels531")
OUT.mkdir(parents=True, exist_ok=True)


def save(fig, name):
    fig.savefig(OUT / f"{name}.png", dpi=200)
    fig.savefig(OUT / f"{name}.pdf")
    print(f"  saved: {OUT}/{name}.png + .pdf")


def load_run(p):
    df = pd.read_csv(p, dtype={"basin_id": str}, keep_default_na=False)
    df["basin_id"] = df["basin_id"].str.zfill(8)
    df["nse"] = pd.to_numeric(df["nse"], errors="coerce")
    df["_cal_nse"] = pd.to_numeric(df["_cal_nse"], errors="coerce")
    return df[["basin_id", "_cal_nse", "nse"]]


# ============================================================================
# Load all data
# ============================================================================
runs = {
    "v1":  ("Oudin + tight bounds",      "results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/summary/hbv_lite_cma_local_full.csv"),
    "v5":  ("Oudin + wider bounds",      "results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_BEST/summary/hbv_lite_cma_local_full.csv"),
    "v6":  ("PT + wider bounds",         "results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_v6_PT/summary/hbv_lite_cma_local_full.csv"),
    "v7":  ("PT + tight, init=0.5",      "results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_v7_PT_tight/summary/hbv_lite_cma_local_full.csv"),
    "v8":  ("PT + tight, init=0.3",      "results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_v8_PT_tight_init03/summary/hbv_lite_cma_local_full.csv"),
    "v9":  ("PT + tight, init=0.7",      "results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_v9_PT_tight_init07/summary/hbv_lite_cma_local_full.csv"),
    "v10": ("PT + tight, init=0.9",      "results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_v10_PT_tight_init09/summary/hbv_lite_cma_local_full.csv"),
    "v11": ("PT + tight, KGE 0.1",       "results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_v11_PT_KGE01/summary/hbv_lite_cma_local_full.csv"),
    "v12": ("PT + tight, sigma=0.5",     "results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01_v12_PT_sigma05/summary/hbv_lite_cma_local_full.csv"),
}
dfs = [load_run(p).rename(columns={"_cal_nse": f"c_{n}", "nse": f"e_{n}"}) for n, (_, p) in runs.items()]
m = dfs[0]
for d in dfs[1:]:
    m = m.merge(d, on="basin_id")

# Add regime
reg = pd.read_csv("results/10_global_conceptual_model_benchmark/camels_us_531_repro_v01/diagnostic/cross_method_per_basin_nse.csv",
                  dtype={"basin_id": str})
reg["basin_id"] = reg["basin_id"].str.zfill(8)
reg_map = reg.drop_duplicates("basin_id").set_index("basin_id")["regime"]
m["regime"] = m["basin_id"].map(reg_map)

# Add SAC and HBV-upper per basin
sac = reg[reg["model"] == "SAC-SMA + Snow-17"].set_index("basin_id")["nse"]
hbv_up = reg[reg["model"] == "HBV (upper)"].set_index("basin_id")["nse"]
m["sac"] = m["basin_id"].map(sac)
m["hbv_upper"] = m["basin_id"].map(hbv_up)

# Ensemble (6-way = v1+v5+v6+v7+v8+v9)
ens_runs = ["v1", "v5", "v6", "v7", "v8", "v9"]
cal_cols = [f"c_{n}" for n in ens_runs]
m["best"] = m[cal_cols].idxmax(axis=1).str.replace("c_", "")
m["ens"] = m.apply(lambda r: r[f"e_{r['best']}"], axis=1)

print(f"Loaded {len(m)} basins")
print(f"v1 median: {m['e_v1'].median():.4f}")
print(f"ensemble median: {m['ens'].median():.4f}")

# Add basin lat/lon
topo = pd.read_csv("data/camels_us/camels_attributes_v2.0/camels_topo.txt", sep=";")
topo["gauge_id"] = topo["gauge_id"].astype(str).str.zfill(8)
m = m.merge(topo[["gauge_id", "gauge_lat", "gauge_lon"]].rename(columns={"gauge_id": "basin_id"}), on="basin_id", how="left")

# ============================================================================
# Figure 1: Iteration progress
# ============================================================================
print("\n[Fig 1] Iteration progress...")
fig, ax = plt.subplots(figsize=(10, 5.5))

iter_data = [
    ("v1",          0.5564, "single", "Oudin + tight"),
    ("v5",          0.5995, "single", "Oudin + wider"),
    ("v1+v5 ens",   0.6000, "ensemble", "+ ensemble"),
    ("v6",          0.6107, "single", "+ PT PET ⭐"),
    ("3-way ens",   0.6186, "ensemble", "+ 3-way ens"),
    ("v7",          0.6138, "single", "+ tight + PT"),
    ("4-way ens",   0.6201, "ensemble", "+ 4-way ens"),
    ("v8 init=0.3", 0.6159, "single", "+ init=0.3"),
    ("5-way ens",   0.6208, "ensemble", "+ 5-way ens"),
    ("v9 init=0.7", 0.6180, "single", "+ init=0.7 (best single)"),
    ("6-way ens",   0.6227, "ensemble", "+ 6-way ens ⭐"),
    ("v10 init=0.9", 0.6153, "single", "+ init=0.9"),
    ("7-way ens",   0.6222, "ensemble", "saturated"),
    ("v11 KGE0.1",  0.6164, "single", "+ KGE 0.1"),
    ("v12 sigma=0.5", 0.6167, "single", "+ sigma=0.5"),
    ("9-way mega",  0.6227, "ensemble", "final mega"),
]
x = list(range(len(iter_data)))
y = [v[1] for v in iter_data]
labels = [v[0] for v in iter_data]
kinds = [v[2] for v in iter_data]

# Plot two series: single models (open circles) and ensembles (filled squares)
for i, (lab, val, kind, ann) in enumerate(iter_data):
    if kind == "single":
        ax.scatter(i, val, s=60, c="#0066CC", alpha=0.7, marker="o", edgecolors="none", zorder=5)
    else:
        ax.scatter(i, val, s=80, c="#CC6600", alpha=0.9, marker="s", edgecolors="white", linewidth=1.2, zorder=6)

# Connecting line
ax.plot(x, y, color="gray", linewidth=1, alpha=0.4, zorder=1)

# Best line
ax.axhline(0.6227, color="#CC6600", linestyle="--", linewidth=1, alpha=0.6, zorder=2, label="Best ensemble 0.6227")
ax.axhline(0.603, color="black", linestyle=":", linewidth=1.2, alpha=0.7, zorder=2, label="Kratzert SAC-SMA 0.603")
ax.axhline(0.676, color="darkgreen", linestyle=":", linewidth=1.2, alpha=0.6, zorder=2, label="Kratzert HBV-upper 0.676 (best-of-50)")

# Legend
from matplotlib.lines import Line2D
legend_elements = [
    Line2D([0], [0], marker='o', color='w', markerfacecolor='#0066CC', markersize=8, label='Single model'),
    Line2D([0], [0], marker='s', color='w', markerfacecolor='#CC6600', markersize=8, label='Ensemble'),
    Line2D([0], [0], color="#CC6600", linestyle="--", label="Best ensemble 0.6227"),
    Line2D([0], [0], color="black", linestyle=":", label="Kratzert SAC-SMA 0.603"),
    Line2D([0], [0], color="darkgreen", linestyle=":", label="Kratzert HBV-upper 0.676"),
]
ax.legend(handles=legend_elements, loc="lower right", framealpha=0.95)

ax.set_xticks(x)
ax.set_xticklabels(labels, rotation=45, ha="right")
ax.set_ylabel("Median NSE on 531 basins")
ax.set_title("HBV-lite calibration iterations: PT PET fix at iter 1 + ensemble saturate at 0.6227")
ax.set_ylim(0.54, 0.70)
ax.grid(True, axis="y", alpha=0.3)

save(fig, "fig1_iteration_progress")
plt.close()


# ============================================================================
# Figure 2: Regime breakdown grouped bars
# ============================================================================
print("[Fig 2] Regime breakdown...")
fig, ax = plt.subplots(figsize=(10, 5.5))

regimes = ["humid", "snow-dominated", "semi-humid", "semi-arid/arid", "Overall"]
n_by_reg = {"humid": 282, "snow-dominated": 152, "semi-humid": 54, "semi-arid/arid": 43, "Overall": 531}

# Median NSE per regime
our_vals = []
sac_vals = []
hbv_vals = []
for r in regimes[:-1]:
    g = m[m["regime"] == r]
    our_vals.append(g["ens"].median())
    sac_vals.append(g["sac"].median())
    hbv_vals.append(g["hbv_upper"].median())
# Overall (all 531)
our_vals.append(m["ens"].median())
sac_vals.append(m["sac"].median())
hbv_vals.append(m["hbv_upper"].median())

x = np.arange(len(regimes))
width = 0.26

bars1 = ax.bar(x - width, our_vals, width, label="HBV-lite ensemble (ours)", color="#0066CC", alpha=0.85)
bars2 = ax.bar(x,         sac_vals, width, label="SAC-SMA + Snow-17 (Kratzert)", color="#666666", alpha=0.85)
bars3 = ax.bar(x + width, hbv_vals, width, label="HBV-upper best-of-50 (Kratzert)", color="darkgreen", alpha=0.7)

# Annotate values
for bars in [bars1, bars2, bars3]:
    for b in bars:
        h = b.get_height()
        if not np.isnan(h):
            ax.text(b.get_x() + b.get_width() / 2, h + 0.008, f"{h:.3f}",
                    ha="center", va="bottom", fontsize=8.5)

ax.set_xticks(x)
labels_with_n = [f"{r}\n(n={n_by_reg[r]})" for r in regimes]
ax.set_xticklabels(labels_with_n)
ax.set_ylabel("Median NSE on eval period")
ax.set_title("HBV-lite ensemble matches or exceeds SAC-SMA on 3/4 regimes (531 basins)")
ax.legend(loc="upper right", framealpha=0.95)
ax.set_ylim(0, 0.78)
ax.axhline(0.6, color="gray", linestyle=":", alpha=0.5)
ax.grid(True, axis="y", alpha=0.3)

save(fig, "fig2_regime_breakdown")
plt.close()


# ============================================================================
# Figure 3: NSE CDF comparison
# ============================================================================
print("[Fig 3] NSE CDF...")
fig, ax = plt.subplots(figsize=(8, 5.5))

def cdf(series):
    s = np.sort(series.dropna().values)
    f = np.arange(1, len(s) + 1) / len(s)
    return s, f

for series, label, color, lw in [
    (m["e_v1"],      "v1 (Oudin tight) baseline", "#999999", 1.5),
    (m["e_v6"],      "v6 (PT wider)",             "#88CCEE", 1.7),
    (m["e_v7"],      "v7 (PT tight)",             "#117733", 1.7),
    (m["ens"],       "Ensemble (ours)",           "#0066CC", 2.5),
    (m["sac"],       "SAC-SMA + Snow-17",         "#CC3311", 2.0),
    (m["hbv_upper"], "HBV-upper best-of-50",      "darkgreen", 1.7),
]:
    s, f = cdf(series)
    ax.plot(s, f, label=label, color=color, linewidth=lw)

ax.axvline(0.6, color="black", linestyle=":", alpha=0.5)
ax.axvline(0.0, color="black", linestyle=":", alpha=0.3)
ax.set_xlim(-1.5, 1.0)
ax.set_xlabel("NSE on eval period")
ax.set_ylabel("Fraction of basins (CDF)")
ax.set_title("NSE distribution across 531 basins: ensemble shifts left tail right")
ax.legend(loc="lower right", framealpha=0.95)
ax.grid(True, alpha=0.3)

save(fig, "fig3_nse_cdf")
plt.close()


# ============================================================================
# Figure 4: per-basin scatter ours vs SAC-SMA
# ============================================================================
print("[Fig 4] Scatter ours vs SAC-SMA...")
fig, ax = plt.subplots(figsize=(7, 7))

regime_colors = {
    "humid":          "#117733",
    "snow-dominated": "#88CCEE",
    "semi-humid":     "#DDCC77",
    "semi-arid/arid": "#CC6677",
}

scatter_data = m.dropna(subset=["ens", "sac", "regime"])
for r, color in regime_colors.items():
    g = scatter_data[scatter_data["regime"] == r]
    ax.scatter(g["sac"], g["ens"], s=22, c=color, alpha=0.65, edgecolors="none",
               label=f"{r} (n={len(g)})")

ax.plot([-2, 1.5], [-2, 1.5], "k-", linewidth=1, alpha=0.7, label="1:1 (parity)")
ax.set_xlim(-1.5, 1.0)
ax.set_ylim(-1.5, 1.0)
ax.set_aspect("equal")
ax.set_xlabel("SAC-SMA + Snow-17 NSE (Kratzert published)")
ax.set_ylabel("HBV-lite ensemble NSE (ours)")
ax.set_title("Per-basin NSE: above diagonal = we beat SAC-SMA")

# Tally
n_above = (scatter_data["ens"] > scatter_data["sac"]).sum()
n_total = len(scatter_data)
ax.text(0.04, 0.96, f"We win: {n_above}/{n_total} ({100*n_above/n_total:.0f}%)",
        transform=ax.transAxes, fontsize=11, verticalalignment="top",
        bbox=dict(boxstyle="round,pad=0.4", facecolor="white", alpha=0.9, edgecolor="gray"))

ax.legend(loc="lower right", framealpha=0.95)
ax.grid(True, alpha=0.3)
ax.axhline(0, color="gray", linewidth=0.5, alpha=0.4)
ax.axvline(0, color="gray", linewidth=0.5, alpha=0.4)

save(fig, "fig4_scatter_vs_SAC")
plt.close()


# ============================================================================
# Figure 5: CAMELS-US map colored by NSE
# ============================================================================
print("[Fig 5] CAMELS-US geographic map...")
fig, ax = plt.subplots(figsize=(11, 6.5))

# Filter to CONUS bounds
geo = m.dropna(subset=["gauge_lat", "gauge_lon", "ens"]).copy()
geo = geo[(geo["gauge_lat"] > 24) & (geo["gauge_lat"] < 50) &
          (geo["gauge_lon"] > -126) & (geo["gauge_lon"] < -66)]

# Diverging colormap centered at 0.6 (our target)
from matplotlib.colors import TwoSlopeNorm
norm = TwoSlopeNorm(vmin=-0.3, vcenter=0.6, vmax=0.9)

sc = ax.scatter(geo["gauge_lon"], geo["gauge_lat"], c=geo["ens"], cmap="RdYlBu",
                norm=norm, s=42, edgecolors="black", linewidths=0.3, alpha=0.92)

cbar = plt.colorbar(sc, ax=ax, shrink=0.75, pad=0.02)
cbar.set_label("HBV-lite ensemble NSE", fontsize=11)
cbar.ax.axhline(0.6, color="black", linewidth=0.8)

ax.set_xlim(-126, -66)
ax.set_ylim(24, 50)
ax.set_xlabel("Longitude")
ax.set_ylabel("Latitude")
ax.set_title(f"CAMELS-US 531 basins colored by HBV-lite ensemble NSE  (median = {geo['ens'].median():.3f})")
ax.set_aspect(1.2)  # roughly area-correct for CONUS lat band
ax.grid(True, alpha=0.3)

# Summary box
n_high = (geo["ens"] >= 0.6).sum()
n_low = (geo["ens"] < 0).sum()
ax.text(0.02, 0.97, f"n = {len(geo)} basins\n"
                    f"NSE ≥ 0.6: {n_high} ({100*n_high/len(geo):.0f}%)\n"
                    f"NSE < 0:    {n_low} ({100*n_low/len(geo):.0f}%)",
        transform=ax.transAxes, fontsize=10, verticalalignment="top",
        bbox=dict(boxstyle="round,pad=0.4", facecolor="white", alpha=0.92, edgecolor="gray"),
        family="monospace")

save(fig, "fig5_geographic_map")
plt.close()


print(f"\nAll 5 figures saved to {OUT}/")
print("Files:")
for f in sorted(OUT.iterdir()):
    print(f"  {f}")
