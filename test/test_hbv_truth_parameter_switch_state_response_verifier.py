import os
import subprocess
import sys

import numpy as np

from hbv_multilead_joint_uncertainty.scripts.verify_g3_truth_parameter_switch_state_response_causal_control import (
    _maximum_difference,
)


def test_maximum_difference_rejects_shape_or_label_mismatch():
    assert _maximum_difference(np.ones(1), np.ones((1, 1))) == float("inf")
    assert _maximum_difference(np.asarray(["a"]), np.asarray(["b"])) == float("inf")
    assert _maximum_difference(np.asarray([1.0]), np.asarray([1.0])) == 0.0


def test_verifier_imports_neither_production_control_nor_forecast_modules():
    environment = os.environ.copy()
    environment["PYTHONPATH"] = "src"
    command = (
        "import importlib,sys;"
        "importlib.import_module('hbv_multilead_joint_uncertainty.scripts."
        "verify_g3_truth_parameter_switch_state_response_causal_control');"
        "print('hbv_multilead_joint_uncertainty.truth_parameter_switch_state_response' in sys.modules);"
        "print(any('forecast' in name for name in sys.modules "
        "if name.startswith('hbv_multilead_joint_uncertainty')))"
    )
    completed = subprocess.run(
        [sys.executable, "-c", command],
        check=True,
        capture_output=True,
        text=True,
        env=environment,
    )
    assert completed.stdout.strip().splitlines() == ["False", "False"]
