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
    "font.family": "serif",
    "font.serif": ["Times New Roman", "DejaVu Serif"],
    "font.size": 11,
    "axes.labelsize": 13,
    "axes.titlesize": 13,
    "xtick.labelsize": 11,
    "ytick.labelsize": 11,
    "legend.fontsize": 10,
    "figure.figsize": (7, 5),
    "figure.dpi": 150,
    "savefig.dpi": 300,
    "axes.spines.top": False,
    "axes.spines.right": False,
    "axes.linewidth": 0.8,
    "xtick.major.width": 0.8,
    "ytick.major.width": 0.8,
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
    """Print Table 1: attack methods x epsilon values, median (IQR) DELTA-NSE."""
    mask = (df["constraint"] == "lp") & (df["target"] == "untargeted")
    sub = df.loc[mask & df["attack"].isin(TABLE1_ATTACKS)]
    if sub.empty:
        warnings.warn("Table 1: no data after filtering (constraint=lp, target=untargeted).")
        return

    epsilons = sorted(sub["epsilon"].unique())
    headers = ["Attack", "N"] + [f"eps={e}" for e in epsilons]

    # Pre-compute Gaussian median per epsilon for amplification ratio
    gauss = sub[sub["attack"] == "gaussian_noise"]
    gauss_med = gauss.groupby("epsilon")["delta_nse"].median().to_dict()

    rows: list[list[str]] = []
    for atk in TABLE1_ATTACKS:
        atk_df = sub[sub["attack"] == atk]
        n_basins = atk_df["basin"].nunique()
        row = [ATTACK_DISPLAY.get(atk, atk), str(n_basins)]
        for eps in epsilons:
            cell = atk_df[atk_df["epsilon"] == eps]["delta_nse"]
            if cell.empty:
                row.append("--")
            else:
                med = cell.median()
                q25, q75 = cell.quantile(0.25), cell.quantile(0.75)
                row.append(f"{med:.3f} [{q25:.3f}, {q75:.3f}]")
        rows.append(row)

    # Amplification ratio row (median-based)
    ratio_row = ["Ampl. ratio (APGD/Gauss)", ""]
    apgd = sub[sub["attack"] == "auto_pgd"]
    for eps in epsilons:
        apgd_med = apgd[apgd["epsilon"] == eps]["delta_nse"].median()
        g_med = gauss_med.get(eps, None)
        if g_med is not None and g_med != 0 and not np.isnan(apgd_med):
            ratio_row.append(f"{apgd_med / g_med:.1f}x")
        else:
            ratio_row.append("--")
    rows.append(ratio_row)

    _print_md_table(headers, rows)


# ===================================================================
# TABLE 2 — Constraint Ablation
# ===================================================================

def table_constraint_ablation(df: pd.DataFrame) -> None:
    """Print Table 2: constraint levels x epsilon values, median DELTA-NSE."""
    mask = (df["attack"] == "auto_pgd") & (df["target"] == "untargeted")
    sub = df.loc[mask]
    if sub.empty:
        warnings.warn("Table 2: no data after filtering (attack=auto_pgd, target=untargeted).")
        return

    constraints = sorted(sub["constraint"].unique())
    epsilons = sorted(sub["epsilon"].unique())
    headers = ["Constraint", "N"] + [f"eps={e}" for e in epsilons]

    rows: list[list[str]] = []
    for con in constraints:
        con_df = sub[sub["constraint"] == con]
        n_basins = con_df["basin"].nunique()
        row = [str(con), str(n_basins)]
        for eps in epsilons:
            cell = con_df[con_df["epsilon"] == eps]["delta_nse"]
            if cell.empty:
                row.append("--")
            else:
                row.append(f"{cell.median():.3f} ({cell.mean():.3f})")
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
    sub = df.loc[mask].copy()
    if sub.empty:
        warnings.warn("Table 3: no data after filtering (APGD, eps=0.1, lp).")
        return

    # Compute delta_kge if not present
    if "delta_kge" not in sub.columns:
        if "kge_clean" in sub.columns and "kge_adv" in sub.columns:
            sub["delta_kge"] = sub["kge_adv"] - sub["kge_clean"]

    # Cap peak_error at 10 (1000%) to remove exploded values from near-zero obs
    if "peak_error" in sub.columns:
        sub["peak_error"] = sub["peak_error"].clip(upper=10.0)

    targets = sorted(sub["target"].unique())
    metrics = ["delta_nse", "delta_kge", "peak_error"]
    metric_labels = ["delta-NSE", "delta-KGE", "peak_error (%)"]

    if "delta_kge" not in sub.columns:
        metrics = ["delta_nse", "peak_error"]
        metric_labels = ["delta-NSE", "peak_error (%)"]

    headers = ["Target", "N"] + metric_labels

    rows: list[list[str]] = []
    for tgt in targets:
        tgt_df = sub[sub["target"] == tgt]
        n_basins = tgt_df["basin"].nunique()
        row = [str(tgt), str(n_basins)]
        for m in metrics:
            if m in tgt_df.columns:
                vals = tgt_df[m].dropna()
                if vals.empty:
                    row.append("--")
                else:
                    med = vals.median()
                    q25, q75 = vals.quantile(0.25), vals.quantile(0.75)
                    if m == "peak_error":
                        row.append(f"{med * 100:.0f}% [{q25 * 100:.0f}%, {q75 * 100:.0f}%]")
                    else:
                        row.append(f"{med:.3f} [{q25:.3f}, {q75:.3f}]")
            else:
                row.append("--")
        rows.append(row)

    _print_md_table(headers, rows)


# ===================================================================
# FIG 1 — Epsilon Curve
# ===================================================================

def fig_epsilon_curve(df: pd.DataFrame, out: Path) -> None:
    """Line plot: epsilon (log) vs median DELTA-NSE with IQR band, one line per attack."""
    mask = (df["constraint"] == "lp") & (df["target"] == "untargeted")
    sub = df.loc[mask & df["attack"].isin(TABLE1_ATTACKS)]
    if sub.empty:
        warnings.warn("fig1: no data — skipping epsilon curve.")
        return

    fig, (ax_top, ax_bot) = plt.subplots(2, 1, figsize=(7, 8),
                                          sharex=True, gridspec_kw={"hspace": 0.15})

    for atk in TABLE1_ATTACKS:
        atk_df = sub[sub["attack"] == atk]
        if atk_df.empty:
            continue
        grp = atk_df.groupby("epsilon")["delta_nse"]
        medians = grp.median().sort_index()
        q25 = grp.quantile(0.25).sort_index()
        q75 = grp.quantile(0.75).sort_index()
        eps_vals = medians.index.values
        color = ATTACK_COLORS.get(atk, None)
        label = ATTACK_DISPLAY.get(atk, atk)

        # Top panel: adversarial attacks (Auto-PGD, FGSM)
        if atk in ("auto_pgd", "fgsm"):
            ax_top.plot(eps_vals, medians.values, marker="o", label=label, color=color,
                        linewidth=2, markersize=6)
            ax_top.fill_between(eps_vals, q25.values, q75.values, alpha=0.2, color=color)
        # Bottom panel: random baselines
        else:
            ax_bot.plot(eps_vals, medians.values, marker="s", label=label, color=color,
                        linewidth=2, markersize=6)
            ax_bot.fill_between(eps_vals, q25.values, q75.values, alpha=0.2, color=color)

    for ax in (ax_top, ax_bot):
        ax.set_xscale("log")
        ax.axhline(0, color="grey", linewidth=0.5, linestyle="--")
        ax.legend(frameon=False, loc="lower left")
        ax.set_ylabel("Median $\\Delta$NSE")

    ax_top.set_title("(a) Adversarial attacks")
    ax_bot.set_title("(b) Random noise baselines")
    ax_bot.set_xlabel("Perturbation budget ($\\varepsilon$)")
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
    vals = basin_dnse.values

    # Key statistics
    med = np.median(vals)
    p10 = np.percentile(vals, 10)
    p90 = np.percentile(vals, 90)
    n_total = len(vals)
    n_below_neg1 = (vals < -1).sum()

    # Clip to [-20, 1] for readability; note outliers in annotation
    clip_lo = -20
    vals_clipped = np.clip(vals, clip_lo, None)
    n_clipped = (vals < clip_lo).sum()

    fig, ax1 = plt.subplots(figsize=(8, 5))
    bins = np.linspace(clip_lo, 0.5, 40)
    ax1.hist(vals_clipped, bins=bins, color="#4878CF", alpha=0.8, edgecolor="white", linewidth=0.5)
    ax1.set_xlabel("$\\Delta$NSE per basin")
    ax1.set_ylabel("Number of basins")
    ax1.set_title(f"Basin Vulnerability Distribution (Auto-PGD, $\\varepsilon$=0.1, N={n_total})")

    # CDF on twin axis (use unclipped for accurate CDF)
    ax2 = ax1.twinx()
    sorted_all = np.sort(vals)
    cdf = np.arange(1, len(sorted_all) + 1) / len(sorted_all)
    ax2.plot(sorted_all, cdf, color="#d62728", linewidth=2, label="CDF", zorder=5)
    ax2.set_ylabel("Cumulative fraction")
    ax2.set_xlim(clip_lo, 0.5)
    ax2.set_ylim(0, 1.05)

    # Percentile markers with offset labels
    for val, lbl, yoff in [(med, f"Median: {med:.2f}", 0.85), (p10, f"10th: {p10:.2f}", 0.15),
                           (p90, f"90th: {p90:.2f}", 0.95)]:
        ax1.axvline(val, color="black", linestyle=":", linewidth=1, alpha=0.7)
        ax1.annotate(lbl, xy=(val, ax1.get_ylim()[1] * yoff), fontsize=9, ha="right",
                     backgroundcolor="white", alpha=0.9,
                     xytext=(-5, 0), textcoords="offset points")

    # Annotate clipped outliers
    if n_clipped > 0:
        ax1.annotate(f"{n_clipped} basins below {clip_lo}\n({n_below_neg1} below -1)",
                     xy=(clip_lo, ax1.get_ylim()[1] * 0.7), fontsize=9, ha="left",
                     color="#d62728", fontstyle="italic")

    lines1, labels1 = ax1.get_legend_handles_labels()
    lines2, labels2 = ax2.get_legend_handles_labels()
    ax1.legend(lines1 + lines2, labels1 + labels2, frameon=False, loc="upper left")

    fig.tight_layout()
    _save_fig(fig, out, "fig2_basin_vulnerability")


# ===================================================================
# FIG 3 — Causal Window
# ===================================================================

def fig_causal_window(df: pd.DataFrame, out: Path) -> None:
    """Box plot with jittered dots: pre_window vs DELTA-NSE for causal_trigger, eps=0.1."""
    mask = (df["attack"] == "causal_trigger") & (df["epsilon"] == 0.1)
    sub = df.loc[mask]
    if sub.empty:
        warnings.warn("fig3: no causal_trigger data — skipping causal window figure.")
        return
    if "pre_window" not in sub.columns:
        warnings.warn("fig3: 'pre_window' column missing — skipping.")
        return

    windows = sorted(sub["pre_window"].unique())
    data_groups = [sub[sub["pre_window"] == w]["delta_nse"].values for w in windows]

    # Clip to [-5, 0.5] for readability
    data_clipped = [np.clip(d, -5, 0.5) for d in data_groups]

    fig, ax = plt.subplots(figsize=(7, 5))

    bp = ax.boxplot(data_clipped, positions=range(len(windows)), widths=0.5,
                    patch_artist=True, showfliers=False,
                    medianprops=dict(color="black", linewidth=1.5))
    for patch in bp["boxes"]:
        patch.set_facecolor("#8c564b")
        patch.set_alpha(0.6)

    # Jittered dots (subsample if too many)
    rng = np.random.default_rng(42)
    for i, d in enumerate(data_clipped):
        n = len(d)
        sample = d if n <= 200 else rng.choice(d, 200, replace=False)
        jitter = rng.uniform(-0.15, 0.15, len(sample))
        ax.scatter(i + jitter, sample, s=8, alpha=0.3, color="#8c564b", edgecolors="none", zorder=3)

    # Annotate medians
    for i, d in enumerate(data_groups):
        med = np.median(d)
        ax.annotate(f"{med:.3f}", xy=(i, med), xytext=(0.3, 0),
                    textcoords="offset fontsize", fontsize=9, color="#333333")

    ax.set_xticks(range(len(windows)))
    ax.set_xticklabels([f"{int(w)}d" for w in windows])
    ax.set_xlabel("Pre-event perturbation window")
    ax.set_ylabel("$\\Delta$NSE")
    ax.set_title("Causal Trigger: Perturbation Window Effect ($\\varepsilon$=0.1)")
    ax.axhline(0, color="grey", linewidth=0.5, linestyle="--")
    fig.tight_layout()
    _save_fig(fig, out, "fig3_causal_window")


# ===================================================================
# FIG 4 — C&W Perturbation Distribution
# ===================================================================

def fig_cw_perturbation(df: pd.DataFrame, out: Path) -> None:
    """Histogram of L2 norms from C&W results, filtering failed convergences."""
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

    # Separate converged (l2 > threshold) from failed (l2 ~ 0)
    converge_threshold = 0.01
    converged = l2_vals[l2_vals > converge_threshold]
    n_failed = (l2_vals <= converge_threshold).sum()
    n_total = len(l2_vals)

    fig, ax = plt.subplots(figsize=(7, 5))
    if len(converged) > 0:
        bins = np.linspace(0, converged.quantile(0.98), 30)
        ax.hist(converged.values, bins=bins, color="#e377c2", alpha=0.8, edgecolor="white")
        med = converged.median()
        ax.axvline(med, color="black", linestyle="--", linewidth=1.5,
                   label=f"Median: {med:.3f} (converged)")
    ax.set_xlabel("L$_2$ perturbation norm")
    ax.set_ylabel("Number of basins")
    ax.set_title(f"C&W: Minimum Perturbation to Reach NSE<0 (N={n_total})")

    # Annotate failed count
    if n_failed > 0:
        ax.annotate(f"{n_failed}/{n_total} basins: L$_2$ $\\approx$ 0\n(already NSE<0 or failed)",
                    xy=(0.97, 0.95), xycoords="axes fraction", fontsize=9,
                    ha="right", va="top", fontstyle="italic", color="#888888",
                    bbox=dict(boxstyle="round,pad=0.3", facecolor="white", edgecolor="#cccccc"))

    ax.legend(frameon=False)
    fig.tight_layout()
    _save_fig(fig, out, "fig4_cw_perturbation")


# ===================================================================
# FIG 5 — Detectability
# ===================================================================

def fig_detectability(df: pd.DataFrame, out: Path) -> None:
    """Scatter: |DELTA-NSE| vs KS p-value, colored by attack method. Log x-axis."""
    if "detectability_ks" not in df.columns:
        warnings.warn("fig5: 'detectability_ks' column missing — skipping.")
        return

    sub = df.dropna(subset=["delta_nse", "detectability_ks"]).copy()
    if sub.empty:
        warnings.warn("fig5: no data with both delta_nse and detectability_ks — skipping.")
        return

    sub["abs_dnse"] = sub["delta_nse"].abs()
    # Filter out zero/near-zero for log scale
    sub = sub[sub["abs_dnse"] > 1e-4]

    fig, ax = plt.subplots(figsize=(8, 5))

    # Plot in consistent order
    plot_order = ["auto_pgd", "fgsm", "gaussian_noise", "multiplicative_bias",
                  "temporal_correlated_noise", "causal_trigger", "cw_regression"]
    for atk in plot_order:
        atk_df = sub[sub["attack"] == atk]
        if atk_df.empty:
            continue
        color = ATTACK_COLORS.get(atk, None)
        ax.scatter(
            atk_df["abs_dnse"],
            atk_df["detectability_ks"],
            label=ATTACK_DISPLAY.get(atk, atk),
            color=color,
            alpha=0.4,
            s=15,
            edgecolors="none",
        )

    ax.axhline(0.05, color="red", linestyle="--", linewidth=1, alpha=0.8, label="p = 0.05")
    ax.set_xscale("log")
    ax.set_xlabel("|$\\Delta$NSE|")
    ax.set_ylabel("KS test p-value")
    ax.set_title("Attack Effectiveness vs. Statistical Detectability")
    ax.legend(frameon=False, fontsize=9, ncol=2, loc="upper right",
              markerscale=2)
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
