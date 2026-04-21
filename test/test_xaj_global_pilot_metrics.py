import pandas as pd

from src.xaj_global_pilot.metrics import compute_metrics


def test_compute_metrics_returns_expected_values_for_perfect_simulation():
    idx = pd.date_range("2000-01-01", periods=4, freq="D")
    obs = pd.Series([1.0, 2.0, 3.0, 4.0], index=idx)
    sim = obs.copy()

    metrics = compute_metrics(obs, sim)

    assert metrics["nse"] == 1.0
    assert metrics["kge"] == 1.0
    assert metrics["bias"] == 0.0
    assert metrics["peak_bias"] == 0.0
    assert metrics["lowflow_bias"] == 0.0

