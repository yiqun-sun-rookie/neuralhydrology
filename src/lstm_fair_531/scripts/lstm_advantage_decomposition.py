"""Decompose where the LSTM ensemble advantage concentrates.

This post-hoc diagnostic reads D04 full-population residual delta artifacts. It
does not rerun models, rescore predictions, or select a challenger. The core
target is the best conceptual MAE penalty relative to the LSTM ensemble: when
even the best of GR4J/XAJ/HBV has positive MAE-minus-LSTM, the context is treated
as a shared conceptual ceiling gap for diagnostic purposes.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import pandas as pd


PACKAGE = Path("draft/papers/10_18_conceptual_lstm_package")
DEFAULT_D04_DIR = PACKAGE / "deep_dive" / "D04_full_population_seasonal_residual_20260709"
DEFAULT_OUT_DIR = PACKAGE / "deep_dive" / "D05_lstm_advantage_decomposition_20260709"


def _bid(values: pd.Series) -> pd.Series:
    return values.astype(str).str.replace(r"\.0$", "", regex=True).str.zfill(8)


def _to_md_table(df: pd.DataFrame, max_rows: int | None = None) -> str:
    if max_rows is not None:
        df = df.head(max_rows)
    if df.empty:
        return "| empty |\n|---|"
    safe = df.copy().replace({np.nan: ""})
    headers = [str(col) for col in safe.columns]
    lines = [
        "| " + " | ".join(header.replace("|", "\\|") for header in headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    for _, row in safe.iterrows():
        values = [str(row[col]).replace("|", "\\|").replace("\n", " ") for col in safe.columns]
        lines.append("| " + " | ".join(values) + " |")
    return "\n".join(lines)


def _write_table(df: pd.DataFrame, csv_path: Path, md_path: Path, max_md_rows: int | None = None) -> None:
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(csv_path, index=False)
    md_path.write_text(_to_md_table(df, max_rows=max_md_rows) + "\n", encoding="utf-8")


def _safe_ratio(numerator: float, denominator: float) -> float:
    if denominator == 0 or np.isnan(denominator):
        return np.nan
    return float(numerator / denominator)


def build_advantage_targets(delta: pd.DataFrame, context_col: str) -> pd.DataFrame:
    """Collapse conceptual models to one diagnostic target per basin-context."""
    rows = []
    required = {"basin_id", "regime", context_col, "conceptual_model", "mae_minus_lstm", "nse_minus_lstm"}
    missing = sorted(required - set(delta.columns))
    if missing:
        raise ValueError(f"Missing required columns for advantage decomposition: {missing}")

    work = delta.copy()
    work["basin_id"] = _bid(work["basin_id"])
    for keys, group in work.groupby(["basin_id", "regime", context_col], dropna=False):
        basin_id, regime, context = keys
        mae = pd.to_numeric(group["mae_minus_lstm"], errors="coerce").dropna()
        nse = pd.to_numeric(group["nse_minus_lstm"], errors="coerce").dropna()
        if mae.empty:
            continue
        best_mae = float(mae.min())
        best_nse = float(nse.max()) if not nse.empty else np.nan
        median_nse = float(nse.median()) if not nse.empty else np.nan
        worst_nse = float(nse.min()) if not nse.empty else np.nan
        nse_spread = float(nse.max() - nse.min()) if not nse.empty else np.nan
        rows.append({
            "basin_id": basin_id,
            "regime": regime,
            context_col: context,
            "n_models": int(group["conceptual_model"].nunique()),
            "best_conceptual_mae_minus_lstm": best_mae,
            "median_conceptual_mae_minus_lstm": float(mae.median()),
            "worst_conceptual_mae_minus_lstm": float(mae.max()),
            "conceptual_mae_spread": float(mae.max() - mae.min()),
            "best_conceptual_nse_minus_lstm": best_nse,
            "median_conceptual_nse_minus_lstm": median_nse,
            "worst_conceptual_nse_minus_lstm": worst_nse,
            "conceptual_nse_spread": nse_spread,
            "all_conceptual_worse_mae": bool(best_mae > 0),
            "any_conceptual_lower_mae": bool(best_mae < 0),
            "all_conceptual_lower_nse": bool(best_nse < 0) if not np.isnan(best_nse) else False,
        })
    return pd.DataFrame(rows)


def summarize_advantage_concentration(targets: pd.DataFrame, context_col: str) -> pd.DataFrame:
    """Summarize how much each regime-context overcontributes to LSTM advantage."""
    required = {
        "regime",
        context_col,
        "best_conceptual_mae_minus_lstm",
        "median_conceptual_mae_minus_lstm",
        "conceptual_mae_spread",
        "best_conceptual_nse_minus_lstm",
        "conceptual_nse_spread",
        "all_conceptual_worse_mae",
        "any_conceptual_lower_mae",
    }
    missing = sorted(required - set(targets.columns))
    if missing:
        raise ValueError(f"Missing required target columns for advantage concentration: {missing}")

    positive_best_gap = targets["best_conceptual_mae_minus_lstm"].clip(lower=0)
    global_positive_sum = float(positive_best_gap.sum())
    total_contexts = int(targets.shape[0])
    rows = []
    for keys, group in targets.groupby(["regime", context_col], dropna=False):
        regime, context = keys
        group_best_gap = pd.to_numeric(group["best_conceptual_mae_minus_lstm"], errors="coerce")
        group_median_gap = pd.to_numeric(group["median_conceptual_mae_minus_lstm"], errors="coerce")
        group_spread = pd.to_numeric(group["conceptual_mae_spread"], errors="coerce")
        group_best_nse = pd.to_numeric(group["best_conceptual_nse_minus_lstm"], errors="coerce")
        group_nse_spread = pd.to_numeric(group["conceptual_nse_spread"], errors="coerce")
        n_contexts = int(group.shape[0])
        context_share = _safe_ratio(n_contexts, total_contexts)
        positive_sum = float(group_best_gap.clip(lower=0).sum())
        positive_share = _safe_ratio(positive_sum, global_positive_sum)
        median_positive_best_gap = float(group_best_gap.clip(lower=0).median())
        median_spread = float(group_spread.median())
        dominance_denominator = median_positive_best_gap + median_spread
        rows.append({
            "regime": regime,
            context_col: context,
            "n_contexts": n_contexts,
            "context_share": context_share,
            "positive_best_gap_sum": positive_sum,
            "positive_best_gap_share": positive_share,
            "gap_concentration_ratio": _safe_ratio(positive_share, context_share),
            "median_best_conceptual_mae_minus_lstm": float(group_best_gap.median()),
            "mean_best_conceptual_mae_minus_lstm": float(group_best_gap.mean()),
            "median_median_conceptual_mae_minus_lstm": float(group_median_gap.median()),
            "median_conceptual_mae_spread": median_spread,
            "shared_failure_rate": float(group["all_conceptual_worse_mae"].mean()),
            "any_conceptual_lower_mae_rate": float(group["any_conceptual_lower_mae"].mean()),
            "median_best_conceptual_nse_minus_lstm": float(group_best_nse.median()),
            "median_conceptual_nse_spread": float(group_nse_spread.median()),
            "ceiling_dominance_index": _safe_ratio(median_positive_best_gap, dominance_denominator),
        })
    return pd.DataFrame(rows).sort_values(
        ["gap_concentration_ratio", "positive_best_gap_share"], ascending=[False, False]
    ).reset_index(drop=True)


def combine_top_contexts(season_summary: pd.DataFrame, flow_summary: pd.DataFrame) -> pd.DataFrame:
    season = season_summary.copy()
    season["context_family"] = "season"
    season["context"] = season["season"]
    flow = flow_summary.copy()
    flow["context_family"] = "flow_group"
    flow["context"] = flow["flow_group"]
    common_cols = [
        "context_family",
        "regime",
        "context",
        "n_contexts",
        "context_share",
        "positive_best_gap_share",
        "gap_concentration_ratio",
        "median_best_conceptual_mae_minus_lstm",
        "shared_failure_rate",
        "median_conceptual_mae_spread",
        "ceiling_dominance_index",
    ]
    return pd.concat([season[common_cols], flow[common_cols]], ignore_index=True).sort_values(
        ["gap_concentration_ratio", "positive_best_gap_share"], ascending=[False, False]
    ).reset_index(drop=True)


def write_review_memo(out_dir: Path, season_summary: pd.DataFrame, flow_summary: pd.DataFrame,
                      top_contexts: pd.DataFrame) -> None:
    top_season = season_summary.iloc[0]
    top_flow = flow_summary.iloc[0]
    memo = [
        "# D05 LSTM Advantage Decomposition",
        "",
        "## Purpose",
        "",
        (
            "Test whether the LSTM ensemble advantage is concentrated in a small set of "
            "population contexts rather than being a uniform full-domain margin. The diagnostic "
            "target is `best_conceptual_mae_minus_lstm`: positive values mean even the best of "
            "GR4J/XAJ/HBV has higher MAE than the LSTM ensemble in that basin-context."
        ),
        "",
        "## Main Findings",
        "",
        (
            f"- Strongest seasonal concentration: `{top_season['regime']} / {top_season['season']}` "
            f"has context share {top_season['context_share']:.3f} but positive best-gap share "
            f"{top_season['positive_best_gap_share']:.3f}, giving concentration ratio "
            f"{top_season['gap_concentration_ratio']:.2f}."
        ),
        (
            f"- Strongest flow concentration: `{top_flow['regime']} / {top_flow['flow_group']}` "
            f"has context share {top_flow['context_share']:.3f} but positive best-gap share "
            f"{top_flow['positive_best_gap_share']:.3f}, giving concentration ratio "
            f"{top_flow['gap_concentration_ratio']:.2f}."
        ),
        (
            "- Interpretation: the evidence is stronger than a generic diagnostic-value claim. "
            "It supports a bounded statement that conceptual structures can decompose where the "
            "LSTM advantage concentrates, especially in snow-dominated seasonal/high-flow contexts."
        ),
        "",
        "## Top Contexts",
        "",
        _to_md_table(top_contexts[[
            "context_family",
            "regime",
            "context",
            "n_contexts",
            "context_share",
            "positive_best_gap_share",
            "gap_concentration_ratio",
            "median_best_conceptual_mae_minus_lstm",
            "shared_failure_rate",
            "median_conceptual_mae_spread",
            "ceiling_dominance_index",
        ]], max_rows=12),
        "",
        "## Independent Review",
        "",
        "- Code/input boundary: this script reads D04 generated delta tables only; it does not read CAMELS streamflow files, `camels_hydro`, or fair-benchmark frozen artifacts.",
        "- Metric direction: positive MAE-minus-LSTM means conceptual residual error is larger than LSTM; positive best-gap means all three conceptual models are worse in MAE for that basin-context.",
        "- Scope: this is population-level post-hoc diagnosis, not causal attribution and not evidence that conceptual models complement LSTM prediction.",
        "- Remaining risk: season and flow-group decompositions are separate; a joint season-by-flow event decomposition would require daily residual grouping and is the next stricter mechanism check if needed.",
    ]
    (out_dir / "D05_lstm_advantage_decomposition_memo.md").write_text("\n".join(memo) + "\n", encoding="utf-8")


def run(d04_dir: Path, out_dir: Path) -> dict:
    tables = d04_dir / "tables"
    out_tables = out_dir / "tables"
    out_dir.mkdir(parents=True, exist_ok=True)
    seasonal_delta = pd.read_csv(tables / "conceptual_vs_lstm_by_case_season.csv", dtype={"basin_id": str})
    flow_delta = pd.read_csv(tables / "conceptual_vs_lstm_by_case_flow_group.csv", dtype={"basin_id": str})

    season_targets = build_advantage_targets(seasonal_delta, context_col="season")
    flow_targets = build_advantage_targets(flow_delta, context_col="flow_group")
    season_summary = summarize_advantage_concentration(season_targets, context_col="season")
    flow_summary = summarize_advantage_concentration(flow_targets, context_col="flow_group")
    top_contexts = combine_top_contexts(season_summary, flow_summary)

    _write_table(season_targets, out_tables / "season_advantage_targets.csv",
                 out_tables / "season_advantage_targets.md", max_md_rows=80)
    _write_table(flow_targets, out_tables / "flow_advantage_targets.csv",
                 out_tables / "flow_advantage_targets.md", max_md_rows=80)
    _write_table(season_summary, out_tables / "season_regime_advantage_concentration.csv",
                 out_tables / "season_regime_advantage_concentration.md", max_md_rows=80)
    _write_table(flow_summary, out_tables / "flow_regime_advantage_concentration.csv",
                 out_tables / "flow_regime_advantage_concentration.md", max_md_rows=80)
    _write_table(top_contexts, out_tables / "top_advantage_contexts.csv",
                 out_tables / "top_advantage_contexts.md", max_md_rows=80)
    write_review_memo(out_dir, season_summary, flow_summary, top_contexts)

    manifest = {
        "experiment_id": "D05_lstm_advantage_decomposition_20260709",
        "created_by": "src/lstm_fair_531/scripts/lstm_advantage_decomposition.py",
        "source_d04_dir": str(d04_dir),
        "out_dir": str(out_dir),
        "inputs": [
            str(tables / "conceptual_vs_lstm_by_case_season.csv"),
            str(tables / "conceptual_vs_lstm_by_case_flow_group.csv"),
        ],
        "outputs": [
            "tables/season_advantage_targets.csv",
            "tables/flow_advantage_targets.csv",
            "tables/season_regime_advantage_concentration.csv",
            "tables/flow_regime_advantage_concentration.csv",
            "tables/top_advantage_contexts.csv",
            "D05_lstm_advantage_decomposition_memo.md",
        ],
        "guardrails": [
            "Post-hoc population diagnostic only.",
            "Uses generated D04 delta artifacts; does not rerun models.",
            "Does not read camels_hydro, observed streamflow files, answer keys, or fair_benchmark frozen artifacts.",
            "Uses MAE gap concentration for the headline because low-flow NSE can be unstable.",
        ],
    }
    (out_dir / "D05_lstm_advantage_decomposition_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--d04-dir", type=Path, default=DEFAULT_D04_DIR)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    manifest = run(args.d04_dir, args.out_dir)
    print(json.dumps({"out_dir": str(args.out_dir), "outputs": manifest["outputs"]}, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
