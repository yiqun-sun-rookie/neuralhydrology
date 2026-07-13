import pandas as pd

from src.lstm_fair_531.scripts.population_residual_attribute_review import (
    build_population_delta_targets,
    summarize_attribute_links,
)


def test_build_population_delta_targets_collapses_models_per_basin_context():
    delta = pd.DataFrame({
        "basin_id": ["1", "1", "1", "2", "2", "2"],
        "regime": ["snow"] * 6,
        "season": ["MAM"] * 6,
        "conceptual_model": ["GR4J", "XAJ", "HBV"] * 2,
        "mae_minus_lstm": [0.3, 0.5, 0.4, -0.1, 0.2, 0.1],
        "nse_minus_lstm": [-0.3, -0.5, -0.4, 0.1, -0.2, -0.1],
    })

    targets = build_population_delta_targets(delta, context_col="season")

    first = targets[targets["basin_id"] == "00000001"].iloc[0]
    assert first["best_conceptual_mae_minus_lstm"] == 0.3
    assert first["median_conceptual_mae_minus_lstm"] == 0.4
    assert first["conceptual_mae_spread"] == 0.2
    assert first["best_conceptual_nse_minus_lstm"] == -0.3


def test_summarize_attribute_links_reports_contextual_spearman_relationships():
    targets = pd.DataFrame({
        "basin_id": [f"{idx:08d}" for idx in range(1, 7)],
        "regime": ["snow"] * 6,
        "season": ["MAM"] * 6,
        "best_conceptual_mae_minus_lstm": [1, 2, 3, 4, 5, 6],
        "median_conceptual_mae_minus_lstm": [1, 2, 3, 4, 5, 6],
        "conceptual_mae_spread": [6, 5, 4, 3, 2, 1],
        "best_conceptual_nse_minus_lstm": [-1, -2, -3, -4, -5, -6],
    })
    panel = pd.DataFrame({
        "basin_id": [f"{idx:08d}" for idx in range(1, 7)],
        "clim_frac_snow": [1, 2, 3, 4, 5, 6],
        "clim_aridity": [6, 5, 4, 3, 2, 1],
    })

    summary = summarize_attribute_links(
        targets,
        panel,
        context_col="season",
        feature_cols=["clim_frac_snow", "clim_aridity"],
        min_n=3,
    )

    row = summary[(summary["context"] == "MAM") &
                  (summary["target"] == "best_conceptual_mae_minus_lstm") &
                  (summary["feature"] == "clim_frac_snow")].iloc[0]
    assert row["spearman_rho"] == 1.0
    assert row["n"] == 6
