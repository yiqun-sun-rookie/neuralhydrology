import pandas as pd
import pytest

from src.lstm_fair_531.scripts.lstm_advantage_decomposition import (
    build_advantage_targets,
    summarize_advantage_concentration,
)


def test_build_advantage_targets_marks_shared_lstm_advantage():
    delta = pd.DataFrame({
        "basin_id": ["1", "1", "1", "2", "2", "2"],
        "regime": ["snow"] * 6,
        "season": ["MAM"] * 6,
        "conceptual_model": ["GR4J", "XAJ", "HBV"] * 2,
        "mae_minus_lstm": [0.4, 0.7, 0.5, -0.1, 0.2, 0.1],
        "nse_minus_lstm": [-0.4, -0.7, -0.5, 0.1, -0.2, -0.1],
    })

    targets = build_advantage_targets(delta, context_col="season")

    shared = targets[targets["basin_id"] == "00000001"].iloc[0]
    mixed = targets[targets["basin_id"] == "00000002"].iloc[0]
    assert shared["best_conceptual_mae_minus_lstm"] == 0.4
    assert shared["conceptual_mae_spread"] == pytest.approx(0.3)
    assert bool(shared["all_conceptual_worse_mae"]) is True
    assert bool(mixed["all_conceptual_worse_mae"]) is False
    assert bool(mixed["any_conceptual_lower_mae"]) is True


def test_build_advantage_targets_keeps_mae_context_when_nse_is_missing():
    delta = pd.DataFrame({
        "basin_id": ["3", "3", "3"],
        "regime": ["arid"] * 3,
        "flow_group": ["low"] * 3,
        "conceptual_model": ["GR4J", "XAJ", "HBV"],
        "mae_minus_lstm": [0.2, 0.1, 0.3],
        "nse_minus_lstm": [float("nan"), float("nan"), float("nan")],
    })

    targets = build_advantage_targets(delta, context_col="flow_group")

    assert len(targets) == 1
    row = targets.iloc[0]
    assert row["basin_id"] == "00000003"
    assert row["best_conceptual_mae_minus_lstm"] == 0.1
    assert pd.isna(row["best_conceptual_nse_minus_lstm"])
    assert bool(row["all_conceptual_worse_mae"]) is True


def test_summarize_advantage_concentration_reports_overrepresented_gap_contexts():
    targets = pd.DataFrame({
        "basin_id": [f"{idx:08d}" for idx in range(1, 7)],
        "regime": ["snow", "snow", "snow", "humid", "humid", "humid"],
        "season": ["MAM", "MAM", "DJF", "MAM", "MAM", "DJF"],
        "best_conceptual_mae_minus_lstm": [2.0, 1.0, 0.0, 0.5, -0.2, 0.5],
        "median_conceptual_mae_minus_lstm": [2.2, 1.2, 0.1, 0.7, 0.1, 0.6],
        "conceptual_mae_spread": [0.2, 0.4, 0.1, 0.3, 0.2, 0.1],
        "best_conceptual_nse_minus_lstm": [-2.0, -1.0, 0.0, -0.5, 0.2, -0.5],
        "conceptual_nse_spread": [0.2, 0.4, 0.1, 0.3, 0.2, 0.1],
        "all_conceptual_worse_mae": [True, True, False, True, False, True],
        "any_conceptual_lower_mae": [False, False, False, False, True, False],
    })

    summary = summarize_advantage_concentration(targets, context_col="season")

    snow_mam = summary[(summary["regime"] == "snow") & (summary["season"] == "MAM")].iloc[0]
    assert snow_mam["n_contexts"] == 2
    assert snow_mam["shared_failure_rate"] == 1.0
    assert snow_mam["positive_best_gap_share"] == 0.75
    assert snow_mam["context_share"] == 2 / 6
    assert snow_mam["gap_concentration_ratio"] == 2.25
    assert snow_mam["ceiling_dominance_index"] > 0.8
