"""Tests for rolling candidate-specific forecast residual correction."""

from __future__ import annotations

import numpy as np

from hbv_multilead_joint_uncertainty.candidate_bias_correction import (
    rolling_candidate_bias_corrected_readout,
)


def _case():
    leads = np.asarray([1, 3, 7], dtype=np.int64)
    origins = np.arange(12, dtype=np.int64)
    targets = origins[:, None] + leads
    observations = np.arange(30, dtype=np.float64)
    history = np.empty((12, 3, 2), dtype=np.float64)
    history[:, 0, 0] = observations[targets[:, 0]] - 99.0
    history[:, 0, 1] = observations[targets[:, 0]] + 99.0
    history[:, 1, 0] = observations[targets[:, 1]] - 2.0
    history[:, 1, 1] = observations[targets[:, 1]] + 4.0
    history[:, 2, 0] = observations[targets[:, 2]] - 3.0
    history[:, 2, 1] = observations[targets[:, 2]] + 1.0
    return {
        "origin_indices": origins,
        "target_indices": targets,
        "historical_candidate_predictions": history,
        "observations": observations,
        "final_candidate_predictions": np.asarray(
            [[10.0, 20.0], [30.0, 40.0], [50.0, 60.0]]
        ),
        "final_probabilities": np.asarray([0.25, 0.75]),
        "final_origin_index": 11,
        "lead_days": leads,
        "window": 3,
    }


def test_bias_correction_preserves_one_day_and_corrects_each_candidate():
    case = _case()

    result = rolling_candidate_bias_corrected_readout(**case)

    np.testing.assert_allclose(
        result.corrections,
        [[0.0, 0.0], [2.0, -4.0], [3.0, -1.0]],
        rtol=0.0,
        atol=0.0,
    )
    np.testing.assert_allclose(
        result.corrected_candidate_predictions,
        [[10.0, 20.0], [32.0, 36.0], [53.0, 59.0]],
        rtol=0.0,
        atol=0.0,
    )
    np.testing.assert_allclose(
        result.weights,
        [[0.25, 0.75], [0.25, 0.75], [0.25, 0.75]],
        rtol=0.0,
        atol=0.0,
    )
    np.testing.assert_allclose(
        result.predictions,
        [17.5, 35.0, 57.5],
        rtol=0.0,
        atol=0.0,
    )
    assert result.predictions[0] == 17.5


def test_bias_correction_uses_only_latest_completed_same_lead_forecasts():
    case = _case()
    history = case["historical_candidate_predictions"]
    history[:6, 1, :] += 1000.0
    history[:2, 2, :] -= 1000.0

    result = rolling_candidate_bias_corrected_readout(**case)

    np.testing.assert_allclose(result.corrections[1], [2.0, -4.0])
    np.testing.assert_allclose(result.corrections[2], [3.0, -1.0])
    np.testing.assert_array_equal(
        result.history_origin_indices[1],
        [6, 7, 8],
    )
    np.testing.assert_array_equal(
        result.history_origin_indices[2],
        [2, 3, 4],
    )


def test_future_observations_cannot_change_bias_correction():
    case = _case()
    baseline = rolling_candidate_bias_corrected_readout(**case)
    changed = dict(case)
    observations = case["observations"].copy()
    observations[12:] = -1e12
    changed["observations"] = observations

    result = rolling_candidate_bias_corrected_readout(**changed)

    np.testing.assert_array_equal(result.predictions, baseline.predictions)
    np.testing.assert_array_equal(result.corrections, baseline.corrections)


def test_bias_correction_does_not_mutate_inputs_and_returns_readonly_arrays():
    case = _case()
    snapshots = {
        key: value.copy()
        for key, value in case.items()
        if isinstance(value, np.ndarray)
    }

    result = rolling_candidate_bias_corrected_readout(**case)

    for key, expected in snapshots.items():
        np.testing.assert_array_equal(case[key], expected)
    for values in (
        result.lead_days,
        result.predictions,
        result.weights,
        result.corrections,
        result.corrected_candidate_predictions,
        result.history_origin_indices,
    ):
        assert not values.flags.writeable
