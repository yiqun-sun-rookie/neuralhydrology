import os
import subprocess
import sys

import numpy as np

from hbv_multilead_joint_uncertainty.scripts.verify_g3_fixed_process_state_interaction_global_posterior_audit import (
    _maximum_difference,
)


def test_maximum_difference_handles_shapes_and_nan_patterns():
    assert _maximum_difference([1.0, np.nan], [1.0, np.nan]) == 0.0
    assert _maximum_difference([1.0], [[1.0]]) == float("inf")


def test_verifier_imports_no_production_or_forecast_module():
    environment = os.environ.copy()
    environment["PYTHONPATH"] = "src"
    forbidden = (
        "hbv_multilead_joint_uncertainty.state_interaction_global_posterior_audit",
        "hbv_multilead_joint_uncertainty.scripts."
        "run_g3_fixed_process_state_interaction_global_posterior_audit",
    )
    command = (
        "import importlib,sys;"
        "importlib.import_module('hbv_multilead_joint_uncertainty.scripts."
        "verify_g3_fixed_process_state_interaction_global_posterior_audit');"
        f"print(any(name in sys.modules for name in {forbidden!r}));"
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
