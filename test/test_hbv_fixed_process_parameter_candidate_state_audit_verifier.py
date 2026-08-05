import os
import subprocess
import sys

import numpy as np

from hbv_multilead_joint_uncertainty.scripts.verify_g3_fixed_process_parameter_candidate_complete_state_audit import (
    _maximum_difference,
)


def test_maximum_difference_handles_shape_and_nan_patterns():
    assert _maximum_difference([1.0, np.nan], [1.0, np.nan]) == 0.0
    assert _maximum_difference([1.0], [[1.0]]) == float("inf")


def test_verifier_imports_neither_forecast_nor_production_state_summary():
    environment = os.environ.copy()
    environment["PYTHONPATH"] = "src"
    names = (
        "hbv_multilead_joint_uncertainty.deterministic_unique_state_forecast",
        "hbv_multilead_joint_uncertainty.fixed_process_parameter_candidate_state_audit",
    )
    command = (
        "import importlib,sys;"
        "importlib.import_module('hbv_multilead_joint_uncertainty.scripts."
        "verify_g3_fixed_process_parameter_candidate_complete_state_audit');"
        f"[print(name, name in sys.modules) for name in {names!r}]"
    )
    completed = subprocess.run(
        [sys.executable, "-c", command],
        check=True,
        capture_output=True,
        text=True,
        env=environment,
    )
    assert completed.stdout.strip().splitlines() == [
        f"{names[0]} False",
        f"{names[1]} False",
    ]
