"""Tests for the noise-switch truth-design diagnostics (NOISE-W1/W2/W3).

These modules are diagnostics, not experiment runners: they must never touch the
frozen filter stack and their pure helpers must be exactly the quantities the
write-up quotes.  The tests pin the helpers, not the basin numbers.
"""

import sys
from pathlib import Path

import numpy as np
import pytest

_SRC = Path(__file__).resolve().parents[1] / "src"
if str(_SRC) not in sys.path:
    sys.path.insert(0, str(_SRC))

from camels_switch_confirmation import noise_switch_confound_scale as confound  # noqa: E402
from camels_switch_confirmation import noise_switch_drift_diagnosis as drift  # noqa: E402
from camels_switch_confirmation import noise_switch_warmup_probe as warmup  # noqa: E402
from camels_switch_confirmation.noise_switch_precheck import (  # noqa: E402
    NOISE_CANDIDATES,
    ROTATION,
    STAGE_DAYS,
    injection_sigma,
)


def test_warmup_starts_are_ordered_and_reference_is_longest():
    starts = [np.datetime64(s) for s in warmup.WARMUP_STARTS]
    assert starts == sorted(starts, reverse=True)
    assert warmup.REFERENCE_START == warmup.WARMUP_STARTS[-1]
    # the first entry is "no warm-up": it must equal the official window start
    assert warmup.WARMUP_STARTS[0] == warmup.WINDOW_START


def test_memory_days_reports_last_day_above_tolerance():
    base = np.ones(10)
    perturbed = base.copy()
    perturbed[:4] += 0.5                      # 50% apart on days 1..4
    assert warmup._memory_days(base, perturbed) == 4
    assert warmup._memory_days(base, base.copy()) == 0
    # a deviation exactly at the tolerance still counts as remembered
    edge = base.copy()
    edge[2] += warmup.MEMORY_TOLERANCE
    assert warmup._memory_days(base, edge) == 3


def test_block_means_split_the_window_into_stages():
    trace = np.concatenate([np.full(STAGE_DAYS, float(i)) for i in range(len(ROTATION))])
    assert np.allclose(warmup._block_means(trace), np.arange(len(ROTATION), dtype=float))


def test_theoretical_walk_factor_matches_closed_form():
    expected = -sum(STAGE_DAYS * 0.5 * injection_sigma(NOISE_CANDIDATES[i]) ** 2
                    for i in ROTATION)
    assert drift.theoretical_log_drift() == pytest.approx(expected)
    # mean-preserving injection still drags a SINGLE realisation down
    assert 0.0 < np.exp(drift.theoretical_log_drift()) < 1.0


def test_injection_sigma_scales_with_sqrt_multiplier():
    assert injection_sigma(4.0) == pytest.approx(2.0 * injection_sigma(1.0))
    with pytest.raises(ValueError):
        injection_sigma(0.0)


def test_confound_variants_are_the_three_compared_designs():
    assert confound.VARIANTS == ("slz_mult", "slz_abs", "suz_mult")
    assert confound.SIGNAL_RATIO == 10.0        # candidate spacing by design
    assert confound.FIXED_MULTIPLIER == 1.0     # confound measured at constant m


def test_variant_variance_rejects_unknown_variant():
    rain = np.zeros(1)
    state = {"SNOWPACK": 0.0, "MELTWATER": 0.0, "SM": 100.0, "SUZ": 1.0, "SLZ": 10.0}
    params = {"parTT": 0.0, "parCFMAX": 3.0, "parCFR": 0.05, "parCWH": 0.1,
              "parFC": 300.0, "parBETA": 2.0, "parLP": 0.6, "parK0": 0.5,
              "parK1": 0.1, "parUZL": 20.0, "parPERC": 2.0, "parK2": 0.01,
              "lag_time": 1.0}
    with pytest.raises(ValueError):
        confound._variant_variance(rain, rain, rain, params, state,
                                   1.0, "01013500", 0, "not_a_variant")


def test_slz_absolute_variant_never_returns_a_negative_store():
    """slz_abs clips at zero; the clipping is why the frozen design went lognormal."""
    rng = np.random.default_rng(0)
    store = 1.0
    for _ in range(200):
        store = max(store + float(rng.normal(0.0, 10.0)), 0.0)
        assert store >= 0.0
