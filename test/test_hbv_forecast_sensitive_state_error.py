"""Forecast-sensitive state-error intervention and statistic tests."""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.hbv_adapter import STATE_NAMES  # noqa: E402
from hbv_multilead_joint_uncertainty.forecast_sensitive_state_error import (  # noqa: E402
    COMPONENT_INTERVENTIONS,
    INTERVENTION_NAMES,
    STATE_METHODS,
    build_state_interventions,
    summarize_intervention_forecasts,
)


def test_interventions_replace_exactly_the_named_state_slice():
    estimated = np.arange(30, dtype=np.float64).reshape(2, 15)
    truth = estimated + 100.0
    interventions = build_state_interventions(estimated, truth)

    assert tuple(interventions) == INTERVENTION_NAMES
    for index, state_name in enumerate(STATE_NAMES):
        values = interventions[f"truth_component__{state_name}"]
        np.testing.assert_array_equal(values[..., index], truth[..., index])
        retained = [position for position in range(15) if position != index]
        np.testing.assert_array_equal(values[..., retained], estimated[..., retained])
    np.testing.assert_array_equal(
        interventions["truth_hydrologic_group"][..., :5], truth[..., :5]
    )
    np.testing.assert_array_equal(
        interventions["truth_hydrologic_group"][..., 5:], estimated[..., 5:]
    )
    np.testing.assert_array_equal(
        interventions["truth_routing_group"][..., :5], estimated[..., :5]
    )
    np.testing.assert_array_equal(
        interventions["truth_routing_group"][..., 5:], truth[..., 5:]
    )
    np.testing.assert_array_equal(interventions["truth_all_states"], truth)


def test_interventions_reject_incomplete_or_nonfinite_state():
    with pytest.raises(ValueError, match="15"):
        build_state_interventions(np.zeros(14), np.zeros(14))
    invalid = np.zeros(15)
    invalid[3] = np.nan
    with pytest.raises(ValueError, match="finite"):
        build_state_interventions(invalid, np.zeros(15))


def test_summary_uses_paired_block_differences_and_frozen_screening_rule():
    truth = np.zeros((2, 1, 2, 1), dtype=np.float64)
    mask = np.ones((1, 2, 1), dtype=bool)
    bootstrap = np.tile(np.array([[0, 1]], dtype=np.int64), (200, 1))
    forecasts = {}
    for method in STATE_METHODS:
        forecasts[method] = {}
        for intervention in INTERVENTION_NAMES:
            value = 2.0
            if intervention == COMPONENT_INTERVENTIONS[0]:
                value = 1.0
            elif intervention == COMPONENT_INTERVENTIONS[1]:
                value = 3.0
            forecasts[method][intervention] = np.full_like(truth, value)

    summary = summarize_intervention_forecasts(
        forecasts,
        truth,
        mask,
        bootstrap,
    )
    first = INTERVENTION_NAMES.index(COMPONENT_INTERVENTIONS[0])
    second = INTERVENTION_NAMES.index(COMPONENT_INTERVENTIONS[1])
    np.testing.assert_allclose(summary["rmse"][:, 0, 0], 2.0)
    np.testing.assert_allclose(summary["relative_rmse_change"][:, first, 0], -0.5)
    np.testing.assert_allclose(summary["relative_rmse_change"][:, second, 0], 0.5)
    assert np.all(summary["material_contributor"][:, first, 0])
    assert np.all(summary["material_harmful"][:, second, 0])
    assert np.all(summary["component_ranking"][:, 0, 0] == COMPONENT_INTERVENTIONS[0])
