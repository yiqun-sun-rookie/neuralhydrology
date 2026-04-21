import pandas as pd

from src.xaj_global_pilot.reporting import (
    summarize_ablation_deltas,
    summarize_by_regime,
    summarize_win_counts,
)


def test_summarize_by_regime_emits_required_columns():
    rows = pd.DataFrame(
        [
            {
                "basin_id": "b1",
                "regime": "humid",
                "model": "xaj",
                "period": "test",
                "nse": 0.5,
                "kge": 0.4,
                "bias": 0.1,
                "peak_bias": 0.2,
                "lowflow_bias": -0.1,
                "run_status": "success",
                "error_message": "",
            },
            {
                "basin_id": "b2",
                "regime": "humid",
                "model": "hbv",
                "period": "test",
                "nse": 0.7,
                "kge": 0.6,
                "bias": 0.0,
                "peak_bias": 0.1,
                "lowflow_bias": -0.2,
                "run_status": "success",
                "error_message": "",
            },
            {
                "basin_id": "b3",
                "regime": "humid",
                "model": "hbv",
                "period": "test",
                "nse": 0.6,
                "kge": 0.5,
                "bias": -0.1,
                "peak_bias": 0.0,
                "lowflow_bias": -0.3,
                "run_status": "failed",
                "error_message": "boom",
            },
        ]
    )

    summary = summarize_by_regime(rows)

    assert "median_nse" in summary.columns
    assert "n_failed" in summary.columns
    assert "delta_nse_vs_xaj" in summary.columns
    humid_hbv = summary[(summary["regime"] == "humid") & (summary["model"] == "hbv")].iloc[0]
    assert humid_hbv["n_basins"] == 2
    assert humid_hbv["n_failed"] == 1
    assert humid_hbv["delta_nse_vs_xaj"] == 0.15


def test_summarize_by_regime_handles_all_failed_rows():
    rows = pd.DataFrame(
        [
            {
                "basin_id": "b1",
                "regime": "snow-dominated",
                "model": "xaj",
                "period": "test",
                "nse": pd.NA,
                "kge": pd.NA,
                "bias": pd.NA,
                "peak_bias": pd.NA,
                "lowflow_bias": pd.NA,
                "run_status": "failed",
                "error_message": "boom",
            }
        ]
    )

    summary = summarize_by_regime(rows)

    assert len(summary) == 1
    assert summary.loc[0, "n_failed"] == 1
    assert pd.isna(summary.loc[0, "delta_nse_vs_xaj"])


def test_summarize_win_counts_counts_basin_level_winners():
    rows = pd.DataFrame(
        [
            {"basin_id": "b1", "model": "xaj_pdd", "nse": 0.6, "run_status": "success"},
            {"basin_id": "b1", "model": "hbv", "nse": 0.5, "run_status": "success"},
            {"basin_id": "b1", "model": "gr4j_pdd", "nse": 0.4, "run_status": "success"},
            {"basin_id": "b2", "model": "xaj_pdd", "nse": 0.2, "run_status": "success"},
            {"basin_id": "b2", "model": "hbv", "nse": 0.7, "run_status": "success"},
            {"basin_id": "b2", "model": "gr4j_pdd", "nse": 0.1, "run_status": "success"},
        ]
    )

    win_counts = summarize_win_counts(rows)

    assert tuple(win_counts["model"]) == ("hbv", "xaj_pdd")
    assert tuple(win_counts["n_best_basins"]) == (1, 1)


def test_summarize_ablation_deltas_compares_pdd_variants_to_bare_models():
    rows = pd.DataFrame(
        [
            {"basin_id": "b1", "model": "xaj", "nse": 0.1, "kge": 0.2, "run_status": "success"},
            {"basin_id": "b1", "model": "xaj_pdd", "nse": 0.6, "kge": 0.7, "run_status": "success"},
            {"basin_id": "b1", "model": "gr4j", "nse": 0.3, "kge": 0.4, "run_status": "success"},
            {"basin_id": "b1", "model": "gr4j_pdd", "nse": 0.5, "kge": 0.6, "run_status": "success"},
        ]
    )

    deltas = summarize_ablation_deltas(rows)

    assert set(deltas["comparison"]) == {"gr4j_pdd_vs_gr4j", "xaj_pdd_vs_xaj"}
    xaj_delta = deltas[deltas["comparison"] == "xaj_pdd_vs_xaj"].iloc[0]
    assert xaj_delta["delta_nse"] == 0.5
    assert xaj_delta["delta_kge"] == 0.5
