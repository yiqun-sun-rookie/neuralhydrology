"""Tests for the post-switch forecast-window development runner."""

from __future__ import annotations

import importlib

import numpy as np
import pytest


RUNNER_MODULE = (
    "hbv_multilead_joint_uncertainty.scripts."
    "run_g3_post_switch_forecast_development"
)


def _config():
    return {
        "classification": "development_screen",
        "forecast_contract": {
            "model_transition_during_forecast": "identity",
            "candidate_probabilities_during_forecast": (
                "fixed_at_origin_assimilation_posterior"
            ),
            "cross_candidate_state_mixing_during_forecast": False,
        },
        "lead_days": [1, 3, 7],
        "switch_days": [180, 360],
        "post_switch_offsets": [0, 1, 2, 3, 4, 5, 6],
        "crosscheck_origin": 539,
        "expected_block_count": 8,
        "expected_truth_count": 3,
        "primary_candidate_method_name": "parameter_only",
        "selected_process_id": "process_2",
        "factor_transition_stay_probability": 0.98,
        "development_gates": {
            "one_day_maximum_rmse_harm_fraction": 0.01,
            "three_day_minimum_rmse_improvement_fraction": 0.01,
            "seven_day_minimum_rmse_improvement_fraction": 0.01,
        },
        "sealed_ideal_input_evidence": {
            "path": "ideal.npz",
            "sha256": "0" * 64,
        },
        "sealed_baseline_evidence": {
            "path": "baseline.npz",
            "sha256": "1" * 64,
        },
        "process_noise_source": {"selected_process_id": "process_2"},
    }


@pytest.mark.parametrize(
    ("mutation", "match"),
    [
        (
            lambda config: config["post_switch_offsets"].append(7),
            "offsets",
        ),
        (
            lambda config: config["switch_days"].__setitem__(1, 359),
            "switch days",
        ),
        (
            lambda config: config["development_gates"].__setitem__(
                "three_day_minimum_rmse_improvement_fraction", 0.0
            ),
            "development gates",
        ),
        (
            lambda config: config["forecast_contract"].__setitem__(
                "model_transition_during_forecast", "markov"
            ),
            "forecast contract",
        ),
    ],
)
def test_fixed_contract_rejects_drift(mutation, match):
    runner = importlib.import_module(RUNNER_MODULE)
    config = _config()
    mutation(config)

    with pytest.raises(ValueError, match=match):
        runner._validate_config_contract(config)


def _arrays():
    truth = np.zeros((2, 3, 14, 3), dtype=np.float64)
    none = np.broadcast_to([2.0, 4.0, 10.0], truth.shape).copy()
    full = np.broadcast_to([2.01, 3.8, 8.8], truth.shape).copy()
    return full, none, truth


def test_summary_applies_fixed_transition_window_gates():
    runner = importlib.import_module(RUNNER_MODULE)
    full, none, truth = _arrays()

    summary, evidence = runner._summarize_development(
        full_forecasts=full,
        none_forecasts=none,
        truth_forecasts=truth,
        integrity_cross_checks={"passed": True},
        gates=_config()["development_gates"],
    )

    assert summary["development_decision"] == "advance_to_new_formal_design"
    assert all(summary["gates"].values())
    np.testing.assert_allclose(summary["rmse"]["full"], [2.01, 3.8, 8.8])
    np.testing.assert_allclose(summary["rmse"]["none"], [2.0, 4.0, 10.0])
    assert summary["relative_full_minus_none_rmse_percent"][0] == pytest.approx(
        0.5
    )
    assert set(evidence) >= {
        "squared_error_full",
        "squared_error_none",
    }


@pytest.mark.parametrize(
    "lead_index",
    [0, 1, 2],
)
def test_any_failed_transition_window_gate_stops_formal(lead_index):
    runner = importlib.import_module(RUNNER_MODULE)
    full, none, truth = _arrays()
    if lead_index == 0:
        full[..., 0] = 2.03
    elif lead_index == 1:
        full[..., 1] = 3.98
    else:
        full[..., 2] = 9.95

    summary, _ = runner._summarize_development(
        full_forecasts=full,
        none_forecasts=none,
        truth_forecasts=truth,
        integrity_cross_checks={"passed": True},
        gates=_config()["development_gates"],
    )

    assert summary["development_decision"] == "stop_no_formal_experiment"
    assert not all(summary["gates"].values())
