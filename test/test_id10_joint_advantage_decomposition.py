import pandas as pd

from src.lstm_fair_531.scripts.joint_advantage_decomposition import summarize_joint_advantage


def test_summarize_joint_advantage_collapses_daily_residuals_by_season_and_flow():
    rows = []
    for model, offset in [
        ("LSTM_ensemble_8seed", 0.0),
        ("GR4J", 2.0),
        ("XAJ", 1.0),
        ("HBV", 3.0),
    ]:
        for day, obs in [("1990-04-01", 1.0), ("1990-04-02", 3.0)]:
            rows.append({
                "basin_id": "1",
                "date": day,
                "model": model,
                "obs": obs,
                "sim": obs + offset,
                "season": "MAM",
                "flow_group": "high",
                "regime": "snow-dominated",
                "case_type": "population_all",
            })
    daily = pd.DataFrame(rows)

    model_metrics, delta, targets, concentration = summarize_joint_advantage(daily, min_days=2)

    assert set(model_metrics["model"]) == {"LSTM_ensemble_8seed", "GR4J", "XAJ", "HBV"}
    assert len(delta) == 3
    target = targets.iloc[0]
    assert target["basin_id"] == "00000001"
    assert target["season"] == "MAM"
    assert target["flow_group"] == "high"
    assert target["best_conceptual_mae_minus_lstm"] == 1.0
    assert target["conceptual_mae_spread"] == 2.0
    assert bool(target["all_conceptual_worse_mae"]) is True
    summary = concentration.iloc[0]
    assert summary["regime"] == "snow-dominated"
    assert summary["season"] == "MAM"
    assert summary["flow_group"] == "high"
    assert summary["shared_failure_rate"] == 1.0
