"""Adversarial robustness analysis: tables (markdown) and figures (PDF+PNG).

Usage:
    python src/adversarial/scripts/analyze_results.py \
        --input results/adversarial_eval/full/merged_all.json \
        --output-dir results/adversarial_eval/full/figures
"""
import argparse
import json
import logging
import warnings
from pathlib import Path

import matplotlib
matplotlib.use("Agg")  # non-interactive backend — must precede pyplot import

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Publication-quality defaults
# ---------------------------------------------------------------------------
plt.rcParams.update({
    "font.size": 11,
    "axes.labelsize": 12,
    "figure.figsize": (7, 5),
    "figure.dpi": 150,
    "savefig.dpi": 300,
    "savefig.bbox_inches": "tight",
    "axes.spines.top": False,
    "axes.spines.right": False,
})

# Display names for attack methods
ATTACK_DISPLAY = {
    "auto_pgd": "Auto-PGD",
    "fgsm": "FGSM",
    "gaussian_noise": "Gaussian",
    "multiplicative_bias": "Mult. Bias",
    "temporal_correlated_noise": "Temp. Corr.",
    "causal_trigger": "Causal Trigger",
    "cw_regression": "C&W",
}

# Ordered list of attack methods for Table 1 / fig1
TABLE1_ATTACKS = [
    "auto_pgd",
    "fgsm",
    "gaussian_noise",
    "multiplicative_bias",
    "temporal_correlated_noise",
]

# Colour palette keyed by internal attack name
ATTACK_COLORS = {
    "auto_pgd": "#d62728",
    "fgsm": "#ff7f0e",
    "gaussian_noise": "#2ca02c",
    "multiplicative_bias": "#1f77b4",
    "temporal_correlated_noise": "#9467bd",
    "causal_trigger": "#8c564b",
    "cw_regression": "#e377c2",
}


# ===================================================================
# I/O
# ===================================================================

def load_results(path: str) -> pd.DataFrame:
    """Load a JSON file (list of records) into a DataFrame."""
    p = Path(path)
    if not p.exists():
        raise FileNotFoundError(f"Input file not found: {p}")
    with open(p, "r", encoding="utf-8") as f:
        data = json.load(f)
    if not isinstance(data, list) or len(data) == 0:
        raise ValueError("Expected a non-empty JSON array of records.")
    df = pd.DataFrame(data)
    logger.info("Loaded %d records from %s", len(df), p)
    return df


def _save_fig(fig: plt.Figure, out_dir: Path, stem: str) -> None:
    """Save a figure as both PDF and PNG."""
    for ext in ("pdf", "png"):
        dest = out_dir / f"{stem}.{ext}"
        fig.savefig(dest)
        logger.info("Saved %s", dest)
    plt.close(fig)


# ===================================================================
# Helper: Markdown table printer
# ===================================================================

def _print_md_table(headers: list[str], rows: list[list[str]]) -> None:
    """Pretty-print a markdown table to stdout."""
    widths = [len(h) for h in headers]
    for row in rows:
        for i, cell in enumerate(row):
            widths[i] = max(widths[i], len(cell))
    fmt = "| " + " | ".join(f"{{:<{w}}}" for w in widths) + " |"
    sep = "|" + "|".join("-" * (w + 2) for w in widths) + "|"
    print(fmt.format(*headers))
    print(sep)
    for row in rows:
        print(fmt.format(*row))
    print()


# ===================================================================
# TABLE 1 — Attack Comparison
# ===================================================================

def table_attack_comparison(df: pd.DataFrame) -> None:
    """Print Table 1: attack methods x epsilon values, mean DELTA-NSE +/- std."""
    mask = (df["constraint"] == "lp") & (df["target"] == "untargeted")
    sub = df.loc[mask & df["attack"].isin(TABLE1_ATTACKS)]
    if sub.empty:
        warnings.warn("Table 1: no data after filtering (constraint=lp, target=untargeted).")
        return

    epsilons = sorted(sub["epsilon"].unique())
    eps_strs = [str(e) for e in epsilons]
    headers = ["Attack"] + [f"eps={e}" for e in eps_strs]

    # Pre-compute Gaussian mean per epsilon for amplification ratio
    gauss = sub[sub["attack"] == "gaussian_noise"]
    gauss_mean = gauss.groupby("epsilon")["delta_nse"].mean().to_dict()

    rows: list[list[str]] = []
    for atk in TABLE1_ATTACKS:
        atk_df = sub[sub["attack"] == atk]
        row = [ATTACK_DISPLAY.get(atk, atk)]
        for eps in epsilons:
            cell = atk_df[atk_df["epsilon"] == eps]["delta_nse"]
            if cell.empty:
                row.append("--")
            else:
                row.append(f"{cell.mean():.3f} +/- {cell.std():.3f}")
        rows.append(row)

    # Amplification ratio row
    ratio_row = ["Ampl. ratio (APGD/Gauss)"]
    apgd = sub[sub["attack"] == "auto_pgd"]
    for eps in epsilons:
        apgd_mean = apgd[apgd["epsilon"] == eps]["delta_nse"].mean()
        g_mean = gauss_mean.get(eps, None)
        if g_mean is not None and g_mean != 0 and not np.isnan(apgd_mean):
            ratio_row.append(f"{apgd_mean / g_mean:.2f}x")
        else:
            ratio_row.append("--")
    rows.append(ratio_row)

    _print_md_table(headers, rows)


# ===================================================================
# TABLE 2 — Constraint Ablation
# ===================================================================

def table_constraint_ablation(df: pd.DataFrame) -> None:
    """Print Table 2: constraint levels x epsilon values, mean DELTA-NSE."""
    mask = (df["attack"] == "auto_pgd") & (df["target"] == "untargeted")
    sub = df.loc[mask]
    if sub.empty:
        warnings.warn("Table 2: no data after filtering (attack=auto_pgd, target=untargeted).")
        return

    constraints = sorted(sub["constraint"].unique())
    epsilons = sorted(sub["epsilon"].unique())
    headers = ["Constraint"] + [f"eps={e}" for e in epsilons]

    rows: list[list[str]] = []
    for con in constraints:
        row = [str(con)]
        for eps in epsilons:
            cell = sub[(sub["constraint"] == con) & (sub["epsilon"] == eps)]["delta_nse"]
            if cell.empty:
                row.append("--")
            else:
                row.append(f"{cell.mean():.3f}")
        rows.append(row)

    _print_md_table(headers, rows)


# ===================================================================
# TABLE 3 — Targeted Attacks
# ===================================================================

def table_targeted_attacks(df: pd.DataFrame) -> None:
    """Print Table 3: target types x metrics for APGD eps=0.1, constraint=lp."""
    mask = (
        (df["attack"] == "auto_pgd")
        & (df["epsilon"] == 0.1)
        & (df["constraint"] == "lp")
    )
    sub = df.loc[mask]
    if sub.empty:
        warnings.warn("Table 3: no data after filtering (APGD, eps=0.1, lp).")
        return

    targets = sorted(sub["target"].unique())
    metrics = ["delta_nse", "delta_kge", "peak_error"]
    metric_labels = ["delta-NSE", "delta-KGE", "peak_error"]

    # Compute delta_kge if not present
    if "delta_kge" not in sub.columns:
        if "kge_clean" in sub.columns and "kge_adv" in sub.columns:
            sub = sub.copy()
            sub["delta_kge"] = sub["kge_adv"] - sub["kge_clean"]
        else:
            warnings.warn("Table 3: cannot compute delta_kge — missing columns.")
            metrics = ["delta_nse", "peak_error"]
            metric_labels = ["delta-NSE", "peak_error"]

    headers = ["Target"] + metric_labels

    rows: list[list[str]] = []
    for tgt in targets:
        tgt_df = sub[sub["target"] == tgt]
        row = [str(tgt)]
        for m in metrics:
            if m in tgt_df.columns:
                vals = tgt_df[m].dropna()
                if vals.empty:
                    row.append("--")
                else:
                    row.append(f"{vals.mean():.3f} +/- {vals.std():.3f}")
            else:
                row.append("--")
        rows.append(row)

    _print_md_table(headers, rows)


# ===================================================================
# FIG 1 — Epsilon Curve
# ===================================================================

def fig_epsilon_curve(df: pd.DataFrame, out: Path) -> None:
    """Line plot: epsilon (log) vs mean DELTA-NSE, one line per attack."""
    mask = (df["constraint"] == "lp") & (df["target"] == "untargeted")
    sub = df.loc[mask & df["attack"].isin(TABLE1_ATTACKS)]
    if sub.empty:
        warnings.warn("fig1: no data — skipping epsilon curve.")
        return

    fig, ax = plt.subplots()
    for atk in TABLE1_ATTACKS:
        atk_df = sub[sub["attack"] == atk]
        if atk_df.empty:
            continue
        grp = atk_df.groupby("epsilon")["delta_nse"]
        means = grp.mean().sort_index()
        stds = grp.std().sort_index().fillna(0)
        eps_vals = means.index.values
        color = ATTACK_COLORS.get(atk, None)
        ax.plot(eps_vals, means.values, marker="o", label=ATTACK_DISPLAY.get(atk, atk), color=color)
        ax.fill_between(eps_vals, (means - stds).values, (means + stds).values, alpha=0.15, color=color)

    ax.set_xscale("log")
    ax.set_xlabel("Perturbation budget (epsilon)")
    ax.set_ylabel("Mean delta-NSE")
    ax.set_title("Attack Strength vs. NSE Degradation")
    ax.legend(frameon=False)
    ax.axhline(0, color="grey", linewidth=0.5, linestyle="--")
    fig.tight_layout()
    _save_fig(fig, out, "fig1_epsilon_curve")


# ===================================================================
# FIG 2 — Basin Vulnerability
# ===================================================================

def fig_basin_vulnerability(df: pd.DataFrame, out: Path) -> None:
    """Histogram + CDF of per-basin DELTA-NSE for APGD, eps=0.1."""
    mask = (
        (df["attack"] == "auto_pgd")
        & (df["epsilon"] == 0.1)
        & (df["constraint"] == "lp")
        & (df["target"] == "untargeted")
    )
    sub = df.loc[mask]
    if sub.empty:
        warnings.warn("fig2: no APGD eps=0.1 data — skipping basin vulnerability.")
        return

    basin_dnse = sub.groupby("basin")["delta_nse"].mean()

    fig, ax1 = plt.subplots()
    # Histogram
    n_bins = min(30, max(10, len(basin_dnse) // 3))
    ax1.hist(basin_dnse.values, bins=n_bins, color="#1f77b4", alpha=0.7, edgecolor="white", label="Histogram")
    ax1.set_xlabel("Mean delta-NSE per basin")
    ax1.set_ylabel("Count")
    ax1.set_title("Basin Vulnerability Distribution (Auto-PGD, eps=0.1)")

    # CDF on twin axis
    ax2 = ax1.twinx()
    sorted_vals = np.sort(basin_dnse.values)
    cdf = np.arange(1, len(sorted_vals) + 1) / len(sorted_vals)
    ax2.plot(sorted_vals, cdf, color="#d62728", linewidth=2, label="CDF")
    ax2.set_ylabel("CDF")

    # Percentile markers
    med = np.median(basin_dnse.values)
    p10 = np.percentile(basin_dnse.values, 10)
    p90 = np.percentile(basin_dnse.values, 90)
    for val, lbl, ls in [(med, "Median", "--"), (p10, "10th pctl", ":"), (p90, "90th pctl", ":")]:
        ax1.axvline(val, color="black", linestyle=ls, linewidth=1)
        ax1.annotate(f"{lbl}: {val:.2f}", xy=(val, ax1.get_ylim()[1] * 0.9),
                     fontsize=8, ha="center", backgroundcolor="white")

    # Combined legend
    lines1, labels1 = ax1.get_legend_handles_labels()
    lines2, labels2 = ax2.get_legend_handles_labels()
    ax1.legend(lines1 + lines2, labels1 + labels2, frameon=False, loc="upper left")

    fig.tight_layout()
    _save_fig(fig, out, "fig2_basin_vulnerability")


# ===================================================================
# FIG 3 — Causal Window
# ===================================================================

def fig_causal_window(df: pd.DataFrame, out: Path) -> None:
    """Bar chart: pre_window vs mean DELTA-NSE for causal_trigger, eps=0.1."""
    mask = (df["attack"] == "causal_trigger") & (df["epsilon"] == 0.1)
    sub = df.loc[mask]
    if sub.empty:
        warnings.warn("fig3: no causal_trigger data — skipping causal window figure.")
        return
    if "pre_window" not in sub.columns:
        warnings.warn("fig3: 'pre_window' column missing — skipping.")
        return

    grp = sub.groupby("pre_window")["delta_nse"]
    means = grp.mean().sort_index()
    stds = grp.std().sort_index().fillna(0)

    fig, ax = plt.subplots()
    windows = means.index.values
    x_pos = np.arange(len(windows))
    ax.bar(x_pos, means.values, yerr=stds.values, capsize=5,
           color="#8c564b", alpha=0.8, edgecolor="white")
    ax.set_xticks(x_pos)
    ax.set_xticklabels([f"{int(w)}d" for w in windows])
    ax.set_xlabel("Pre-event window (days)")
    ax.set_ylabel("Mean delta-NSE")
    ax.set_title("Causal Trigger: Effect of Perturbation Window")
    ax.axhline(0, color="grey", linewidth=0.5, linestyle="--")
    fig.tight_layout()
    _save_fig(fig, out, "fig3_causal_window")


# ===================================================================
# FIG 4 — C&W Perturbation Distribution
# ===================================================================

def fig_cw_perturbation(df: pd.DataFrame, out: Path) -> None:
    """Histogram of L2 norms from C&W results."""
    mask = df["attack"] == "cw_regression"
    sub = df.loc[mask]
    if sub.empty:
        warnings.warn("fig4: no C&W results — skipping perturbation distribution.")
        return
    if "l2" not in sub.columns:
        warnings.warn("fig4: 'l2' column missing — skipping.")
        return

    l2_vals = sub["l2"].dropna()
    if l2_vals.empty:
        warnings.warn("fig4: all L2 values are NaN — skipping.")
        return

    fig, ax = plt.subplots()
    n_bins = min(30, max(10, len(l2_vals) // 3))
    ax.hist(l2_vals.values, bins=n_bins, color="#e377c2", alpha=0.8, edgecolor="white")
    ax.set_xlabel("L2 perturbation norm")
    ax.set_ylabel("Count")
    ax.set_title("C&W Attack: Perturbation Magnitude Distribution")
    ax.axvline(l2_vals.median(), color="black", linestyle="--", linewidth=1,
               label=f"Median: {l2_vals.median():.4f}")
    ax.legend(frameon=False)
    fig.tight_layout()
    _save_fig(fig, out, "fig4_cw_perturbation")


# ===================================================================
# FIG 5 — Detectability
# ===================================================================

def fig_detectability(df: pd.DataFrame, out: Path) -> None:
    """Scatter: |DELTA-NSE| vs KS statistic, colored by attack method."""
    if "detectability_ks" not in df.columns:
        warnings.warn("fig5: 'detectability_ks' column missing — skipping.")
        return

    sub = df.dropna(subset=["delta_nse", "detectability_ks"])
    if sub.empty:
        warnings.warn("fig5: no data with both delta_nse and detectability_ks — skipping.")
        return

    fig, ax = plt.subplots()
    for atk in sub["attack"].unique():
        atk_df = sub[sub["attack"] == atk]
        color = ATTACK_COLORS.get(atk, None)
        ax.scatter(
            atk_df["delta_nse"].abs(),
            atk_df["detectability_ks"],
            label=ATTACK_DISPLAY.get(atk, atk),
            color=color,
            alpha=0.6,
            s=20,
            edgecolors="none",
        )

    ax.axhline(0.05, color="red", linestyle="--", linewidth=1, label="p = 0.05")
    ax.set_xlabel("|delta-NSE|")
    ax.set_ylabel("KS test p-value")
    ax.set_title("Attack Effectiveness vs. Detectability")
    ax.legend(frameon=False, fontsize=8, ncol=2, loc="upper right")
    fig.tight_layout()
    _save_fig(fig, out, "fig5_detectability")


# ===================================================================
# Main
# ===================================================================

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Analyze adversarial robustness results: generate tables and figures."
    )
    parser.add_argument("--input", required=True, help="Path to merged JSON results file.")
    parser.add_argument("--output-dir", required=True, help="Directory for output figures.")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")

    df = load_results(args.input)
    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)

    # Compute delta_kge if missing
    if "delta_kge" not in df.columns and "kge_clean" in df.columns and "kge_adv" in df.columns:
        df["delta_kge"] = df["kge_adv"] - df["kge_clean"]

    # --- Tables ---
    print("=" * 60)
    print("TABLE 1: Attack Comparison (constraint=lp, target=untargeted)")
    print("=" * 60)
    table_attack_comparison(df)

    print("=" * 60)
    print("TABLE 2: Constraint Ablation (attack=auto_pgd, target=untargeted)")
    print("=" * 60)
    table_constraint_ablation(df)

    print("=" * 60)
    print("TABLE 3: Targeted Attacks (APGD, eps=0.1, constraint=lp)")
    print("=" * 60)
    table_targeted_attacks(df)

    # --- Figures ---
    print("=" * 60)
    print("Generating figures ...")
    print("=" * 60)

    fig_epsilon_curve(df, out)
    fig_basin_vulnerability(df, out)
    fig_causal_window(df, out)
    fig_cw_perturbation(df, out)
    fig_detectability(df, out)

    print(f"Done. Figures saved to: {out.resolve()}")


if __name__ == "__main__":
    main()
