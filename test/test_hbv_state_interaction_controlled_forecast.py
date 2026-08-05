import numpy as np
import pytest

from hbv_multilead_joint_uncertainty.state_interaction_controlled_forecast import (
    CONTROLLED_METHODS,
    summarize_state_interaction_forecasts,
)


def _example_arrays():
    truth = np.zeros((2, 1, 3, 2), dtype=np.float64)
    full = np.empty_like(truth)
    none = np.empty_like(truth)
    full[0] = 1.0
    full[1] = 2.0
    none[0] = 2.0
    none[1] = 4.0
    mask = np.asarray([[[True, True], [True, False], [False, True]]])
    bootstrap = np.asarray([[0, 0], [0, 1], [1, 1]], dtype=np.int64)
    return truth, full, none, mask, bootstrap


def test_difference_direction_is_full_minus_none_and_uses_matched_blocks():
    truth, full, none, mask, bootstrap = _example_arrays()
    result = summarize_state_interaction_forecasts(
        forecasts={
            "fully_interacting_global_posterior_state": full,
            "noninteracting_global_posterior_state": none,
        },
        truth_forecasts=truth,
        same_stage_mask=mask,
        bootstrap_indices=bootstrap,
        minimum_relative_rmse_reduction=0.01,
    )

    assert result["method_names"] == CONTROLLED_METHODS
    np.testing.assert_allclose(
        result["block_mse_difference"],
        result["block_mse"]["fully_interacting_global_posterior_state"]
        - result["block_mse"]["noninteracting_global_posterior_state"],
    )
    np.testing.assert_allclose(result["block_mse_difference"], [[-3.0, -3.0], [-12.0, -12.0]])
    np.testing.assert_allclose(
        result["rmse"]["fully_interacting_global_posterior_state"],
        np.sqrt([2.5, 2.5]),
    )
    np.testing.assert_allclose(
        result["rmse"]["noninteracting_global_posterior_state"],
        np.sqrt([10.0, 10.0]),
    )
    np.testing.assert_allclose(result["relative_rmse_fraction"], [-0.5, -0.5])
    np.testing.assert_array_equal(result["same_stage_sample_count_per_block"], [2, 2])
    np.testing.assert_array_equal(result["same_stage_sample_count_all_blocks"], [4, 4])
    assert np.all(result["ci_high"] < 0.0)
    np.testing.assert_array_equal(result["improvement_decision"], [True, True])


def test_statistics_require_exact_method_order_finite_shapes_and_valid_mask():
    truth, full, none, mask, bootstrap = _example_arrays()
    with pytest.raises(ValueError, match="exactly match"):
        summarize_state_interaction_forecasts(
            forecasts={
                "noninteracting_global_posterior_state": none,
                "fully_interacting_global_posterior_state": full,
            },
            truth_forecasts=truth,
            same_stage_mask=mask,
            bootstrap_indices=bootstrap,
            minimum_relative_rmse_reduction=0.01,
        )

    invalid = full.copy()
    invalid[0, 0, 0, 0] = np.nan
    with pytest.raises(ValueError, match="finite and match truth"):
        summarize_state_interaction_forecasts(
            forecasts={
                CONTROLLED_METHODS[0]: invalid,
                CONTROLLED_METHODS[1]: none,
            },
            truth_forecasts=truth,
            same_stage_mask=mask,
            bootstrap_indices=bootstrap,
            minimum_relative_rmse_reduction=0.01,
        )

    with pytest.raises(ValueError, match="every lead"):
        summarize_state_interaction_forecasts(
            forecasts={
                CONTROLLED_METHODS[0]: full,
                CONTROLLED_METHODS[1]: none,
            },
            truth_forecasts=truth,
            same_stage_mask=np.zeros_like(mask),
            bootstrap_indices=bootstrap,
            minimum_relative_rmse_reduction=0.01,
        )
