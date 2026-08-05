import os
import subprocess
import sys
from pathlib import Path

import numpy as np

from hbv_multilead_joint_uncertainty.scripts.verify_g3_fixed_process_state_interaction_controlled_forecast import (
    _maximum_difference,
    _recompute_statistics,
)


def test_maximum_difference_requires_identical_shapes_and_values():
    assert _maximum_difference(np.asarray([1.0, 2.0]), np.asarray([1.0, 2.0])) == 0.0
    assert _maximum_difference(np.asarray([1.0]), np.asarray([[1.0]])) == float("inf")


def test_independent_statistics_use_full_minus_none_direction():
    truth = np.zeros((2, 1, 2, 1), dtype=np.float64)
    forecasts = {
        "fully_interacting_global_posterior_state": np.asarray(
            [[[[1.0], [1.0]]], [[[2.0], [2.0]]]]
        ),
        "noninteracting_global_posterior_state": np.asarray(
            [[[[2.0], [2.0]]], [[[4.0], [4.0]]]]
        ),
    }
    mask = np.ones((1, 2, 1), dtype=bool)
    bootstrap = np.asarray([[0, 0], [0, 1], [1, 1]], dtype=np.int64)
    result = _recompute_statistics(forecasts, truth, mask, bootstrap)
    np.testing.assert_allclose(result["difference"], [[-3.0], [-12.0]])
    np.testing.assert_allclose(result["relative"], [-0.5])
    assert result["decision"].tolist() == [True]


def test_independent_verifier_import_does_not_load_production_modules():
    environment = os.environ.copy()
    environment["PYTHONPATH"] = "src"
    command = (
        "import importlib,sys; "
        "importlib.import_module('hbv_multilead_joint_uncertainty.scripts."
        "verify_g3_fixed_process_state_interaction_controlled_forecast'); "
        "[print(name, name in sys.modules) for name in "
        "('hbv_multilead_joint_uncertainty.scripts."
        "run_g3_fixed_process_state_interaction_controlled_forecast',"
        "'hbv_multilead_joint_uncertainty.state_interaction_controlled_forecast',"
        "'hbv_multilead_joint_uncertainty.deterministic_unique_state_forecast')"
        "]"
    )
    completed = subprocess.run(
        [sys.executable, "-c", command],
        check=True,
        capture_output=True,
        text=True,
        env=environment,
    )
    assert completed.stdout.strip().splitlines() == [
        "hbv_multilead_joint_uncertainty.scripts.run_g3_fixed_process_state_interaction_controlled_forecast False",
        "hbv_multilead_joint_uncertainty.state_interaction_controlled_forecast False",
        "hbv_multilead_joint_uncertainty.deterministic_unique_state_forecast False",
    ]


def test_verifier_source_does_not_import_production_implementations():
    verifier_source = Path(
        "src/hbv_multilead_joint_uncertainty/scripts/"
        "verify_g3_fixed_process_state_interaction_controlled_forecast.py"
    ).read_text(encoding="utf-8")
    assert "run_g3_fixed_process_state_interaction_controlled_forecast" not in verifier_source
    assert "state_interaction_controlled_forecast" not in verifier_source
    assert "forecast_deterministic_state" not in verifier_source
