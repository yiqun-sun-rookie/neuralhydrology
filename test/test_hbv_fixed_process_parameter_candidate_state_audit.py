import numpy as np
import pytest

from hbv_multilead_joint_uncertainty.fixed_process_parameter_candidate_state_audit import (
    CONTROLLED_STATE_METHODS,
    STATE_METHOD_ROLES,
    summarize_complete_state_controlled_error,
)


STATE_NAMES = tuple(f"state_{index}" for index in range(15))


def _truth():
    values = np.arange(2 * 1 * 4 * 15, dtype=np.float64).reshape(2, 1, 4, 15)
    return values / 10.0


def test_complete_state_summary_keeps_every_state_and_matched_block():
    truth = _truth()
    single = truth + 2.0
    three = truth + 1.0
    estimates = np.stack((single, three), axis=2)
    bootstrap = np.asarray([[0, 0], [0, 1], [1, 1]], dtype=np.int64)

    result = summarize_complete_state_controlled_error(
        estimates,
        truth,
        CONTROLLED_STATE_METHODS,
        STATE_NAMES,
        bootstrap,
    )

    assert result["per_state_rmse"].shape == (2, 15)
    assert result["method_roles"] == STATE_METHOD_ROLES
    assert STATE_METHOD_ROLES[CONTROLLED_STATE_METHODS[1]] == (
        "fully_interacting_multiple_model_global_posterior_state"
    )
    np.testing.assert_allclose(result["per_state_rmse"][0], 2.0)
    np.testing.assert_allclose(result["per_state_rmse"][1], 1.0)
    assert result["per_state_block_mse_difference"].shape == (2, 15)
    np.testing.assert_allclose(result["per_state_block_mse_difference"], -3.0)
    assert result["complete_standardized_rmse"].shape == (2,)
    assert result["complete_decision"] == "improves"
    assert tuple(result["per_state_decision"]) == ("improves",) * 15


def test_complete_state_summary_separates_hydrologic_and_routing_outcomes():
    truth = _truth()
    single = truth + 2.0
    three = truth.copy()
    three[..., :5] += 1.0
    three[..., 5:] += 3.0
    estimates = np.stack((single, three), axis=2)
    bootstrap = np.asarray([[0, 1]], dtype=np.int64)

    result = summarize_complete_state_controlled_error(
        estimates,
        truth,
        CONTROLLED_STATE_METHODS,
        STATE_NAMES,
        bootstrap,
    )

    np.testing.assert_allclose(result["group_raw_rmse"][:, 0], [2.0, 1.0])
    np.testing.assert_allclose(result["group_raw_rmse"][:, 1], [2.0, 3.0])
    assert tuple(result["group_decision"]) == ("improves", "worsens")


def test_complete_state_summary_rejects_five_state_only_audit():
    truth = np.zeros((2, 1, 4, 5), dtype=np.float64)
    estimates = np.stack((truth, truth), axis=2)
    with pytest.raises(ValueError, match="exactly fifteen"):
        summarize_complete_state_controlled_error(
            estimates,
            truth,
            CONTROLLED_STATE_METHODS,
            tuple(f"state_{index}" for index in range(5)),
            np.asarray([[0, 1]], dtype=np.int64),
        )


def test_complete_state_summary_rejects_zero_truth_variation():
    truth = np.zeros((2, 1, 4, 15), dtype=np.float64)
    estimates = np.stack((truth, truth), axis=2)
    with pytest.raises(ValueError, match="truth state must vary"):
        summarize_complete_state_controlled_error(
            estimates,
            truth,
            CONTROLLED_STATE_METHODS,
            STATE_NAMES,
            np.asarray([[0, 1]], dtype=np.int64),
        )
