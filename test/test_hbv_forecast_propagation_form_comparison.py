import numpy as np

from hbv_multilead_joint_uncertainty.scripts.run_g3_forecast_propagation_form_comparison import (
    _summarize,
)


def test_propagation_comparison_preserves_matched_blocks():
    methods = ("a", "b", "c", "d", "e")
    truth = np.zeros((2, 1, 3, 7))
    forecasts = {name: np.full_like(truth, position + 1.0) for position, name in enumerate(methods)}
    mask = np.ones((3, 7), dtype=bool)
    bootstrap = np.asarray([[0, 1], [1, 0]])
    rmse, block_mse, comparisons = _summarize(
        forecasts, truth, mask, bootstrap, methods
    )
    assert rmse["a"][0] == 1.0
    assert block_mse["a"].shape == (2, 7)
    assert set(comparisons) == {"b", "c", "d", "e"}
