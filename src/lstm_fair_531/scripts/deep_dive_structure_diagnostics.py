"""Deep-dive diagnostics for the ID10 conceptual/LSTM benchmark.

The script reads existing benchmark artifacts and CAMELS attributes, then writes
an auditable diagnostic package. It does not recalibrate, retrain, or rescore any
model.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict, Iterable, List, Sequence

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy import stats
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn.impute import SimpleImputer
from sklearn.metrics import balanced_accuracy_score, roc_auc_score
from sklearn.model_selection import StratifiedKFold, KFold, cross_val_predict
from sklearn.pipeline import make_pipeline


REPO = Path(".")
PACKAGE = Path("draft/papers/10_18_conceptual_lstm_package")
DEFAULT_SCORE_PANEL = PACKAGE / "tables" / "per_basin_combined_nse.csv"
DEFAULT_ATTR_ROOT = Path("data/camels_us/camels_attributes_v2.0")
DEFAULT_OUT_DIR = PACKAGE / "deep_dive" / "D01_structure_diagnostic_20260709"

PRIMARY_ATTR_FILES = {
    "clim": "camels_clim.txt",
    "topo": "camels_topo.txt",
    "soil": "camels_soil.txt",
    "geol": "camels_geol.txt",
    "vege": "camels_vege.txt",
}
SUPPLEMENTAL_HYDRO_FILES = {"hydro": "camels_hydro.txt"}

LITERATURE_ROWS = [
    {
        "theme": "LSTM large-sample performance",
        "citation": "Kratzert et al. (2019), HESS",
        "evidence": "Regional LSTM on 531 CAMELS basins outperformed several hydrological benchmarks and used static attributes to learn basin similarities.",
        "gap_for_this_study": "The performance ceiling is known; the remaining question is whether conceptual structure disagreement adds diagnostic information under that ceiling.",
        "url": "https://hess.copernicus.org/articles/23/5089/2019/",
    },
    {
        "theme": "CAMELS attribute basis",
        "citation": "Addor et al. (2017), HESS",
        "evidence": "CAMELS provides climate, streamflow, land-cover, soil, geology, and topographic attributes for comparative hydrology.",
        "gap_for_this_study": "Attribute-rich basins allow testing whether model disagreements align with interpretable basin properties.",
        "url": "https://hess.copernicus.org/articles/21/5293/2017/",
    },
    {
        "theme": "Conceptual structure comparison",
        "citation": "Knoben et al. (2019), GMD",
        "evidence": "MARRMoT was built to compare many published conceptual rainfall-runoff structures objectively.",
        "gap_for_this_study": "Structure comparison is established, but our three-school comparison needs a tested diagnostic role rather than a benchmark-only claim.",
        "url": "https://gmd.copernicus.org/articles/12/2463/2019/",
    },
    {
        "theme": "Structure-signature correspondence",
        "citation": "Santos et al. (2022), WRR",
        "evidence": "Prior work links suitable conceptual structures and hydrological signatures in large samples.",
        "gap_for_this_study": "We need to test whether GR4J/XAJ/HBV disagreements expose useful mechanisms in this exact protocol and LSTM reference setting.",
        "url": "https://agupubs.onlinelibrary.wiley.com/doi/full/10.1029/2021WR030619",
    },
    {
        "theme": "LSTM interpretability",
        "citation": "De la Fuente et al. (2024), HESS",
        "evidence": "HydroLSTM-style work shows the interpretability problem remains active despite strong LSTM streamflow skill.",
        "gap_for_this_study": "If conceptual models cannot localize LSTM weaknesses or mechanism regimes, their paper role should be limited.",
        "url": "https://hess.copernicus.org/articles/28/945/2024/",
    },
    {
        "theme": "Same-period conceptual benchmarks",
        "citation": "CAMELS benchmark models, HydroShare",
        "evidence": "Existing CAMELS model outputs use common Maurer forcing and the 1999-2008 calibration / 1989-1999 validation split.",
        "gap_for_this_study": "A fair protocol is necessary but not sufficient; diagnostic value must be shown separately from headline NSE.",
        "url": "https://www.hydroshare.org/resource/474ecc37e7db45baa425cdb4fc1b61e1/",
    },
]

TARGET_COLS = [
    "gr4j_minus_xaj",
    "gr4j_minus_hbv",
    "xaj_minus_hbv",
    "conceptual_spread",
    "lstm_minus_best_conceptual",
    "best_conceptual_minus_lstm",
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


def write_table(df: pd.DataFrame, csv_path: Path, md_path: Path, max_md_rows: int | None = None) -> None:
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(csv_path, index=False)
    md_path.write_text(_to_md_table(df, max_rows=max_md_rows) + "\n", encoding="utf-8")


def read_camels_attributes(group_to_path: Dict[str, Path]) -> pd.DataFrame:
    """Read semicolon-delimited CAMELS attribute files and prefix columns."""
    frames: List[pd.DataFrame] = []
    groups: List[str] = []
    for group, path in group_to_path.items():
        df = pd.read_csv(path, sep=";", na_values=["NA", "NaN", "nan"], dtype={"gauge_id": str})
        df["basin_id"] = _bid(df["gauge_id"])
        df = df.drop(columns=["gauge_id"]).set_index("basin_id")
        df = df.rename(columns={col: f"{group}_{col}" for col in df.columns})
        frames.append(df)
        groups.append(group)
    if not frames:
        return pd.DataFrame()
    merged = pd.concat(frames, axis=1)
    merged["attr_source_groups"] = ";".join(groups)
    return merged


def add_diagnostic_targets(panel: pd.DataFrame) -> pd.DataFrame:
    df = panel.copy()
    df["basin_id"] = _bid(df["basin_id"])
    df["gr4j_minus_xaj"] = df["GR4J"] - df["XAJ"]
    df["gr4j_minus_hbv"] = df["GR4J"] - df["HBV"]
    df["xaj_minus_hbv"] = df["XAJ"] - df["HBV"]
    df["conceptual_spread"] = df[["GR4J", "XAJ", "HBV"]].max(axis=1) - df[["GR4J", "XAJ", "HBV"]].min(axis=1)
    df["best_conceptual_minus_lstm"] = df["best_conceptual"] - df["LSTM_ensemble_8seed"]
    df["conceptual_beats_lstm"] = df["best_conceptual_minus_lstm"] > 0
    df["xaj_or_hbv_winner"] = df["conceptual_winner"].isin(["XAJ", "HBV"])
    return df


def numeric_feature_columns(df: pd.DataFrame, excluded: Iterable[str]) -> List[str]:
    excluded_set = set(excluded)
    cols: List[str] = []
    for col in df.columns:
        if col in excluded_set:
            continue
        if pd.api.types.is_numeric_dtype(df[col]):
            cols.append(col)
    return cols


def apply_bh_fdr(df: pd.DataFrame, p_col: str = "p_value", q_col: str = "q_value",
                 reject_col: str = "significant_fdr_05", alpha: float = 0.05) -> pd.DataFrame:
    """Apply Benjamini-Hochberg FDR correction."""
    if df.empty:
        out = df.copy()
        out[q_col] = []
        out[reject_col] = []
        return out
    out = df.copy()
    p_values = out[p_col].astype(float).to_numpy()
    order = np.argsort(p_values)
    ranked = p_values[order]
    n = len(ranked)
    adjusted = ranked * n / np.arange(1, n + 1)
    adjusted = np.minimum.accumulate(adjusted[::-1])[::-1]
    adjusted = np.clip(adjusted, 0.0, 1.0)
    q_values = np.empty_like(adjusted)
    q_values[order] = adjusted
    out[q_col] = q_values
    out[reject_col] = out[q_col] <= alpha
    return out


def summarize_spearman_relationships(panel: pd.DataFrame, feature_cols: Sequence[str],
                                     target_cols: Sequence[str], min_n: int = 3) -> pd.DataFrame:
    rows = []
    for target in target_cols:
        if target not in panel.columns:
            continue
        for feature in feature_cols:
            pair = panel[[feature, target]].replace([np.inf, -np.inf], np.nan).dropna()
            if pair.shape[0] < min_n:
                continue
            if pair[feature].nunique() <= 1 or pair[target].nunique() <= 1:
                continue
            rho, p_value = stats.spearmanr(pair[feature], pair[target])
            if np.isnan(rho) or np.isnan(p_value):
                continue
            if np.isclose(rho, 1.0):
                rho = 1.0
            elif np.isclose(rho, -1.0):
                rho = -1.0
            q25 = pair[feature].quantile(0.25)
            q75 = pair[feature].quantile(0.75)
            low = pair[pair[feature] <= q25][target]
            high = pair[pair[feature] >= q75][target]
            rows.append({
                "target": target,
                "feature": feature,
                "n": int(pair.shape[0]),
                "spearman_rho": float(rho),
                "abs_spearman_rho": float(abs(rho)),
                "p_value": float(p_value),
                "feature_q25": float(q25),
                "feature_q75": float(q75),
                "target_median_low_feature_q25": float(low.median()) if not low.empty else np.nan,
                "target_median_high_feature_q75": float(high.median()) if not high.empty else np.nan,
                "quartile_median_effect_high_minus_low": (
                    float(high.median() - low.median()) if not high.empty and not low.empty else np.nan
                ),
            })
    if not rows:
        return pd.DataFrame(columns=[
            "target",
            "feature",
            "n",
            "spearman_rho",
            "abs_spearman_rho",
            "p_value",
            "feature_q25",
            "feature_q75",
            "target_median_low_feature_q25",
            "target_median_high_feature_q75",
            "quartile_median_effect_high_minus_low",
        ])
    summary = pd.DataFrame(rows)
    summary = apply_bh_fdr(summary)
    return summary.sort_values(["target", "abs_spearman_rho"], ascending=[True, False]).reset_index(drop=True)


def build_case_selection(panel: pd.DataFrame, per_category: int = 8) -> pd.DataFrame:
    panel = panel.copy()
    if "best_conceptual_minus_lstm" not in panel.columns and {"best_conceptual", "LSTM_ensemble_8seed"} <= set(panel.columns):
        panel["best_conceptual_minus_lstm"] = panel["best_conceptual"] - panel["LSTM_ensemble_8seed"]
    if "conceptual_beats_lstm" not in panel.columns and "best_conceptual_minus_lstm" in panel.columns:
        panel["conceptual_beats_lstm"] = panel["best_conceptual_minus_lstm"] > 0

    categories = [
        (
            "conceptual_beats_lstm",
            panel[panel["conceptual_beats_lstm"]].assign(
                case_score=panel["best_conceptual_minus_lstm"],
                case_reason="best conceptual NSE exceeds LSTM ensemble NSE",
            ).sort_values("case_score", ascending=False),
        ),
        (
            "largest_lstm_gap",
            panel.assign(
                case_score=panel["lstm_minus_best_conceptual"],
                case_reason="largest LSTM ensemble advantage over best conceptual model",
            ).sort_values("case_score", ascending=False),
        ),
        (
            "largest_conceptual_disagreement",
            panel.assign(
                case_score=panel["conceptual_spread"],
                case_reason="largest NSE spread among GR4J/XAJ/HBV",
            ).sort_values("case_score", ascending=False),
        ),
    ]
    if {"XAJ", "GR4J", "HBV"} <= set(panel.columns):
        categories.extend([
            (
                "xaj_winner",
                panel[panel["conceptual_winner"] == "XAJ"].assign(
                    case_score=panel["XAJ"] - panel[["GR4J", "HBV"]].max(axis=1),
                    case_reason="XAJ is the best conceptual model",
                ).sort_values("case_score", ascending=False),
            ),
            (
                "hbv_winner",
                panel[panel["conceptual_winner"] == "HBV"].assign(
                    case_score=panel["HBV"] - panel[["GR4J", "XAJ"]].max(axis=1),
                    case_reason="HBV is the best conceptual model",
                ).sort_values("case_score", ascending=False),
            ),
        ])
    selected = []
    used: set[str] = set()
    for rank in range(per_category):
        for case_type, candidates in categories:
            remaining = candidates[~candidates["basin_id"].isin(used)]
            if remaining.shape[0] <= rank:
                continue
            row = remaining.iloc[rank].copy()
            basin_id = str(row["basin_id"])
            if basin_id in used:
                continue
            used.add(basin_id)
            row["case_type"] = case_type
            selected.append(row)
    if not selected:
        return pd.DataFrame()
    keep_cols = [
        "case_type",
        "basin_id",
        "regime",
        "conceptual_winner",
        "case_score",
        "case_reason",
        "GR4J",
        "XAJ",
        "HBV",
        "LSTM_ensemble_8seed",
        "best_conceptual",
        "lstm_minus_best_conceptual",
        "conceptual_spread",
    ]
    available_cols = [col for col in keep_cols if col in selected[0].index]
    return pd.DataFrame(selected)[available_cols].reset_index(drop=True)


def _safe_cv_splits(y: pd.Series, classification: bool) -> int:
    if not classification:
        return 5 if y.shape[0] >= 50 else 3
    counts = y.value_counts()
    if counts.empty:
        return 0
    return max(0, min(5, int(counts.min())))


def predictability_checks(panel: pd.DataFrame, feature_cols: Sequence[str]) -> pd.DataFrame:
    rows = []
    features = panel[list(feature_cols)].replace([np.inf, -np.inf], np.nan)
    for target in ["conceptual_spread", "lstm_minus_best_conceptual", "gr4j_minus_xaj", "gr4j_minus_hbv"]:
        data = pd.concat([features, panel[target]], axis=1).dropna(subset=[target])
        n_splits = _safe_cv_splits(data[target], classification=False)
        if n_splits < 3:
            continue
        model = make_pipeline(
            SimpleImputer(strategy="median"),
            RandomForestRegressor(n_estimators=300, random_state=20260709, min_samples_leaf=8, n_jobs=-1),
        )
        cv = KFold(n_splits=n_splits, shuffle=True, random_state=20260709)
        pred = cross_val_predict(model, data[list(feature_cols)], data[target], cv=cv, n_jobs=None)
        rho, p_value = stats.spearmanr(data[target], pred)
        ss_res = float(np.sum((data[target].to_numpy() - pred)**2))
        ss_tot = float(np.sum((data[target].to_numpy() - data[target].mean())**2))
        rows.append({
            "target": target,
            "task": "regression",
            "n": int(data.shape[0]),
            "metric_primary": "cv_spearman_pred_vs_obs",
            "metric_value": float(rho),
            "p_value": float(p_value),
            "cv_r2": float(1 - ss_res / ss_tot) if ss_tot > 0 else np.nan,
        })
    for target in ["conceptual_beats_lstm", "xaj_or_hbv_winner", "conceptual_winner"]:
        data = pd.concat([features, panel[target]], axis=1).dropna(subset=[target])
        n_splits = _safe_cv_splits(data[target], classification=True)
        if n_splits < 3:
            continue
        model = make_pipeline(
            SimpleImputer(strategy="median"),
            RandomForestClassifier(
                n_estimators=300,
                random_state=20260709,
                min_samples_leaf=8,
                class_weight="balanced_subsample",
                n_jobs=-1,
            ),
        )
        cv = StratifiedKFold(n_splits=n_splits, shuffle=True, random_state=20260709)
        pred = cross_val_predict(model, data[list(feature_cols)], data[target], cv=cv, n_jobs=None)
        row = {
            "target": target,
            "task": "classification",
            "n": int(data.shape[0]),
            "metric_primary": "cv_balanced_accuracy",
            "metric_value": float(balanced_accuracy_score(data[target], pred)),
            "p_value": np.nan,
            "cv_r2": np.nan,
        }
        if target != "conceptual_winner" and data[target].nunique() == 2:
            try:
                proba = cross_val_predict(model, data[list(feature_cols)], data[target], cv=cv, method="predict_proba")
                classes = model.fit(data[list(feature_cols)], data[target]).classes_
                positive = True if True in set(classes) else classes[-1]
                pos_idx = list(classes).index(positive)
                row["roc_auc"] = float(roc_auc_score(data[target], proba[:, pos_idx]))
            except Exception:
                row["roc_auc"] = np.nan
        rows.append(row)
    return pd.DataFrame(rows)


def target_summary(panel: pd.DataFrame) -> pd.DataFrame:
    rows = []
    for target in TARGET_COLS:
        vals = panel[target].dropna()
        rows.append({
            "target": target,
            "n": int(vals.shape[0]),
            "median": float(vals.median()),
            "mean": float(vals.mean()),
            "q10": float(vals.quantile(0.10)),
            "q90": float(vals.quantile(0.90)),
        })
    rows.append({
        "target": "conceptual_beats_lstm_count",
        "n": int(panel.shape[0]),
        "median": int(panel["conceptual_beats_lstm"].sum()),
        "mean": float(panel["conceptual_beats_lstm"].mean()),
        "q10": np.nan,
        "q90": np.nan,
    })
    return pd.DataFrame(rows)


def write_top_relationship_figure(primary: pd.DataFrame, supplemental: pd.DataFrame, out_path: Path) -> None:
    top_primary = primary.assign(source="primary_static").sort_values("abs_spearman_rho", ascending=False).head(12)
    top_supp = supplemental.assign(source="supplemental_hydro").sort_values("abs_spearman_rho", ascending=False).head(8)
    plot_df = pd.concat([top_primary, top_supp], ignore_index=True)
    if plot_df.empty:
        return
    plot_df["label"] = plot_df["target"] + "\n" + plot_df["feature"]
    colors = np.where(plot_df["source"] == "primary_static", "#4C78A8", "#F58518")
    plt.figure(figsize=(10, max(4, 0.42 * len(plot_df))))
    plt.barh(np.arange(plot_df.shape[0]), plot_df["abs_spearman_rho"], color=colors)
    plt.yticks(np.arange(plot_df.shape[0]), plot_df["label"], fontsize=8)
    plt.xlabel("|Spearman rho|")
    plt.title("Top univariate diagnostic relationships")
    plt.gca().invert_yaxis()
    plt.tight_layout()
    out_path.parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(out_path, dpi=200)
    plt.close()


def write_review_memo(out_dir: Path, primary: pd.DataFrame, supplemental: pd.DataFrame,
                      predictability: pd.DataFrame) -> None:
    strongest_primary = primary.sort_values("abs_spearman_rho", ascending=False).head(5)
    lstm_primary = primary[primary["target"] == "lstm_minus_best_conceptual"].sort_values(
        "abs_spearman_rho", ascending=False
    ).head(5)
    hydro_top = supplemental.sort_values("abs_spearman_rho", ascending=False).head(5)
    pred = predictability.copy()
    text = [
        "# D01 Independent Review Memo",
        "",
        "## Code Review",
        "",
        "- The script reads existing benchmark tables and CAMELS attributes only; it does not recalibrate, retrain, or edit frozen fair-benchmark artifacts.",
        "- Primary diagnostic relationships exclude `camels_hydro` because those attributes are derived from observed streamflow; hydro signatures are written as a separate supplemental table.",
        "- Targets are derived from already reported NSE columns, so this is an explanatory/post-hoc diagnostic analysis rather than a Track-0 challenger submission.",
        "",
        "## Result Review",
        "",
        "Strongest primary static-attribute relationships:",
        "",
        _to_md_table(strongest_primary[[
            "target",
            "feature",
            "n",
            "spearman_rho",
            "q_value",
            "quartile_median_effect_high_minus_low",
        ]], max_rows=5),
        "",
        "Primary relationships for LSTM gap:",
        "",
        _to_md_table(lstm_primary[[
            "target",
            "feature",
            "n",
            "spearman_rho",
            "q_value",
            "quartile_median_effect_high_minus_low",
        ]], max_rows=5),
        "",
        "Strongest supplemental hydro-signature relationships:",
        "",
        _to_md_table(hydro_top[[
            "target",
            "feature",
            "n",
            "spearman_rho",
            "q_value",
            "quartile_median_effect_high_minus_low",
        ]], max_rows=5),
        "",
        "Cross-validated predictability checks:",
        "",
        _to_md_table(pred, max_rows=12),
        "",
        "## Independent Verification Of Review Concerns",
        "",
        "- Concern: `camels_hydro` may create information leakage if treated as model input. Verification: the output separates primary static attributes from supplemental hydro signatures, and the claim map forbids using hydro signatures as a Track-0 predictor claim.",
        "- Concern: statistically significant correlations may be practically small. Verification: tables include effect sizes as Spearman rho and top-vs-bottom quartile median target shifts; weak relationships are labeled exploratory.",
        "- Concern: LSTM comparison might be overstated. Verification: targets use LSTM as a reference ceiling only, not a same-information conceptual challenger.",
        "",
        "## Goal Check",
        "",
        "This iteration tests whether diagnostic value becomes concrete at the basin-attribute level. If LSTM-gap relationships remain weak while conceptual deltas align with snow/aridity/baseflow signals, the defensible paper claim is limited to conceptual-family structure-regime specialization, not LSTM weakness localization.",
    ]
    (out_dir / "independent_review_memo.md").write_text("\n".join(text) + "\n", encoding="utf-8")


def write_claim_map(out_dir: Path, primary: pd.DataFrame, supplemental: pd.DataFrame,
                    predictability: pd.DataFrame) -> pd.DataFrame:
    top_primary = primary.sort_values("abs_spearman_rho", ascending=False).head(1)
    top_lstm = primary[primary["target"] == "lstm_minus_best_conceptual"].sort_values(
        "abs_spearman_rho", ascending=False
    ).head(1)
    pred_lstm = predictability[predictability["target"] == "lstm_minus_best_conceptual"].head(1)

    rows = []
    if not top_primary.empty and bool(top_primary.iloc[0]["significant_fdr_05"]):
        rows.append({
            "claim_id": "D01-C1",
            "claim": "Conceptual model disagreements are not random across basins; at least some static CAMELS attributes align with GR4J/XAJ/HBV performance deltas.",
            "status": "paper-defensible with correlational language",
            "evidence": "tables/primary_static_spearman.csv",
            "boundary": "Correlation and post-hoc diagnosis only; no causal mechanism proven.",
        })
    else:
        rows.append({
            "claim_id": "D01-C1",
            "claim": "Static CAMELS attributes strongly explain conceptual model disagreements.",
            "status": "not supported",
            "evidence": "tables/primary_static_spearman.csv",
            "boundary": "Use only as negative finding unless later event analysis adds support.",
        })

    if not top_lstm.empty and abs(float(top_lstm.iloc[0]["spearman_rho"])) >= 0.25 and bool(
            top_lstm.iloc[0]["significant_fdr_05"]):
        status = "exploratory but usable"
    else:
        status = "weak or not supported"
    rows.append({
        "claim_id": "D01-C2",
        "claim": "Conceptual structure diagnostics localize where LSTM has large residual advantage.",
        "status": status,
        "evidence": "tables/primary_static_spearman.csv; tables/predictability_checks.csv",
        "boundary": "Requires event/season residual analysis before any mechanism claim about LSTM failures.",
    })

    if not pred_lstm.empty and float(pred_lstm.iloc[0]["metric_value"]) > 0.25:
        pred_status = "attribute-predictable signal exists"
    else:
        pred_status = "little cross-validated predictive support"
    rows.append({
        "claim_id": "D01-C3",
        "claim": "Basin attributes provide practically useful prediction of the LSTM-vs-conceptual gap.",
        "status": pred_status,
        "evidence": "tables/predictability_checks.csv",
        "boundary": "Random-forest CV here is diagnostic screening, not a tuned predictive model.",
    })

    rows.append({
        "claim_id": "D01-C4",
        "claim": "Hydrological signatures can strengthen interpretation of model-structure differences.",
        "status": "supplemental only" if not supplemental.empty else "not evaluated",
        "evidence": "tables/supplemental_hydro_spearman.csv",
        "boundary": "`camels_hydro` derives from observed streamflow and must not be presented as Track-0-allowed model input.",
    })
    claim_map = pd.DataFrame(rows)
    write_table(claim_map, out_dir / "tables" / "claim_map.csv", out_dir / "claim_map.md")
    return claim_map


def write_readme(out_dir: Path, claim_map: pd.DataFrame, sources: dict) -> None:
    text = [
        "# D01 Structure Diagnostic Deep Dive",
        "",
        "Goal: test whether GR4J/XAJ/HBV structure differences provide concrete diagnostic information under the existing LSTM reference ceiling.",
        "",
        "## Inputs",
        "",
        _to_md_table(pd.DataFrame([{"name": k, "path": v} for k, v in sources.items()])),
        "",
        "## Outputs",
        "",
        "- `tables/basin_attribute_panel.csv`: basin-level scores, derived targets, and CAMELS attributes.",
        "- `tables/primary_static_spearman.csv`: main static-attribute diagnostic relationships; excludes streamflow-derived `camels_hydro`.",
        "- `tables/supplemental_hydro_spearman.csv`: descriptive hydro-signature relationships only.",
        "- `tables/predictability_checks.csv`: cross-validated screening of whether attributes predict diagnostic targets.",
        "- `tables/case_basin_list.csv`: basins for follow-up hydrograph/event analysis.",
        "- `claim_map.md`: paper-safe claims and boundaries.",
        "- `independent_review_memo.md`: code/result review and verification of concerns.",
        "",
        "## Current Claim Status",
        "",
        _to_md_table(claim_map),
    ]
    (out_dir / "README.md").write_text("\n".join(text) + "\n", encoding="utf-8")


def run(score_panel_path: Path, attr_root: Path, out_dir: Path) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    tables = out_dir / "tables"
    figures = out_dir / "figures"
    tables.mkdir(exist_ok=True)
    figures.mkdir(exist_ok=True)

    score_panel = pd.read_csv(score_panel_path, dtype={"basin_id": str})
    score_panel = add_diagnostic_targets(score_panel)

    primary_paths = {name: attr_root / filename for name, filename in PRIMARY_ATTR_FILES.items()}
    supplemental_paths = {name: attr_root / filename for name, filename in SUPPLEMENTAL_HYDRO_FILES.items()}
    primary_attrs = read_camels_attributes(primary_paths)
    hydro_attrs = read_camels_attributes(supplemental_paths)

    primary_panel = score_panel.merge(primary_attrs, left_on="basin_id", right_index=True, how="left")
    full_panel = primary_panel.merge(
        hydro_attrs.drop(columns=["attr_source_groups"], errors="ignore"),
        left_on="basin_id",
        right_index=True,
        how="left",
    )

    target_cols = [col for col in TARGET_COLS if col in full_panel.columns]
    score_cols = set(score_panel.columns) | {"conceptual_beats_lstm", "xaj_or_hbv_winner"}
    primary_features = numeric_feature_columns(primary_panel, excluded=score_cols | set(TARGET_COLS))
    hydro_features = [col for col in hydro_attrs.columns if col.startswith("hydro_") and pd.api.types.is_numeric_dtype(hydro_attrs[col])]

    primary_spearman = summarize_spearman_relationships(primary_panel, primary_features, target_cols, min_n=10)
    hydro_spearman = summarize_spearman_relationships(full_panel, hydro_features, target_cols, min_n=10)
    predictability = predictability_checks(primary_panel, primary_features)
    cases = build_case_selection(full_panel, per_category=8)
    targets = target_summary(full_panel)
    literature = pd.DataFrame(LITERATURE_ROWS)

    write_table(full_panel, tables / "basin_attribute_panel.csv", tables / "basin_attribute_panel.md", max_md_rows=25)
    write_table(primary_spearman, tables / "primary_static_spearman.csv", tables / "primary_static_spearman.md", max_md_rows=50)
    write_table(hydro_spearman, tables / "supplemental_hydro_spearman.csv", tables / "supplemental_hydro_spearman.md", max_md_rows=50)
    write_table(predictability, tables / "predictability_checks.csv", tables / "predictability_checks.md")
    write_table(cases, tables / "case_basin_list.csv", tables / "case_basin_list.md")
    write_table(targets, tables / "target_summary.csv", tables / "target_summary.md")
    write_table(literature, tables / "literature_gap_table.csv", tables / "literature_gap_table.md")

    write_top_relationship_figure(primary_spearman, hydro_spearman, figures / "top_diagnostic_relationships.png")
    write_review_memo(out_dir, primary_spearman, hydro_spearman, predictability)
    claim_map = write_claim_map(out_dir, primary_spearman, hydro_spearman, predictability)

    sources = {
        "score_panel": str(score_panel_path),
        "primary_camels_attributes": str(attr_root),
        "hydro_signatures_supplemental": str(attr_root / "camels_hydro.txt"),
    }
    manifest = {
        "experiment_id": "D01_structure_diagnostic_20260709",
        "created_by": "src/lstm_fair_531/scripts/deep_dive_structure_diagnostics.py",
        "purpose": "Test whether conceptual model structure differences provide concrete diagnostic value.",
        "sources": sources,
        "outputs": {
            "tables": sorted(path.name for path in tables.glob("*.csv")),
            "figures": sorted(path.name for path in figures.glob("*")),
            "memos": ["README.md", "claim_map.md", "independent_review_memo.md"],
        },
        "guardrails": [
            "No recalibration or retraining.",
            "Primary claims exclude streamflow-derived camels_hydro attributes.",
            "LSTM is treated as a reference ceiling, not a same-information conceptual challenger.",
        ],
    }
    (out_dir / "MANIFEST.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    write_readme(out_dir, claim_map, sources)
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--score-panel", type=Path, default=DEFAULT_SCORE_PANEL)
    parser.add_argument("--attr-root", type=Path, default=DEFAULT_ATTR_ROOT)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    manifest = run(args.score_panel, args.attr_root, args.out_dir)
    print(json.dumps({"out_dir": str(args.out_dir), "outputs": manifest["outputs"]}, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
