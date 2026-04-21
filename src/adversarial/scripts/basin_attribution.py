"""Basin attribution analysis: CAMELS attributes vs adversarial vulnerability.

Produces:
  - fig7_attribution_rf.pdf/png: Random Forest feature importance (top 15)
  - fig8_attribution_scatter.pdf/png: Scatter plots of top 4 attributes vs ΔNSE
  - Console: Spearman correlation table

Usage:
    python src/adversarial/scripts/basin_attribution.py \
        --results results/adversarial_eval/final_with_static/merged_all.json \
        --camels-dir data/camels_us/camels_attributes_v2.0 \
        --output-dir draft/papers/05_adversarial_latex/figures
"""
import argparse
import json
import logging
from pathlib import Path

import matplotlib
matplotlib.use("Agg")

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy import stats
from sklearn.ensemble import RandomForestRegressor

logger = logging.getLogger(__name__)

plt.rcParams.update({
    "font.family": "serif",
    "font.serif": ["Times New Roman", "DejaVu Serif"],
    "font.size": 11,
    "axes.labelsize": 13,
    "axes.titlesize": 13,
    "xtick.labelsize": 10,
    "ytick.labelsize": 10,
    "legend.fontsize": 10,
    "figure.dpi": 150,
    "savefig.dpi": 300,
    "axes.spines.top": False,
    "axes.spines.right": False,
})


def load_camels_attributes(camels_dir: Path) -> pd.DataFrame:
    """Load all CAMELS attribute files and merge on gauge_id."""
    dfs = []
    for f in sorted(camels_dir.glob("camels_*.txt")):
        if f.name == "camels_name.txt":
            continue
        df = pd.read_csv(f, sep=";", dtype={"gauge_id": str})
        df["gauge_id"] = df["gauge_id"].str.zfill(8)
        dfs.append(df)
    merged = dfs[0]
    for df in dfs[1:]:
        merged = merged.merge(df, on="gauge_id", how="outer")
    return merged


def load_adversarial_results(path: Path) -> pd.DataFrame:
    """Load merged JSON and compute per-basin mean ΔNSE for APGD ε=0.1."""
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    df = pd.DataFrame(data)
    mask = (
        (df["attack"] == "auto_pgd")
        & (df["epsilon"] == 0.1)
        & (df["constraint"] == "lp")
        & (df["target"] == "untargeted")
    )
    sub = df.loc[mask].dropna(subset=["delta_nse"])
    basin_stats = sub.groupby("basin").agg(
        delta_nse=("delta_nse", "mean"),
        nse_clean=("nse_clean", "mean"),
    ).reset_index()
    basin_stats["basin"] = basin_stats["basin"].str.zfill(8)
    return basin_stats


def main():
    parser = argparse.ArgumentParser(description="Basin attribution analysis.")
    parser.add_argument("--results", required=True, help="Path to merged JSON results.")
    parser.add_argument("--camels-dir", required=True, help="Path to CAMELS attributes directory.")
    parser.add_argument("--output-dir", required=True, help="Output directory for figures.")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)

    # Load data
    attrs = load_camels_attributes(Path(args.camels_dir))
    adv = load_adversarial_results(Path(args.results))

    # Merge
    merged = adv.merge(attrs, left_on="basin", right_on="gauge_id", how="inner")
    logger.info("Merged: %d catchments with both attributes and adversarial results.", len(merged))

    # Select numeric attribute columns (exclude IDs and non-numeric)
    exclude_cols = {"gauge_id", "basin", "delta_nse", "nse_clean", "gauge_lat", "gauge_lon"}
    attr_cols = [c for c in attrs.columns if c not in exclude_cols and pd.api.types.is_numeric_dtype(merged[c])]

    # Drop columns with too many NaNs
    attr_cols = [c for c in attr_cols if merged[c].notna().sum() > 100]
    logger.info("Using %d attribute columns.", len(attr_cols))

    # --- Spearman correlation table ---
    print("=" * 70)
    print("Spearman correlations: CAMELS attributes vs ΔNSE (APGD, ε=0.1)")
    print("=" * 70)
    corr_results = []
    for col in attr_cols:
        valid = merged[[col, "delta_nse"]].dropna()
        if len(valid) < 30:
            continue
        rho, pval = stats.spearmanr(valid[col], valid["delta_nse"])
        corr_results.append({"attribute": col, "rho": rho, "p_value": pval, "n": len(valid)})
    corr_df = pd.DataFrame(corr_results).sort_values("rho", key=abs, ascending=False)

    print(f"{'Attribute':<30} {'rho':>8} {'p-value':>12} {'N':>5}")
    print("-" * 58)
    for _, row in corr_df.head(20).iterrows():
        sig = "***" if row["p_value"] < 0.001 else "**" if row["p_value"] < 0.01 else "*" if row["p_value"] < 0.05 else ""
        print(f"{row['attribute']:<30} {row['rho']:>8.3f} {row['p_value']:>12.2e} {int(row['n']):>5} {sig}")

    # --- Random Forest feature importance ---
    X = merged[attr_cols].copy()
    y = merged["delta_nse"].values

    # Impute NaN with column median
    for col in attr_cols:
        X[col] = X[col].fillna(X[col].median())

    rf = RandomForestRegressor(n_estimators=500, max_depth=10, min_samples_leaf=5, random_state=42, n_jobs=-1)
    rf.fit(X, y)
    importances = pd.Series(rf.feature_importances_, index=attr_cols).sort_values(ascending=False)
    r2 = rf.score(X, y)
    logger.info("Random Forest R^2 (in-sample): %.3f", r2)
    print(f"\nRandom Forest R^2 = {r2:.3f}")

    # Top 15 features
    top15 = importances.head(15)

    # Pretty names for common CAMELS attributes
    pretty_names = {
        "p_mean": "Mean precip.",
        "pet_mean": "Mean PET",
        "aridity": "Aridity index",
        "frac_snow": "Snow fraction",
        "high_prec_freq": "High precip. freq.",
        "high_prec_dur": "High precip. dur.",
        "low_prec_freq": "Low precip. freq.",
        "low_prec_dur": "Low precip. dur.",
        "elev_mean": "Mean elevation",
        "slope_mean": "Mean slope",
        "area_gages2": "Catchment area",
        "forest_frac": "Forest fraction",
        "lai_max": "Max LAI",
        "lai_diff": "LAI seasonality",
        "gvf_max": "Max green veg. frac.",
        "gvf_diff": "GVF seasonality",
        "soil_depth_pelletier": "Soil depth",
        "soil_depth_statsgo": "Soil depth (STATSGO)",
        "soil_porosity": "Soil porosity",
        "soil_conductivity": "Soil conductivity",
        "max_water_content": "Max water content",
        "sand_frac": "Sand fraction",
        "silt_frac": "Silt fraction",
        "clay_frac": "Clay fraction",
        "carbonate_rocks_frac": "Carbonate rock frac.",
        "geol_permeability": "Geol. permeability",
        "q_mean": "Mean streamflow",
        "runoff_ratio": "Runoff ratio",
        "stream_elas": "Streamflow elasticity",
        "slope_fdc": "FDC slope",
        "baseflow_index": "Baseflow index",
        "hfd_mean": "Half-flow date",
        "q5": "Q5 (low flow)",
        "q95": "Q95 (high flow)",
        "high_q_freq": "High flow freq.",
        "high_q_dur": "High flow dur.",
        "low_q_freq": "Low flow freq.",
        "low_q_dur": "Low flow dur.",
        "zero_q_freq": "Zero flow freq.",
    }

    # --- Figure 7: RF importance bar chart ---
    fig, ax = plt.subplots(figsize=(7, 6))
    labels = [pretty_names.get(name, name) for name in top15.index]
    colors = ["#d62728" if importances[name] == top15.iloc[0] else "#4878CF" for name in top15.index]
    ax.barh(range(len(top15)), top15.values[::-1], color=colors[::-1], edgecolor="white")
    ax.set_yticks(range(len(top15)))
    ax.set_yticklabels(labels[::-1])
    ax.set_xlabel("Feature Importance (MDI)")
    ax.set_title(f"Random Forest: Catchment Attributes Predicting $\\Delta$NSE\n(R$^2$ = {r2:.2f}, $N$ = {len(merged)})")
    fig.tight_layout()
    for ext in ("pdf", "png"):
        fig.savefig(out / f"fig7_attribution_rf.{ext}")
        logger.info("Saved fig7_attribution_rf.%s", ext)
    plt.close(fig)

    # --- Figure 8: Top 4 scatter plots ---
    top4 = corr_df.head(4)["attribute"].tolist()
    fig, axes = plt.subplots(2, 2, figsize=(10, 8))
    for ax, attr in zip(axes.flat, top4):
        valid = merged[[attr, "delta_nse"]].dropna()
        rho, pval = stats.spearmanr(valid[attr], valid["delta_nse"])
        ax.scatter(valid[attr], valid["delta_nse"], s=12, alpha=0.4, color="#4878CF", edgecolors="none")
        ax.set_xlabel(pretty_names.get(attr, attr))
        ax.set_ylabel("$\\Delta$NSE")
        ax.axhline(0, color="grey", linewidth=0.5, linestyle="--")
        ax.axhline(-1, color="red", linewidth=0.5, linestyle=":", alpha=0.5)
        ax.set_title(f"$\\rho$ = {rho:.2f}, p = {pval:.1e}", fontsize=11)
    fig.suptitle("Catchment Attributes vs. Adversarial Vulnerability (Auto-PGD, $\\varepsilon$=0.1)", fontsize=13, y=1.01)
    fig.tight_layout()
    for ext in ("pdf", "png"):
        fig.savefig(out / f"fig8_attribution_scatter.{ext}", bbox_inches="tight")
        logger.info("Saved fig8_attribution_scatter.%s", ext)
    plt.close(fig)

    print(f"\nDone. Figures saved to {out.resolve()}")


if __name__ == "__main__":
    main()
