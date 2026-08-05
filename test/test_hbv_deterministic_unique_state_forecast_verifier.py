from pathlib import Path

import numpy as np

from hbv_multilead_joint_uncertainty.scripts.verify_g3_deterministic_unique_state_forecast_attribution import (
    _maximum_difference,
)


def test_maximum_difference_is_exact_for_matching_arrays():
    values = np.arange(12, dtype=float).reshape(3, 4)
    assert _maximum_difference(values, values.copy()) == 0.0


def test_maximum_difference_rejects_shape_drift():
    assert np.isinf(_maximum_difference(np.zeros(2), np.zeros(3)))


def test_verifier_does_not_import_production_forecast_module():
    source = Path(
        "src/hbv_multilead_joint_uncertainty/scripts/"
        "verify_g3_deterministic_unique_state_forecast_attribution.py"
    ).read_text(encoding="utf-8")
    forbidden = (
        "from hbv_multilead_joint_uncertainty."
        "deterministic_unique_state_forecast import"
    )
    assert forbidden not in source
