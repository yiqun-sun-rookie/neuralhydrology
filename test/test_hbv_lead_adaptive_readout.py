"""Tests for the lead-adaptive posterior forecast readout."""

from __future__ import annotations

import numpy as np
import pytest

from hbv_multilead_joint_uncertainty.lead_adaptive_readout import (
    lead_adaptive_posterior_readout,
)


RULE_BY_LEAD = {
    1: "uniform",
    3: "highest_posterior",
    7: "highest_posterior",
}


def test_readout_uses_uniform_weights_for_one_day_and_posterior_mode_later():
    probabilities = np.asarray([0.1, 0.8, 0.1])
    forecasts = np.asarray(
        [
            [1.0, 4.0, 7.0],
            [2.0, 5.0, 8.0],
            [3.0, 6.0, 9.0],
        ]
    )

    result = lead_adaptive_posterior_readout(
        probabilities,
        forecasts,
        lead_days=(1, 3, 7),
        rule_by_lead=RULE_BY_LEAD,
    )

    np.testing.assert_allclose(result.predictions, [4.0, 5.0, 6.0])
    np.testing.assert_allclose(
        result.weights,
        [
            [1.0 / 3.0, 1.0 / 3.0, 1.0 / 3.0],
            [0.0, 1.0, 0.0],
            [0.0, 1.0, 0.0],
        ],
    )
    np.testing.assert_array_equal(result.lead_days, [1, 3, 7])
    assert result.selected_candidate_index == 1


def test_readout_breaks_highest_posterior_ties_by_lowest_index():
    result = lead_adaptive_posterior_readout(
        [0.45, 0.45, 0.1],
        [[2.0, 5.0, 9.0]],
        lead_days=(3,),
        rule_by_lead={3: "highest_posterior"},
    )

    assert result.selected_candidate_index == 0
    np.testing.assert_array_equal(result.weights, [[1.0, 0.0, 0.0]])
    np.testing.assert_array_equal(result.predictions, [2.0])


def test_readout_accepts_and_normalizes_probability_roundoff_at_tolerance():
    probabilities = np.asarray([0.2, 0.3, 0.5 + 5e-13])

    result = lead_adaptive_posterior_readout(
        probabilities,
        [[1.0, 2.0, 3.0]],
        lead_days=(1,),
        rule_by_lead={1: "uniform"},
    )

    assert result.selected_candidate_index == 2
    np.testing.assert_array_equal(result.predictions, [2.0])


@pytest.mark.parametrize(
    ("probabilities", "forecasts", "lead_days", "rule_by_lead", "match"),
    [
        ([[0.5, 0.5]], [[1.0, 2.0]], (1,), {1: "uniform"}, "one-dimensional"),
        ([0.5, 0.5], [1.0, 2.0], (1,), {1: "uniform"}, "two-dimensional"),
        ([0.5, 0.5], [[1.0, 2.0, 3.0]], (1,), {1: "uniform"}, "candidate"),
        ([0.5, 0.5], [[1.0, 2.0]], (1, 3), RULE_BY_LEAD, "lead"),
        ([0.5, np.nan], [[1.0, 2.0]], (1,), {1: "uniform"}, "finite"),
        ([0.5, 0.5], [[1.0, np.inf]], (1,), {1: "uniform"}, "finite"),
        ([-0.1, 1.1], [[1.0, 2.0]], (1,), {1: "uniform"}, "nonnegative"),
        ([0.4, 0.5], [[1.0, 2.0]], (1,), {1: "uniform"}, "sum"),
        ([0.5, 0.5], [[1.0, 2.0], [2.0, 3.0]], (1, 1), {1: "uniform"}, "unique"),
        ([0.5, 0.5], [[1.0, 2.0]], (1,), {}, "missing"),
        ([0.5, 0.5], [[1.0, 2.0]], (1,), {1: "posterior_mean"}, "rule"),
    ],
)
def test_readout_rejects_invalid_inputs(
    probabilities,
    forecasts,
    lead_days,
    rule_by_lead,
    match,
):
    with pytest.raises((TypeError, ValueError), match=match):
        lead_adaptive_posterior_readout(
            probabilities,
            forecasts,
            lead_days=lead_days,
            rule_by_lead=rule_by_lead,
        )


def test_readout_does_not_mutate_inputs_and_weights_reconstruct_predictions():
    probabilities = np.asarray([0.1, 0.8, 0.1])
    forecasts = np.arange(9, dtype=np.float64).reshape(3, 3)
    leads = np.asarray([1, 3, 7])
    probabilities_before = probabilities.copy()
    forecasts_before = forecasts.copy()
    leads_before = leads.copy()

    result = lead_adaptive_posterior_readout(
        probabilities,
        forecasts,
        lead_days=leads,
        rule_by_lead=RULE_BY_LEAD,
    )

    np.testing.assert_array_equal(probabilities, probabilities_before)
    np.testing.assert_array_equal(forecasts, forecasts_before)
    np.testing.assert_array_equal(leads, leads_before)
    np.testing.assert_allclose(
        result.predictions,
        np.sum(result.weights * forecasts, axis=1),
        rtol=0.0,
        atol=0.0,
    )
    assert not result.predictions.flags.writeable
    assert not result.weights.flags.writeable
    assert not result.lead_days.flags.writeable
