import sys
from pathlib import Path

import numpy as np
import pytest


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from hbv_multilead_joint_uncertainty.daily_combined_state_error import (  # noqa: E402
    bootstrap_block_indices,
    posterior_weighted_parameters,
    summarize_daily_combined_state_error,
)


def _example():
    truth = np.broadcast_to(
        np.arange(4, dtype=np.float64)[None, None, :, None],
        (2, 1, 4, 5),
    ).copy()
    states = np.broadcast_to(
        truth[:, :, None],
        (2, 1, 3, 4, 5),
    ).copy()
    states[:, :, 0] += 2.0
    states[:, :, 1] += 1.0
    states[:, :, 2] += 3.0
    names = ("open_loop", "parameter_only", "fixed_filter")
    bootstrap = np.array([[0, 1], [1, 1], [0, 0]], dtype=np.int64)
    return states, truth, names, bootstrap


def test_all_days_are_evaluated_without_switch_strata():
    states, truth, names, bootstrap = _example()
    result = summarize_daily_combined_state_error(
        states,
        truth,
        names,
        bootstrap,
        primary_method="parameter_only",
        baseline_methods=("fixed_filter", "open_loop"),
    )

    np.testing.assert_array_equal(result["day_indices"], np.arange(4))
    np.testing.assert_allclose(
        result["all_day_rmse"],
        np.array([[2.0] * 5, [1.0] * 5, [3.0] * 5]),
    )
    np.testing.assert_allclose(
        result["relative_rmse_fraction"],
        np.array([[-2.0 / 3.0] * 5, [-0.5] * 5]),
    )
    assert "stratum_names" not in result
    assert "days_since_switch" not in result


def test_time_since_switch_arguments_are_not_accepted():
    states, truth, names, bootstrap = _example()
    with pytest.raises(TypeError):
        summarize_daily_combined_state_error(
            states,
            truth,
            names,
            bootstrap,
            switch_days=(2,),
        )


def test_weighted_parameters_change_with_daily_probabilities():
    probabilities = np.array(
        [[[[1.0, 0.0], [0.25, 0.75], [0.0, 1.0]]]],
        dtype=np.float64,
    )
    parameters = np.array([[10.0, 20.0], [30.0, 60.0]])
    weighted = posterior_weighted_parameters(probabilities, parameters)

    np.testing.assert_allclose(
        weighted[0, 0],
        np.array([[10.0, 20.0], [25.0, 50.0], [30.0, 60.0]]),
    )


def test_block_bootstrap_is_deterministic_and_bounded():
    first = bootstrap_block_indices(8, 20, 3309761)
    second = bootstrap_block_indices(8, 20, 3309761)

    np.testing.assert_array_equal(first, second)
    assert first.shape == (20, 8)
    assert int(first.min()) >= 0
    assert int(first.max()) < 8
