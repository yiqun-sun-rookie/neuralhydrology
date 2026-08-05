from __future__ import annotations

from copy import deepcopy

import numpy as np
import pytest

from hbv_multilead_joint_uncertainty.state_domain_consistent_parameter_switch_confirmation import (
    audit_candidate_distinguishability,
    build_fixed_lower_groundwater_covariance,
    build_rotating_parameter_schedule,
    exact_binomial_interval,
    first_complete_clear_dominance_run,
    generate_parameter_switch_truth,
    run_parameter_switch_confirmation,
    summarize_parameter_switch_response,
    validate_parameter_candidates,
)


def _candidates() -> dict[str, dict[str, float]]:
    shared = {
        "parCWH": 0.05,
        "parFC": 200.0,
    }
    return {
        "candidate_1": {
            "parTT": -1.0,
            "parCFMAX": 2.0,
            "parCFR": 0.02,
            **shared,
            "parBETA": 2.0,
            "parLP": 0.6,
            "parK0": 0.2,
            "parK1": 0.1,
            "parUZL": 60.0,
            "parPERC": 2.0,
            "parK2": 0.01,
            "lag_time": 3.0,
        },
        "candidate_2": {
            "parTT": 0.0,
            "parCFMAX": 3.0,
            "parCFR": 0.04,
            **shared,
            "parBETA": 3.0,
            "parLP": 0.8,
            "parK0": 0.5,
            "parK1": 0.25,
            "parUZL": 40.0,
            "parPERC": 4.0,
            "parK2": 0.05,
            "lag_time": 2.0,
        },
        "candidate_3": {
            "parTT": 1.0,
            "parCFMAX": 4.0,
            "parCFR": 0.08,
            **shared,
            "parBETA": 5.0,
            "parLP": 0.4,
            "parK0": 0.7,
            "parK1": 0.4,
            "parUZL": 15.0,
            "parPERC": 7.0,
            "parK2": 0.15,
            "lag_time": 1.5,
        },
    }


def _forcing(day_count: int, block_count: int = 1) -> np.ndarray:
    days = np.arange(day_count, dtype=np.float64)
    rain = 6.0 + 0.5 * np.sin(days / 3.0)
    one = np.column_stack((rain, np.full(day_count, 2.0), np.full(day_count, 10.0)))
    return np.repeat(one[None, :, :], block_count, axis=0)


def test_candidate_validation_requires_equal_state_limits_and_distinct_vectors():
    identifiers, values = validate_parameter_candidates(_candidates())
    assert identifiers == ("candidate_1", "candidate_2", "candidate_3")
    assert values["candidate_1"]["parFC"] == values["candidate_3"]["parFC"]

    unequal_fc = deepcopy(_candidates())
    unequal_fc["candidate_3"]["parFC"] = 201.0
    with pytest.raises(ValueError, match="same parFC"):
        validate_parameter_candidates(unequal_fc)

    unequal_cwh = deepcopy(_candidates())
    unequal_cwh["candidate_1"]["parCWH"] = 0.04
    with pytest.raises(ValueError, match="same parCWH"):
        validate_parameter_candidates(unequal_cwh)

    outside_bounds = deepcopy(_candidates())
    outside_bounds["candidate_2"]["parK2"] = 0.3
    with pytest.raises(ValueError, match="outside frozen bounds"):
        validate_parameter_candidates(outside_bounds)

    duplicate = deepcopy(_candidates())
    duplicate["candidate_3"] = duplicate["candidate_2"].copy()
    with pytest.raises(ValueError, match="must be distinct"):
        validate_parameter_candidates(duplicate)


def test_rotating_schedule_has_two_copies_of_each_direction_per_three_trials():
    identifiers = tuple(_candidates())
    schedule = build_rotating_parameter_schedule(identifiers, 180)
    assert schedule.shape == (3, 540)
    counts = {(identifiers[0], identifiers[1]): 0, (identifiers[1], identifiers[2]): 0, (identifiers[2], identifiers[0]): 0}
    for trial in schedule:
        boundaries = np.flatnonzero(trial[1:] != trial[:-1]) + 1
        assert boundaries.tolist() == [180, 360]
        for boundary in boundaries:
            counts[(str(trial[boundary - 1]), str(trial[boundary]))] += 1
    assert set(counts.values()) == {2}
    assert {key: value * 8 for key, value in counts.items()} == {
        (identifiers[0], identifiers[1]): 16,
        (identifiers[1], identifiers[2]): 16,
        (identifiers[2], identifiers[0]): 16,
    }


def test_clear_dominance_rejects_rank_only_near_ties_and_accepts_clear_run():
    weak = np.tile(np.array([0.34, 0.33, 0.33]), (30, 1))
    assert first_complete_clear_dominance_run(weak, 0, 5, 30, 0.5, 0.1) is None

    strong = np.tile(np.array([0.2, 0.2, 0.6]), (30, 1))
    assert first_complete_clear_dominance_run(strong, 2, 5, 30, 0.5, 0.1) == 0

    insufficient_margin = np.tile(np.array([0.51, 0.49, 0.0]), (30, 1))
    assert (
        first_complete_clear_dominance_run(
            insufficient_margin, 0, 5, 30, 0.5, 0.1
        )
        is None
    )


def test_exact_interval_thirteen_of_sixteen_passes_strict_half_gate():
    lower, upper = exact_binomial_interval(13, 16)
    assert lower == pytest.approx(0.5435434537683882)
    assert upper == pytest.approx(0.9595262660940541)
    assert lower > 0.5


def test_truth_switch_keeps_full_state_unprojected():
    candidates = _candidates()
    schedule = build_rotating_parameter_schedule(tuple(candidates), 4)[0]
    forcing = _forcing(12)[0]
    initial_state = np.array(
        [0.0, 0.0, 60.0, 5.0, 50.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]
    )
    truth = generate_parameter_switch_truth(
        forcing,
        candidates,
        initial_state,
        schedule,
        process_standard_deviation_mm_day=0.01,
        lower_groundwater_standard_normals=np.zeros(12),
    )
    assert np.count_nonzero(truth["projection_adjustments"]) == 0
    assert np.count_nonzero(truth["switch_boundary_projection_adjustments"]) == 0
    assert truth["states"].shape == (12, 15)


def test_response_summary_has_sixteen_events_per_directed_transition():
    identifiers = tuple(_candidates())
    schedule = build_rotating_parameter_schedule(identifiers, 40)
    probabilities = np.empty((8, 3, 120, 3), dtype=np.float64)
    index = {identifier: position for position, identifier in enumerate(identifiers)}
    for block in range(8):
        for trial in range(3):
            probabilities[block, trial] = 0.1
            for day, identifier in enumerate(schedule[trial]):
                probabilities[block, trial, day, index[str(identifier)]] = 0.8
    events, summaries = summarize_parameter_switch_response(
        probabilities,
        schedule,
        identifiers,
        response_window_days=30,
        consecutive_clear_days=5,
        minimum_probability_exclusive=0.5,
        minimum_margin_inclusive=0.1,
        minimum_successful_events=13,
        minimum_interval_lower_bound=0.5,
    )
    assert len(events) == 48
    assert [row["event_count"] for row in summaries] == [16, 16, 16]
    assert [row["numerically_successful_event_count"] for row in summaries] == [16, 16, 16]
    assert all(row["numerical_criterion_passed"] for row in summaries)


def test_candidate_distinguishability_returns_all_three_pairs():
    rows = audit_candidate_distinguishability(
        _forcing(30, block_count=2),
        _candidates(),
        warmup_days=5,
        observation_standard_deviation=0.1,
        minimum_observation_standard_deviation_multiple=0.01,
        minimum_center_standard_deviation_multiple=0.001,
    )
    assert len(rows) == 3
    assert all(row["passed"] for row in rows)
    assert all(row["maximum_daily_start_projection_adjustment"] == 0.0 for row in rows)


def test_small_assimilation_run_is_finite_normalized_and_unprojected():
    result = run_parameter_switch_confirmation(
        _forcing(2 + 12),
        block_ids=("block_01",),
        parameter_vectors=_candidates(),
        process_noise_seeds=(101,),
        observation_noise_seeds=(201,),
        warmup_days=2,
        stage_length_days=4,
        initial_covariance_fraction=0.001,
        process_standard_deviation_mm_day=0.01,
        observation_standard_deviation=0.1,
        factor_transition_stay_probability=0.98,
    )
    assert result.posterior_probabilities.shape == (1, 3, 12, 3)
    assert np.allclose(result.posterior_probabilities.sum(axis=-1), 1.0)
    assert np.count_nonzero(result.truth_projection_adjustments) == 0
    assert np.count_nonzero(result.switch_boundary_projection_adjustments) == 0
    assert np.all(np.isfinite(result.global_posterior_states))


def test_fixed_process_covariance_has_one_nonzero_variance():
    covariance = build_fixed_lower_groundwater_covariance(1.0)
    assert covariance.shape == (15, 15)
    assert covariance[4, 4] == 1.0
    assert np.count_nonzero(covariance) == 1
