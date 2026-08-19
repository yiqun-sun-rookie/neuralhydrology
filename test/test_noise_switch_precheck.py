"""Contract tests for the NOISE-G1 precheck (pure functions, no filter runs)."""

import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from camels_switch_confirmation.g1_precheck import (  # noqa: E402
    SLZ_LOGNORMAL_SIGMA,
)
from camels_switch_confirmation.noise_switch_precheck import (  # noqa: E402
    ENSEMBLE_SIZE,
    NOISE_CANDIDATES,
    ROTATION,
    STAGE_DAYS,
    T_LIK_MAX_DAYS,
    WINDOW_DAYS,
    days_to_odds,
    directed_switch_pairs,
    injection_sigma,
    kl_variance_rate,
)


def test_injection_sigma_matches_moment_match_rule():
    assert injection_sigma(1.0) == pytest.approx(SLZ_LOGNORMAL_SIGMA)
    assert injection_sigma(4.0) == pytest.approx(2.0 * SLZ_LOGNORMAL_SIGMA)
    assert injection_sigma(0.25) == pytest.approx(0.5 * SLZ_LOGNORMAL_SIGMA)
    for bad in (0.0, -1.0, float("nan")):
        with pytest.raises(ValueError):
            injection_sigma(bad)


def test_kl_is_zero_for_identical_variances_and_positive_otherwise():
    variance = np.array([1.0, 2.0, 3.0])
    assert kl_variance_rate(variance, variance) == pytest.approx(0.0)
    assert kl_variance_rate(np.array([1.0]), np.array([4.0])) > 0.0
    assert kl_variance_rate(np.array([4.0]), np.array([1.0])) > 0.0


def test_kl_analytic_value():
    # v_true=1, v_rival=4 -> 0.5*(ln4 - 1 + 1/4)
    expected = 0.5 * (np.log(4.0) - 1.0 + 0.25)
    assert kl_variance_rate(np.array([1.0]), np.array([4.0])) == pytest.approx(expected)


def test_kl_is_asymmetric_harder_to_detect_smaller_noise():
    """Detecting a 10x SMALLER rival is harder than a 10x LARGER one when the
    true variance is the reference -- the physical reason small-noise switches
    are near-unidentifiable."""
    true_variance = np.array([1.0])
    up_rate = kl_variance_rate(true_variance, np.array([10.0]))
    down_rate = kl_variance_rate(true_variance, np.array([0.1]))
    assert down_rate > up_rate  # rival below truth is the easier direction here
    assert days_to_odds(up_rate) > days_to_odds(down_rate)


def test_days_to_odds_handles_zero_rate():
    assert days_to_odds(0.0) == float("inf")
    assert days_to_odds(np.log(19.0)) == pytest.approx(1.0)


def test_rotation_covers_all_six_directed_switches():
    pairs = directed_switch_pairs()
    assert len(pairs) == 6
    assert len(set(pairs)) == 6
    assert all(source != destination for source, destination in pairs)
    assert set(pairs) == {(a, b) for a in range(3) for b in range(3) if a != b}


def test_frozen_design_constants():
    assert NOISE_CANDIDATES == (1.0, 0.1, 10.0)
    assert ROTATION == (0, 1, 2, 0, 2, 1, 0)
    assert STAGE_DAYS == 180
    assert WINDOW_DAYS == 1260
    assert ENSEMBLE_SIZE == 40
    assert T_LIK_MAX_DAYS == 90.0
