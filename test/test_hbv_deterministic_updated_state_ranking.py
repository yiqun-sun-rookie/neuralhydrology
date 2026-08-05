import numpy as np
from pathlib import Path

from hbv_multilead_joint_uncertainty.scripts.run_g3_deterministic_updated_state_ranking import (
    _summarize,
)


def test_summary_ranks_lower_rmse_first_and_keeps_block_pairing():
    methods = (
        "open_loop",
        "fixed_filter",
        "parameter_only",
        "noise_only",
        "joint",
        "truth_state_oracle",
    )
    truth = np.zeros((2, 1, 2, 7))
    forecasts = {
        method: np.full_like(truth, float(position))
        for position, method in enumerate(methods[::-1])
    }
    mask = np.ones((1, 2, 7), dtype=bool)
    bootstrap = np.asarray([[0, 1], [1, 0]], dtype=np.int64)
    rmse, block_mse, comparisons, ranking = _summarize(
        forecasts, truth, mask, bootstrap, methods
    )
    assert ranking.shape == (7, 6)
    assert ranking[0, 0] == "truth_state_oracle"
    assert rmse["truth_state_oracle"][0] == 0.0
    assert block_mse["open_loop"].shape == (2, 7)
    assert "truth_state_oracle" in comparisons


def test_independent_verifier_does_not_import_production_forecast_module():
    source = Path(
        "src/hbv_multilead_joint_uncertainty/scripts/"
        "verify_g3_deterministic_updated_state_ranking.py"
    ).read_text(encoding="utf-8")
    assert "deterministic_unique_state_forecast import" not in source
