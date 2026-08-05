import os
import subprocess
import sys

import numpy as np

from hbv_multilead_joint_uncertainty.scripts.verify_g3_fixed_process_parameter_candidate_controlled_forecast import (
    _maximum_difference,
)


def test_maximum_difference_requires_identical_shape_and_values():
    assert _maximum_difference(np.asarray([1.0, 2.0]), np.asarray([1.0, 2.0])) == 0.0
    assert _maximum_difference(np.asarray([1.0]), np.asarray([[1.0]])) == float("inf")


def test_independent_verifier_import_does_not_load_production_forecast_modules():
    environment = os.environ.copy()
    environment["PYTHONPATH"] = "src"
    command = (
        "import importlib,sys; "
        "importlib.import_module('hbv_multilead_joint_uncertainty.scripts."
        "verify_g3_fixed_process_parameter_candidate_controlled_forecast'); "
        "[print(name, name in sys.modules) for name in "
        "('hbv_multilead_joint_uncertainty.deterministic_unique_state_forecast',"
        "'hbv_multilead_joint_uncertainty.fixed_process_parameter_candidate_forecast')"
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
        "hbv_multilead_joint_uncertainty.deterministic_unique_state_forecast False",
        "hbv_multilead_joint_uncertainty.fixed_process_parameter_candidate_forecast False",
    ]
