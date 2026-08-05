"""Contract tests for the full-stage daily rolling development runner."""

from __future__ import annotations

import importlib

import numpy as np
import pytest


RUNNER_MODULE = (
    "hbv_multilead_joint_uncertainty.scripts."
    "run_g3_daily_rolling_forecast_development"
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
        "comparison_methods": [
            "full",
            "none",
            "uniform_independent",
        ],
        "lead_days": list(range(1, 8)),
        "stage_lengths": [180, 180, 180],
        "switch_days": [180, 360],
        "origin_start_day": 180,
        "crosscheck_origin": 539,
        "expected_block_count": 8,
        "expected_truth_count": 3,
        "primary_candidate_method_name": "parameter_only",
        "selected_process_id": "process_2",
        "factor_transition_stay_probability": 0.98,
        "bootstrap": {
            "unit": "matched_block",
            "replicates": 20000,
            "seed": 8820001,
            "shared_resample_indices_across_leads_and_comparisons": True,
        },
        "development_gates": {
            "minimum_full_stage_rmse_improvement_fraction": 0.01,
            "require_all_seven_leads_against_both_controls": True,
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
            lambda config: config["lead_days"].remove(4),
            "lead days",
        ),
        (
            lambda config: config["switch_days"].__setitem__(1, 359),
            "switch days",
        ),
        (
            lambda config: config["stage_lengths"].__setitem__(1, 179),
            "stage lengths",
        ),
        (
            lambda config: config["comparison_methods"].remove(
                "uniform_independent"
            ),
            "comparison methods",
        ),
        (
            lambda config: config["forecast_contract"].__setitem__(
                "model_transition_during_forecast", "markov"
            ),
            "forecast contract",
        ),
        (
            lambda config: config["bootstrap"].__setitem__(
                "unit", "daily_origin"
            ),
            "bootstrap",
        ),
        (
            lambda config: config["development_gates"].__setitem__(
                "minimum_full_stage_rmse_improvement_fraction", 0.0
            ),
            "development gates",
        ),
    ],
)
def test_development_contract_rejects_drift(mutation, match):
    runner = importlib.import_module(RUNNER_MODULE)
    config = _config()
    mutation(config)

    with pytest.raises(ValueError, match=match):
        runner._validate_config_contract(config)


def test_development_decision_requires_all_fourteen_point_estimates():
    runner = importlib.import_module(RUNNER_MODULE)
    rmse = {
        "full": np.ones(7),
        "none": np.full(7, 1.02),
        "uniform_independent": np.full(7, 1.03),
    }

    decision = runner._development_decision(
        rmse,
        _config()["development_gates"],
        integrity_passed=True,
    )

    assert decision["advance_to_formal_confirmation"] is True
    assert np.all(decision["full_vs_none_passes"])
    assert np.all(decision["full_vs_uniform_independent_passes"])


def test_one_failed_development_comparison_stops_formal():
    runner = importlib.import_module(RUNNER_MODULE)
    rmse = {
        "full": np.ones(7),
        "none": np.full(7, 1.02),
        "uniform_independent": np.full(7, 1.03),
    }
    rmse["none"][-1] = 1.005

    decision = runner._development_decision(
        rmse,
        _config()["development_gates"],
        integrity_passed=True,
    )

    assert decision["full_vs_none_passes"][-1] is np.False_ or not bool(
        decision["full_vs_none_passes"][-1]
    )
    assert decision["advance_to_formal_confirmation"] is False
