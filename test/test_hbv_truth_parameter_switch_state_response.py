import numpy as np
import pytest
from pathlib import Path

from hbv_multilead_joint_uncertainty.truth_parameter_switch_state_response import (
    BRANCH_NAMES,
    STATE_GROUP_NAMES,
    build_switch_events,
    evaluate_physical_checks,
    propagate_matched_parameter_branches,
    summarize_state_response,
)


def _parameters(field_capacity=300.0):
    return {
        "parTT": 0.0,
        "parCFMAX": 2.0,
        "parCFR": 0.05,
        "parCWH": 0.1,
        "parFC": field_capacity,
        "parBETA": 2.0,
        "parLP": 0.8,
        "parK0": 0.2,
        "parK1": 0.1,
        "parUZL": 20.0,
        "parPERC": 1.0,
        "parK2": 0.03,
        "lag_time": 3.0,
    }


def _initial_state():
    return np.asarray(
        [0.0, 0.0, 250.0, 8.0, 40.0, 3.0, 2.5, 2.0, 1.5, 1.0, 0.5, 0.25, 0.1, 0.0, 0.0],
        dtype=np.float64,
    )


def test_matched_branches_share_initial_state_forcing_and_perturbations():
    initial_state = _initial_state()
    forcing = np.column_stack(
        (
            np.linspace(0.0, 4.0, 30),
            np.full(30, 1.0),
            np.full(30, 5.0),
        )
    )
    perturbations = np.zeros((30, 15), dtype=np.float64)
    result = propagate_matched_parameter_branches(
        initial_state=initial_state,
        forcing=forcing,
        process_perturbations=perturbations,
        old_parameters=_parameters(300.0),
        new_parameters=_parameters(100.0),
    )

    assert tuple(result["branch_names"].astype(str)) == BRANCH_NAMES
    assert result["branch_states"].shape == (2, 30, 15)
    np.testing.assert_array_equal(
        result["initial_states"], np.stack((initial_state, initial_state))
    )
    np.testing.assert_array_equal(result["shared_forcing"], forcing)
    np.testing.assert_array_equal(
        result["shared_process_perturbations"], perturbations
    )
    assert result["pretransition_projection_adjustments"][1, 0, 2] == -150.0
    assert result["pretransition_projection_adjustments"][0, 0, 2] == 0.0


def test_identical_parameters_produce_exactly_zero_response():
    parameters = _parameters(300.0)
    result = propagate_matched_parameter_branches(
        initial_state=_initial_state(),
        forcing=np.column_stack(
            (np.ones(30), np.ones(30), np.full(30, 5.0))
        ),
        process_perturbations=np.zeros((30, 15), dtype=np.float64),
        old_parameters=parameters,
        new_parameters=parameters,
    )

    np.testing.assert_array_equal(result["branch_state_difference"], 0.0)
    np.testing.assert_array_equal(result["branch_states"][0], result["branch_states"][1])


def test_propagation_rejects_routing_memory_process_noise():
    perturbations = np.zeros((30, 15), dtype=np.float64)
    perturbations[0, 5] = 1e-6
    with pytest.raises(ValueError, match="routing-memory process perturbations"):
        propagate_matched_parameter_branches(
            _initial_state(),
            np.column_stack((np.ones(30), np.ones(30), np.full(30, 5.0))),
            perturbations,
            _parameters(300.0),
            _parameters(100.0),
        )


def test_summary_reports_all_states_groups_transitions_and_projection_gate():
    event_count = 4
    response_days = 3
    differences = np.zeros((event_count, response_days, 15), dtype=np.float64)
    differences[:, 0, 0] = [1.0, -1.0, 2.0, -2.0]
    differences[:, 1, 0] = [2.0, -2.0, 4.0, -4.0]
    differences[:, 2, 0] = [0.5, -0.5, 1.0, -1.0]
    differences[:, :, 5] = 3.0
    scales = np.ones(15, dtype=np.float64)
    transition_labels = np.asarray(["a_to_b", "a_to_b", "b_to_c", "b_to_c"])
    projection = np.zeros((event_count, 15), dtype=np.float64)
    projection[1, 2] = -10.0

    result = summarize_state_response(
        differences,
        scales,
        transition_labels,
        projection,
        tolerance=1e-12,
    )

    assert result["standardized_response"].shape == (4, 3, 15)
    assert result["pooled_state_root_mean_square_standardized_response"].shape == (
        3,
        15,
    )
    assert result["transition_state_root_mean_square_standardized_response"].shape == (
        2,
        3,
        15,
    )
    assert result["group_root_mean_square_standardized_response"].shape == (3, 2)
    assert tuple(result["state_group_names"].astype(str)) == STATE_GROUP_NAMES
    assert result["per_state_peak_lead"][0] == 2
    assert result["initial_new_parameter_domain_projection_event_count"] == 1
    assert result["initial_new_parameter_domain_projection_state_event_count"][2] == 1
    assert result["decision"] == (
        "requires_separate_fixed_parameter_state_jump_recovery_experiment"
    )


def test_sealed_switch_events_form_48_exact_truth_reconstructions():
    project_root = Path(__file__).resolve().parents[1]
    source = (
        project_root
        / "results/23_hbv_multilead_joint_uncertainty"
        / "g3_ideal_gate_param_switch_v01/evidence.npz"
    )
    required = (
        "forcing_blocks",
        "warmup_days",
        "truth_states",
        "truth_process_perturbations",
        "truth_parameter_indices",
        "parameter_ids",
        "parameter_vectors",
    )
    with np.load(source, allow_pickle=False) as archive:
        arrays = {name: archive[name] for name in required}
    events = build_switch_events(
        **arrays,
        switch_boundaries=[180, 360],
        response_days=30,
    )

    assert events["branch_states"].shape == (48, 2, 30, 15)
    assert events["new_branch_truth_reconstruction_maximum_absolute_error"] == 0.0
    assert events["routing_shift_maximum_absolute_error"] == 0.0
    assert evaluate_physical_checks(events, tolerance=1e-12)["passed"] is True
