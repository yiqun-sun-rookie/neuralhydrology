"""Contract tests for the stage-4 step-1 skill-weighting rule (pure functions)."""

import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from camels_switch_confirmation.stage4_skill_weighting import (  # noqa: E402
    argmin_mixture,
    discounted_squared_errors,
    inverse_error_weights,
    skill_mixture,
)


def test_scores_are_causal_day_zero_empty():
    forecasts = np.array([[1.0, 2.0, 3.0], [1.0, 1.0, 1.0]])
    observations = np.array([1.0, 1.0, 1.0])
    scores = discounted_squared_errors(forecasts, observations, forget=0.5)
    assert np.array_equal(scores[:, 0], [0.0, 0.0])  # no history on day 0
    # day 1 sees only day-0 errors: cell0 err 0, cell1 err 0
    assert np.array_equal(scores[:, 1], [0.0, 0.0])
    # day 2 sees day-1 errors: cell0 (2-1)^2=1, cell1 0
    assert np.allclose(scores[:, 2], [1.0, 0.0])


def test_scores_ignore_future_observations():
    forecasts = np.array([[1.0, 2.0, 3.0, 4.0]])
    observations_a = np.array([1.0, 2.0, 0.0, 0.0])
    observations_b = np.array([1.0, 2.0, 9.9, -7.3])  # differ only on days 2,3
    scores_a = discounted_squared_errors(forecasts, observations_a)
    scores_b = discounted_squared_errors(forecasts, observations_b)
    assert np.array_equal(scores_a[:, :3], scores_b[:, :3])


def test_inverse_error_weights_analytic():
    scores = np.array([[1.0], [3.0]])
    weights = inverse_error_weights(scores)
    assert np.allclose(weights[:, 0], [0.75, 0.25])  # 1/1 : 1/3 normalized
    assert np.allclose(weights.sum(axis=0), 1.0)


def test_zero_score_cells_take_all_weight_equally():
    scores = np.array([[0.0], [0.0], [2.0]])
    weights = inverse_error_weights(scores)
    assert np.allclose(weights[:, 0], [0.5, 0.5, 0.0])
    all_zero = np.zeros((3, 1))
    assert np.allclose(inverse_error_weights(all_zero)[:, 0], 1.0 / 3.0)


def test_skill_mixture_matches_manual():
    forecasts = np.array([[2.0, 2.0, 2.0], [4.0, 4.0, 4.0]])
    observations = np.array([2.0, 3.0, 2.0])
    mixed, weights = skill_mixture(forecasts, observations, forget=1.0)
    assert mixed[0] == pytest.approx(3.0)  # day 0 uniform: (2+4)/2
    manual = (weights * forecasts).sum(axis=0)
    assert np.allclose(mixed, manual)
    # cell 0 is always closer to obs, so its weight must grow
    assert weights[0, 2] > weights[1, 2]


def test_argmin_follows_lowest_score_cell():
    forecasts = np.array([[10.0, 10.0, 10.0], [1.0, 1.0, 1.0]])
    observations = np.array([1.0, 1.0, 1.0])
    picked = argmin_mixture(forecasts, observations)
    # day 0 ties at score 0 -> argmin picks cell 0; afterwards cell 1 wins
    assert picked[0] == 10.0
    assert np.array_equal(picked[1:], [1.0, 1.0])
