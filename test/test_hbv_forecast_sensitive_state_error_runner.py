"""Guard tests for the forecast-sensitive state-error runner."""

from __future__ import annotations

import copy
import json
import sys
from pathlib import Path

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.scripts.run_g3_forecast_sensitive_state_error_attribution import (  # noqa: E402
    DEFAULT_CONFIG,
    _select_state_sources,
    _truth_forecasts,
    _validate_config,
)


def test_frozen_config_contract_rejects_scope_drift():
    config = json.loads(DEFAULT_CONFIG.read_text(encoding="utf-8"))
    _validate_config(config)
    changed = copy.deepcopy(config)
    changed["state_methods"] = ["joint", "parameter_only"]
    with pytest.raises(ValueError, match="state method order"):
        _validate_config(changed)
    changed = copy.deepcopy(config)
    changed["screening_rule"]["multiplicity_controlled"] = True
    with pytest.raises(ValueError, match="multiplicity"):
        _validate_config(changed)


def test_state_source_selection_requires_sealed_method_order():
    names = np.asarray(
        ["open_loop", "fixed_filter", "parameter_only", "noise_only", "joint"]
    )
    states = np.arange(2 * 3 * 5 * 4 * 15, dtype=np.float64).reshape(2, 3, 5, 4, 15)
    selected = _select_state_sources(names, states)
    np.testing.assert_array_equal(selected["parameter_only"], states[:, :, 2])
    np.testing.assert_array_equal(selected["joint"], states[:, :, 4])
    with pytest.raises(ValueError, match="order"):
        _select_state_sources(names[::-1], states)


def test_truth_forecast_indexing_is_exact_t_plus_h():
    truth = np.arange(2 * 3 * 10, dtype=np.float64).reshape(2, 3, 10)
    targets = np.asarray([[1, 3], [2, 4]], dtype=np.int64)
    result = _truth_forecasts(truth, targets)
    assert result.shape == (2, 3, 2, 2)
    np.testing.assert_array_equal(result[1, 2], truth[1, 2, targets])
