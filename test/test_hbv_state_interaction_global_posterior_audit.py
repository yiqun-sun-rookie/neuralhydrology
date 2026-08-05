import numpy as np
import pytest

from hbv_multilead_joint_uncertainty.state_interaction_global_posterior_audit import (
    INTERACTION_STATE_METHODS,
    summarize_state_interaction_global_posterior_error,
)


STATE_NAMES = tuple(f"state_{index}" for index in range(15))


def _truth():
    values = np.arange(2 * 1 * 4 * 15, dtype=np.float64).reshape(2, 1, 4, 15)
    return values / 10.0


def test_summary_uses_full_minus_none_and_all_fifteen_states():
    truth = _truth()
    full = truth + 1.0
    none = truth + 2.0
    estimates = np.stack((full, none), axis=2)
    bootstrap = np.asarray([[0, 0], [0, 1], [1, 1]], dtype=np.int64)

    result = summarize_state_interaction_global_posterior_error(
        estimates,
        truth,
        INTERACTION_STATE_METHODS,
        STATE_NAMES,
        bootstrap,
    )

    np.testing.assert_allclose(result["per_state_rmse"][0], 1.0)
    np.testing.assert_allclose(result["per_state_rmse"][1], 2.0)
    np.testing.assert_allclose(result["per_state_block_mse_difference"], -3.0)
    assert result["per_state_block_mse_difference"].shape == (2, 15)
    assert tuple(result["per_state_decision"]) == ("improves",) * 15
    assert result["complete_decision"] == "improves"
    assert result["difference_definition"] == "full_interaction_minus_no_interaction"


def test_summary_separates_hydrologic_stores_and_routing_memory():
    truth = _truth()
    none = truth + 2.0
    full = truth.copy()
    full[..., :5] += 1.0
    full[..., 5:] += 3.0
    estimates = np.stack((full, none), axis=2)

    result = summarize_state_interaction_global_posterior_error(
        estimates,
        truth,
        INTERACTION_STATE_METHODS,
        STATE_NAMES,
        np.asarray([[0, 1]], dtype=np.int64),
    )

    np.testing.assert_allclose(result["group_raw_rmse"][:, 0], [1.0, 2.0])
    np.testing.assert_allclose(result["group_raw_rmse"][:, 1], [3.0, 2.0])
    assert tuple(result["group_decision"]) == ("improves", "worsens")


def test_summary_rejects_wrong_method_order_or_incomplete_state():
    truth = _truth()
    estimates = np.stack((truth, truth), axis=2)
    bootstrap = np.asarray([[0, 1]], dtype=np.int64)
    with pytest.raises(ValueError, match="method order"):
        summarize_state_interaction_global_posterior_error(
            estimates,
            truth,
            tuple(reversed(INTERACTION_STATE_METHODS)),
            STATE_NAMES,
            bootstrap,
        )
    with pytest.raises(ValueError, match="fifteen"):
        summarize_state_interaction_global_posterior_error(
            estimates[..., :5],
            truth[..., :5],
            INTERACTION_STATE_METHODS,
            STATE_NAMES[:5],
            bootstrap,
        )
