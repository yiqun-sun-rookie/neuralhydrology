import pandas as pd


def summarize_overall_metrics(rows: pd.DataFrame) -> pd.DataFrame:
    if rows.empty:
        return pd.DataFrame(
            columns=[
                "model",
                "family",
                "parameter_count",
                "n_basins",
                "n_success",
                "n_failed",
                "median_nse",
                "mean_nse",
                "median_kge",
                "mean_kge",
            ]
        )

    grouped = (
        rows.groupby(["model", "family", "parameter_count"], dropna=False)
        .apply(_summarize_group, include_groups=False)
        .reset_index()
    )
    return grouped[
        [
            "model",
            "family",
            "parameter_count",
            "n_basins",
            "n_success",
            "n_failed",
            "median_nse",
            "mean_nse",
            "median_kge",
            "mean_kge",
        ]
    ].sort_values(["median_nse", "model"], ascending=[False, True]).reset_index(drop=True)


def summarize_best_model_by_basin(rows: pd.DataFrame) -> pd.DataFrame:
    if rows.empty:
        return pd.DataFrame(columns=["basin_id", "best_model", "best_nse"])

    success_rows = rows[rows["run_status"] == "success"].copy()
    if success_rows.empty:
        return pd.DataFrame(columns=["basin_id", "best_model", "best_nse"])

    success_rows["nse_num"] = pd.to_numeric(success_rows["nse"], errors="coerce")
    winners = (
        success_rows.sort_values(["basin_id", "nse_num", "model"], ascending=[True, False, True])
        .groupby("basin_id", as_index=False)
        .first()
        .rename(columns={"model": "best_model", "nse_num": "best_nse"})
    )
    winners["basin_id"] = winners["basin_id"].astype(str).str.zfill(8)
    return winners[["basin_id", "best_model", "best_nse"]].sort_values("basin_id").reset_index(drop=True)


def summarize_by_regime(rows: pd.DataFrame) -> pd.DataFrame:
    if rows.empty:
        return pd.DataFrame(
            columns=[
                "regime",
                "model",
                "n_basins",
                "n_success",
                "n_failed",
                "median_nse",
                "mean_nse",
                "median_kge",
                "mean_kge",
                "median_bias",
                "mean_bias",
                "median_peak_bias",
                "median_lowflow_bias",
                "delta_nse_vs_xaj",
                "delta_kge_vs_xaj",
                "iqr_nse",
                "iqr_kge",
            ]
        )

    grouped = (
        rows.groupby(["regime", "model"], dropna=False)
        .apply(_summarize_group, include_groups=False)
        .reset_index()
    )

    xaj_baseline = grouped[grouped["model"] == "xaj"][["regime", "median_nse", "median_kge"]].rename(
        columns={
            "median_nse": "xaj_median_nse",
            "median_kge": "xaj_median_kge",
        }
    )
    summary = grouped.merge(xaj_baseline, on="regime", how="left")
    delta_nse = pd.to_numeric(summary["median_nse"], errors="coerce") - pd.to_numeric(
        summary["xaj_median_nse"], errors="coerce"
    )
    delta_kge = pd.to_numeric(summary["median_kge"], errors="coerce") - pd.to_numeric(
        summary["xaj_median_kge"], errors="coerce"
    )
    summary["delta_nse_vs_xaj"] = delta_nse.round(6)
    summary["delta_kge_vs_xaj"] = delta_kge.round(6)
    return summary.drop(columns=["xaj_median_nse", "xaj_median_kge"])


def summarize_win_counts(rows: pd.DataFrame) -> pd.DataFrame:
    if rows.empty:
        return pd.DataFrame(columns=["model", "n_best_basins"])

    success_rows = rows[rows["run_status"] == "success"].copy()
    if success_rows.empty:
        return pd.DataFrame(columns=["model", "n_best_basins"])

    success_rows["nse_num"] = pd.to_numeric(success_rows["nse"], errors="coerce")
    winners = (
        success_rows.sort_values(["basin_id", "nse_num", "model"], ascending=[True, False, True])
        .groupby("basin_id", as_index=False)
        .first()
    )
    counts = (
        winners.groupby("model", as_index=False)
        .size()
        .rename(columns={"size": "n_best_basins"})
        .sort_values(["n_best_basins", "model"], ascending=[False, True])
        .reset_index(drop=True)
    )
    return counts


def summarize_ablation_deltas(rows: pd.DataFrame) -> pd.DataFrame:
    comparisons = [
        ("xaj_pdd", "xaj", "xaj_pdd_vs_xaj"),
        ("gr4j_pdd", "gr4j", "gr4j_pdd_vs_gr4j"),
    ]
    results = []
    for with_snow, bare, label in comparisons:
        with_snow_rows = rows[rows["model"] == with_snow][["basin_id", "nse", "kge"]].rename(
            columns={"nse": "with_snow_nse", "kge": "with_snow_kge"}
        )
        bare_rows = rows[rows["model"] == bare][["basin_id", "nse", "kge"]].rename(
            columns={"nse": "bare_nse", "kge": "bare_kge"}
        )
        merged = with_snow_rows.merge(bare_rows, on="basin_id", how="inner")
        if merged.empty:
            continue
        delta_nse = pd.to_numeric(merged["with_snow_nse"], errors="coerce") - pd.to_numeric(
            merged["bare_nse"], errors="coerce"
        )
        delta_kge = pd.to_numeric(merged["with_snow_kge"], errors="coerce") - pd.to_numeric(
            merged["bare_kge"], errors="coerce"
        )
        results.append(
            {
                "comparison": label,
                "n_basins": int(len(merged)),
                "delta_nse": round(float(delta_nse.mean()), 6),
                "delta_kge": round(float(delta_kge.mean()), 6),
            }
        )

    return pd.DataFrame(results, columns=["comparison", "n_basins", "delta_nse", "delta_kge"])


def _summarize_group(group: pd.DataFrame) -> pd.Series:
    return pd.Series(
        {
            "n_basins": int(len(group)),
            "n_success": int((group["run_status"] == "success").sum()),
            "n_failed": int((group["run_status"] != "success").sum()),
            "median_nse": _safe_stat(group["nse"], "median"),
            "mean_nse": _safe_stat(group["nse"], "mean"),
            "median_kge": _safe_stat(group["kge"], "median"),
            "mean_kge": _safe_stat(group["kge"], "mean"),
            "median_bias": _safe_stat(group["bias"], "median"),
            "mean_bias": _safe_stat(group["bias"], "mean"),
            "median_peak_bias": _safe_stat(group["peak_bias"], "median"),
            "median_lowflow_bias": _safe_stat(group["lowflow_bias"], "median"),
            "iqr_nse": _safe_iqr(group["nse"]),
            "iqr_kge": _safe_iqr(group["kge"]),
        }
    )


def _safe_stat(series: pd.Series, method: str):
    cleaned = pd.to_numeric(series, errors="coerce").dropna()
    if cleaned.empty:
        return pd.NA
    value = getattr(cleaned, method)()
    return round(float(value), 6)


def _safe_iqr(series: pd.Series):
    cleaned = pd.to_numeric(series, errors="coerce").dropna()
    if cleaned.empty:
        return pd.NA
    value = cleaned.quantile(0.75) - cleaned.quantile(0.25)
    return round(float(value), 6)
