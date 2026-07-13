import numpy as np
import pandas as pd

from src.lstm_fair_531.scripts.seasonal_residual_deep_dive import (
    aggregate_delta,
    experiment_id_for_population,
    flow_group_labels,
    load_population_basins,
    nse_or_nan,
    select_basin_metadata,
    season_labels,
    summarize_group_metrics,
)


def test_season_labels_use_hydrologic_quarters():
    dates = pd.to_datetime(["1990-01-15", "1990-04-01", "1990-07-01", "1990-10-01"])

    assert season_labels(dates).tolist() == ["DJF", "MAM", "JJA", "SON"]


def test_flow_group_labels_mark_low_mid_high_by_observed_quantiles():
    obs = pd.Series([0, 1, 2, 3, 4, 5], dtype=float)

    labels = flow_group_labels(obs, low_q=0.2, high_q=0.8)

    assert labels.tolist() == ["low", "low", "mid", "mid", "high", "high"]


def test_nse_or_nan_returns_nan_for_constant_observations():
    assert np.isnan(nse_or_nan(np.array([1.0, 1.0]), np.array([1.0, 1.1])))
    assert nse_or_nan(np.array([1.0, 2.0, 3.0]), np.array([1.0, 2.0, 2.0])) < 1.0


def test_summarize_group_metrics_reports_model_skill_by_group():
    df = pd.DataFrame({
        "basin_id": ["b"] * 6,
        "model": ["M"] * 6,
        "obs": [1, 2, 3, 4, 5, 6],
        "sim": [1, 2, 2, 4, 4, 6],
        "season": ["DJF", "DJF", "MAM", "MAM", "MAM", "MAM"],
        "flow_group": ["low", "mid", "mid", "mid", "high", "high"],
    })

    summary = summarize_group_metrics(df, group_cols=["basin_id", "model", "season"])

    assert set(summary["season"]) == {"DJF", "MAM"}
    mam = summary[summary["season"] == "MAM"].iloc[0]
    assert mam["n_days"] == 4
    assert mam["mae"] == 0.5


def test_load_population_basins_selects_snow_regime_without_case_enrichment(tmp_path):
    panel = pd.DataFrame({
        "basin_id": ["123", "00000002", "45"],
        "regime": ["snow-dominated", "humid", "snow-dominated"],
        "conceptual_winner": ["HBV", "GR4J", "XAJ"],
        "clim_frac_snow": [0.3, 0.0, 0.2],
    })
    path = tmp_path / "panel.csv"
    panel.to_csv(path, index=False)

    selected = load_population_basins(path, population="snow", max_basins=0)

    assert selected["basin_id"].tolist() == ["00000123", "00000045"]
    assert selected["case_type"].tolist() == ["population_snow", "population_snow"]
    assert selected["case_reason"].str.contains("snow-dominated").all()


def test_select_basin_metadata_can_use_panel_all_or_legacy_case_list(tmp_path):
    cases = pd.DataFrame({
        "basin_id": ["1", "2"],
        "regime": ["humid", "snow-dominated"],
        "conceptual_winner": ["GR4J", "HBV"],
        "case_score": [0.1, 0.2],
    })
    case_path = tmp_path / "cases.csv"
    cases.to_csv(case_path, index=False)
    panel_path = tmp_path / "missing_panel.csv"

    legacy = select_basin_metadata(case_path, panel_path, population="cases", max_basins=1)

    assert legacy["basin_id"].tolist() == ["00000001"]
    assert legacy["case_type"].tolist() == ["legacy_case_list"]


def test_aggregate_delta_reports_pairwise_inference_columns():
    delta = pd.DataFrame({
        "basin_id": ["a", "b", "c", "a", "b", "c"],
        "regime": ["snow"] * 6,
        "season": ["MAM"] * 6,
        "conceptual_model": ["GR4J", "GR4J", "GR4J", "HBV", "HBV", "HBV"],
        "mae_minus_lstm": [0.2, 0.4, 0.6, -0.1, 0.1, 0.3],
        "nse_minus_lstm": [-0.2, -0.4, -0.6, 0.1, -0.1, -0.3],
    })

    summary = aggregate_delta(delta, group_cols=["regime", "season", "conceptual_model"])

    gr4j = summary[summary["conceptual_model"] == "GR4J"].iloc[0]
    assert gr4j["median_mae_minus_lstm"] == 0.4
    assert gr4j["n_positive_mae_minus_lstm"] == 3
    assert "median_mae_minus_lstm_ci95_low" in summary.columns
    assert "wilcoxon_p_mae_greater_than_zero" in summary.columns


def test_experiment_id_tracks_population_scope():
    assert experiment_id_for_population("cases") == "D02_seasonal_residual_20260709"
    assert experiment_id_for_population("snow") == "D03_population_seasonal_residual_20260709"
    assert experiment_id_for_population("all") == "D04_full_population_seasonal_residual_20260709"
