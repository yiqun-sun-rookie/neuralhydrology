from pathlib import Path

import numpy as np
import pandas as pd

from src.lstm_fair_531.scripts.deep_dive_structure_diagnostics import (
    apply_bh_fdr,
    build_case_selection,
    read_camels_attributes,
    summarize_spearman_relationships,
)


def test_read_camels_attributes_pads_basin_ids_and_tags_source(tmp_path: Path):
    attr_file = tmp_path / "camels_clim.txt"
    attr_file.write_text(
        "gauge_id;p_mean;frac_snow;high_prec_timing\n"
        "123;2.5;0.20;mam\n"
        "01022500;3.0;0.10;son\n",
        encoding="utf-8",
    )

    attrs = read_camels_attributes({"clim": attr_file})

    assert attrs.index.tolist() == ["00000123", "01022500"]
    assert attrs.loc["00000123", "clim_p_mean"] == 2.5
    assert attrs.loc["01022500", "clim_high_prec_timing"] == "son"
    assert attrs.loc["00000123", "attr_source_groups"] == "clim"


def test_apply_bh_fdr_flags_expected_discoveries():
    df = pd.DataFrame({"p_value": [0.001, 0.02, 0.04, 0.20]})

    adjusted = apply_bh_fdr(df, p_col="p_value", q_col="q_value", reject_col="significant_fdr_05")

    assert np.allclose(adjusted["q_value"], [0.004, 0.04, 0.0533333333, 0.2])
    assert adjusted["significant_fdr_05"].tolist() == [True, True, False, False]


def test_summarize_spearman_relationships_orders_by_target_and_strength():
    panel = pd.DataFrame({
        "snow": [0.0, 0.1, 0.2, 0.3, 0.4],
        "aridity": [5, 4, 3, 2, 1],
        "target_a": [1, 2, 3, 4, 5],
        "target_b": [2, 2, 2, 2, 2],
    })

    summary = summarize_spearman_relationships(
        panel,
        feature_cols=["snow", "aridity"],
        target_cols=["target_a", "target_b"],
    )

    strong = summary[summary["target"] == "target_a"].iloc[0]
    constant = summary[summary["target"] == "target_b"]
    assert strong["feature"] in {"snow", "aridity"}
    assert strong["n"] == 5
    assert abs(strong["spearman_rho"]) == 1.0
    assert constant.empty


def test_build_case_selection_returns_unique_ranked_cases():
    panel = pd.DataFrame({
        "basin_id": ["a", "b", "c", "d"],
        "conceptual_winner": ["GR4J", "XAJ", "HBV", "GR4J"],
        "best_conceptual": [0.9, 0.7, 0.5, 0.6],
        "LSTM_ensemble_8seed": [0.8, 0.9, 0.4, 0.7],
        "lstm_minus_best_conceptual": [-0.1, 0.2, -0.1, 0.1],
        "conceptual_spread": [0.2, 0.4, 0.1, 0.3],
        "regime": ["humid", "snow-dominated", "snow-dominated", "semi-arid/arid"],
    })

    cases = build_case_selection(panel, per_category=2)

    assert cases["basin_id"].is_unique
    assert {"conceptual_beats_lstm", "largest_lstm_gap", "largest_conceptual_disagreement"} <= set(cases["case_type"])
