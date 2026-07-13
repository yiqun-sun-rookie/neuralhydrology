"""Seasonal residual deep dive for selected ID10 diagnostic cases.

This script turns the basin-level diagnostic cases into a small hydrograph-level
audit. It replays saved conceptual parameters for selected basins and compares
their seasonal residuals with an 8-seed LSTM ensemble reconstructed from saved
daily test predictions.
"""
from __future__ import annotations

import argparse
import json
import pickle
import sys
from pathlib import Path
from typing import Iterable, List, Sequence

import numpy as np
import pandas as pd
from scipy import stats

_HERE = Path(__file__).resolve()
_REPO_ROOT = _HERE.parents[3]
if str(_REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT / "src"))
if str(_REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(_REPO_ROOT))

from hydroagent.data_loading import load_camels_basin  # noqa: E402
from src.xaj_global_pilot.scripts.replay_conceptual_saved_params import (  # noqa: E402
    DEFAULT_SUMMARIES,
    _build_model_specs,
    _extract_params,
    _forcing_arrays,
    _read_summary,
    _state_from_saved_row,
)
from xaj_global_pilot.config import REPRO_FORCING, repro_split_periods  # noqa: E402


PACKAGE = Path("draft/papers/10_18_conceptual_lstm_package")
D01_DIR = PACKAGE / "deep_dive" / "D01_structure_diagnostic_20260709"
DEFAULT_CASES = D01_DIR / "tables" / "case_basin_list.csv"
DEFAULT_PANEL = D01_DIR / "tables" / "basin_attribute_panel.csv"
DEFAULT_OUT_DIR = PACKAGE / "deep_dive" / "D02_seasonal_residual_20260709"
DEFAULT_LSTM_ROOT = Path("results/18_lstm_fair_531")


def experiment_id_for_population(population: str) -> str:
    if population == "cases":
        return "D02_seasonal_residual_20260709"
    if population == "snow":
        return "D03_population_seasonal_residual_20260709"
    if population == "all":
        return "D04_full_population_seasonal_residual_20260709"
    raise ValueError(f"Unsupported population selection: {population}")


def season_labels(dates: Iterable[pd.Timestamp]) -> pd.Series:
    months = pd.DatetimeIndex(dates).month
    labels = np.select(
        [
            np.isin(months, [12, 1, 2]),
            np.isin(months, [3, 4, 5]),
            np.isin(months, [6, 7, 8]),
            np.isin(months, [9, 10, 11]),
        ],
        ["DJF", "MAM", "JJA", "SON"],
        default="unknown",
    )
    return pd.Series(labels)


def flow_group_labels(obs: pd.Series, low_q: float = 0.1, high_q: float = 0.9) -> pd.Series:
    obs_num = pd.to_numeric(obs, errors="coerce")
    low = obs_num.quantile(low_q)
    high = obs_num.quantile(high_q)
    labels = np.full(obs_num.shape[0], "mid", dtype=object)
    labels[obs_num <= low] = "low"
    labels[obs_num >= high] = "high"
    labels[obs_num.isna().to_numpy()] = "missing"
    return pd.Series(labels, index=obs.index)


def nse_or_nan(obs: np.ndarray, sim: np.ndarray) -> float:
    mask = np.isfinite(obs) & np.isfinite(sim)
    if int(mask.sum()) < 2:
        return np.nan
    obs_m = obs[mask].astype(float)
    sim_m = sim[mask].astype(float)
    denom = float(np.sum((obs_m - obs_m.mean())**2))
    if denom <= 0:
        return np.nan
    return float(1.0 - np.sum((sim_m - obs_m)**2) / denom)


def summarize_group_metrics(df: pd.DataFrame, group_cols: Sequence[str]) -> pd.DataFrame:
    rows = []
    for keys, group in df.groupby(list(group_cols), dropna=False):
        if not isinstance(keys, tuple):
            keys = (keys,)
        obs = group["obs"].to_numpy(dtype=float)
        sim = group["sim"].to_numpy(dtype=float)
        resid = sim - obs
        abs_resid = np.abs(resid)
        row = dict(zip(group_cols, keys))
        row.update({
            "n_days": int(group.shape[0]),
            "nse": nse_or_nan(obs, sim),
            "mae": float(np.nanmean(abs_resid)),
            "rmse": float(np.sqrt(np.nanmean(resid**2))),
            "bias": float(np.nanmean(resid)),
            "median_abs_residual": float(np.nanmedian(abs_resid)),
            "obs_mean": float(np.nanmean(obs)),
            "sim_mean": float(np.nanmean(sim)),
        })
        rows.append(row)
    return pd.DataFrame(rows)


def _data_vars_for_lstm(ds) -> tuple[str, str]:
    obs_vars = [name for name in ds.data_vars if name.endswith("_obs")]
    sim_vars = [name for name in ds.data_vars if name.endswith("_sim")]
    if len(obs_vars) != 1 or len(sim_vars) != 1:
        raise RuntimeError(f"Unexpected LSTM xarray variables: {list(ds.data_vars)}")
    return obs_vars[0], sim_vars[0]


def _series_from_xarray(ds, var_name: str) -> pd.Series:
    values = ds[var_name].values
    if values.ndim == 2:
        values = values[:, 0]
    return pd.Series(values.astype(float), index=pd.DatetimeIndex(ds["date"].values))


def find_lstm_result_pickles(lstm_root: Path) -> list[Path]:
    return sorted(lstm_root.glob("lstm_cudalstm_maurer_s*/test/model_epoch030/test_results.p"))


def load_lstm_ensemble_daily(basin_ids: Sequence[str], lstm_root: Path) -> pd.DataFrame:
    basin_ids = [str(b).zfill(8) for b in basin_ids]
    pickles = find_lstm_result_pickles(lstm_root)
    if not pickles:
        raise FileNotFoundError(f"No LSTM test_results.p files found under {lstm_root}")
    by_basin: dict[str, list[pd.Series]] = {b: [] for b in basin_ids}
    obs_by_basin: dict[str, pd.Series] = {}
    for path in pickles:
        with path.open("rb") as fp:
            payload = pickle.load(fp)
        for basin_id in basin_ids:
            if basin_id not in payload:
                continue
            ds = payload[basin_id]["1D"]["xr"]
            obs_var, sim_var = _data_vars_for_lstm(ds)
            sim = _series_from_xarray(ds, sim_var)
            obs = _series_from_xarray(ds, obs_var)
            by_basin[basin_id].append(sim)
            obs_by_basin.setdefault(basin_id, obs)
    rows = []
    for basin_id, sims in by_basin.items():
        if not sims:
            continue
        sim_df = pd.concat(sims, axis=1)
        sim_ens = sim_df.mean(axis=1)
        obs = obs_by_basin[basin_id].reindex(sim_ens.index)
        for date, sim_value in sim_ens.items():
            rows.append({
                "basin_id": basin_id,
                "date": date,
                "model": "LSTM_ensemble_8seed",
                "obs": float(obs.loc[date]),
                "sim": float(sim_value),
                "source": "lstm_test_results_p_8seed_mean",
                "n_lstm_seeds": len(sims),
            })
    return pd.DataFrame(rows)


def replay_conceptual_daily(basin_ids: Sequence[str], models: Sequence[str], data_root: str, forcing: str,
                            pet_method: str) -> pd.DataFrame:
    specs = _build_model_specs()
    summaries = {model: _read_summary(DEFAULT_SUMMARIES[model]) for model in models}
    eval_period = repro_split_periods()["evaluation"]
    rows = []
    for model in models:
        spec = specs[model]
        summary = summaries[model]
        eval_rows = summary[(summary["period"].astype(str) == "evaluation") &
                            (summary["run_status"].astype(str) == "success")].set_index("basin_id", drop=False)
        for basin_id in [str(b).zfill(8) for b in basin_ids]:
            if basin_id not in eval_rows.index:
                continue
            row = eval_rows.loc[basin_id]
            if isinstance(row, pd.DataFrame):
                row = row.iloc[0]
            params = _extract_params(row, spec.param_names)
            initial_state = _state_from_saved_row(spec, row)
            forcing_eval, obs_eval, _ = load_camels_basin(
                basin_id,
                data_root=data_root,
                start_date=eval_period[0],
                end_date=eval_period[1],
                forcing=forcing,
                pet_method=pet_method,
                keep_obs_nan_days=True,
            )
            rain_eval, pet_eval, temp_eval = _forcing_arrays(forcing_eval, spec.fill_nan_forcing)
            q_eval, _ = spec.simulate(rain_eval, pet_eval, temp_eval, params, initial_state)
            for date, sim_value in pd.Series(q_eval, index=obs_eval.index).items():
                rows.append({
                    "basin_id": basin_id,
                    "date": pd.Timestamp(date),
                    "model": model,
                    "obs": float(obs_eval.loc[date]),
                    "sim": float(sim_value),
                    "source": "saved_parameter_replay_saved_state",
                    "n_lstm_seeds": np.nan,
                })
            print(f"replayed {model} {basin_id}", flush=True)
    return pd.DataFrame(rows)


def _apply_max_basins(df: pd.DataFrame, max_basins: int) -> pd.DataFrame:
    if max_basins is None or max_basins <= 0:
        return df.copy()
    return df.head(max_basins).copy()


def load_case_basins(case_path: Path, max_basins: int) -> pd.DataFrame:
    cases = pd.read_csv(case_path, dtype={"basin_id": str})
    cases["basin_id"] = cases["basin_id"].astype(str).str.zfill(8)
    selected = _apply_max_basins(cases.drop_duplicates("basin_id"), max_basins)
    if "case_type" not in selected.columns:
        selected["case_type"] = "legacy_case_list"
    if "case_score" not in selected.columns:
        selected["case_score"] = np.nan
    if "case_reason" not in selected.columns:
        selected["case_reason"] = "D01 representative case list"
    return selected


def load_population_basins(panel_path: Path, population: str, max_basins: int) -> pd.DataFrame:
    panel = pd.read_csv(panel_path, dtype={"basin_id": str})
    panel["basin_id"] = panel["basin_id"].astype(str).str.zfill(8)
    if population == "snow":
        selected = panel[panel["regime"].astype(str) == "snow-dominated"].copy()
        case_type = "population_snow"
        case_reason = "All D01 basins labeled snow-dominated by the regime diagnostic."
    elif population == "all":
        selected = panel.copy()
        case_type = "population_all"
        case_reason = "All D01 basins with conceptual and LSTM benchmark scores."
    else:
        raise ValueError(f"Unsupported population selection: {population}")

    selected = selected.drop_duplicates("basin_id")
    selected["case_type"] = case_type
    selected["case_score"] = selected.get("clim_frac_snow", pd.Series(np.nan, index=selected.index))
    selected["case_reason"] = case_reason
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
    available = [col for col in keep_cols if col in selected.columns]
    return _apply_max_basins(selected[available], max_basins)


def select_basin_metadata(case_path: Path, panel_path: Path, population: str, max_basins: int) -> pd.DataFrame:
    if population == "cases":
        return load_case_basins(case_path, max_basins=max_basins)
    return load_population_basins(panel_path, population=population, max_basins=max_basins)


def add_labels(daily: pd.DataFrame) -> pd.DataFrame:
    df = daily.copy()
    df["date"] = pd.to_datetime(df["date"])
    df["season"] = season_labels(df["date"]).to_numpy()
    flow_labels = []
    for _, group in df.groupby("basin_id", sort=False):
        basin_obs = group.drop_duplicates("date").set_index("date")["obs"].sort_index()
        labels = flow_group_labels(basin_obs)
        flow_labels.append(group["date"].map(labels).rename("flow_group"))
    df["flow_group"] = pd.concat(flow_labels).sort_index()
    df["residual"] = df["sim"] - df["obs"]
    df["abs_residual"] = df["residual"].abs()
    return df


def conceptual_vs_lstm_delta(summary: pd.DataFrame, group_cols: Sequence[str]) -> pd.DataFrame:
    pivot = summary.pivot_table(index=list(group_cols), columns="model", values=["mae", "nse"], aggfunc="first")
    rows = []
    for idx, row in pivot.iterrows():
        if not isinstance(idx, tuple):
            idx = (idx,)
        base = dict(zip(group_cols, idx))
        lstm_mae = row.get(("mae", "LSTM_ensemble_8seed"), np.nan)
        lstm_nse = row.get(("nse", "LSTM_ensemble_8seed"), np.nan)
        for model in ["GR4J", "XAJ", "HBV"]:
            model_mae = row.get(("mae", model), np.nan)
            model_nse = row.get(("nse", model), np.nan)
            item = base.copy()
            item.update({
                "conceptual_model": model,
                "mae_minus_lstm": float(model_mae - lstm_mae) if pd.notna(model_mae) and pd.notna(lstm_mae) else np.nan,
                "nse_minus_lstm": float(model_nse - lstm_nse) if pd.notna(model_nse) and pd.notna(lstm_nse) else np.nan,
                "conceptual_mae": float(model_mae) if pd.notna(model_mae) else np.nan,
                "lstm_mae": float(lstm_mae) if pd.notna(lstm_mae) else np.nan,
                "conceptual_nse": float(model_nse) if pd.notna(model_nse) else np.nan,
                "lstm_nse": float(lstm_nse) if pd.notna(lstm_nse) else np.nan,
            })
            rows.append(item)
    return pd.DataFrame(rows)


def _finite_array(values: pd.Series) -> np.ndarray:
    arr = pd.to_numeric(values, errors="coerce").to_numpy(dtype=float)
    return arr[np.isfinite(arr)]


def _bootstrap_median_ci(values: pd.Series, n_boot: int = 2000) -> tuple[float, float]:
    arr = _finite_array(values)
    if arr.size == 0:
        return np.nan, np.nan
    if arr.size == 1:
        median = float(np.median(arr))
        return median, median
    rng = np.random.default_rng(20260709 + int(arr.size))
    draws = rng.choice(arr, size=(n_boot, arr.size), replace=True)
    medians = np.median(draws, axis=1)
    low, high = np.percentile(medians, [2.5, 97.5])
    return float(low), float(high)


def _wilcoxon_p(values: pd.Series, alternative: str) -> float:
    arr = _finite_array(values)
    arr = arr[arr != 0]
    if arr.size == 0:
        return np.nan
    try:
        return float(stats.wilcoxon(arr, alternative=alternative).pvalue)
    except ValueError:
        return np.nan


def aggregate_delta(delta: pd.DataFrame, group_cols: Sequence[str]) -> pd.DataFrame:
    rows = []
    for keys, group in delta.groupby(list(group_cols), dropna=False):
        if not isinstance(keys, tuple):
            keys = (keys,)
        mae_low, mae_high = _bootstrap_median_ci(group["mae_minus_lstm"])
        nse_low, nse_high = _bootstrap_median_ci(group["nse_minus_lstm"])
        row = dict(zip(group_cols, keys))
        row.update({
            "n_cases": int(group["basin_id"].nunique()) if "basin_id" in group else int(group.shape[0]),
            "median_mae_minus_lstm": float(group["mae_minus_lstm"].median()),
            "mean_mae_minus_lstm": float(group["mae_minus_lstm"].mean()),
            "median_mae_minus_lstm_ci95_low": mae_low,
            "median_mae_minus_lstm_ci95_high": mae_high,
            "n_positive_mae_minus_lstm": int((group["mae_minus_lstm"] > 0).sum()),
            "wilcoxon_p_mae_greater_than_zero": _wilcoxon_p(group["mae_minus_lstm"], alternative="greater"),
            "median_nse_minus_lstm": float(group["nse_minus_lstm"].median()),
            "median_nse_minus_lstm_ci95_low": nse_low,
            "median_nse_minus_lstm_ci95_high": nse_high,
            "n_negative_nse_minus_lstm": int((group["nse_minus_lstm"] < 0).sum()),
            "wilcoxon_p_nse_less_than_zero": _wilcoxon_p(group["nse_minus_lstm"], alternative="less"),
            "frac_conceptual_lower_mae_than_lstm": float((group["mae_minus_lstm"] < 0).mean()),
        })
        rows.append(row)
    return pd.DataFrame(rows)


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


def write_memos(out_dir: Path, selected_cases: pd.DataFrame, seasonal_delta: pd.DataFrame,
                aggregate: pd.DataFrame, flow_aggregate: pd.DataFrame, population: str) -> None:
    snow_mam = aggregate[(aggregate["regime"] == "snow-dominated") & (aggregate["season"] == "MAM")]
    top = seasonal_delta.sort_values("mae_minus_lstm", ascending=False).head(12)
    if population == "cases":
        title = "D02 Seasonal Residual Deep Dive"
        purpose = "move from basin-level attribute correlations to process-facing seasonal residual checks on D01 representative basins."
        selection_header = "Selected Cases"
        result_risk = "selected cases are deliberately enriched for interesting failures, so aggregate seasonal numbers are diagnostic case evidence, not population-wide estimates."
        goal_check = "If seasonal/flow residuals align with the D01 snow/aridity signals, the paper can claim a concrete diagnostic workflow. If they do not, the D01 attribute result should remain exploratory."
    else:
        title = "D03 Population Seasonal Residual Diagnostic"
        purpose = "test whether the D02 seasonal/high-flow residual pattern holds beyond selected cases."
        selection_header = f"Population Selection: {population}"
        result_risk = "this is a post-hoc population residual diagnostic for the selected basin population, not a Track-0 challenger evaluation or causal proof."
        goal_check = "If population residuals align with D01 snow/topography/aridity signals, the mechanism-facing diagnostic claim is stronger. If they do not, restrict D02 to illustrative cases and center the paper on D01 attribute diagnostics."
    text = [
        f"# {title}",
        "",
        f"Purpose: {purpose}",
        "",
        f"## {selection_header}",
        "",
        _to_md_table(selected_cases[["case_type", "basin_id", "regime", "conceptual_winner", "case_score"]], max_rows=30),
        "",
        "## Snow-Dominated MAM Check",
        "",
        _to_md_table(snow_mam, max_rows=20),
        "",
        "## Largest Conceptual MAE Penalties Relative To LSTM",
        "",
        _to_md_table(top[[
            "basin_id",
            "regime",
            "season",
            "conceptual_model",
            "mae_minus_lstm",
            "nse_minus_lstm",
            "conceptual_mae",
            "lstm_mae",
        ]], max_rows=12),
        "",
        "## Flow Group Aggregate",
        "",
        _to_md_table(flow_aggregate, max_rows=30),
        "",
        "## Independent Review",
        "",
        "- Code risk: this analysis reads observed daily discharge through saved LSTM test artifacts and CAMELS loading, so it is a post-hoc residual diagnosis, not a Track-0 challenger input.",
        f"- Result risk: {result_risk}",
        "- Verification: conceptual simulations use saved-state replay paths already covered by the R01 full 531 replay audit; LSTM daily simulations are averaged across the eight saved test-result pickles.",
        "",
        "## Goal Check",
        "",
        goal_check,
    ]
    (out_dir / "README.md").write_text("\n".join(text) + "\n", encoding="utf-8")


def run(case_path: Path, panel_path: Path, out_dir: Path, lstm_root: Path, data_root: str, forcing: str,
        pet_method: str, max_basins: int, population: str) -> dict:
    out_dir.mkdir(parents=True, exist_ok=True)
    tables = out_dir / "tables"
    tables.mkdir(exist_ok=True)

    selected_cases = select_basin_metadata(case_path, panel_path, population=population, max_basins=max_basins)
    basin_ids = selected_cases["basin_id"].tolist()
    lstm_daily = load_lstm_ensemble_daily(basin_ids, lstm_root)
    conceptual_daily = replay_conceptual_daily(
        basin_ids,
        models=["GR4J", "XAJ", "HBV"],
        data_root=data_root,
        forcing=forcing,
        pet_method=pet_method,
    )
    daily = pd.concat([conceptual_daily, lstm_daily], ignore_index=True)
    daily = add_labels(daily)
    daily = daily.merge(selected_cases[["basin_id", "case_type", "regime", "conceptual_winner"]], on="basin_id", how="left")

    seasonal = summarize_group_metrics(daily, group_cols=["basin_id", "regime", "case_type", "model", "season"])
    flow = summarize_group_metrics(daily, group_cols=["basin_id", "regime", "case_type", "model", "flow_group"])
    seasonal_delta = conceptual_vs_lstm_delta(seasonal, group_cols=["basin_id", "regime", "case_type", "season"])
    flow_delta = conceptual_vs_lstm_delta(flow, group_cols=["basin_id", "regime", "case_type", "flow_group"])
    seasonal_aggregate = aggregate_delta(seasonal_delta, group_cols=["regime", "season", "conceptual_model"])
    flow_aggregate = aggregate_delta(flow_delta, group_cols=["regime", "flow_group", "conceptual_model"])

    write_table(selected_cases, tables / "selected_cases.csv", tables / "selected_cases.md")
    write_table(seasonal, tables / "seasonal_model_metrics.csv", tables / "seasonal_model_metrics.md", max_md_rows=80)
    write_table(flow, tables / "flow_group_model_metrics.csv", tables / "flow_group_model_metrics.md", max_md_rows=80)
    write_table(seasonal_delta, tables / "conceptual_vs_lstm_by_case_season.csv",
                tables / "conceptual_vs_lstm_by_case_season.md", max_md_rows=80)
    write_table(flow_delta, tables / "conceptual_vs_lstm_by_case_flow_group.csv",
                tables / "conceptual_vs_lstm_by_case_flow_group.md", max_md_rows=80)
    write_table(seasonal_aggregate, tables / "seasonal_delta_aggregate.csv",
                tables / "seasonal_delta_aggregate.md")
    write_table(flow_aggregate, tables / "flow_delta_aggregate.csv", tables / "flow_delta_aggregate.md")
    daily.to_csv(tables / "daily_residuals_selected_cases.csv.gz", index=False, compression="gzip")

    write_memos(out_dir, selected_cases, seasonal_delta, seasonal_aggregate, flow_aggregate, population=population)
    manifest = {
        "experiment_id": experiment_id_for_population(population),
        "created_by": "src/lstm_fair_531/scripts/seasonal_residual_deep_dive.py",
        "purpose": (
            "Hydrograph-level seasonal residual check for representative D01 diagnostic cases."
            if population == "cases" else
            "Population seasonal/high-flow residual diagnostic for D01 basin populations."
        ),
        "sources": {
            "case_list": str(case_path),
            "basin_attribute_panel": str(panel_path),
            "lstm_root": str(lstm_root),
            "conceptual_summary_files": {k: str(v) for k, v in DEFAULT_SUMMARIES.items()},
            "data_root": data_root,
            "forcing": forcing,
            "pet_method": pet_method,
        },
        "population": population,
        "n_selected_basins": int(len(basin_ids)),
        "outputs": sorted(path.name for path in tables.glob("*.csv")) + ["daily_residuals_selected_cases.csv.gz"],
        "guardrails": [
            "Post-hoc residual diagnosis only; not a Track-0 challenger submission.",
            "Conceptual models are replayed from saved parameters, not recalibrated.",
            "LSTM daily series uses the mean of saved eight seed predictions.",
            (
                "Selected cases are diagnostic examples, not population-wide estimates."
                if population == "cases" else
                "Population residuals are post-hoc diagnostics, not causal proof or model-selection evidence."
            ),
        ],
    }
    (out_dir / "MANIFEST.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    return manifest


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", type=Path, default=DEFAULT_CASES)
    parser.add_argument("--panel", type=Path, default=DEFAULT_PANEL)
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT_DIR)
    parser.add_argument("--lstm-root", type=Path, default=DEFAULT_LSTM_ROOT)
    parser.add_argument("--data-root", default="data/camels_us")
    parser.add_argument("--forcing", default=REPRO_FORCING)
    parser.add_argument("--pet-method", choices=["oudin", "priestley_taylor"], default="priestley_taylor")
    parser.add_argument("--max-basins", type=int, default=24)
    parser.add_argument("--population", choices=["cases", "snow", "all"], default="cases")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    manifest = run(
        case_path=args.cases,
        panel_path=args.panel,
        out_dir=args.out_dir,
        lstm_root=args.lstm_root,
        data_root=args.data_root,
        forcing=args.forcing,
        pet_method=args.pet_method,
        max_basins=args.max_basins,
        population=args.population,
    )
    print(json.dumps({"out_dir": str(args.out_dir), "n_selected_basins": manifest["n_selected_basins"]},
                     indent=2,
                     ensure_ascii=False))


if __name__ == "__main__":
    main()
