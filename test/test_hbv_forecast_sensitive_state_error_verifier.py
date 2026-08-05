"""Independent verifier helper tests."""

from __future__ import annotations

import sys
import subprocess
from pathlib import Path

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.hbv_adapter import STATE_NAMES  # noqa: E402
from hbv_multilead_joint_uncertainty.scripts.verify_g3_forecast_sensitive_state_error_attribution import (  # noqa: E402
    INTERVENTIONS,
    _maximum_difference,
    _rebuild_interventions,
)


def test_independent_intervention_rebuild_has_frozen_order_and_exact_replacement():
    estimated = np.arange(15, dtype=np.float64)
    truth = estimated + 50.0
    rebuilt = _rebuild_interventions(estimated, truth)
    assert tuple(rebuilt) == INTERVENTIONS
    for index, name in enumerate(STATE_NAMES):
        corrected = rebuilt[f"truth_component__{name}"]
        assert corrected[index] == truth[index]
        np.testing.assert_array_equal(
            np.delete(corrected, index), np.delete(estimated, index)
        )


def test_maximum_difference_treats_labels_and_booleans_exactly():
    assert np.isclose(
        _maximum_difference(np.array([1.0]), np.array([1.0 + 1e-12])),
        1e-12,
        rtol=1e-3,
        atol=0.0,
    )
    assert _maximum_difference(np.array(["a"]), np.array(["a"])) == 0.0
    assert np.isinf(_maximum_difference(np.array(["a"]), np.array(["b"])))
    assert _maximum_difference(np.array([True]), np.array([True])) == 0.0
    assert np.isinf(_maximum_difference(np.array([True]), np.array([False])))


def test_verifier_does_not_import_production_forecast_modules():
    code = f"""
import sys
sys.path.insert(0, {str(REPO_ROOT / 'src')!r})
import hbv_multilead_joint_uncertainty.scripts.verify_g3_forecast_sensitive_state_error_attribution
forbidden = {{
    'hbv_multilead_joint_uncertainty.forecast_sensitive_state_error',
    'hbv_multilead_joint_uncertainty.deterministic_unique_state_forecast',
}}
loaded = sorted(forbidden.intersection(sys.modules))
if loaded:
    raise SystemExit('forbidden production imports: ' + ', '.join(loaded))
"""
    completed = subprocess.run(
        [sys.executable, "-c", code],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
    )
    assert completed.returncode == 0, completed.stderr or completed.stdout
