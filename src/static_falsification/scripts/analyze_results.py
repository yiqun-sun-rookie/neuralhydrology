"""Aggregate results across folds, compute statistics, and generate figures.

Usage:
    python -m static_falsification.scripts.analyze_results --results-dir results/11_static_falsification
"""
import argparse
import json
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy import stats


CONDITIONS = ["e1", "e2", "e3", "e4"]
CONDITION_LABELS = {
    "e1": "E1: Correct Static",
    "e2": "E2: Train Correct, Test Shuffle",
    "e3": "E3: Train+Test Shuffle",
    "e4": "E4: Constant (Zero) Static",
}


def load_results(results_dir: Path) -> pd.DataFrame:
    """Load per-basin NSE/KGE from all experiment run directories."""
    rows = []
    for condition in CONDITIONS:
        for fold_idx in range(5):
            pattern = f"sf_{condition}_fold{fold_idx}_*"
            run_dirs = sorted(results_dir.glob(pattern))
            if not run_dirs:
                print(f"WARNING: No run directory for {condition} fold {fold_idx}")
                continue
            run_dir = run_dirs[-1]

            # Find the test results CSV
            test_results = list(run_dir.glob("test/model_epoch*/test_results.csv"))
            if not test_results:
                test_results = list(run_dir.glob("test/model_epoch*/test_results.p"))
            if not test_results:
                print(f"WARNING: No test results in {run_dir}")
                continue

            results_file = test_results[-1]
            if results_file.suffix == ".csv":
                df = pd.read_csv(results_file, index_col=0)
            else:
                df = pd.read_pickle(results_file)

            for basin in df.index:
                row = {
                    "condition": condition,
                    "fold": fold_idx,
                    "basin": basin,
                }
                if "NSE" in df.columns:
                    row["NSE"] = df.loc[basin, "NSE"]
                if "KGE" in df.columns:
                    row["KGE"] = df.loc[basin, "KGE"]
                rows.append(row)

    return pd.DataFrame(rows)


def compute_table1(df: pd.DataFrame) -> pd.DataFrame:
    """Table 1: median NSE/KGE per condition, with Wilcoxon p-values vs E1."""
    summary = []
    for condition in CONDITIONS:
        cond_df = df[df["condition"] == condition]
        row = {
            "Condition": CONDITION_LABELS[condition],
            "Median NSE": cond_df["NSE"].median(),
            "Mean NSE": cond_df["NSE"].mean(),
            "Median KGE": cond_df.get("KGE", pd.Series(dtype=float)).median(),
        }
        if condition != "e1":
            e1_nse = df[df["condition"] == "e1"].set_index(["fold", "basin"])["NSE"]
            cx_nse = cond_df.set_index(["fold", "basin"])["NSE"]
            common = e1_nse.index.intersection(cx_nse.index)
            if len(common) > 0:
                stat, pval = stats.wilcoxon(e1_nse.loc[common], cx_nse.loc[common])
                row["p-value vs E1"] = pval
            else:
                row["p-value vs E1"] = float("nan")
        else:
            row["p-value vs E1"] = float("nan")
        summary.append(row)
    return pd.DataFrame(summary)


def plot_fig1_boxplots(df: pd.DataFrame, out_dir: Path):
    """Fig 1: E1-E4 PUB NSE box plots."""
    fig, ax = plt.subplots(figsize=(8, 5))
    data = [df[df["condition"] == c]["NSE"].dropna().values for c in CONDITIONS]
    labels = [CONDITION_LABELS[c] for c in CONDITIONS]
    bp = ax.boxplot(data, labels=labels, patch_artist=True)
    colors = ["#2196F3", "#FF9800", "#9C27B0", "#607D8B"]
    for patch, color in zip(bp["boxes"], colors):
        patch.set_facecolor(color)
        patch.set_alpha(0.7)
    ax.set_ylabel("NSE")
    ax.set_title("PUB Performance: Static Attribute Permutation Experiment")
    ax.axhline(y=0, color="gray", linestyle="--", alpha=0.5)
    plt.xticks(rotation=15, ha="right")
    plt.tight_layout()
    fig.savefig(out_dir / "fig1_boxplots.png", dpi=150)
    plt.close(fig)
    print(f"Saved {out_dir / 'fig1_boxplots.png'}")


def plot_fig2_scatter(df: pd.DataFrame, out_dir: Path):
    """Fig 2: E1 vs E2 per-basin NSE scatter."""
    e1 = df[df["condition"] == "e1"].set_index(["fold", "basin"])["NSE"]
    e2 = df[df["condition"] == "e2"].set_index(["fold", "basin"])["NSE"]
    common = e1.index.intersection(e2.index)

    fig, ax = plt.subplots(figsize=(6, 6))
    ax.scatter(e1.loc[common], e2.loc[common], alpha=0.4, s=10, color="#2196F3")
    lims = [min(ax.get_xlim()[0], ax.get_ylim()[0]), max(ax.get_xlim()[1], ax.get_ylim()[1])]
    ax.plot(lims, lims, "k--", alpha=0.5, label="y = x (no difference)")
    ax.set_xlabel("E1 NSE (Correct Static)")
    ax.set_ylabel("E2 NSE (Shuffled Static at Test)")
    ax.set_title("E1 vs E2: Does Shuffling Static Attributes Hurt?")
    ax.legend()
    ax.set_aspect("equal")
    plt.tight_layout()
    fig.savefig(out_dir / "fig2_scatter_e1_vs_e2.png", dpi=150)
    plt.close(fig)
    print(f"Saved {out_dir / 'fig2_scatter_e1_vs_e2.png'}")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-dir", type=str, required=True)
    args = parser.parse_args()

    results_dir = Path(args.results_dir)
    out_dir = results_dir / "analysis"
    out_dir.mkdir(parents=True, exist_ok=True)

    print("Loading results...")
    df = load_results(results_dir)
    if df.empty:
        print("ERROR: No results found. Check results-dir and run directories.")
        return

    print(f"Loaded {len(df)} basin-level results across {df['condition'].nunique()} conditions")

    table1 = compute_table1(df)
    print("\n=== Table 1: Summary ===")
    print(table1.to_string(index=False))
    table1.to_csv(out_dir / "table1_summary.csv", index=False)

    plot_fig1_boxplots(df, out_dir)
    plot_fig2_scatter(df, out_dir)

    e1_median = df[df["condition"] == "e1"]["NSE"].median()
    e2_median = df[df["condition"] == "e2"]["NSE"].median()
    diff = e1_median - e2_median
    print(f"\n=== Key Result ===")
    print(f"E1 median NSE: {e1_median:.4f}")
    print(f"E2 median NSE: {e2_median:.4f}")
    print(f"Difference (E1 - E2): {diff:.4f}")
    if abs(diff) < 0.02:
        print("INTERPRETATION: Static attributes appear to have minimal impact (< 0.02 NSE)")
    else:
        print(f"INTERPRETATION: Static attributes have measurable impact ({diff:.4f} NSE)")


if __name__ == "__main__":
    main()
