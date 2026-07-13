"""Attribute-link review for population seasonal residual diagnostics.

This script reads D03/D04 residual delta artifacts and D01 basin attributes. It
does not replay models or rescore predictions; it checks whether population
seasonal/flow residual patterns align with the static diagnostic axes already
identified in D01.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Sequence

import numpy as np
import pandas as pd
from scipy import stats


PACKAGE = Path("draft/papers/10_18_conceptual_lstm_package")
D01_DIR = PACKAGE / "deep_dive" / "D01_structure_diagnostic_20260709"
DEFAULT_PANEL = D01_DIR / "tables" / "basin_attribute_panel.csv"
DEFAULT_DIVE_DIR = PACKAGE / "deep_dive" / "D04_full_population_seasonal_residual_20260709"

DEFAULT_FEATURE_COLS = [
    "clim_frac_snow",
    "clim_aridity",
    "topo_elev_mean",
    "topo_slope_mean",
    "conceptual_spread",
    "lstm_minus_best_conceptual",
]
TARGET_COLS = [
    "best_conceptual_mae_minus_lstm",
    "median_conceptual_mae_minus_lstm",
    "conceptual_mae_spread",
    "best_conceptual_nse_minus_lstm",
    "median_conceptual_nse_minus_lstm",
    "conceptual_nse_spread",
]


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


def apply_bh_fdr(df: pd.DataFrame, p_col: str = "p_value") -> pd.DataFrame:
    if df.empty:
        out = df.copy()
        out["q_value"] = []
        out["significant_fdr_05"] = []
        return out
    out = df.copy()
    p_values = out[p_col].astype(float).to_numpy()
    order = np.argsort(p_values)
    ranked = p_values[order]
    n = ranked.size
    adjusted = ranked * n / np.arange(1, n + 1)
    adjusted = np.minimum.accumulate(adjusted[::-1])[::-1]
    adjusted = np.clip(adjusted, 0.0, 1.0)
    q_values = np.empty_like(adjusted)
    q_values[order] = adjusted
    out["q_value"] = q_values
    out["significant_fdr_05"] = out["q_value"] <= 0.05
    return out


def build_population_delta_targets(delta: pd.DataFrame, context_col: str) -> pd.DataFrame:
    rows = []
    group_cols = ["basin_id", "regime", context_col]
    for keys, group in delta.groupby(group_cols, dropna=False):
        basin_id, regime, context = keys
        mae = pd.to_numeric(group["mae_minus_lstm"], errors="coerce")
        nse = pd.to_numeric(group["nse_minus_lstm"], errors="coerce")
        rows.append({
            "basin_id": str(basin_id).zfill(8),
            "regime": regime,
            context_col: context,
            "n_models": int(group["conceptual_model"].nunique()),
            "best_conceptual_mae_minus_lstm": float(mae.min()),
            "median_conceptual_mae_minus_lstm": float(mae.median()),
            "worst_conceptual_mae_minus_lstm": float(mae.max()),
            "conceptual_mae_spread": float(mae.max() - mae.min()),
            "best_conceptual_nse_minus_lstm": float(nse.max()),
            "median_conceptual_nse_minus_lstm": float(nse.median()),
            "worst_conceptual_nse_minus_lstm": float(nse.min()),
            "conceptual_nse_spread": float(nse.max() - nse.min()),
        })
    return pd.DataFrame(rows)


def summarize_attribute_links(targets: pd.DataFrame, panel: pd.DataFrame, context_col: str,
                              feature_cols: Sequence[str], min_n: int = 20) -> pd.DataFrame:
    panel = panel.copy()
    panel["basin_id"] = _bid(panel["basin_id"])
    merged = targets.merge(panel[["basin_id"] + list(feature_cols)], on="basin_id", how="left")
    rows = []
    for context, context_df in merged.groupby(context_col, dropna=False):
        for target in [col for col in TARGET_COLS if col in context_df.columns]:
            for feature in feature_cols:
                if feature not in context_df.columns:
                    continue
                pair = context_df[[target, feature]].replace([np.inf, -np.inf], np.nan).dropna()
                if pair.shape[0] < min_n:
                    continue
                if pair[target].nunique() <= 1 or pair[feature].nunique() <= 1:
                    continue
                rho, p_value = stats.spearmanr(pair[feature], pair[target])
                if np.isnan(rho) or np.isnan(p_value):
                    continue
                if np.isclose(rho, 1.0):
                    rho = 1.0
                elif np.isclose(rho, -1.0):
                    rho = -1.0
                rows.append({
                    "context_col": context_col,
                    "context": context,
                    "target": target,
                    "feature": feature,
                    "n": int(pair.shape[0]),
                    "spearman_rho": float(rho),
                    "abs_spearman_rho": float(abs(rho)),
                    "p_value": float(p_value),
                })
    if not rows:
        return pd.DataFrame(columns=[
            "context_col",
            "context",
            "target",
            "feature",
            "n",
            "spearman_rho",
            "abs_spearman_rho",
            "p_value",
            "q_value",
            "significant_fdr_05",
        ])
    return apply_bh_fdr(pd.DataFrame(rows)).sort_values(
        ["context_col", "context", "abs_spearman_rho"], ascending=[True, True, False]
    ).reset_index(drop=True)


def write_review_memo(dive_dir: Path, seasonal_links: pd.DataFrame, flow_links: pd.DataFrame) -> None:
    snow_mam = seasonal_links[(seasonal_links["context"] == "MAM") &
                              (seasonal_links["feature"].isin(["clim_frac_snow", "topo_elev_mean"]))]
    high_flow = flow_links[(flow_links["context"] == "high") &
                           (flow_links["feature"].isin(["clim_frac_snow", "topo_elev_mean"]))]
    top = pd.concat([
        seasonal_links.assign(source="seasonal").head(8),
        flow_links.assign(source="flow").head(8),
    ], ignore_index=True)
    text = [
        "# Population Residual Attribute Review",
        "",
        "Purpose: independently check whether D04 full-population seasonal/flow residual targets align with D01 diagnostic axes.",
        "",
        "## Snow/Topography Checks",
        "",
        "MAM seasonal links:",
        "",
        _to_md_table(snow_mam.sort_values("abs_spearman_rho", ascending=False).head(12), max_rows=12),
        "",
        "High-flow links:",
        "",
        _to_md_table(high_flow.sort_values("abs_spearman_rho", ascending=False).head(12), max_rows=12),
        "",
        "## Strongest Links Overall",
        "",
        _to_md_table(top[[
            "source",
            "context",
            "target",
            "feature",
            "n",
            "spearman_rho",
            "q_value",
        ]], max_rows=16),
        "",
        "## Independent Review",
        "",
        "- This review reads already generated D04 delta tables and the D01 basin-attribute panel; it does not rerun models or use streamflow-derived `camels_hydro` attributes.",
        "- Positive MAE-minus-LSTM targets mean conceptual residuals are larger than the LSTM ensemble. Negative NSE-minus-LSTM targets mean conceptual skill is lower.",
        "- These are post-hoc diagnostic links, not causal attribution and not Track-0 model inputs.",
    ]
    (dive_dir / "population_residual_attribute_review.md").write_text("\n".join(text) + "\n", encoding="utf-8")


def run(dive_dir: Path, panel_path: Path, feature_cols: Sequence[str]) -> dict:
    tables = dive_dir / "tables"
    seasonal_delta = pd.read_csv(tables / "conceptual_vs_lstm_by_case_season.csv", dtype={"basin_id": str})
    flow_delta = pd.read_csv(tables / "conceptual_vs_lstm_by_case_flow_group.csv", dtype={"basin_id": str})
    panel = pd.read_csv(panel_path, dtype={"basin_id": str})

    available_features = [col for col in feature_cols if col in panel.columns]
    seasonal_targets = build_population_delta_targets(seasonal_delta, context_col="season")
    flow_targets = build_population_delta_targets(flow_delta, context_col="flow_group")
    seasonal_links = summarize_attribute_links(seasonal_targets, panel, "season", available_features)
    flow_links = summarize_attribute_links(flow_targets, panel, "flow_group", available_features)

    _write_table(seasonal_targets, tables / "seasonal_population_residual_targets.csv",
                 tables / "seasonal_population_residual_targets.md", max_md_rows=80)
    _write_table(flow_targets, tables / "flow_population_residual_targets.csv",
                 tables / "flow_population_residual_targets.md", max_md_rows=80)
    _write_table(seasonal_links, tables / "seasonal_attribute_link_checks.csv",
                 tables / "seasonal_attribute_link_checks.md", max_md_rows=80)
    _write_table(flow_links, tables / "flow_attribute_link_checks.csv",
                 tables / "flow_attribute_link_checks.md", max_md_rows=80)
    write_review_memo(dive_dir, seasonal_links, flow_links)

    manifest = {
        "created_by": "src/lstm_fair_531/scripts/population_residual_attribute_review.py",
        "dive_dir": str(dive_dir),
        "panel_path": str(panel_path),
        "feature_cols": available_features,
        "outputs": [
            "tables/seasonal_population_residual_targets.csv",
            "tables/flow_population_residual_targets.csv",
            "tables/seasonal_attribute_link_checks.csv",
            "tables/flow_attribute_link_checks.csv",
            "population_residual_attribute_review.md",
        ],
        "guardrails": [
            "Post-hoc diagnostic review only.",
            "Uses D01 primary/static diagnostic axes and does not use camels_hydro attributes.",
            "Does not rerun models or select a challenger.",
        ],
    }
    (dive_dir / "population_residual_attribute_review_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dive-dir", type=Path, default=DEFAULT_DIVE_DIR)
    parser.add_argument("--panel", type=Path, default=DEFAULT_PANEL)
    parser.add_argument("--feature", action="append", dest="features")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    features = args.features if args.features else DEFAULT_FEATURE_COLS
    manifest = run(args.dive_dir, args.panel, features)
    print(json.dumps({"dive_dir": str(args.dive_dir), "outputs": manifest["outputs"]}, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
