"""Tests for full-stage daily rolling forecast indexing and statistics."""

from __future__ import annotations

import numpy as np
import pytest

from hbv_multilead_joint_uncertainty.daily_rolling_forecast import (
    build_daily_rolling_index,
    summarize_daily_rolling_forecasts,
)


def test_daily_rolling_index_uses_lead_specific_same_stage_samples():
    index = build_daily_rolling_index()

    np.testing.assert_array_equal(index.lead_days, np.arange(1, 8))
    np.testing.assert_array_equal(index.origin_indices, np.arange(180, 540))
    np.testing.assert_array_equal(
        np.sum(index.same_stage_mask, axis=0),
        [358, 356, 354, 352, 350, 348, 346],
    )
    np.testing.assert_array_equal(
        np.sum(index.cross_switch_mask, axis=0),
        [1, 2, 3, 4, 5, 6, 7],
    )
    np.testing.assert_array_equal(
        np.sum(index.unavailable_mask, axis=0),
        [1, 2, 3, 4, 5, 6, 7],
    )
    assert not np.any(index.same_stage_mask & index.cross_switch_mask)
    assert not np.any(index.same_stage_mask & index.unavailable_mask)
    assert not np.any(index.cross_switch_mask & index.unavailable_mask)
    np.testing.assert_array_equal(
        (
            index.same_stage_mask
            | index.cross_switch_mask
            | index.unavailable_mask
        ),
        np.ones_like(index.same_stage_mask, dtype=bool),
    )
    assert all(
        not getattr(index, name).flags.writeable
        for name in (
            "lead_days",
            "origin_indices",
            "target_indices",
            "origin_stage_indices",
            "target_stage_indices",
            "days_since_switch",
            "same_stage_mask",
            "cross_switch_mask",
            "unavailable_mask",
        )
    )


@pytest.mark.parametrize(
    ("kwargs", "match"),
    [
        ({"lead_days": (1, 3, 2)}, "strictly increasing"),
        ({"stage_lengths": (180, 179, 180)}, "stage lengths"),
        ({"switch_days": (179, 360)}, "switch days"),
        ({"stage_lengths": (180, 180)}, "three stages"),
    ],
)
def test_invalid_daily_rolling_contract_is_rejected(kwargs, match):
    with pytest.raises(ValueError, match=match):
        build_daily_rolling_index(**kwargs)


def _perfect_full_case():
    index = build_daily_rolling_index()
    shape = (2, 3, len(index.origin_indices), len(index.lead_days))
    truth = np.zeros(shape, dtype=np.float64)
    forecasts = {
        "full": np.zeros(shape, dtype=np.float64),
        "none": np.full(shape, 2.0, dtype=np.float64),
        "uniform_independent": np.full(shape, 3.0, dtype=np.float64),
    }
    return index, truth, forecasts


def test_statistics_ignore_cross_switch_and_unavailable_targets():
    index, truth, forecasts = _perfect_full_case()
    for values in forecasts.values():
        values[:, :, index.cross_switch_mask] = 1e6
        values[:, :, index.unavailable_mask] = -1e6
    truth[:, :, index.cross_switch_mask] = -2e6
    truth[:, :, index.unavailable_mask] = 2e6

    summary = summarize_daily_rolling_forecasts(
        forecasts,
        truth,
        index,
        bootstrap_replicates=100,
        bootstrap_seed=123,
        minimum_meaningful_rmse_fraction=0.01,
    )

    np.testing.assert_array_equal(
        summary["same_stage_sample_count_per_block_truth"],
        [358, 356, 354, 352, 350, 348, 346],
    )
    np.testing.assert_allclose(summary["rmse"]["full"], 0.0)
    np.testing.assert_allclose(summary["rmse"]["none"], 2.0)
    np.testing.assert_allclose(
        summary["rmse"]["uniform_independent"], 3.0
    )
    np.testing.assert_allclose(summary["block_mse"]["none"], 4.0)
    assert summary["retention_gates"]["retain"] is True


def test_bootstrap_resamples_only_blocks_and_is_shared():
    index, truth, forecasts = _perfect_full_case()
    forecasts["full"][0] = 1.0
    forecasts["full"][1] = 0.0

    summary = summarize_daily_rolling_forecasts(
        forecasts,
        truth,
        index,
        bootstrap_replicates=50,
        bootstrap_seed=456,
        minimum_meaningful_rmse_fraction=0.01,
    )

    assert summary["bootstrap_indices"].shape == (50, 2)
    assert np.all(summary["bootstrap_indices"] >= 0)
    assert np.all(summary["bootstrap_indices"] < 2)
    for comparison in (
        "full_minus_none",
        "full_minus_uniform_independent",
    ):
        assert summary["paired"][comparison]["block_mean"].shape == (2, 7)


def test_one_failed_lead_prevents_general_retention():
    index, truth, forecasts = _perfect_full_case()
    forecasts["full"][..., -1] = forecasts["none"][..., -1]

    summary = summarize_daily_rolling_forecasts(
        forecasts,
        truth,
        index,
        bootstrap_replicates=100,
        bootstrap_seed=789,
        minimum_meaningful_rmse_fraction=0.01,
    )

    assert (
        summary["paired"]["full_minus_none"]["materially_improves"][-1]
        is np.False_
        or not bool(
            summary["paired"]["full_minus_none"]["materially_improves"][-1]
        )
    )
    assert summary["retention_gates"]["retain"] is False


def test_fixed_time_strata_do_not_change_primary_statistics():
    index, truth, forecasts = _perfect_full_case()

    summary = summarize_daily_rolling_forecasts(
        forecasts,
        truth,
        index,
        bootstrap_replicates=20,
        bootstrap_seed=101,
        minimum_meaningful_rmse_fraction=0.01,
    )

    assert tuple(summary["time_strata"]) == (
        "days_000_006",
        "days_007_029",
        "days_030_089",
        "days_090_179",
    )
    assert summary["daily_offset"]["offset_days"].shape == (180,)
    assert summary["daily_offset"]["sample_count"]["full"].shape == (180, 7)
    np.testing.assert_allclose(summary["rmse"]["full"], 0.0)
