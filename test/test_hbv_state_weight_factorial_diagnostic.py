"""Tests for the state-path by final-weight forecast compositor."""

from __future__ import annotations

import numpy as np
import pytest

from hbv_multilead_joint_uncertainty.state_weight_factorial_diagnostic import (
    combine_candidate_forecasts,
    state_weight_factorial_forecasts,
)


def test_combine_candidate_forecasts_returns_weighted_sum_by_lead():
    candidate_forecasts = np.asarray(
        [[1.0, 2.0, 4.0], [10.0, 20.0, 40.0]],
        dtype=np.float64,
    )
    probabilities = np.asarray([0.5, 0.25, 0.25], dtype=np.float64)

    combined = combine_candidate_forecasts(candidate_forecasts, probabilities)

    np.testing.assert_array_equal(combined, np.asarray([2.0, 20.0]))


def test_state_weight_factorial_forecasts_returns_all_combinations_and_interaction():
    full_candidate_forecasts = np.asarray(
        [[2.0, 6.0], [5.0, 9.0]],
        dtype=np.float64,
    )
    none_candidate_forecasts = np.asarray(
        [[1.0, 3.0], [4.0, 8.0]],
        dtype=np.float64,
    )
    full_probabilities = np.asarray([0.75, 0.25], dtype=np.float64)
    none_probabilities = np.asarray([0.25, 0.75], dtype=np.float64)

    result = state_weight_factorial_forecasts(
        full_candidate_forecasts,
        none_candidate_forecasts,
        full_probabilities,
        none_probabilities,
    )

    assert set(result) == {
        "full_states_full_weights",
        "full_states_none_weights",
        "none_states_full_weights",
        "none_states_none_weights",
        "prediction_nonadditivity",
    }
    np.testing.assert_array_equal(
        result["full_states_full_weights"], np.asarray([3.0, 6.0])
    )
    np.testing.assert_array_equal(
        result["full_states_none_weights"], np.asarray([5.0, 8.0])
    )
    np.testing.assert_array_equal(
        result["none_states_full_weights"], np.asarray([1.5, 5.0])
    )
    np.testing.assert_array_equal(
        result["none_states_none_weights"], np.asarray([2.5, 7.0])
    )
    np.testing.assert_array_equal(
        result["prediction_nonadditivity"], np.asarray([-1.0, 0.0])
    )


def test_state_weight_factorial_forecasts_does_not_modify_inputs():
    full_candidate_forecasts = np.asarray([[2.0, 6.0]], dtype=np.float64)
    none_candidate_forecasts = np.asarray([[1.0, 3.0]], dtype=np.float64)
    full_probabilities = np.asarray([0.75, 0.25], dtype=np.float64)
    none_probabilities = np.asarray([0.25, 0.75], dtype=np.float64)
    inputs = (
        full_candidate_forecasts,
        none_candidate_forecasts,
        full_probabilities,
        none_probabilities,
    )
    originals = tuple(value.copy() for value in inputs)

    state_weight_factorial_forecasts(*inputs)

    for value, original in zip(inputs, originals):
        np.testing.assert_array_equal(value, original)


@pytest.mark.parametrize(
    ("candidate_forecasts", "probabilities"),
    [
        (np.asarray([1.0, 2.0]), np.asarray([0.5, 0.5])),
        (np.asarray([[1.0, np.nan]]), np.asarray([0.5, 0.5])),
        (np.asarray([[1.0, np.inf]]), np.asarray([0.5, 0.5])),
        (np.asarray([[1.0, 2.0]]), np.asarray([[0.5, 0.5]])),
        (np.asarray([[1.0, 2.0]]), np.asarray([1.0])),
        (np.asarray([[1.0, 2.0]]), np.asarray([0.5, np.nan])),
        (np.asarray([[1.0, 2.0]]), np.asarray([0.5, np.inf])),
        (np.asarray([[1.0, 2.0]]), np.asarray([1.1, -0.1])),
        (np.asarray([[1.0, 2.0]]), np.asarray([0.6, 0.5])),
        (np.asarray([[1.0, 2.0]]), np.asarray([0.5, 0.5 + 2e-12])),
    ],
)
def test_combine_candidate_forecasts_rejects_invalid_inputs(
    candidate_forecasts,
    probabilities,
):
    with pytest.raises(ValueError):
        combine_candidate_forecasts(candidate_forecasts, probabilities)


def test_combine_candidate_forecasts_accepts_probability_sum_at_tolerance():
    candidate_forecasts = np.asarray([[1.0, 3.0]], dtype=np.float64)
    probabilities = np.asarray([0.5, 0.5 + 5e-13], dtype=np.float64)

    combined = combine_candidate_forecasts(candidate_forecasts, probabilities)

    np.testing.assert_allclose(
        combined,
        candidate_forecasts @ probabilities,
        rtol=0.0,
        atol=0.0,
    )


@pytest.mark.parametrize(
    ("full_candidate_forecasts", "none_candidate_forecasts"),
    [
        (
            np.asarray([[1.0, 2.0], [3.0, 4.0]]),
            np.asarray([[1.0, 2.0]]),
        ),
        (
            np.asarray([[1.0, 2.0]]),
            np.asarray([[1.0, 2.0, 3.0]]),
        ),
    ],
)
def test_state_weight_factorial_forecasts_rejects_mismatched_candidate_shapes(
    full_candidate_forecasts,
    none_candidate_forecasts,
):
    with pytest.raises(ValueError):
        state_weight_factorial_forecasts(
            full_candidate_forecasts,
            none_candidate_forecasts,
            np.full(full_candidate_forecasts.shape[1], 1.0 / full_candidate_forecasts.shape[1]),
            np.full(none_candidate_forecasts.shape[1], 1.0 / none_candidate_forecasts.shape[1]),
        )
