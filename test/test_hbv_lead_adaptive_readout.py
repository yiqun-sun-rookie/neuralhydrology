"""Tests for the lead-adaptive posterior forecast readout."""

from __future__ import annotations

import numpy as np
import pytest

from hbv_multilead_joint_uncertainty.lead_adaptive_readout import (
    lead_adaptive_posterior_readout,
    summarize_lead_adaptive_readout,
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


METHOD_NAMES = (
    "lead_adaptive",
    "full_posterior",
    "none_posterior",
    "uniform",
    "oracle",
)


def _constant_summary_inputs(
    lead_adaptive=(1.0, 2.0, 3.0),
    full_posterior=(2.0, 3.0, 4.0),
    none_posterior=(3.0, 4.0, 5.0),
    selected_correct=True,
):
    blocks, truths, leads = 4, 3, 3

    def tiled(values):
        return np.broadcast_to(
            np.asarray(values, dtype=np.float64),
            (blocks, truths, leads),
        ).copy()

    forecasts = {
        "lead_adaptive": tiled(lead_adaptive),
        "full_posterior": tiled(full_posterior),
        "none_posterior": tiled(none_posterior),
        "uniform": tiled((4.0, 5.0, 6.0)),
        "oracle": tiled((0.5, 1.0, 1.5)),
    }
    probabilities = np.zeros((blocks, truths, 3), dtype=np.float64)
    probabilities[..., 0] = 0.98 if selected_correct else 0.01
    probabilities[..., 1] = 0.01 if selected_correct else 0.98
    probabilities[..., 2] = 0.01
    return {
        "forecasts": forecasts,
        "truth_forecasts": np.zeros((blocks, truths, leads), dtype=np.float64),
        "final_probabilities": probabilities,
        "final_true_candidate_indices": np.zeros(
            (blocks, truths), dtype=np.int64
        ),
        "lead_days": (1, 3, 7),
        "bootstrap_replicates": 200,
        "bootstrap_seed": 17027,
        "minimum_meaningful_rmse_fraction": 0.01,
    }


def test_summary_computes_metrics_shared_bootstrap_and_preregistered_gates():
    inputs = _constant_summary_inputs()

    summary = summarize_lead_adaptive_readout(**inputs)

    assert tuple(summary["methods"]) == METHOD_NAMES
    np.testing.assert_allclose(summary["rmse"]["lead_adaptive"], [1.0, 2.0, 3.0])
    np.testing.assert_allclose(summary["rmse"]["full_posterior"], [2.0, 3.0, 4.0])
    np.testing.assert_allclose(summary["rmse"]["none_posterior"], [3.0, 4.0, 5.0])
    np.testing.assert_allclose(summary["rmse"]["uniform"], [4.0, 5.0, 6.0])
    np.testing.assert_allclose(summary["rmse"]["oracle"], [0.5, 1.0, 1.5])

    paired_none = summary["paired"]["lead_adaptive_minus_none_posterior"]
    np.testing.assert_allclose(paired_none["mean"], [-8.0, -12.0, -16.0])
    np.testing.assert_allclose(paired_none["ci_low"], paired_none["mean"])
    np.testing.assert_allclose(paired_none["ci_high"], paired_none["mean"])
    np.testing.assert_allclose(
        paired_none["meaningful_improvement_boundary"],
        np.asarray([9.0, 16.0, 25.0]) * -0.0199,
    )
    np.testing.assert_allclose(
        paired_none["meaningful_harm_boundary"],
        np.asarray([9.0, 16.0, 25.0]) * 0.0201,
    )
    assert np.all(paired_none["materially_improves"])
    assert np.all(paired_none["no_material_harm"])

    composite = summary["multiday_normalized_mse_composite"]
    np.testing.assert_allclose(composite["block_mean"], -0.695)
    assert composite["mean"] == pytest.approx(-0.695)
    assert composite["ci_low"] == pytest.approx(-0.695)
    assert composite["ci_high"] == pytest.approx(-0.695)
    np.testing.assert_array_equal(composite["lead_mask"], [False, True, True])

    assert summary["selection_accuracy"] == 1.0
    np.testing.assert_array_equal(summary["selected_candidate_indices"], 0)
    assert summary["bootstrap_indices"].shape == (200, 4)
    assert np.all(summary["bootstrap_indices"] >= 0)
    assert np.all(summary["bootstrap_indices"] < 4)
    assert summary["retention_gates"] == {
        "none_at_least_one_material_improvement": True,
        "none_all_leads_no_material_harm": True,
        "multiday_composite_improves": True,
        "highest_posterior_selection_accuracy": True,
        "full_at_least_one_material_improvement": True,
        "full_all_leads_no_material_harm": True,
        "retain": True,
    }


@pytest.mark.parametrize(
    ("changes", "failed_gate"),
    [
        (
            {
                "lead_adaptive": (2.985, 3.98, 4.975),
                "full_posterior": (4.0, 5.0, 6.0),
            },
            "none_at_least_one_material_improvement",
        ),
        (
            {"lead_adaptive": (3.06, 3.0, 4.0)},
            "none_all_leads_no_material_harm",
        ),
        (
            {"lead_adaptive": (1.0, 4.0, 5.0)},
            "multiday_composite_improves",
        ),
        (
            {"selected_correct": False},
            "highest_posterior_selection_accuracy",
        ),
        (
            {
                "lead_adaptive": (1.0, 2.0, 3.0),
                "full_posterior": (0.5, 1.0, 1.5),
            },
            "full_at_least_one_material_improvement",
        ),
        (
            {
                "lead_adaptive": (1.0, 2.0, 3.0),
                "full_posterior": (0.99, 1.99, 2.99),
            },
            "full_all_leads_no_material_harm",
        ),
    ],
)
def test_each_retention_gate_can_reject_the_readout(changes, failed_gate):
    inputs = _constant_summary_inputs(**changes)

    summary = summarize_lead_adaptive_readout(**inputs)

    assert summary["retention_gates"][failed_gate] is False
    assert summary["retention_gates"]["retain"] is False


def test_summary_averages_truths_within_block_before_shared_resampling():
    inputs = _constant_summary_inputs()
    lead_adaptive = inputs["forecasts"]["lead_adaptive"]
    lead_adaptive[0, :, 0] = [0.0, 1.0, 2.0]

    summary = summarize_lead_adaptive_readout(**inputs)

    expected_squared_error_difference = (
        np.square(lead_adaptive)
        - np.square(inputs["forecasts"]["none_posterior"])
    )
    expected_block_mean = np.mean(expected_squared_error_difference, axis=1)
    paired = summary["paired"]["lead_adaptive_minus_none_posterior"]
    np.testing.assert_allclose(paired["block_mean"], expected_block_mean)
    bootstrap_recomputed = np.mean(
        expected_block_mean[summary["bootstrap_indices"]],
        axis=1,
    )
    np.testing.assert_allclose(
        paired["ci_low"],
        np.percentile(bootstrap_recomputed, 2.5, axis=0),
    )
    np.testing.assert_allclose(
        paired["ci_high"],
        np.percentile(bootstrap_recomputed, 97.5, axis=0),
    )


@pytest.mark.parametrize(
    ("mutation", "match"),
    [
        (lambda inputs: inputs["forecasts"].pop("oracle"), "methods"),
        (
            lambda inputs: inputs["forecasts"].__setitem__(
                "oracle", np.zeros((4, 3, 2))
            ),
            "shape",
        ),
        (
            lambda inputs: inputs["final_probabilities"].__setitem__(
                (0, 0, 0), np.nan
            ),
            "finite",
        ),
        (
            lambda inputs: inputs.__setitem__("lead_days", (1, 3, 3)),
            "unique",
        ),
        (
            lambda inputs: inputs.__setitem__(
                "minimum_meaningful_rmse_fraction", 0.0
            ),
            "fraction",
        ),
    ],
)
def test_summary_rejects_invalid_contracts(mutation, match):
    inputs = _constant_summary_inputs()
    mutation(inputs)

    with pytest.raises((TypeError, ValueError), match=match):
        summarize_lead_adaptive_readout(**inputs)
