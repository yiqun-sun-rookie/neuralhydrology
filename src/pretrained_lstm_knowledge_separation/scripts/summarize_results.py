"""Summarize knowledge separation experiment results.

Aggregates per-basin metrics across adaptation groups and shift conditions,
computes gain/loss statistics, and produces a compact summary table.
"""
import argparse
from pathlib import Path

import numpy as np
import pandas as pd


def aggregate_metrics(results: pd.DataFrame, metric: str = "NSE") -> pd.DataFrame:
    """Pivot mean metric by (adaptation_group, split_label).

    Returns DataFrame with groups as rows and shifts as columns.
    """
    pivot = results.pivot_table(
        values=metric,
        index="adaptation_group",
        columns="split_label",
        aggfunc="mean",
    )
    return pivot.astype(np.float64)


def compute_gain_loss(
    results: pd.DataFrame,
    metric: str = "NSE",
    baseline_col: str = "source_NSE",
) -> pd.DataFrame:
    """Count basins that improved or degraded vs. source baseline.

    Returns DataFrame indexed by (adaptation_group, split_label) with
    gain_count, loss_count, gain_frac columns.
    """
    results = results.copy()
    results["gain"] = results[metric] > results[baseline_col]

    grouped = results.groupby(["adaptation_group", "split_label"])
    gain_count = grouped["gain"].sum().astype(int)
    total = grouped["gain"].count()
    loss_count = total - gain_count

    out = pd.DataFrame({
        "gain_count": gain_count,
        "loss_count": loss_count,
        "gain_frac": (gain_count / total).round(3),
    })
    return out


def build_summary_table(
    results: pd.DataFrame,
    metric: str = "NSE",
    baseline_col: str = "source_NSE",
) -> pd.DataFrame:
    """Build a compact summary table with mean metrics and gain fractions.

    Returns DataFrame with adaptation groups as rows and columns for each
    shift condition's mean metric and gain fraction.
    """
    agg = aggregate_metrics(results, metric=metric)
    gl = compute_gain_loss(results, metric=metric, baseline_col=baseline_col)

    rows = []
    for group in agg.index:
        row = {"adaptation_group": group}
        for shift in agg.columns:
            row[f"{shift}_mean_{metric}"] = agg.loc[group, shift]
            try:
                row[f"{shift}_gain_frac"] = gl.loc[(group, shift), "gain_frac"]
            except KeyError:
                row[f"{shift}_gain_frac"] = np.nan
        rows.append(row)
    return pd.DataFrame(rows).set_index("adaptation_group")


def main():
    parser = argparse.ArgumentParser(description="Summarize knowledge separation experiment results.")
    parser.add_argument("--results-csv", type=Path, required=True, help="CSV with per-basin results")
    parser.add_argument("--output-dir", type=Path, default=Path("."))
    args = parser.parse_args()

    results = pd.read_csv(args.results_csv)
    table = build_summary_table(results, metric="NSE", baseline_col="source_NSE")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    table.to_csv(args.output_dir / "summary_table.csv")

    md = ["# Knowledge Separation Summary\n"]
    md.append(table.to_markdown())
    (args.output_dir / "summary.md").write_text("\n".join(md), encoding="utf-8")

    print(table.to_string())


if __name__ == "__main__":
    main()
