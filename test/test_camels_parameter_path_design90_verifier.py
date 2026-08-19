from __future__ import annotations

from copy import deepcopy

import pytest

from camels_switch_confirmation.verify_parameter_path_design90 import (
    evaluate_design90_gates,
)


DIRECTIONS = (
    "center_to_half",
    "center_to_double",
    "half_to_center",
    "half_to_double",
    "double_to_center",
    "double_to_half",
)


def _passing_metrics():
    arm_summary = {
        "C": {
            "task_count": 180,
            "event_count": 1080,
            "events_passed": 706,
            "event_pass_rate": 706 / 1080,
            "multiclass_brier": 0.3579735233144937,
            "mean_true_negative_log_probability": 9543.506547898589,
        },
        "P": {
            "task_count": 180,
            "event_count": 1080,
            "events_passed": 720,
            "event_pass_rate": 720 / 1080,
            "multiclass_brier": 0.30,
            "mean_true_negative_log_probability": 1.0,
            "true_probability_below_0_01_days": 100,
            "severe_negative_log_probability_days": 0,
            "zero_true_probability_days": 0,
        },
    }
    direction_summary = []
    for direction in DIRECTIONS:
        direction_summary.extend(
            [
                {"arm_id": "C", "direction": direction, "events": 180, "passed": 115},
                {"arm_id": "P", "direction": direction, "events": 180, "passed": 120},
            ]
        )
    return arm_summary, direction_summary


def test_design90_gate_accepts_all_registered_conditions():
    arms, directions = _passing_metrics()
    decision = evaluate_design90_gates(
        verification_passed=True,
        task_count=360,
        arm_summary=arms,
        direction_summary=directions,
    )
    assert decision["overall_status"] == "GO"
    assert all(decision["conditions"].values())


@pytest.mark.parametrize(
    "mutation",
    [
        "technical",
        "baseline_event_count",
        "p_not_better",
        "minimum_direction",
        "direction_decline",
        "brier",
        "mean_negative_log_probability",
        "low_probability_days",
        "severe_days",
        "zero_days",
    ],
)
def test_design90_gate_holds_when_any_registered_boundary_fails(mutation):
    arms, directions = _passing_metrics()
    verification_passed = True
    task_count = 360
    if mutation == "technical":
        task_count = 359
    elif mutation == "baseline_event_count":
        arms["C"]["events_passed"] = 705
    elif mutation == "p_not_better":
        arms["P"]["events_passed"] = 706
        arms["P"]["event_pass_rate"] = 706 / 1080
    elif mutation == "minimum_direction":
        next(row for row in directions if row["arm_id"] == "P")["passed"] = 89
    elif mutation == "direction_decline":
        c_row = next(row for row in directions if row["arm_id"] == "C")
        p_row = next(row for row in directions if row["arm_id"] == "P")
        c_row["passed"] = 120
        p_row["passed"] = 110
    elif mutation == "brier":
        arms["P"]["multiclass_brier"] = 0.7
    elif mutation == "mean_negative_log_probability":
        arms["P"]["mean_true_negative_log_probability"] = 1.2
    elif mutation == "low_probability_days":
        arms["P"]["true_probability_below_0_01_days"] = 1945
    elif mutation == "severe_days":
        arms["P"]["severe_negative_log_probability_days"] = 1
    elif mutation == "zero_days":
        arms["P"]["zero_true_probability_days"] = 1
    decision = evaluate_design90_gates(
        verification_passed=verification_passed,
        task_count=task_count,
        arm_summary=deepcopy(arms),
        direction_summary=deepcopy(directions),
    )
    assert decision["overall_status"] == "HOLD"


def test_design90_gate_rejects_missing_direction():
    arms, directions = _passing_metrics()
    directions.pop()
    with pytest.raises(ValueError, match="direction"):
        evaluate_design90_gates(
            verification_passed=True,
            task_count=360,
            arm_summary=arms,
            direction_summary=directions,
        )
