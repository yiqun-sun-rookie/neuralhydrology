"""Tests for the NOISE-X2 paired switch-vs-null contrast analysis.

Pins the registered decision logic: stage indexing, the paired difference, the
placebo gate, the positive-fraction gate, and the rank AUC -- all on synthetic
inputs with analytically known answers.
"""

import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

_SRC = Path(__file__).resolve().parents[1] / "src"
if str(_SRC) not in sys.path:
    sys.path.insert(0, str(_SRC))

from camels_switch_confirmation import noise_switch_paired_contrast as contrast  # noqa: E402
from camels_switch_confirmation.noise_switch_precheck import (  # noqa: E402
    NOISE_CANDIDATES,
    ROTATION,
    STAGE_DAYS,
)


def test_stage_days_match_the_frozen_rotation():
    low = contrast.stage_days_for(1)
    high = contrast.stage_days_for(2)
    middle = contrast.stage_days_for(0)
    assert low.tolist() == (list(range(180, 360)) + list(range(900, 1080)))
    assert high.tolist() == (list(range(360, 540)) + list(range(720, 900)))
    assert len(middle) == 3 * STAGE_DAYS          # stages 1, 4, 7
    assert len(low) == len(high) == 2 * STAGE_DAYS
    with pytest.raises(ValueError):
        contrast.stage_days_for(7)


def test_paired_uplift_is_the_difference_on_the_same_days():
    n_days = len(ROTATION) * STAGE_DAYS
    switch = np.full((n_days, 3), 0.2)
    null = np.full((n_days, 3), 0.2)
    switch[contrast.stage_days_for(1), 1] = 0.8     # low candidate rises on its stages
    uplift, switch_mean, null_mean = contrast.paired_uplift(switch, null, 1)
    assert switch_mean == pytest.approx(0.8)
    assert null_mean == pytest.approx(0.2)
    assert uplift == pytest.approx(0.6)
    # a candidate that never moves has zero uplift
    assert contrast.paired_uplift(switch, null, 2)[0] == pytest.approx(0.0)


def test_paired_uplift_ignores_days_outside_the_shared_window():
    short = np.full((400, 3), 0.5)
    full = np.full((len(ROTATION) * STAGE_DAYS, 3), 0.1)
    uplift, switch_mean, _null = contrast.paired_uplift(short, full, 1)
    assert switch_mean == pytest.approx(0.5)       # only days < 400 contribute
    assert uplift == pytest.approx(0.4)


def test_rank_auc_endpoints_and_ties():
    assert contrast.rank_auc([1.0, 2.0], [0.0, 0.5]) == pytest.approx(1.0)
    assert contrast.rank_auc([0.0, 0.5], [1.0, 2.0]) == pytest.approx(0.0)
    assert contrast.rank_auc([1.0, 1.0], [1.0, 1.0]) == pytest.approx(0.5)


def _frame(low_uplift, high_uplift, placebo_uplift, n=20):
    rows = []
    for k in range(n):
        rows.append({
            "basin_id": f"{k:08d}", "seed": 2, "arm": "C",
            "uplift_m1": placebo_uplift, "switch_mean_m1": 0.5,
            "null_mean_m1": 0.5 - placebo_uplift,
            "uplift_m0.1": low_uplift, "switch_mean_m0.1": 0.5,
            "null_mean_m0.1": 0.5 - low_uplift,
            "uplift_m10": high_uplift, "switch_mean_m10": 0.6,
            "null_mean_m10": 0.6 - high_uplift,
            "switch_argmax_accuracy": 0.7, "null_argmax_accuracy": 0.66,
        })
    return pd.DataFrame(rows)


def test_judge_confirms_when_both_levels_clear_the_gates():
    verdict = contrast.judge(_frame(0.26, 0.43, -0.01), ["C"])["C"]
    assert verdict["placebo_gate_passed"]
    assert verdict["verdict"] == "identification_confirmed"
    assert verdict["levels"]["m0.1"]["positive_fraction"] == 1.0
    assert verdict["levels"]["m10"]["auc_switch_vs_null"] == pytest.approx(1.0)


def test_judge_rejects_when_uplift_sits_at_or_below_the_threshold():
    verdict = contrast.judge(_frame(0.10, 0.43, 0.0), ["C"])["C"]
    assert verdict["verdict"] == "not_confirmed"          # strict >, not >=
    assert not verdict["levels"]["m0.1"]["gate_passed"]
    assert verdict["levels"]["m10"]["gate_passed"]


def test_placebo_gate_voids_the_arm_even_when_levels_pass():
    verdict = contrast.judge(_frame(0.26, 0.43, 0.2), ["C"])["C"]
    assert not verdict["placebo_gate_passed"]
    assert verdict["verdict"] == "void_placebo_gate_violated"


def test_positive_fraction_gate_uses_the_registered_threshold():
    frame = _frame(0.26, 0.43, 0.0, n=20)
    frame.loc[frame.index[:3], "uplift_m0.1"] = -0.05     # 17/20 = 0.85 < 0.90
    verdict = contrast.judge(frame, ["C"])["C"]
    assert verdict["levels"]["m0.1"]["positive_fraction"] == pytest.approx(0.85)
    assert verdict["verdict"] == "not_confirmed"


def test_registered_thresholds_are_the_frozen_values():
    assert contrast.MEDIAN_UPLIFT_MIN == 0.10
    assert contrast.POSITIVE_FRACTION_MIN == 0.90
    assert contrast.PLACEBO_ABS_MEDIAN_MAX == 0.05
    assert contrast.TESTED_LEVELS == (1, 2)
    assert NOISE_CANDIDATES[contrast.PLACEBO_LEVEL] == 1.0
    assert contrast.PREREGISTRATION_SHA256 == (
        "fdb5ceb3b16d93d463e3457dabc3e6b989c3f48a3fbd3e6a0631e9679f61c5ee")
