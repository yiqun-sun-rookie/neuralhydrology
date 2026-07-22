import importlib
import hashlib
import json
import sys
from dataclasses import replace
from pathlib import Path

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.sigma_filter import ModifiedUnscentedFilter  # noqa: E402
from hbv_joint_uncertainty.hbv_adapter import initial_state_vector, simulate_adapter  # noqa: E402
from hbv_multilead_joint_uncertainty.methods import MethodCandidate, build_method_bank  # noqa: E402


def _diagnostic_module():
    return importlib.import_module("hbv_multilead_joint_uncertainty.state_correction_diagnostic")


def _diagnostic_script_module():
    return importlib.import_module(
        "hbv_multilead_joint_uncertainty.scripts.run_state_correction_diagnostic"
    )


def _two_state_filter(filter_class, state_update_weights=None):
    covariance = np.array([[1.0, 0.35], [0.35, 0.8]], dtype=np.float64)
    arguments = {
        "state": np.array([2.0, 4.0], dtype=np.float64),
        "covariance": covariance,
        "transition": lambda values: np.asarray(values, dtype=np.float64),
        "observation": lambda values: np.array([values[0] + 0.5 * values[1]], dtype=np.float64),
        "process_covariance": np.diag([0.02, 0.03]),
        "observation_covariance": np.array([[0.2]], dtype=np.float64),
        "alpha": 0.6874,
        "beta": 2.0,
        "kappa": 0.0,
    }
    if state_update_weights is not None:
        arguments["state_update_weights"] = state_update_weights
    return filter_class(**arguments)


def _one_candidate_hbv_bank():
    parameters = {
        "parTT": 0.0,
        "parCFMAX": 3.0,
        "parCFR": 0.05,
        "parCWH": 0.1,
        "parFC": 150.0,
        "parBETA": 2.0,
        "parLP": 0.7,
        "parK0": 0.2,
        "parK1": 0.06,
        "parUZL": 15.0,
        "parPERC": 1.0,
        "parK2": 0.015,
        "lag_time": 3.0,
    }
    process_covariance = np.diag(np.r_[np.full(5, 1e-5), np.zeros(10)])
    candidate = MethodCandidate(
        candidate_id="trained_center__middle",
        parameter_id="trained_center",
        process_id="middle",
        process_scale=1e-5,
        parameters=parameters,
        process_covariance=process_covariance,
    )
    state = initial_state_vector(parameters)
    covariance = np.diag((0.01 * np.maximum(np.abs(state), 1.0))**2)
    return build_method_bank(
        candidates=(candidate,),
        initial_states={"trained_center": state},
        initial_covariance=covariance,
        observation_standard_deviation=0.1,
        factor_transition_stay_probability=0.98,
        interaction_mode="full",
    ), parameters


def test_partial_measurement_update_changes_only_allowed_state_mean():
    weighted_filter_class = getattr(_diagnostic_module(), "WeightedStateUpdateFilter")
    state_filter = _two_state_filter(weighted_filter_class, state_update_weights=np.array([1.0, 0.0]))

    result = state_filter.step(np.array([8.0]))

    assert result.posterior_state[0] != result.prior_state[0]
    assert result.posterior_state[1] == result.prior_state[1]
    np.testing.assert_array_equal(state_filter.state, result.posterior_state)
    np.testing.assert_allclose(result.posterior_covariance, result.posterior_covariance.T, rtol=0.0, atol=1e-12)
    assert float(np.min(np.linalg.eigvalsh(result.posterior_covariance))) >= -1e-12


def test_all_allowed_update_is_bitwise_identical_to_frozen_filter_path():
    weighted_filter_class = getattr(_diagnostic_module(), "WeightedStateUpdateFilter")
    frozen = _two_state_filter(ModifiedUnscentedFilter)
    diagnostic = _two_state_filter(weighted_filter_class, state_update_weights=np.ones(2))

    expected = frozen.step(np.array([8.0]))
    actual = diagnostic.step(np.array([8.0]))

    for field in (
        "prior_state",
        "prior_covariance",
        "prior_observation",
        "innovation",
        "innovation_covariance",
        "posterior_state",
        "posterior_covariance",
    ):
        np.testing.assert_array_equal(getattr(actual, field), getattr(expected, field))
    assert actual.log_likelihood == expected.log_likelihood


@pytest.mark.parametrize(
    "weights",
    [
        np.array([1.0]),
        np.array([1.0, 0.0, 1.0]),
        np.array([1.0, -0.1]),
        np.array([1.0, 1.1]),
        np.array([1.0, np.nan]),
    ],
)
def test_state_update_weights_reject_wrong_length_or_values(weights):
    weighted_filter_class = getattr(_diagnostic_module(), "WeightedStateUpdateFilter")

    with pytest.raises(ValueError, match="state update weights"):
        _two_state_filter(weighted_filter_class, state_update_weights=weights)


def test_lead_retention_is_frozen_to_three_day_half_life_after_day_one():
    retention_function = getattr(_diagnostic_module(), "lead_decay_retention")

    values = retention_function(np.array([1, 3, 7]), half_life_days=3.0)

    np.testing.assert_array_equal(
        values,
        np.array([1.0, 0.6299605249474366, 0.25], dtype=np.float64),
    )


@pytest.mark.parametrize(
    ("lead_days", "half_life_days"),
    [
        (np.array([0, 3, 7]), 3.0),
        (np.array([1, 3, 3]), 3.0),
        (np.array([1.0, 3.0, 7.0]), 3.0),
        (np.array([1, 3, 7]), 0.0),
        (np.array([1, 3, 7]), np.nan),
    ],
)
def test_lead_retention_rejects_invalid_contract(lead_days, half_life_days):
    retention_function = getattr(_diagnostic_module(), "lead_decay_retention")

    with pytest.raises(ValueError):
        retention_function(lead_days, half_life_days=half_life_days)


def test_physical_retention_uses_recession_and_half_triangular_routing_memory():
    retention_function = getattr(_diagnostic_module(), "physical_lead_retention")
    parameters = {
        "parK0": 0.2,
        "parK1": 0.1,
        "parUZL": 10.0,
        "parK2": 0.05,
        "lag_time": 4.0,
    }
    origin_state = np.zeros(15, dtype=np.float64)
    origin_state[3] = 12.0

    values = retention_function(np.array([1, 3, 7]), parameters, origin_state)

    assert values.shape == (3, 15)
    np.testing.assert_array_equal(values[0], np.ones(15))
    np.testing.assert_array_equal(values[:, :3], np.ones((3, 3)))
    np.testing.assert_allclose(values[1, 3], ((1.0 - 0.2) * (1.0 - 0.1))**2, rtol=0.0, atol=1e-15)
    np.testing.assert_allclose(values[1, 4], (1.0 - 0.05)**2, rtol=0.0, atol=1e-15)
    np.testing.assert_allclose(values[1, 5:9], np.array([0.5, 1.0 / 3.0, 0.0, 0.0]), rtol=0.0, atol=1e-15)
    np.testing.assert_array_equal(values[2, 5:], np.zeros(10))


def test_physical_retention_uses_slow_upper_recession_below_threshold():
    retention_function = getattr(_diagnostic_module(), "physical_lead_retention")
    parameters = {
        "parK0": 0.2,
        "parK1": 0.1,
        "parUZL": 10.0,
        "parK2": 0.05,
        "lag_time": 4.0,
    }
    origin_state = np.zeros(15, dtype=np.float64)
    origin_state[3] = 9.0

    values = retention_function(np.array([1, 3, 7]), parameters, origin_state)

    np.testing.assert_allclose(values[1, 3], (1.0 - 0.1)**2, rtol=0.0, atol=1e-15)


@pytest.mark.parametrize(
    ("lead_days", "parameters", "origin_state"),
    [
        (np.array([1, 3, 3]), {"parK0": 0.2, "parK1": 0.1, "parUZL": 10.0, "parK2": 0.05, "lag_time": 4.0}, np.zeros(15)),
        (np.array([1, 3, 7]), {"parK0": 0.2, "parK1": 0.1, "parUZL": 10.0, "parK2": 0.05}, np.zeros(15)),
        (np.array([1, 3, 7]), {"parK0": 0.2, "parK1": 1.1, "parUZL": 10.0, "parK2": 0.05, "lag_time": 4.0}, np.zeros(15)),
        (np.array([1, 3, 7]), {"parK0": 0.2, "parK1": 0.1, "parUZL": 10.0, "parK2": 0.05, "lag_time": 4.0}, np.zeros(14)),
    ],
)
def test_physical_retention_rejects_invalid_contract(lead_days, parameters, origin_state):
    retention_function = getattr(_diagnostic_module(), "physical_lead_retention")

    with pytest.raises(ValueError):
        retention_function(lead_days, parameters, origin_state)


def test_version_two_config_freezes_hydrologic_contract_before_results():
    config_path = (
        REPO_ROOT
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "configs"
        / "state_correction_propagation_v02.json"
    )
    config = json.loads(config_path.read_text(encoding="utf-8"))

    assert [entry["index"] for entry in config["state_contract"]] == list(range(15))
    assert [entry["name"] for entry in config["state_contract"][:5]] == [
        "SNOWPACK",
        "MELTWATER",
        "SM",
        "SUZ",
        "SLZ",
    ]
    assert [entry["unit"] for entry in config["state_contract"][:5]] == ["mm"] * 5
    assert [entry["unit"] for entry in config["state_contract"][5:]] == ["mm/day"] * 10
    assert config["saved_array_shapes_per_basin"]["target_candidate_states"] == [358, 3, 9, 15]
    assert config["formal_replay_validation"]["maximum_absolute_error"] == 1e-12
    assert config["formal_replay_validation"]["maximum_relative_error"] == 1e-10
    assert config["continuation_gate"]["control_id"] == "physical_recession_routing_mean_decay"
    roles = {control["control_id"]: control["role"] for control in config["controls"]}
    assert roles["three_day_half_life_mean_decay_sensitivity"] == "sensitivity_only_not_eligible_for_continuation_gate"


def test_version_seven_config_replaces_invalid_controls_before_corrected_results():
    load_config = getattr(_diagnostic_script_module(), "load_effective_config")
    config_path = (
        REPO_ROOT
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "configs"
        / "state_correction_propagation_v07.json"
    )

    config, overlay = load_config(config_path)

    control_ids = [entry["control_id"] for entry in config["controls"]]
    assert "physical_recession_routing_mean_decay" not in control_ids
    assert "three_day_half_life_additional_mean_taper_sensitivity" in control_ids
    assert config["continuation_gate"]["control_id"] == "hydrologic_five_states_only"
    assert config["natural_state_correction_propagation"]["uses_model_propagation_count"] == 1
    assert config["natural_state_correction_propagation"]["produces_separate_tapered_forecast"] is False
    assert config["state_mask_branching"]["shared_prior_each_origin"] is True
    assert config["state_mask_branching"]["branch_enters_next_origin"] is False
    assert config["checkpoint"]["atomic"] is True
    assert config["checkpoint"]["resume_exact_array_requirement"] is True
    assert config["resource"] == overlay["resource"]


def test_combined_origin_correction_separates_state_update_from_probability_reweighting():
    decomposition_function = getattr(_diagnostic_module(), "decompose_combined_origin_correction")
    prior_states = np.array([[1.0, 10.0], [3.0, 20.0]], dtype=np.float64)
    posterior_states = np.array([[2.0, 10.5], [5.0, 19.0]], dtype=np.float64)
    prior_probabilities = np.array([0.75, 0.25], dtype=np.float64)
    posterior_probabilities = np.array([0.4, 0.6], dtype=np.float64)

    result = decomposition_function(
        prior_states,
        posterior_states,
        prior_probabilities,
        posterior_probabilities,
    )

    expected_prior = prior_probabilities @ prior_states
    expected_posterior = posterior_probabilities @ posterior_states
    expected_state_update = posterior_probabilities @ (posterior_states - prior_states)
    expected_probability_reweighting = (posterior_probabilities - prior_probabilities) @ prior_states
    np.testing.assert_allclose(result["combined_prior_state"], expected_prior, rtol=0.0, atol=1e-15)
    np.testing.assert_allclose(result["combined_posterior_state"], expected_posterior, rtol=0.0, atol=1e-15)
    np.testing.assert_allclose(result["state_update_contribution"], expected_state_update, rtol=0.0, atol=1e-15)
    np.testing.assert_allclose(
        result["probability_reweighting_contribution"],
        expected_probability_reweighting,
        rtol=0.0,
        atol=1e-15,
    )
    np.testing.assert_allclose(
        result["total_correction"],
        expected_state_update + expected_probability_reweighting,
        rtol=0.0,
        atol=1e-15,
    )


def test_blended_target_state_preserves_reference_at_retention_one_and_removed_at_zero():
    blend_function = getattr(_diagnostic_module(), "blend_target_state_correction")
    reference_state = np.array([4.0, 8.0], dtype=np.float64)
    removed_state = np.array([2.0, 10.0], dtype=np.float64)
    reference_covariance = np.array([[2.0, 0.1], [0.1, 1.0]], dtype=np.float64)
    removed_covariance = np.array([[4.0, 0.2], [0.2, 3.0]], dtype=np.float64)

    state_one, covariance_one = blend_function(
        reference_state,
        removed_state,
        reference_covariance,
        removed_covariance,
        retention=1.0,
    )
    state_zero, covariance_zero = blend_function(
        reference_state,
        removed_state,
        reference_covariance,
        removed_covariance,
        retention=0.0,
    )

    np.testing.assert_array_equal(state_one, reference_state)
    np.testing.assert_array_equal(covariance_one, reference_covariance)
    np.testing.assert_array_equal(state_zero, removed_state)
    np.testing.assert_array_equal(covariance_zero, removed_covariance)


@pytest.mark.parametrize("retention", [-0.1, 1.1, np.nan])
def test_blended_target_state_rejects_invalid_retention(retention):
    blend_function = getattr(_diagnostic_module(), "blend_target_state_correction")

    with pytest.raises(ValueError, match="retention"):
        blend_function(
            np.ones(2),
            np.zeros(2),
            np.eye(2),
            np.eye(2),
            retention=retention,
        )


def test_origin_mean_retention_scales_only_the_candidate_mean_correction():
    apply_function = getattr(_diagnostic_module(), "apply_origin_mean_retention")
    prior = np.array([[1.0, 3.0], [2.0, 5.0]])
    posterior = np.array([[2.0, 1.0], [6.0, 9.0]])
    retention = np.array([[1.0, 0.0], [0.25, 0.5]])

    adjusted = apply_function(prior, posterior, retention)

    np.testing.assert_array_equal(adjusted, prior + retention * (posterior - prior))


def test_replay_validation_reports_frozen_absolute_and_relative_errors():
    validate_function = getattr(_diagnostic_module(), "validate_replay_arrays")
    saved = {"predictions": np.array([1.0, 2.0]), "probabilities": np.array([0.0, 0.5])}
    replayed = {
        "predictions": np.array([1.0 + 5e-13, 2.0]),
        "probabilities": np.array([5e-13, 0.5]),
    }

    report = validate_function(
        replayed,
        saved,
        maximum_absolute_error=1e-12,
        maximum_relative_error=1.0,
        relative_error_denominator_floor=1e-12,
    )

    assert report["passed"] is True
    assert report["maximum_absolute_error"] == pytest.approx(5e-13, rel=1e-4)
    assert report["maximum_relative_error"] == pytest.approx(0.5, rel=1e-12)
    assert set(report["arrays"]) == set(saved)


def test_replay_validation_rejects_shape_mismatch():
    validate_function = getattr(_diagnostic_module(), "validate_replay_arrays")

    with pytest.raises(ValueError, match="shape"):
        validate_function(
            {"predictions": np.ones(2)},
            {"predictions": np.ones(3)},
            maximum_absolute_error=1e-12,
            maximum_relative_error=1e-10,
            relative_error_denominator_floor=1e-12,
        )


def test_small_diagnostic_replay_is_causal_and_preserves_input_bank():
    run_function = getattr(_diagnostic_module(), "run_state_diagnostic_assimilation")
    bank, parameters = _one_candidate_hbv_bank()
    forcing = np.column_stack(
        (
            np.array([1.0, 0.0, 2.0, 0.0, 0.5, 0.0, 1.5, 0.0, 0.0, 1.0]),
            np.full(10, 0.4),
            np.full(10, 5.0),
        )
    )
    observations, _ = simulate_adapter(
        forcing[:, 0], forcing[:, 1], forcing[:, 2], parameters, initial_state=initial_state_vector(parameters)
    )
    observations = observations + np.linspace(0.05, 0.2, len(observations))
    perturbed = observations.copy()
    perturbed[1:] += 100.0
    original_state = bank.estimator.filters[0].state.copy()
    masks = {
        "current_joint_all_fifteen_states": np.ones(15),
        "hydrologic_five_states_only": np.r_[np.ones(5), np.zeros(10)],
        "runoff_two_states_only": np.r_[np.zeros(3), np.ones(2), np.zeros(10)],
    }

    reference = run_function(forcing, observations, bank, masks, lead_days=(1, 3, 7))
    changed_future = run_function(forcing, perturbed, bank, masks, lead_days=(1, 3, 7))

    np.testing.assert_array_equal(bank.estimator.filters[0].state, original_state)
    assert reference.origin_indices.shape == (3,)
    assert reference.target_indices.shape == (3, 3)
    assert reference.origin_candidate_prior_states.shape == (3, 1, 15)
    assert reference.origin_candidate_posterior_states.shape == (3, 1, 15)
    assert reference.controls["current_joint_all_fifteen_states"].candidate_states.shape == (3, 3, 1, 15)
    np.testing.assert_array_equal(
        reference.controls["current_joint_all_fifteen_states"].predictions[0],
        changed_future.controls["current_joint_all_fifteen_states"].predictions[0],
    )
    np.testing.assert_array_equal(
        reference.controls[
            "three_day_half_life_additional_mean_taper_sensitivity"
        ].predictions[:, 0],
        reference.controls["current_joint_all_fifteen_states"].predictions[:, 0],
    )


def test_diagnostic_array_export_contains_complete_state_evidence():
    run_function = getattr(_diagnostic_module(), "run_state_diagnostic_assimilation")
    export_function = getattr(_diagnostic_module(), "diagnostic_result_arrays")
    bank, parameters = _one_candidate_hbv_bank()
    forcing = np.column_stack((np.ones(8), np.full(8, 0.2), np.full(8, 5.0)))
    observations, _ = simulate_adapter(
        forcing[:, 0], forcing[:, 1], forcing[:, 2], parameters, initial_state=initial_state_vector(parameters)
    )
    masks = {"current_joint_all_fifteen_states": np.ones(15)}
    result = run_function(forcing, observations, bank, masks, lead_days=(1, 3, 7))

    arrays = export_function(result)

    required = {
        "origin_candidate_prior_states",
        "origin_candidate_posterior_states",
        "origin_candidate_state_corrections",
        "origin_prior_probabilities",
        "origin_posterior_probabilities",
        "natural_hbv_candidate_state_correction",
        "natural_hbv_combined_state_correction",
        "natural_hbv_combined_prediction_correction",
        "current_joint_all_fifteen_states__origin_candidate_prior_states",
        "current_joint_all_fifteen_states__origin_candidate_posterior_states",
        "three_day_half_life_additional_mean_taper_sensitivity__origin_retention",
    }
    assert required <= set(arrays)
    assert arrays["origin_candidate_prior_states"].shape == (1, 1, 15)


def test_hbv_equation_water_balance_is_zero_for_one_deterministic_step():
    balance_function = getattr(_diagnostic_module(), "hbv_water_balance_residual")
    _, parameters = _one_candidate_hbv_bank()
    state = initial_state_vector(parameters)

    result = balance_function(state, rain=8.0, pet=0.7, temperature=5.0, parameters=parameters)

    assert result["absolute_residual_mm"] <= 1e-12
    np.testing.assert_allclose(
        result["storage_change_mm"],
        result["precipitation_mm"] - result["actual_evaporation_mm"] - result["raw_runoff_mm"],
        rtol=0.0,
        atol=1e-12,
    )


def test_continuation_gate_uses_per_basin_percentages_before_medians():
    gate_function = getattr(_diagnostic_module(), "evaluate_continuation_gate")
    rows = []
    for index in range(16):
        basin_id = f"{index:08d}"
        open_loop_7 = 10.0 + index
        hydrologic_7 = open_loop_7 * (0.99 if index < 9 else 1.01)
        joint_1 = 2.0 + index
        hydrologic_1 = joint_1 * 1.005
        rows.extend(
            [
                {"basin_id": basin_id, "control_id": "open_loop", "lead_days": 7, "rmse": open_loop_7},
                {
                    "basin_id": basin_id,
                    "control_id": "hydrologic_five_states_only",
                    "lead_days": 7,
                    "rmse": hydrologic_7,
                },
                {"basin_id": basin_id, "control_id": "current_joint_all_fifteen_states", "lead_days": 1, "rmse": joint_1},
                {
                    "basin_id": basin_id,
                    "control_id": "hydrologic_five_states_only",
                    "lead_days": 1,
                    "rmse": hydrologic_1,
                },
            ]
        )

    decision = gate_function(rows, expected_basin_count=16)

    assert decision["seven_day_strict_win_count_vs_open_loop"] == 9
    assert decision["seven_day_median_rmse_change_percent_vs_open_loop"] == pytest.approx(-1.0)
    assert decision["one_day_median_rmse_increase_percent_vs_current_joint"] == pytest.approx(0.5)
    assert decision["all_conditions_passed"] is True
    assert decision["recommend_larger_sample"] is True


def test_checksum_package_verifier_checks_table_hash_and_every_file(tmp_path):
    verify_function = getattr(_diagnostic_script_module(), "verify_checksum_package")
    (tmp_path / "nested").mkdir()
    value_path = tmp_path / "nested" / "value.txt"
    value_path.write_text("frozen\n", encoding="utf-8")
    file_hash = hashlib.sha256(value_path.read_bytes()).hexdigest()
    checksum_path = tmp_path / "checksums.json"
    checksum_path.write_text(
        json.dumps({"nested/value.txt": file_hash}, indent=2) + "\n",
        encoding="utf-8",
    )
    checksum_hash = hashlib.sha256(checksum_path.read_bytes()).hexdigest()

    result = verify_function(tmp_path, checksum_hash)

    assert result["passed"] is True
    assert result["declared_file_count"] == 1
    assert result["verified_file_count"] == 1

    (tmp_path / "nested" / "value.txt").write_text("changed\n", encoding="utf-8")
    with pytest.raises(ValueError, match="checksum"):
        verify_function(tmp_path, checksum_hash)


def test_finalize_output_checksums_refreshes_resource_history_after_monitor_finish(tmp_path):
    module = _diagnostic_script_module()
    finalize = getattr(module, "finalize_output_checksums")
    payload_path = tmp_path / "payload.txt"
    resource_path = tmp_path / "resource_history.json"
    payload_path.write_text("stable payload\n", encoding="utf-8")
    resource_path.write_text("monitor still running\n", encoding="utf-8")
    stable_hashes = {
        "payload.txt": hashlib.sha256(payload_path.read_bytes()).hexdigest(),
    }

    resource_path.write_text("monitor finished\n", encoding="utf-8")
    result = finalize(
        tmp_path,
        stable_hashes=stable_hashes,
        refresh_relatives={"resource_history.json"},
    )

    declared = json.loads((tmp_path / "checksums.json").read_text(encoding="utf-8"))
    assert declared["payload.txt"] == stable_hashes["payload.txt"]
    assert declared["resource_history.json"] == hashlib.sha256(resource_path.read_bytes()).hexdigest()
    assert result["verified_file_count"] == 2
    assert result["checksum_table_sha256"] == hashlib.sha256(
        (tmp_path / "checksums.json").read_bytes()
    ).hexdigest()


def test_control_metric_rows_use_exact_target_observations():
    metric_function = getattr(_diagnostic_script_module(), "control_metric_rows")
    observations = np.array([[1.0, 2.0, 4.0], [2.0, 4.0, 8.0]])
    predictions = {
        "current_joint_all_fifteen_states": observations.copy(),
        "physical_recession_routing_mean_decay": observations + 1.0,
    }

    rows = metric_function("00000001", np.array([1, 3, 7]), observations, predictions)

    assert len(rows) == 6
    exact = [
        row
        for row in rows
        if row["control_id"] == "current_joint_all_fifteen_states" and row["lead_days"] == 7
    ][0]
    assert exact["rmse"] == 0.0
    assert exact["n_origins"] == 2


def test_diagnostic_replay_reports_each_completed_origin_for_resource_checks():
    run_function = getattr(_diagnostic_module(), "run_state_diagnostic_assimilation")
    bank, parameters = _one_candidate_hbv_bank()
    forcing = np.column_stack((np.ones(8), np.full(8, 0.2), np.full(8, 5.0)))
    observations, _ = simulate_adapter(
        forcing[:, 0], forcing[:, 1], forcing[:, 2], parameters, initial_state=initial_state_vector(parameters)
    )
    events = []

    run_function(
        forcing,
        observations,
        bank,
        {"current_joint_all_fifteen_states": np.ones(15)},
        lead_days=(1, 3, 7),
        progress_callback=lambda completed, total: events.append((completed, total)),
    )

    assert events == [(1, 1)]


def test_state_mask_branches_share_the_reference_prior_at_every_origin():
    run_function = getattr(_diagnostic_module(), "run_state_diagnostic_assimilation")
    bank, parameters = _one_candidate_hbv_bank()
    forcing = np.column_stack((np.ones(10), np.full(10, 0.2), np.full(10, 5.0)))
    observations, _ = simulate_adapter(
        forcing[:, 0], forcing[:, 1], forcing[:, 2], parameters, initial_state=initial_state_vector(parameters)
    )
    observations = observations + np.linspace(0.1, 0.3, len(observations))
    masks = {
        "current_joint_all_fifteen_states": np.ones(15),
        "hydrologic_five_states_only": np.r_[np.ones(5), np.zeros(10)],
        "runoff_two_states_only": np.r_[np.zeros(3), np.ones(2), np.zeros(10)],
    }

    result = run_function(forcing, observations, bank, masks, lead_days=(1, 3, 7))

    priors = result.control_origin_candidate_prior_states
    prior_covariances = result.control_origin_candidate_prior_covariance_diagonals
    prior_probabilities = result.control_origin_prior_probabilities
    for control_id in ("hydrologic_five_states_only", "runoff_two_states_only"):
        np.testing.assert_array_equal(
            priors[control_id], priors["current_joint_all_fifteen_states"]
        )
        np.testing.assert_array_equal(
            prior_covariances[control_id],
            prior_covariances["current_joint_all_fifteen_states"],
        )
        np.testing.assert_array_equal(
            prior_probabilities[control_id],
            prior_probabilities["current_joint_all_fifteen_states"],
        )


def test_natural_hbv_propagation_is_measured_without_a_second_recession_taper():
    run_function = getattr(_diagnostic_module(), "run_state_diagnostic_assimilation")
    bank, parameters = _one_candidate_hbv_bank()
    forcing = np.column_stack((np.ones(8), np.full(8, 0.2), np.full(8, 5.0)))
    observations, _ = simulate_adapter(
        forcing[:, 0], forcing[:, 1], forcing[:, 2], parameters, initial_state=initial_state_vector(parameters)
    )

    result = run_function(
        forcing,
        observations,
        bank,
        {"current_joint_all_fifteen_states": np.ones(15)},
        lead_days=(1, 3, 7),
    )

    assert "physical_recession_routing_mean_decay" not in result.controls
    assert "three_day_half_life_additional_mean_taper_sensitivity" in result.controls
    np.testing.assert_array_equal(
        result.natural_hbv_candidate_state_correction,
        result.controls["current_joint_all_fifteen_states"].candidate_states
        - result.controls["origin_mean_correction_removed"].candidate_states,
    )
    np.testing.assert_array_equal(
        result.natural_hbv_combined_prediction_correction,
        result.controls["current_joint_all_fifteen_states"].predictions
        - result.controls["origin_mean_correction_removed"].predictions,
    )


def test_atomic_checkpoint_resume_matches_uninterrupted_diagnostic_arrays(tmp_path):
    module = _diagnostic_module()
    run_function = getattr(module, "run_state_diagnostic_assimilation")
    save_checkpoint = getattr(module, "save_diagnostic_checkpoint")
    load_checkpoint = getattr(module, "load_diagnostic_checkpoint")
    export_function = getattr(module, "diagnostic_result_arrays")
    bank, parameters = _one_candidate_hbv_bank()
    forcing = np.column_stack((np.ones(10), np.full(10, 0.2), np.full(10, 5.0)))
    observations, _ = simulate_adapter(
        forcing[:, 0], forcing[:, 1], forcing[:, 2], parameters, initial_state=initial_state_vector(parameters)
    )
    observations = observations + np.linspace(0.1, 0.3, len(observations))
    masks = {
        "current_joint_all_fifteen_states": np.ones(15),
        "hydrologic_five_states_only": np.r_[np.ones(5), np.zeros(10)],
    }
    checkpoint_path = tmp_path / "origin_checkpoint.npz"
    identity = {
        "experiment_family": "checkpoint-test",
        "config_sha256": "a" * 64,
        "input_sha256": "b" * 64,
        "source_sha256": "c" * 64,
    }

    def interrupt_after_first_origin(completed, total, checkpoint):
        assert total == 3
        if completed == 1:
            save_checkpoint(checkpoint_path, checkpoint, identity)
            raise RuntimeError("injected resource stop")

    with pytest.raises(RuntimeError, match="injected resource stop"):
        run_function(
            forcing,
            observations,
            bank,
            masks,
            lead_days=(1, 3, 7),
            checkpoint_callback=interrupt_after_first_origin,
        )

    resumed = run_function(
        forcing,
        observations,
        bank,
        masks,
        lead_days=(1, 3, 7),
        resume_checkpoint=load_checkpoint(checkpoint_path, identity),
    )
    uninterrupted = run_function(
        forcing,
        observations,
        bank,
        masks,
        lead_days=(1, 3, 7),
    )

    resumed_arrays = export_function(resumed)
    uninterrupted_arrays = export_function(uninterrupted)
    assert set(resumed_arrays) == set(uninterrupted_arrays)
    for name in resumed_arrays:
        np.testing.assert_array_equal(resumed_arrays[name], uninterrupted_arrays[name])


def test_resume_rejects_checkpoint_file_changed_after_manifest_hash(tmp_path):
    module = _diagnostic_module()
    script = _diagnostic_script_module()
    run_function = getattr(module, "run_state_diagnostic_assimilation")
    save_checkpoint = getattr(module, "save_diagnostic_checkpoint")
    load_verified = getattr(script, "load_verified_resume_checkpoint")
    bank, parameters = _one_candidate_hbv_bank()
    forcing = np.column_stack((np.ones(10), np.full(10, 0.2), np.full(10, 5.0)))
    observations, _ = simulate_adapter(
        forcing[:, 0], forcing[:, 1], forcing[:, 2], parameters, initial_state=initial_state_vector(parameters)
    )
    checkpoint_path = tmp_path / "12143600.npz"
    identity = {
        "experiment_family": "checkpoint-test",
        "config_sha256": "a" * 64,
        "input_sha256": "b" * 64,
        "source_sha256": "c" * 64,
        "checkpoint_experiment_id": "original-run",
    }

    def save_first(completed, _total, checkpoint):
        if completed == 1:
            save_checkpoint(checkpoint_path, checkpoint, identity)
            raise RuntimeError("stop")

    with pytest.raises(RuntimeError, match="stop"):
        run_function(
            forcing,
            observations,
            bank,
            {"current_joint_all_fifteen_states": np.ones(15)},
            lead_days=(1, 3, 7),
            checkpoint_callback=save_first,
        )
    manifest_path = checkpoint_path.with_suffix(".json")
    manifest_path.write_text(
        json.dumps(
            {
                "identity": identity,
                "checkpoint_sha256": hashlib.sha256(checkpoint_path.read_bytes()).hexdigest(),
            }
        ),
        encoding="utf-8",
    )
    current_identity = {key: value for key, value in identity.items() if key != "checkpoint_experiment_id"}
    assert load_verified(checkpoint_path, current_identity).completed_origin_count == 1

    changed = bytearray(checkpoint_path.read_bytes())
    changed[-32] ^= 1
    checkpoint_path.write_bytes(changed)
    with pytest.raises(ValueError, match="checkpoint.*checksum"):
        load_verified(checkpoint_path, current_identity)


def test_shared_prior_validation_records_full_covariance_maximum_difference():
    run_function = getattr(_diagnostic_module(), "run_state_diagnostic_assimilation")
    bank, parameters = _one_candidate_hbv_bank()
    forcing = np.column_stack((np.ones(10), np.full(10, 0.2), np.full(10, 5.0)))
    observations, _ = simulate_adapter(
        forcing[:, 0], forcing[:, 1], forcing[:, 2], parameters, initial_state=initial_state_vector(parameters)
    )
    masks = {
        "current_joint_all_fifteen_states": np.ones(15),
        "hydrologic_five_states_only": np.r_[np.ones(5), np.zeros(10)],
        "runoff_two_states_only": np.r_[np.zeros(3), np.ones(2), np.zeros(10)],
    }

    result = run_function(forcing, observations, bank, masks, lead_days=(1, 3, 7))

    validation = result.shared_origin_prior_validation
    assert validation["compared_origin_count"] == 3
    assert validation["compared_branch_count"] == 2
    assert validation["maximum_candidate_state_absolute_difference"] == 0.0
    assert validation["maximum_candidate_full_covariance_absolute_difference"] == 0.0
    assert validation["maximum_model_probability_absolute_difference"] == 0.0


def test_resource_history_verification_is_written_before_output_checksums(tmp_path):
    verify_and_write = getattr(_diagnostic_script_module(), "write_resource_history_verification")
    config = {
        "minimum_start_available_fraction": 0.12,
        "minimum_running_available_fraction": 0.075,
        "maximum_estimated_peak_fraction_of_available": 0.40,
        "minimum_free_disk_gib": 50.0,
        "minimum_output_space_multiplier": 3.0,
        "monitor_interval_seconds": 15.0,
        "reserved_logical_processors": 2,
    }
    common = {
        "total_memory_gib": 32.0,
        "available_memory_gib": 4.0,
        "available_memory_fraction": 0.125,
        "cpu_load_percent": 10.0,
        "logical_processors": 32,
        "disk_free_gib": 100.0,
        "gpu_name": None,
        "gpu_memory_total_mib": None,
        "gpu_memory_free_mib": None,
        "gpu_utilization_percent": None,
        "process_rss_gib": 0.2,
        "process_peak_working_set_gib": 0.3,
    }
    history = [
        {
            **common,
            "event": "start",
            "timestamp": "2026-07-16T00:00:00+08:00",
            "estimated_peak_gib": 0.75,
            "estimated_output_gib": 0.25,
            "numerical_thread_limit": 1,
            "reserved_logical_processors": 2,
        },
        {**common, "event": "finish", "timestamp": "2026-07-16T00:00:10+08:00"},
    ]
    history_path = tmp_path / "resource_history.json"
    report_path = tmp_path / "resource_history_verification.json"
    history_path.write_text(json.dumps(history), encoding="utf-8")

    report = verify_and_write(history_path, config, report_path)

    assert report["sample_count"] == 2
    assert report["first_event"] == "start"
    assert report["last_event"] == "finish"
    assert json.loads(report_path.read_text(encoding="utf-8")) == report


def test_complete_final_origin_checkpoint_resumes_without_recomputing_arrays():
    module = _diagnostic_module()
    run_function = getattr(module, "run_state_diagnostic_assimilation")
    export_function = getattr(module, "diagnostic_result_arrays")
    bank, parameters = _one_candidate_hbv_bank()
    forcing = np.column_stack((np.ones(10), np.full(10, 0.2), np.full(10, 5.0)))
    observations, _ = simulate_adapter(
        forcing[:, 0], forcing[:, 1], forcing[:, 2], parameters, initial_state=initial_state_vector(parameters)
    )
    masks = {
        "current_joint_all_fifteen_states": np.ones(15),
        "hydrologic_five_states_only": np.r_[np.ones(5), np.zeros(10)],
    }
    captured = {}

    def capture_final(completed, total, checkpoint):
        if completed == total:
            captured["checkpoint"] = checkpoint

    uninterrupted = run_function(
        forcing,
        observations,
        bank,
        masks,
        lead_days=(1, 3, 7),
        checkpoint_callback=capture_final,
    )
    final_checkpoint = captured["checkpoint"]
    assert final_checkpoint.completed_origin_count == 3

    resumed = run_function(
        forcing,
        observations,
        bank,
        masks,
        lead_days=(1, 3, 7),
        resume_checkpoint=final_checkpoint,
    )
    expected_arrays = export_function(uninterrupted)
    actual_arrays = export_function(resumed)
    assert set(actual_arrays) == set(expected_arrays)
    for name in expected_arrays:
        np.testing.assert_array_equal(actual_arrays[name], expected_arrays[name])

    with pytest.raises(ValueError, match="completion index"):
        run_function(
            forcing,
            observations,
            bank,
            masks,
            lead_days=(1, 3, 7),
            resume_checkpoint=replace(final_checkpoint, completed_origin_count=0),
        )
    with pytest.raises(ValueError, match="completion index"):
        run_function(
            forcing,
            observations,
            bank,
            masks,
            lead_days=(1, 3, 7),
            resume_checkpoint=replace(final_checkpoint, completed_origin_count=4),
        )
