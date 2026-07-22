"""Tests for the multi-seed anchor summary (matlab_multiseed_params_v01).

Frozen rules under test (design doc 2026-07-22-matlab-multiseed-params-design.md):
quantiles with numpy linear interpolation over non-censored values, censoring
reported alongside, the three-tier rng(1) position rule, the stable<=10 bridge
fraction, and divergent-seed (non-finite) handling.
"""

import sys
from pathlib import Path

import numpy as np
import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "src"))

from hbv_multilead_joint_uncertainty.matlab_multiseed_summary import (  # noqa: E402
    bridge_fraction,
    seed_anchor_row,
    summarize_metric,
)


class TestSummarizeMetric:
    def test_quantiles_use_numpy_linear_interpolation(self):
        result = summarize_metric([5, 10, 20, 40], reference=12)
        assert result["n_observed"] == 4
        assert result["min"] == 5
        assert result["q25"] == pytest.approx(8.75)
        assert result["median"] == pytest.approx(15.0)
        assert result["q75"] == pytest.approx(25.0)
        assert result["max"] == 40

    def test_censored_values_counted_not_dropped_silently(self):
        result = summarize_metric([3, None, 7], reference=5)
        assert result["n_observed"] == 2
        assert result["n_censored"] == 1
        assert result["censored_fraction"] == pytest.approx(1.0 / 3.0)
        assert result["min"] == 3
        assert result["max"] == 7

    def test_reference_inside_iqr_is_plain_normal(self):
        result = summarize_metric([5, 10, 20, 40], reference=12)
        assert result["reference_call"] == "非异常"
        assert result["reference_quantile_note"] is None

    def test_reference_outside_iqr_but_inside_range_reports_quantile(self):
        result = summarize_metric([5, 10, 20, 40], reference=30)
        assert result["reference_call"] == "非异常"
        assert result["reference_quantile_note"] is not None

    def test_reference_outside_range_is_anomalous(self):
        result = summarize_metric([5, 10, 20, 40], reference=724)
        assert result["reference_call"] == "异常，单实现结论依赖种子"

    def test_all_censored_gives_no_quantiles_and_no_reference_call(self):
        result = summarize_metric([None, None], reference=10)
        assert result["n_observed"] == 0
        assert result["median"] is None
        assert result["reference_call"] == "无可比样本"


class TestBridgeFraction:
    def test_censored_counts_as_not_within_budget(self):
        assert bridge_fraction([4, 10, 11, None], budget=10) == pytest.approx(0.5)

    def test_empty_input_rejected(self):
        with pytest.raises(ValueError):
            bridge_fraction([], budget=10)


class TestSeedAnchorRow:
    def _probs(self, total=30, candidates=12, t1_2=10, t2_3=20, true1=10, true2=11):
        probs = np.full((total, candidates), 0.01)
        probs[:, 0] = 0.5
        probs[3:t1_2, true1] = 0.9
        probs[t1_2 + 5:t2_3, true2] = 0.9
        return probs

    def test_row_contains_six_anchor_values_and_flags(self):
        probs = self._probs()
        row = seed_anchor_row(seed=3001001, imm_probs=probs, t1_2=10, t2_3=20)
        assert row["seed"] == 3001001
        assert row["divergent"] is False
        assert row["phase1_first_top_cycle"] == 4
        assert row["phase1_stable_top_cycle"] == 4
        assert row["phase2_first_top_cycle"] == 6
        assert row["phase2_stable_top_cycle"] == 6
        assert 0.0 < row["phase1_true_filter_mean_prob"] < 1.0

    def test_divergent_seed_flagged_and_anchors_none(self):
        probs = self._probs()
        probs[7, 3] = np.nan
        row = seed_anchor_row(seed=3001002, imm_probs=probs, t1_2=10, t2_3=20)
        assert row["divergent"] is True
        assert row["phase1_first_top_cycle"] is None
        assert row["phase2_stable_top_cycle"] is None
