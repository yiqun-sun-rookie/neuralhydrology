from __future__ import annotations

import numpy as np
import pytest

from hbv_multilead_joint_uncertainty.state_domain_consistent_process_noise_switch import (
    LOWER_GROUNDWATER_STATE_INDEX,
    build_lower_groundwater_process_covariances,
    build_rotating_process_schedule,
    exact_binomial_interval,
    first_complete_top_ranked_run,
    generate_state_domain_consistent_truth,
    summarize_switch_response,
)


PROCESS_IDS = (
    "lower_groundwater_low",
    "lower_groundwater_medium",
    "lower_groundwater_high",
)


def _parameters() -> dict[str, float]:
    return {
        "parTT": 0.49,
        "parCFMAX": 2.55,
        "parCFR": 0.046,
        "parCWH": 0.0,
        "parFC": 115.4,
        "parBETA": 1.0,
        "parLP": 1.0,
        "parK0": 0.9,
        "parK1": 0.36,
        "parUZL": 44.4,
        "parPERC": 10.0,
        "parK2": 0.022,
        "lag_time": 1.8,
    }


def _initial_state() -> np.ndarray:
    return np.asarray(
        [
            0.0,
            0.0,
            50.0,
            10.0,
            60.0,
            5.0,
            4.0,
            3.0,
            2.0,
            1.0,
            0.0,
            0.0,
            0.0,
            0.0,
            0.0,
        ],
        dtype=np.float64,
    )


def test_rotating_schedule_has_three_orders_and_balanced_directed_switches():
    schedule = build_rotating_process_schedule(PROCESS_IDS, stage_length_days=2)

    expected = np.asarray(
        [
            [PROCESS_IDS[1]] * 2 + [PROCESS_IDS[2]] * 2 + [PROCESS_IDS[0]] * 2,
            [PROCESS_IDS[2]] * 2 + [PROCESS_IDS[0]] * 2 + [PROCESS_IDS[1]] * 2,
            [PROCESS_IDS[0]] * 2 + [PROCESS_IDS[1]] * 2 + [PROCESS_IDS[2]] * 2,
        ]
    )
    np.testing.assert_array_equal(schedule, expected)
    directed = []
    for trial in range(3):
        directed.append((schedule[trial, 1], schedule[trial, 2]))
        directed.append((schedule[trial, 3], schedule[trial, 4]))
    assert {pair: directed.count(pair) * 8 for pair in set(directed)} == {
        (PROCESS_IDS[0], PROCESS_IDS[1]): 16,
        (PROCESS_IDS[1], PROCESS_IDS[2]): 16,
        (PROCESS_IDS[2], PROCESS_IDS[0]): 16,
    }


def test_covariances_have_only_lower_groundwater_support():
    standard_deviations = dict(zip(PROCESS_IDS, (1.0, 4.0, 16.0)))
    covariances = build_lower_groundwater_process_covariances(standard_deviations)

    assert tuple(covariances) == PROCESS_IDS
    for process_id, standard_deviation in standard_deviations.items():
        covariance = covariances[process_id]
        assert covariance.shape == (15, 15)
        assert np.count_nonzero(covariance) == 1
        assert (
            covariance[
                LOWER_GROUNDWATER_STATE_INDEX, LOWER_GROUNDWATER_STATE_INDEX
            ]
            == standard_deviation**2
        )


def test_truth_rejects_any_projection_adjustment_and_accepts_zero_adjustment():
    forcing = np.asarray([[5.0, 2.0, 10.0]], dtype=np.float64)
    schedule = np.asarray([PROCESS_IDS[2]])
    standard_deviations = dict(zip(PROCESS_IDS, (1.0, 4.0, 16.0)))

    clean = generate_state_domain_consistent_truth(
        forcing,
        _parameters(),
        _initial_state(),
        schedule,
        standard_deviations,
        np.asarray([0.0]),
    )
    np.testing.assert_array_equal(clean["projection_adjustments"], 0.0)

    with pytest.raises(ValueError, match="truth state-domain gate failed"):
        generate_state_domain_consistent_truth(
            forcing,
            _parameters(),
            _initial_state(),
            schedule,
            standard_deviations,
            np.asarray([-100.0]),
        )


def test_first_complete_run_uses_only_complete_five_day_runs_in_window():
    assert (
        first_complete_top_ranked_run(
            np.asarray([False, True, True, True, True, True, False]),
            consecutive_days=5,
            window_days=6,
        )
        == 1
    )
    assert (
        first_complete_top_ranked_run(
            np.asarray([False, False, True, True, True, True, True]),
            consecutive_days=5,
            window_days=6,
        )
        is None
    )


def test_exact_interval_distinguishes_thirteen_from_twelve_successes():
    lower_13, upper_13 = exact_binomial_interval(13, 16)
    lower_12, upper_12 = exact_binomial_interval(12, 16)

    assert lower_13 > 0.5
    assert lower_12 < 0.5
    assert 0.0 < lower_12 < upper_12 < 1.0
    assert 0.0 < lower_13 < upper_13 < 1.0


def test_switch_summary_contains_sixteen_successful_events_per_direction():
    schedule = build_rotating_process_schedule(PROCESS_IDS, stage_length_days=180)
    probabilities = np.full((8, 3, 540, 3), 0.05, dtype=np.float64)
    index = {
        process_id: candidate for candidate, process_id in enumerate(PROCESS_IDS)
    }
    for block in range(8):
        for trial in range(3):
            for day, process_id in enumerate(schedule[trial]):
                probabilities[block, trial, day, index[process_id]] = 0.90

    events, summaries = summarize_switch_response(
        probabilities,
        schedule,
        PROCESS_IDS,
        response_window_days=30,
        consecutive_top_days=5,
        minimum_successful_events=13,
        minimum_interval_lower_bound=0.5,
    )

    assert len(events) == 48
    assert len(summaries) == 3
    assert {row["event_count"] for row in summaries} == {16}
    assert {row["successful_event_count"] for row in summaries} == {16}
    assert all(row["criterion_passed"] for row in summaries)
    assert all(row["median_response_start_day"] == 0.0 for row in summaries)
