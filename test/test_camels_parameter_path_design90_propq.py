"""Contract tests for the 03C proportional-Q Design90 runner and summarizer."""

from __future__ import annotations

import numpy as np
import pytest

from camels_switch_confirmation import run_parameter_path_design90_propq as propq
from camels_switch_confirmation import summarize_parameter_path_design90_propq as summ
from camels_switch_confirmation.g2_switch_confirmation import (
    RESPONSE_WINDOW_DAYS,
    _evaluate_events,
)


def test_expected_filter_contract_is_the_registered_fix():
    assert propq.EXPECTED_FILTER["q_mode"] == "lower_groundwater_state_proportional"
    assert propq.EXPECTED_FILTER["q_structure"] == "lower_groundwater_state_only"
    assert propq.EXPECTED_FILTER["q_state_multiplier"] == 1.0
    assert propq.EXPECTED_FILTER["observation_variance_multiplier"] == 1.0


def test_decision_gates_register_dual_windows_before_execution():
    gates = propq.DECISION_GATES
    assert gates["primary_response_window_days"] == 30
    assert gates["secondary_response_window_days"] == 90
    assert gates["secondary_tier_registered_before_execution"] is True
    assert gates["zero_true_probability_days_max"] == 0
    assert gates["mean_true_negative_log_probability_max"] == pytest.approx(
        np.log(3.0)
    )


def _random_probabilities(rng, n_days=400):
    raw = rng.random((n_days, 3)) ** 4
    return raw / raw.sum(axis=1, keepdims=True)


def test_window_evaluator_matches_registered_rule_at_30_days():
    rng = np.random.default_rng(7)
    for _ in range(20):
        probs = _random_probabilities(rng)
        pairs = [(40, 1), (160, 2), (280, 0)]
        expected = _evaluate_events(probs, pairs)
        observed = summ._evaluate_events_window(probs, pairs, RESPONSE_WINDOW_DAYS)
        assert observed == expected


def test_window_evaluator_wider_window_never_loses_a_pass():
    rng = np.random.default_rng(11)
    for _ in range(20):
        probs = _random_probabilities(rng)
        pairs = [(40, 1), (160, 2), (280, 0)]
        narrow = summ._evaluate_events_window(probs, pairs, 30)
        wide = summ._evaluate_events_window(probs, pairs, 90)
        for event_narrow, event_wide in zip(narrow, wide):
            if event_narrow["passed"]:
                assert event_wide["passed"]
                assert event_wide["response_start"] == event_narrow["response_start"]


def test_window_evaluator_finds_slow_response_only_in_wide_window():
    n_days = 300
    probs = np.full((n_days, 3), np.array([[0.6, 0.3, 0.1]]))
    switch_day = 100
    late_start = switch_day + 50
    probs[late_start:late_start + 5] = np.array([0.2, 0.7, 0.1])
    narrow = summ._evaluate_events_window(probs, [(switch_day, 1)], 30)
    wide = summ._evaluate_events_window(probs, [(switch_day, 1)], 90)
    assert narrow[0]["passed"] is False
    assert wide[0]["passed"] is True
    assert wide[0]["response_start"] == 50


def test_run_rejects_nonpositive_workers():
    with pytest.raises(ValueError):
        propq.run_parameter_path_design90_propq(
            propq.CONFIGURATION,
            "0" * 64,
            0,
        )


def test_verify_rejects_wrong_config_hash(tmp_path):
    config = tmp_path / "config.json"
    config.write_text("{}", encoding="utf-8")
    with pytest.raises(ValueError, match="SHA-256"):
        propq.verify_parameter_path_design90_propq(
            tmp_path,
            config,
            "0" * 64,
        )
