"""Joint season-by-flow decomposition of the LSTM advantage.

D05 shows separate seasonal and flow-group concentration. This script checks the
next minimal question: whether the strongest seasonal and flow signals meet in
the same population contexts when D04 daily residuals are aggregated by season
and flow group jointly.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import pandas as pd

from src.lstm_fair_531.scripts.lstm_advantage_decomposition import (
    _to_md_table,
    _write_table,
    build_advantage_targets,
    summarize_advantage_concentration,
)
from src.lstm_fair_531.scripts.seasonal_residual_deep_dive import (
    conceptual_vs_lstm_delta,
    summarize_group_metrics,
)


PACKAGE = Path("draft/papers/10_18_conceptual_lstm_package")
DEFAULT_D04_DIR = PACKAGE / "deep_dive" / "D04_full_population_seasonal_residual_20260709"
DEFAULT_OUT_DIR = PACKAGE / "deep_dive" / "D06_joint_season_flow_advantage_20260709"
DAILY_RESIDUAL_NAME = "daily_residuals_selected_cases.csv.gz"


def _split_joint_context(df: pd.DataFrame) -> pd.DataFrame:
    out = df.copy()
    parts = out["joint_context"].astype(str).str.split("__", n=1, expand=True)
    out["season"] = parts[0]
    out["flow_group"] = parts[1]
    return out


def summarize_joint_advantage(daily: pd.DataFrame, min_days: int = 10) -> tuple[pd.DataFrame, pd.DataFrame, pd.DataFrame,
                                                                                pd.DataFrame]:
    """Aggregate D04 daily residuals by basin, season, and flow group."""
    required = {"basin_id", "regime", "case_type", "model", "obs", "sim", "season", "flow_group"}
    missing = sorted(required - set(daily.columns))
    if missing:
        raise ValueError(f"Missing required daily residual columns: {missing}")

    work = daily.copy()
    work["basin_id"] = work["basin_id"].astype(str).str.replace(r"\.0$", "", regex=True).str.zfill(8)
    work["joint_context"] = work["season"].astype(str) + "__" + work["flow_group"].astype(str)
    model_metrics = summarize_group_metrics(
        work,
        group_cols=["basin_id", "regime", "case_type", "model", "season", "flow_group", "joint_context"],
    )
    if min_days > 0:
        model_metrics = model_metrics[model_metrics["n_days"] >= min_days].copy()

    delta = conceptual_vs_lstm_delta(
        model_metrics,
        group_cols=["basin_id", "regime", "case_type", "season", "flow_group", "joint_context"],
    )
    targets = build_advantage_targets(delta, context_col="joint_context")
    targets = _split_joint_context(targets)
    concentration = summarize_advantage_concentration(targets, context_col="joint_context")
    concentration = _split_joint_context(concentration)

    target_cols = [
        "basin_id",
        "regime",
        "season",
        "flow_group",
        "joint_context",
        "n_models",
        "best_conceptual_mae_minus_lstm",
        "median_conceptual_mae_minus_lstm",
        "worst_conceptual_mae_minus_lstm",
        "conceptual_mae_spread",
        "best_conceptual_nse_minus_lstm",
        "median_conceptual_nse_minus_lstm",
        "worst_conceptual_nse_minus_lstm",
        "conceptual_nse_spread",
        "all_conceptual_worse_mae",
        "any_conceptual_lower_mae",
        "all_conceptual_lower_nse",
    ]
    summary_cols = [
        "regime",
        "season",
        "flow_group",
        "joint_context",
        "n_contexts",
        "context_share",
        "positive_best_gap_sum",
        "positive_best_gap_share",
        "gap_concentration_ratio",
        "median_best_conceptual_mae_minus_lstm",
        "mean_best_conceptual_mae_minus_lstm",
        "median_median_conceptual_mae_minus_lstm",
        "median_conceptual_mae_spread",
        "shared_failure_rate",
        "any_conceptual_lower_mae_rate",
        "median_best_conceptual_nse_minus_lstm",
        "median_conceptual_nse_spread",
        "ceiling_dominance_index",
    ]
    return (
        model_metrics.reset_index(drop=True),
        delta.reset_index(drop=True),
        targets[target_cols].reset_index(drop=True),
        concentration[summary_cols].reset_index(drop=True),
    )


def write_review_memo(out_dir: Path, concentration: pd.DataFrame, min_days: int) -> None:
    top = concentration.iloc[0]
    snow_mam_high = concentration[(concentration["regime"] == "snow-dominated") &
                                  (concentration["season"] == "MAM") &
                                  (concentration["flow_group"] == "high")]
    lines = [
        "# D06 Joint Season-Flow LSTM Advantage Decomposition",
        "",
        "## Purpose",
        "",
        (
            "Test whether the D05 seasonal and flow-group signals combine into a coherent joint "
            "context. Daily D04 residuals are re-aggregated by basin, season, flow group, and model."
        ),
        "",
        "## Main Findings",
        "",
        (
            f"- Top joint context: `{top['regime']} / {top['season']} / {top['flow_group']}` "
            f"has context share {top['context_share']:.3f} but positive best-gap share "
            f"{top['positive_best_gap_share']:.3f}, with concentration ratio "
            f"{top['gap_concentration_ratio']:.2f}."
        ),
    ]
    if not snow_mam_high.empty:
        row = snow_mam_high.iloc[0]
        lines.append(
            f"- Snow MAM high-flow context: context share {row['context_share']:.3f}, "
            f"positive best-gap share {row['positive_best_gap_share']:.3f}, "
            f"concentration ratio {row['gap_concentration_ratio']:.2f}, "
            f"shared failure rate {row['shared_failure_rate']:.3f}."
        )
    lines.extend([
        "",
        "## Top Joint Contexts",
        "",
        _to_md_table(concentration[[
            "regime",
            "season",
            "flow_group",
            "n_contexts",
            "context_share",
            "positive_best_gap_share",
            "gap_concentration_ratio",
            "median_best_conceptual_mae_minus_lstm",
            "shared_failure_rate",
            "median_conceptual_mae_spread",
            "ceiling_dominance_index",
        ]], max_rows=16),
        "",
        "## Independent Review",
        "",
        f"- Minimum days per basin-model joint context: {min_days}.",
        "- Input boundary: this script reads only the D04 daily residual archive, which has already been reaggregated back to D01 NSE in D04.",
        "- Metric direction: positive best-conceptual MAE gap means all three conceptual models have larger MAE than the LSTM ensemble in that joint context.",
        "- Scope: this is a post-hoc residual decomposition, not a causal event attribution and not evidence of LSTM process realism.",
    ])
    (out_dir / "D06_joint_season_flow_advantage_memo.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def run(d04_dir: Path, out_dir: Path, min_days: int) -> dict:
    tables = d04_dir / "tables"
    out_tables = out_dir / "tables"
    out_dir.mkdir(parents=True, exist_ok=True)
    usecols = [
        "basin_id",
        "model",
        "obs",
        "sim",
        "season",
        "flow_group",
        "case_type",
        "regime",
    ]
    daily = pd.read_csv(tables / DAILY_RESIDUAL_NAME, usecols=usecols, dtype={"basin_id": str})
    model_metrics, delta, targets, concentration = summarize_joint_advantage(daily, min_days=min_days)

    _write_table(model_metrics, out_tables / "joint_season_flow_model_metrics.csv",
                 out_tables / "joint_season_flow_model_metrics.md", max_md_rows=80)
    _write_table(delta, out_tables / "joint_conceptual_vs_lstm_delta.csv",
                 out_tables / "joint_conceptual_vs_lstm_delta.md", max_md_rows=80)
    _write_table(targets, out_tables / "joint_advantage_targets.csv",
                 out_tables / "joint_advantage_targets.md", max_md_rows=80)
    _write_table(concentration, out_tables / "joint_regime_advantage_concentration.csv",
                 out_tables / "joint_regime_advantage_concentration.md", max_md_rows=80)
    _write_table(concentration.head(16), out_tables / "top_joint_advantage_contexts.csv",
                 out_tables / "top_joint_advantage_contexts.md", max_md_rows=80)
    write_review_memo(out_dir, concentration, min_days=min_days)

    manifest = {
        "experiment_id": "D06_joint_season_flow_advantage_20260709",
        "created_by": "src/lstm_fair_531/scripts/joint_advantage_decomposition.py",
        "source_d04_dir": str(d04_dir),
        "out_dir": str(out_dir),
        "min_days": min_days,
        "inputs": [str(tables / DAILY_RESIDUAL_NAME)],
        "outputs": [
            "tables/joint_season_flow_model_metrics.csv",
            "tables/joint_conceptual_vs_lstm_delta.csv",
            "tables/joint_advantage_targets.csv",
            "tables/joint_regime_advantage_concentration.csv",
            "tables/top_joint_advantage_contexts.csv",
            "D06_joint_season_flow_advantage_memo.md",
        ],
        "guardrails": [
            "Post-hoc population residual decomposition only.",
            "Reads generated D04 daily residual archive; does not rerun models.",
            "Does not read camels_hydro, raw streamflow files, answer keys, or fair_benchmark frozen artifacts.",
            "Uses MAE best-gap concentration as the headline diagnostic.",
        ],
    }
    (out_dir / "D06_joint_season_flow_advantage_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--d04-dir", type=Path, default=DEFAULT_D04_DIR)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--min-days", type=int, default=10)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    manifest = run(args.d04_dir, args.out_dir, min_days=args.min_days)
    print(json.dumps({"out_dir": str(args.out_dir), "outputs": manifest["outputs"]}, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
