"""Tests for formal post-switch forecast comparison statistics."""

from __future__ import annotations

import numpy as np
import pytest

from hbv_multilead_joint_uncertainty.post_switch_forecast_confirmation import (
    summarize_post_switch_forecasts,
)


def _forecasts():
    truth = np.zeros((8, 3, 14, 3), dtype=np.float64)
    full = np.broadcast_to([2.0, 4.0, 8.0], truth.shape).copy()
    none = np.broadcast_to([2.2, 4.5, 9.0], truth.shape).copy()
    uniform = np.broadcast_to([2.5, 5.0, 10.0], truth.shape).copy()
    return {
        "full": full,
        "none": none,
        "uniform_independent": uniform,
    }, truth


def test_summary_requires_material_improvement_over_both_controls():
    forecasts, truth = _forecasts()

    result = summarize_post_switch_forecasts(
        forecasts=forecasts,
        truth_forecasts=truth,
        lead_days=(1, 3, 7),
        bootstrap_replicates=500,
        bootstrap_seed=8804001,
        minimum_meaningful_rmse_fraction=0.01,
    )

    np.testing.assert_allclose(result["rmse"]["full"], [2.0, 4.0, 8.0])
    assert np.all(
        result["paired"]["full_minus_none"]["materially_improves"]
    )
    assert np.all(
        result["paired"]["full_minus_uniform_independent"][
            "materially_improves"
        ]
    )
    assert result["retention_gates"]["retain"] is True
    assert result["per_origin_rmse"]["full"].shape == (14, 3)


def test_one_failed_lead_rejects_formal_retention():
    forecasts, truth = _forecasts()
    forecasts["full"][..., 2] = 9.0

    result = summarize_post_switch_forecasts(
        forecasts=forecasts,
        truth_forecasts=truth,
        lead_days=(1, 3, 7),
        bootstrap_replicates=500,
        bootstrap_seed=8804001,
        minimum_meaningful_rmse_fraction=0.01,
    )

    assert (
        result["retention_gates"][
            "full_materially_improves_none_all_leads"
        ]
        is False
    )
    assert result["retention_gates"]["retain"] is False


def test_bootstrap_is_reproducible_and_uses_matched_blocks():
    forecasts, truth = _forecasts()
    forecasts["full"][:, :, :, 0] += np.arange(8)[:, None, None]

    first = summarize_post_switch_forecasts(
        forecasts,
        truth,
        (1, 3, 7),
        100,
        8804001,
        0.01,
    )
    second = summarize_post_switch_forecasts(
        forecasts,
        truth,
        (1, 3, 7),
        100,
        8804001,
        0.01,
    )

    np.testing.assert_array_equal(
        first["bootstrap_indices"],
        second["bootstrap_indices"],
    )
    assert first["bootstrap_indices"].shape == (100, 8)


@pytest.mark.parametrize(
    ("mutation", "match"),
    [
        (
            lambda forecasts, truth: forecasts.pop("uniform_independent"),
            "exactly",
        ),
        (
            lambda forecasts, truth: forecasts["full"].__setitem__(
                (0, 0, 0, 0), np.nan
            ),
            "finite",
        ),
        (
            lambda forecasts, truth: truth.__setitem__((0, 0, 0, 0), np.nan),
            "finite",
        ),
    ],
)
def test_invalid_formal_inputs_are_rejected(mutation, match):
    forecasts, truth = _forecasts()
    mutation(forecasts, truth)

    with pytest.raises(ValueError, match=match):
        summarize_post_switch_forecasts(
            forecasts,
            truth,
            (1, 3, 7),
            100,
            8804001,
            0.01,
        )
