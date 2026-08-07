"""Tests for the joint parameter and process-noise switch confirmation."""

from __future__ import annotations

import json
import re
from pathlib import Path

import numpy as np
import pytest

from hbv_multilead_joint_uncertainty.joint_parameter_process_noise_switch_confirmation import (
    build_aligned_joint_schedules,
    first_complete_top_ranked_run,
    generate_joint_switch_truth,
    run_joint_switch_confirmation,
    summarize_joint_switch_response,
)

REPO_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = (
    REPO_ROOT
    / "src"
    / "hbv_multilead_joint_uncertainty"
    / "configs"
    / "g3_joint_parameter_process_noise_switch_confirmation_v04.json"
)
PARENT_CONFIG_PATH = CONFIG_PATH.with_name(
    "g3_state_domain_consistent_parameter_switch_confirmation_v01.json"
)
VERIFIER_PATH = (
    REPO_ROOT
    / "src"
    / "hbv_multilead_joint_uncertainty"
    / "scripts"
    / "verify_g3_joint_parameter_process_noise_switch_confirmation.py"
)

PARAMETER_IDS = (
    "candidate_1_shared_limits",
    "candidate_2_shared_limits",
    "candidate_3_shared_limits",
)
PROCESS_IDS = (
    "lower_groundwater_low",
    "lower_groundwater_medium",
    "lower_groundwater_high",
)


def _config() -> dict:
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


def _parameter_vectors() -> dict[str, dict[str, float]]:
    config = _config()
    names = (
        "parTT", "parCFMAX", "parCFR", "parCWH", "parFC", "parBETA", "parLP",
        "parK0", "parK1", "parUZL", "parPERC", "parK2", "lag_time",
    )
    return {
        row["parameter_id"]: {name: float(row[name]) for name in names}
        for row in config["parameter_candidates"]
    }


def test_frozen_config_matches_design_contract():
    config = _config()
    assert config["candidate_count"] == 9
    assert config["filter"]["factor_transition_stay_probability"] == 0.98
    assert config["formal_confirmation_seeds"]["forcing"] == list(range(3801001, 3801009))
    assert config["formal_confirmation_seeds"]["process_noise"] == list(range(3802001, 3802009))
    assert config["formal_confirmation_seeds"]["observation_noise"] == list(range(3803001, 3803009))
    assert config["visual_review_rule"]["display_order_seed"] == 3804001
    assert config["visual_review_rule"]["classification_before_numeric_decision_unblinding"] is True
    rule = config["parameter_margin_response_rule"]
    assert rule["response_window_days"] == 30
    assert rule["consecutive_clear_dominance_days"] == 5
    assert rule["minimum_successful_events_per_directed_transition"] == 13
    noise_rule = config["noise_margin_response_rule"]
    assert noise_rule["consecutive_top_ranked_days"] == 5
    assert noise_rule["latest_allowed_response_start_day"] == 25
    expectation = config["preregistered_expectations"][
        "lower_groundwater_low_to_lower_groundwater_medium"
    ]
    assert expectation["expectation"] == "expected_not_to_pass"
    assert config["joint_unique_combination_readout"]["confirmatory"] is False
    assert config["forbidden_scope"]["forecast_executed"] is False


def test_parameter_candidates_copied_exactly_from_sealed_parent_config():
    parent = json.loads(PARENT_CONFIG_PATH.read_text(encoding="utf-8"))
    child = _config()
    assert child["parameter_candidates"] == parent["parameter_candidates"]


def test_aligned_schedules_switch_together_at_two_boundaries():
    config = _config()
    parameter_schedule, process_schedule = build_aligned_joint_schedules(
        config["truth_trial_stage_orders"]["parameter"],
        config["truth_trial_stage_orders"]["process_noise"],
        config["population"]["stage_length_days"],
    )
    assert parameter_schedule.shape == (3, 540)
    assert process_schedule.shape == (3, 540)
    for trial in range(3):
        parameter_switches = [
            day
            for day in range(1, 540)
            if parameter_schedule[trial, day] != parameter_schedule[trial, day - 1]
        ]
        process_switches = [
            day
            for day in range(1, 540)
            if process_schedule[trial, day] != process_schedule[trial, day - 1]
        ]
        assert parameter_switches == [180, 360]
        assert process_switches == [180, 360]
    directed_parameter = set()
    directed_process = set()
    for trial in range(3):
        for day in (180, 360):
            directed_parameter.add(
                (parameter_schedule[trial, day - 1], parameter_schedule[trial, day])
            )
            directed_process.add(
                (process_schedule[trial, day - 1], process_schedule[trial, day])
            )
    assert len(directed_parameter) == 3
    assert len(directed_process) == 3


def test_frozen_pairing_keeps_high_noise_on_fast_recovering_candidate():
    config = _config()
    parameter_orders = config["truth_trial_stage_orders"]["parameter"]
    process_orders = config["truth_trial_stage_orders"]["process_noise"]
    for parameter_order, process_order in zip(parameter_orders, process_orders):
        for parameter_id, process_id in zip(parameter_order, process_order):
            if process_id == "lower_groundwater_high":
                assert parameter_id == "candidate_2_shared_limits"
            if parameter_id == "candidate_3_shared_limits":
                assert process_id == "lower_groundwater_low"
            if parameter_id == "candidate_1_shared_limits":
                assert process_id == "lower_groundwater_medium"


def test_verifier_integrity_entries_are_positively_polarised():
    """Every integrity entry must mean "True is a pass".

    The v03 verifier recorded three entries whose False value meant "correctly
    not imported" while the verdict required every entry to be True, so it was
    structurally incapable of reporting success.  The defect stayed hidden
    because v01 and v02 produced no output to verify.
    """
    source = VERIFIER_PATH.read_text(encoding="utf-8")
    body = source.split("integrity = {", 1)[1].split("\n    }", 1)[0]
    keys = re.findall(r'"([a-z0-9_]+)":', body)
    assert len(keys) >= 15, "could not parse the integrity dictionary"
    inverted = [
        key for key in keys if key.endswith("_imported") and not key.endswith("_not_imported")
    ]
    assert not inverted, f"integrity entries carry inverted polarity: {inverted}"
    assert 'status = "passed" if all(integrity.values()) else "failed"' in source
    assert "isinstance(value, bool)" in source


def test_verifier_measures_module_isolation_instead_of_asserting_it():
    """The isolation entries must be measured, not hard-coded constants."""
    source = VERIFIER_PATH.read_text(encoding="utf-8")
    assert "loaded_modules = set(sys.modules)" in source
    for constant in (
        "PRODUCTION_EXPERIMENT_MODULES",
        "PRODUCTION_RUNNER_MODULE",
        "PROJECT_NAMESPACES",
    ):
        assert constant in source
    assert '"production_experiment_module_not_imported": False' not in source


def test_aligned_schedules_reject_misaligned_orders():
    with pytest.raises(ValueError):
        build_aligned_joint_schedules(
            [PARAMETER_IDS, PARAMETER_IDS, PARAMETER_IDS],
            [PROCESS_IDS, PROCESS_IDS, ("a", "a", "b")],
            10,
        )


def _small_truth_inputs(days: int = 30):
    rng = np.random.default_rng(1234)
    forcing = np.column_stack(
        (
            5.0 + rng.gamma(0.8, 4.0, size=days),
            np.full(days, 2.0),
            np.full(days, 10.0),
        )
    )
    vectors = _parameter_vectors()
    initial_state = np.array(
        [0.0, 0.0, 100.0, 1.0, 150.0] + [3.0] * 10, dtype=np.float64
    )
    return forcing, vectors, initial_state


def test_joint_truth_applies_scheduled_noise_levels_exactly():
    days = 30
    forcing, vectors, initial_state = _small_truth_inputs(days)
    normals = np.random.default_rng(99).standard_normal(days) * 0.1
    parameter_schedule = np.asarray(
        [PARAMETER_IDS[0]] * 15 + [PARAMETER_IDS[1]] * 15, dtype=np.str_
    )
    process_schedule = np.asarray(
        [PROCESS_IDS[0]] * 15 + [PROCESS_IDS[2]] * 15, dtype=np.str_
    )
    stds = {PROCESS_IDS[0]: 1.0, PROCESS_IDS[1]: 4.0, PROCESS_IDS[2]: 16.0}
    truth = generate_joint_switch_truth(
        forcing, vectors, initial_state, parameter_schedule, stds, process_schedule, normals
    )
    perturbation = truth["process_perturbations"][:, 4]
    assert np.allclose(perturbation[:15], normals[:15] * 1.0, rtol=0.0, atol=0.0)
    assert np.allclose(perturbation[15:], normals[15:] * 16.0, rtol=0.0, atol=0.0)
    assert np.all(truth["process_perturbations"][:, :4] == 0.0)
    assert np.all(truth["process_perturbations"][:, 5:] == 0.0)
    assert np.all(truth["projection_adjustments"] == 0.0)
    assert np.all(truth["switch_boundary_projection_adjustments"] == 0.0)


def test_joint_truth_rejects_projecting_noise_realization():
    days = 10
    forcing, vectors, initial_state = _small_truth_inputs(days)
    normals = np.zeros(days)
    normals[5] = -1000.0
    parameter_schedule = np.asarray([PARAMETER_IDS[0]] * days, dtype=np.str_)
    process_schedule = np.asarray([PROCESS_IDS[2]] * days, dtype=np.str_)
    stds = {PROCESS_IDS[0]: 1.0, PROCESS_IDS[1]: 4.0, PROCESS_IDS[2]: 16.0}
    with pytest.raises(ValueError, match="truth transition gate failed"):
        generate_joint_switch_truth(
            forcing, vectors, initial_state, parameter_schedule, stds,
            process_schedule, normals,
        )


def test_first_complete_top_ranked_run_respects_latest_start():
    days = 40
    values = np.full((days, 3), 1.0 / 3.0)
    values[28:40] = np.array([0.1, 0.8, 0.1])
    normalized = values / values.sum(axis=1, keepdims=True)
    late = first_complete_top_ranked_run(normalized, 1, 5, 30, 25)
    assert late is None
    values[20:40] = np.array([0.1, 0.8, 0.1])
    normalized = values / values.sum(axis=1, keepdims=True)
    assert first_complete_top_ranked_run(normalized, 1, 5, 30, 25) == 20


def test_summarize_joint_switch_response_counts_margins_independently():
    days = 120
    blocks, trials = 1, 1
    parameter_margin = np.zeros((blocks, trials, days, 3))
    noise_margin = np.zeros((blocks, trials, days, 3))
    parameter_margin[..., 0] = 1.0
    noise_margin[..., 0] = 1.0
    parameter_margin[0, 0, 60:, :] = np.array([0.05, 0.9, 0.05])
    noise_margin[0, 0, 60:, :] = np.array([0.4, 0.45, 0.15])
    parameter_schedule = np.asarray(
        [[PARAMETER_IDS[0]] * 60 + [PARAMETER_IDS[1]] * 60], dtype=np.str_
    )
    process_schedule = np.asarray(
        [[PROCESS_IDS[0]] * 60 + [PROCESS_IDS[1]] * 60], dtype=np.str_
    )
    parameter_rule = {
        "consecutive_clear_dominance_days": 5,
        "response_window_days": 30,
        "minimum_new_true_candidate_probability_exclusive": 0.5,
        "minimum_probability_margin_over_runner_up_inclusive": 0.1,
        "minimum_successful_events_per_directed_transition": 1,
        "event_count_per_directed_transition": 1,
        "confidence_level": 0.95,
        "minimum_exact_interval_lower_bound_exclusive": 0.025,
    }
    noise_rule = {
        "consecutive_top_ranked_days": 5,
        "response_window_days": 30,
        "latest_allowed_response_start_day": 25,
        "minimum_successful_events_per_directed_transition": 1,
        "event_count_per_directed_transition": 1,
        "confidence_level": 0.95,
        "minimum_exact_interval_lower_bound_exclusive": 0.025,
    }
    summary = summarize_joint_switch_response(
        parameter_margin, noise_margin, parameter_schedule, process_schedule,
        PARAMETER_IDS, PROCESS_IDS, parameter_rule, noise_rule,
    )
    assert len(summary["events"]) == 1
    event = summary["events"][0]
    assert event["parameter_numeric_success"] is True
    assert event["parameter_response_start_day"] == 0
    assert event["noise_numeric_success"] is True
    assert event["noise_response_start_day"] == 0
    assert summary["parameter_margin_summaries"][0]["criterion_passed"] is True


def test_run_joint_switch_confirmation_smoke_produces_clean_margins():
    stage_length = 8
    warmup = 10
    days = warmup + stage_length * 3
    rng = np.random.default_rng(777)
    forcing = np.stack(
        [
            np.column_stack(
                (
                    5.0 + rng.gamma(0.8, 4.0, size=days),
                    np.full(days, 2.0),
                    np.full(days, 10.0),
                )
            )
        ]
    )
    config = _config()
    result = run_joint_switch_confirmation(
        forcing,
        block_ids=("smoke_block_1",),
        parameter_vectors=_parameter_vectors(),
        process_standard_deviations={
            PROCESS_IDS[0]: 1.0, PROCESS_IDS[1]: 4.0, PROCESS_IDS[2]: 16.0
        },
        parameter_orders=config["truth_trial_stage_orders"]["parameter"],
        process_orders=config["truth_trial_stage_orders"]["process_noise"],
        process_noise_seeds=(1,),
        observation_noise_seeds=(2,),
        warmup_days=warmup,
        stage_length_days=stage_length,
        initial_covariance_fraction=0.001,
        observation_standard_deviation=0.1779767450200294,
        factor_transition_stay_probability=0.98,
    )
    assert result.posterior_probabilities.shape == (1, 3, stage_length * 3, 9)
    assert result.parameter_margin_probabilities.shape == (1, 3, stage_length * 3, 3)
    assert np.allclose(
        result.parameter_margin_probabilities.sum(axis=-1), 1.0, atol=1e-12
    )
    assert np.allclose(
        result.noise_margin_probabilities.sum(axis=-1), 1.0, atol=1e-12
    )
    assert np.all(result.truth_projection_adjustments == 0.0)
    assert np.all(result.switch_boundary_projection_adjustments == 0.0)
    assert tuple(result.candidate_parameter_ids[:3]) == (PARAMETER_IDS[0],) * 3
    assert tuple(result.candidate_process_ids[:3]) == PROCESS_IDS
