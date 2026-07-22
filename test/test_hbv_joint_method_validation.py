import sys
import json
from pathlib import Path

import numpy as np


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.joint_method_validation import (  # noqa: E402
    METHOD_NAMES,
    run_stable_joint_method_validation,
)
from hbv_multilead_joint_uncertainty.scripts.run_joint_method_validation import (  # noqa: E402
    _forcing_blocks,
    run as run_packaged_validation,
)


BASE_PARAMETERS = {
    "parTT": 0.0,
    "parCFMAX": 3.2,
    "parCFR": 0.04,
    "parCWH": 0.1,
    "parFC": 250.0,
    "parBETA": 2.1,
    "parLP": 0.7,
    "parK0": 0.2,
    "parK1": 0.06,
    "parUZL": 18.0,
    "parPERC": 1.2,
    "parK2": 0.015,
    "lag_time": 3.0,
}


def test_assimilation_duration_conditions_share_exact_forcing_prefix():
    block = ({"forcing_seed": 980001},)
    base = {
        "lead_days": [1, 3, 7],
        "forcing": {
            "warmup_days": 45,
            "reference_total_days": 97,
            "rain_shape": 0.8,
            "rain_scale": 4.0,
        },
    }
    short = json.loads(json.dumps(base))
    short["assimilation_days"] = 7
    long = json.loads(json.dumps(base))
    long["assimilation_days"] = 45

    short_forcing = _forcing_blocks(short, block)
    long_forcing = _forcing_blocks(long, block)

    assert np.array_equal(short_forcing, long_forcing[:, : short_forcing.shape[1]])


def _contracts():
    parameters = {}
    for index, parameter_id in enumerate(
        ("equifinal_diverse_1", "trained_center", "equifinal_diverse_2")
    ):
        values = BASE_PARAMETERS.copy()
        values["parFC"] += 20.0 * (index - 1)
        values["parK1"] += 0.01 * (index - 1)
        parameters[parameter_id] = values
    covariances = {}
    scales = {}
    for index, process_id in enumerate(("small", "medium", "large")):
        diagonal = np.zeros(15, dtype=np.float64)
        diagonal[:5] = (10.0**index) * np.asarray(
            [1e-3, 1e-5, 1e-3, 1e-4, 1e-3], dtype=np.float64
        )
        covariances[process_id] = np.diag(diagonal)
        scales[process_id] = 10.0 ** (-4 + index)
    return parameters, scales, covariances


def _forcing(seed=8101, days=19):
    rng = np.random.default_rng(seed)
    angle = np.linspace(0.0, 2.0 * np.pi, days)
    return np.column_stack(
        (
            rng.gamma(0.8, 4.0, size=days),
            np.maximum(0.0, 2.0 + np.sin(angle)),
            4.0 + 12.0 * np.sin(angle - np.pi / 2.0),
        )
    )


def _run():
    parameters, scales, covariances = _contracts()
    return run_stable_joint_method_validation(
        forcing_blocks=_forcing()[None, :, :],
        block_ids=("block_01",),
        parameter_vectors=parameters,
        process_scales=scales,
        process_covariances=covariances,
        selected_process_id="large",
        process_noise_seeds=(9101,),
        observation_noise_seeds=(10101,),
        warmup_days=8,
        assimilation_days=4,
        lead_days=(1, 3, 7),
        initial_covariance_fraction=0.001,
        observation_standard_deviation=0.05,
        factor_transition_stay_probability=0.98,
    )


def _run_switching():
    parameters, scales, covariances = _contracts()
    return run_stable_joint_method_validation(
        forcing_blocks=_forcing()[None, :, :],
        block_ids=("block_01",),
        parameter_vectors=parameters,
        process_scales=scales,
        process_covariances=covariances,
        selected_process_id="large",
        process_noise_seeds=(9101,),
        observation_noise_seeds=(10101,),
        warmup_days=8,
        assimilation_days=4,
        lead_days=(1, 3, 7),
        initial_covariance_fraction=0.001,
        observation_standard_deviation=0.05,
        factor_transition_stay_probability=0.98,
        truth_switch_period_days=2,
        truth_switch_candidate_step=4,
    )


def test_periodic_switching_truth_tracks_current_candidate_and_scheduled_process_scale():
    result = _run_switching()
    _, _, covariances = _contracts()
    process_ids = ("small", "medium", "large")

    np.testing.assert_array_equal(
        result.truth_candidate_schedules[:, result.assimilation_days - 1],
        np.arange(9),
    )
    for truth_index in range(9):
        for day, candidate_index in enumerate(result.truth_candidate_schedules[truth_index]):
            process_id = process_ids[int(candidate_index) % 3]
            expected = result.process_standard_normals[0, day] * np.sqrt(
                np.diag(covariances[process_id])
            )
            np.testing.assert_allclose(
                result.truth_process_perturbations[0, truth_index, day],
                expected,
                rtol=0.0,
                atol=0.0,
            )


def test_stable_joint_validation_covers_all_nine_truth_candidates_and_six_controls():
    result = _run()

    assert result.method_names == METHOD_NAMES == (
        "open_loop",
        "fixed_filter",
        "parameter_only",
        "noise_only",
        "joint",
        "oracle_filter",
    )
    assert result.truth_candidate_factors == tuple(
        (parameter_id, process_id)
        for parameter_id in ("equifinal_diverse_1", "trained_center", "equifinal_diverse_2")
        for process_id in ("small", "medium", "large")
    )
    np.testing.assert_array_equal(result.method_candidate_counts, np.array([1, 1, 3, 3, 9, 1]))
    assert result.truth_states.shape == (1, 9, 11, 15)
    assert result.method_predictions.shape == (1, 9, 6, 3)
    assert result.method_candidate_predictions.shape == (1, 9, 6, 3, 9)
    assert result.method_probabilities.shape == (1, 9, 6, 3, 9)
    assert result.method_origin_states.shape == (1, 9, 6, 15)
    assert result.joint_origin_probabilities.shape == (1, 9, 9)
    assert np.all(np.isfinite(result.method_predictions))
    assert np.all(np.isfinite(result.method_absolute_errors))


def test_truth_draws_and_all_method_mixtures_are_reconstructable_from_saved_arrays():
    result = _run()
    _, _, covariances = _contracts()
    process_ids = ("small", "medium", "large")

    for truth_index, (_, process_id) in enumerate(result.truth_candidate_factors):
        expected = result.process_standard_normals[0] * np.sqrt(
            np.diag(covariances[process_id])
        )
        np.testing.assert_allclose(
            result.truth_process_perturbations[0, truth_index], expected, rtol=0.0, atol=0.0
        )
    np.testing.assert_allclose(
        result.observed_discharge,
        result.truth_discharge
        + 0.05 * result.observation_standard_normals[:, None, :],
        rtol=0.0,
        atol=0.0,
    )
    for method_index, count in enumerate(result.method_candidate_counts):
        active = slice(0, int(count))
        np.testing.assert_allclose(
            result.method_probabilities[:, :, method_index, :, active].sum(axis=-1),
            np.ones((1, 9, 3)),
            rtol=0.0,
            atol=1e-12,
        )
        reconstructed = np.sum(
            result.method_probabilities[:, :, method_index, :, active]
            * result.method_candidate_predictions[:, :, method_index, :, active],
            axis=-1,
        )
        np.testing.assert_allclose(
            result.method_predictions[:, :, method_index], reconstructed, rtol=1e-12, atol=1e-12
        )
        np.testing.assert_array_equal(
            result.method_probabilities[:, :, method_index, :, int(count):],
            np.zeros((1, 9, 3, 9 - int(count))),
        )


def test_joint_true_probabilities_and_forecast_targets_use_the_frozen_candidate_order():
    result = _run()

    expected_true = result.joint_origin_probabilities[0, np.arange(9), np.arange(9)]
    np.testing.assert_array_equal(result.joint_origin_true_probabilities[0], expected_true)
    np.testing.assert_array_equal(result.forecast_lead_days, np.array([1, 3, 7]))
    np.testing.assert_array_equal(
        result.truth_forecast_discharge,
        result.truth_discharge[:, :, np.array([4, 6, 10])],
    )
    np.testing.assert_array_equal(
        result.method_absolute_errors,
        np.abs(result.method_predictions - result.truth_forecast_discharge[:, :, None, :]),
    )


def test_packaged_joint_validation_records_raw_arrays_metrics_and_resource_estimate(tmp_path):
    source = (
        REPO_ROOT
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "configs"
        / "joint_method_stable_validation_v04.json"
    )
    config = json.loads(source.read_text(encoding="utf-8"))
    config["experiment_id"] = "joint_method_stable_validation_test"
    config["matched_blocks"] = config["matched_blocks"][:1]
    config["forcing"]["warmup_days"] = 8
    config["assimilation_days"] = 2
    config["bootstrap"]["replicates"] = 50
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")
    output = tmp_path / config["experiment_id"]
    registry = tmp_path / "registry.json"

    summary = run_packaged_validation(REPO_ROOT, config_path, output, registry)

    assert summary["status"] == "passed"
    assert summary["integrity_gate_pass"] is True
    assert (output / "method_metrics.csv").is_file()
    assert (output / "paired_comparisons.csv").is_file()
    assert (output / "condition_decisions.json").is_file()
    decisions = json.loads((output / "condition_decisions.json").read_text(encoding="utf-8"))
    assert set(decisions["origin_state_decision"]) == {
        "effective_against_fixed_filter",
        "added_value_beyond_both_single_factor_methods",
    }
    assert decisions["truth_process_interpretation"][
        "post_projection_distribution_matches_additive_gaussian_candidate"
    ] is False
    assert 0.0 <= decisions["truth_process_interpretation"]["projection_event_fraction"] <= 1.0
    certificate = json.loads(
        (output / "joint_method_certificate.json").read_text(encoding="utf-8")
    )
    summary_document = json.loads((output / "summary.json").read_text(encoding="utf-8"))
    registry_entry = json.loads((output / "registry_entry.json").read_text(encoding="utf-8"))
    assert "in-grid truth" not in json.dumps(certificate).lower()
    assert "in-grid truth" not in json.dumps(registry_entry).lower()
    assert "projected candidate-scale process truth" in certificate["check_type"]
    assert "projected candidate-scale process truth" in registry_entry["paper_name"]
    assert "2 assimilation days" in registry_entry["fixed_factors"]
    for document in (decisions, certificate, summary_document, registry_entry):
        serialized = json.dumps(document).lower()
        assert "fixed complete parameter label" in serialized
        assert (
            "post-projection truth is not an exact additive gaussian candidate model"
            in serialized
        )
    resource = json.loads((output / "resource_preflight.json").read_text(encoding="utf-8"))
    with np.load(output / "evidence.npz") as arrays:
        numeric_bytes = sum(
            arrays[name].nbytes
            for name in arrays.files
            if np.issubdtype(arrays[name].dtype, np.number)
        )
        assert arrays["truth_states"].shape == (1, 9, 9, 15)
        assert arrays["method_predictions"].shape == (1, 9, 6, 3)
    assert resource["expected_saved_numeric_array_bytes"] == numeric_bytes
    assert resource["safe_to_run"] is True
    assert resource["execution_parallelism"] == 1


def test_packaged_switching_validation_records_schedule_and_bounded_metadata(tmp_path):
    source = (
        REPO_ROOT
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "configs"
        / "joint_method_stable_validation_v04.json"
    )
    config = json.loads(source.read_text(encoding="utf-8"))
    config["experiment_id"] = "joint_method_switching_validation_test"
    config["matched_blocks"] = config["matched_blocks"][:1]
    config["forcing"]["warmup_days"] = 8
    config["assimilation_days"] = 2
    config["truth_switch_period_days"] = 2
    config["truth_switch_candidate_step"] = 4
    config["bootstrap"]["replicates"] = 50
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")
    output = tmp_path / config["experiment_id"]

    summary = run_packaged_validation(
        REPO_ROOT,
        config_path,
        output,
        tmp_path / "registry.json",
    )

    assert summary["truth_switch_period_days"] == 2
    with np.load(output / "evidence.npz") as arrays:
        assert arrays["truth_candidate_schedules"].shape == (9, 9)
        numeric_bytes = sum(
            arrays[name].nbytes
            for name in arrays.files
            if np.issubdtype(arrays[name].dtype, np.number)
        )
    resource = json.loads((output / "resource_preflight.json").read_text(encoding="utf-8"))
    assert resource["expected_saved_numeric_array_bytes"] == numeric_bytes
    decisions = json.loads((output / "condition_decisions.json").read_text(encoding="utf-8"))
    assert "periodically switching complete parameter" in decisions["condition"]
    assert decisions["oracle_filter_interpretation"]["dynamic_oracle"] is False
    assert summary["gate_values"][
        "truth_process_perturbation_reconstruction_maximum_absolute_error"
    ] == 0.0
