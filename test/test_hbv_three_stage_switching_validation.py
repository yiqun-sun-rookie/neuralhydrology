import importlib.util
import importlib
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))
MODULE_NAME = "hbv_multilead_joint_uncertainty.three_stage_switching_validation"

from hbv_multilead_joint_uncertainty.methods import build_method_definitions  # noqa: E402


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


def _definitions():
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
    definitions = build_method_definitions(parameters, scales, covariances, "large")
    return definitions


def test_three_stage_switching_validation_module_is_available():
    assert importlib.util.find_spec(MODULE_NAME) is not None


def test_three_stage_truth_schedule_builder_is_available():
    module = importlib.import_module(MODULE_NAME)

    assert hasattr(module, "build_three_stage_truth_schedule")


@pytest.mark.parametrize(
    ("scenario", "truth_count", "primary_method"),
    [
        ("parameter_switch", 3, "parameter_only"),
        ("process_noise_switch", 3, "noise_only"),
        ("parameter_process_noise_switch", 9, "joint"),
    ],
)
def test_three_stage_schedule_is_exact_synchronized_and_holds_during_forecast(
    scenario, truth_count, primary_method
):
    module = importlib.import_module(MODULE_NAME)
    definitions = _definitions()

    schedule = module.build_three_stage_truth_schedule(
        definitions=definitions,
        scenario=scenario,
        selected_process_id="large",
        stage_lengths=(15, 15, 15),
        forecast_days=7,
    )

    assert schedule.scenario == scenario
    assert schedule.primary_method_name == primary_method
    assert schedule.joint_candidate_indices.shape == (truth_count, 52)
    assert schedule.parameter_indices.shape == (truth_count, 52)
    assert schedule.process_indices.shape == (truth_count, 52)
    assert schedule.primary_candidate_indices.shape == (truth_count, 52)
    np.testing.assert_array_equal(schedule.stage_start_days, np.array([0, 15, 30]))
    np.testing.assert_array_equal(schedule.stage_end_days, np.array([15, 30, 45]))
    np.testing.assert_array_equal(
        schedule.joint_candidate_indices[:, 44], schedule.origin_joint_candidate_indices
    )
    np.testing.assert_array_equal(
        schedule.joint_candidate_indices[:, 45:],
        np.repeat(schedule.joint_candidate_indices[:, 44:45], 7, axis=1),
    )

    parameter_changed = schedule.parameter_indices[:, [15, 30]] != schedule.parameter_indices[:, [14, 29]]
    process_changed = schedule.process_indices[:, [15, 30]] != schedule.process_indices[:, [14, 29]]
    if scenario == "parameter_switch":
        assert np.all(parameter_changed)
        assert not np.any(process_changed)
        assert np.all(schedule.process_indices == 2)
    elif scenario == "process_noise_switch":
        assert not np.any(parameter_changed)
        assert np.all(process_changed)
        assert np.all(schedule.parameter_indices == 1)
    else:
        assert np.all(parameter_changed)
        assert np.all(process_changed)


@pytest.mark.parametrize(
    ("stage_lengths", "forecast_days", "error_pattern"),
    [
        ((15, 15), 7, "three"),
        ((15, 0, 15), 7, "positive"),
        ((15, 15, 15), 0, "forecast_days"),
    ],
)
def test_three_stage_schedule_rejects_ambiguous_time_boundaries(
    stage_lengths, forecast_days, error_pattern
):
    module = importlib.import_module(MODULE_NAME)

    with pytest.raises(ValueError, match=error_pattern):
        module.build_three_stage_truth_schedule(
            definitions=_definitions(),
            scenario="parameter_process_noise_switch",
            selected_process_id="large",
            stage_lengths=stage_lengths,
            forecast_days=forecast_days,
        )


def _forcing(seed=8101, days=17):
    rng = np.random.default_rng(seed)
    angle = np.linspace(0.0, 2.0 * np.pi, days)
    return np.column_stack(
        (
            rng.gamma(0.8, 4.0, size=days),
            np.maximum(0.0, 2.0 + np.sin(angle)),
            4.0 + 12.0 * np.sin(angle - np.pi / 2.0),
        )
    )


def _run_joint_switching(future_observation_replacement=None):
    module = importlib.import_module(MODULE_NAME)
    parameters = {
        candidate.parameter_id: candidate.parameters
        for candidate in _definitions()["parameter_only"]
    }
    process_candidates = _definitions()["noise_only"]
    process_scales = {
        candidate.process_id: candidate.process_scale for candidate in process_candidates
    }
    process_covariances = {
        candidate.process_id: candidate.process_covariance
        for candidate in process_candidates
    }
    return module.run_three_stage_switching_validation(
        forcing_blocks=_forcing()[None, :, :],
        block_ids=("block_01",),
        parameter_vectors=parameters,
        process_scales=process_scales,
        process_covariances=process_covariances,
        selected_process_id="large",
        scenario="parameter_process_noise_switch",
        process_noise_seeds=(9101,),
        observation_noise_seeds=(10101,),
        warmup_days=8,
        stage_lengths=(2, 2, 2),
        lead_days=(1, 3),
        initial_covariance_fraction=0.001,
        observation_standard_deviation=0.05,
        factor_transition_stay_probability=0.98,
        future_observation_replacement=future_observation_replacement,
    )


@pytest.fixture(scope="module")
def joint_switching_result():
    return _run_joint_switching()


def test_three_stage_run_saves_daily_weights_truth_draws_and_forecasts(
    joint_switching_result,
):
    result = joint_switching_result

    assert result.scenario == "parameter_process_noise_switch"
    assert result.schedule.joint_candidate_indices.shape == (9, 9)
    assert result.truth_states.shape == (1, 9, 9, 15)
    assert result.method_assimilation_probabilities.shape == (1, 9, 5, 6, 9)
    assert result.method_predictions.shape == (1, 9, 5, 2)
    assert result.method_candidate_predictions.shape == (1, 9, 5, 2, 9)
    assert result.method_forecast_probabilities.shape == (1, 9, 5, 2, 9)
    np.testing.assert_array_equal(
        result.truth_forecast_discharge,
        result.truth_discharge[:, :, np.array([6, 8])],
    )
    assert np.all(np.isfinite(result.method_predictions))

    for method_index, count in enumerate(result.method_candidate_counts):
        active = slice(0, int(count))
        np.testing.assert_allclose(
            result.method_assimilation_probabilities[
                :, :, method_index, :, active
            ].sum(axis=-1),
            1.0,
            rtol=0.0,
            atol=1e-12,
        )
        reconstructed = np.sum(
            result.method_forecast_probabilities[:, :, method_index, :, active]
            * result.method_candidate_predictions[:, :, method_index, :, active],
            axis=-1,
        )
        np.testing.assert_allclose(
            result.method_predictions[:, :, method_index],
            reconstructed,
            rtol=1e-12,
            atol=1e-12,
        )


def test_three_stage_truth_uses_saved_standard_normals_and_scheduled_covariance(
    joint_switching_result,
):
    result = joint_switching_result
    definitions = _definitions()
    joint = definitions["joint"]
    for truth_index in range(9):
        for day, candidate_index in enumerate(
            result.schedule.joint_candidate_indices[truth_index]
        ):
            candidate = joint[int(candidate_index)]
            expected = result.process_standard_normals[0, day] * np.sqrt(
                np.diag(candidate.process_covariance)
            )
            np.testing.assert_allclose(
                result.truth_process_perturbations[0, truth_index, day],
                expected,
                rtol=0.0,
                atol=0.0,
            )


def test_future_discharge_counterfactual_cannot_change_filter_or_forecast_results(
    joint_switching_result,
):
    changed = _run_joint_switching(future_observation_replacement=1.0e12)

    np.testing.assert_array_equal(
        changed.observed_discharge[:, :, :6],
        joint_switching_result.observed_discharge[:, :, :6],
    )
    assert np.all(changed.observed_discharge[:, :, 6:] == 1.0e12)
    np.testing.assert_array_equal(
        changed.method_assimilation_probabilities,
        joint_switching_result.method_assimilation_probabilities,
    )
    np.testing.assert_array_equal(
        changed.method_predictions,
        joint_switching_result.method_predictions,
    )


def test_three_stage_evaluation_reports_each_stage_and_each_forecast_lead(
    joint_switching_result,
):
    module = importlib.import_module(MODULE_NAME)
    evaluation = module.evaluate_three_stage_switching_result(
        joint_switching_result,
        adaptation_days=1,
        bootstrap_replicates=100,
        bootstrap_seed=777,
        candidate_accuracy_minimum=0.5,
        factor_accuracy_minimum=2.0 / 3.0,
        median_true_probability_minimum=0.2,
        relative_root_mean_square_error_improvement_percent_minimum=5.0,
        paired_block_difference_upper_maximum=0.0,
    )

    assert [row["stage_number"] for row in evaluation["stage_identification"]] == [
        1,
        2,
        3,
    ]
    assert all(row["evaluated_day_count_per_truth"] == 1 for row in evaluation["stage_identification"])
    assert [row["lead_days"] for row in evaluation["forecast_decisions"]] == [1, 3]
    assert evaluation["truth_process_interpretation"]["projection_event_total"] == 81


def test_packaged_three_stage_run_freezes_recomputable_evidence(tmp_path):
    from hbv_multilead_joint_uncertainty.scripts.run_three_stage_switching_validation import (
        run,
    )

    source = (
        REPO_ROOT
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "configs"
        / "three_stage_parameter_switch_v01.json"
    )
    config = json.loads(source.read_text(encoding="utf-8"))
    config["experiment_id"] = "three_stage_parameter_switch_packaging_test"
    config["matched_blocks"] = config["matched_blocks"][:1]
    config["forcing"]["warmup_days"] = 8
    config["forcing"]["reference_total_days"] = 17
    config["stage_lengths"] = [2, 2, 2]
    config["lead_days"] = [1, 3]
    config["bootstrap"]["replicates"] = 100
    config["decision_rules"]["adaptation_days_excluded_per_stage"] = 1
    config["protected_paths"] = []
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")
    output = tmp_path / config["experiment_id"]

    summary = run(REPO_ROOT, config_path, output)

    assert summary["integrity_status"] == "passed"
    preregistration = tmp_path / (
        config["experiment_id"] + ".preregistered.json"
    )
    assert preregistration.is_file()
    assert (output / "evidence.npz").is_file()
    assert (output / "stage_identification.csv").is_file()
    assert (output / "future_observation_counterfactual.json").is_file()
    checksums = json.loads((output / "checksums.json").read_text(encoding="utf-8"))
    assert "evidence.npz" in checksums
    assert summary["config_sha256"] == hashlib.sha256(
        (output / "config_snapshot.json").read_bytes()
    ).hexdigest()
    snapshot_names = {
        path.name for path in (output / "source_snapshot").iterdir()
    }
    assert {
        "src__hbv_multilead_joint_uncertainty__scripts__run_model_probability_validation.py",
        "src__hbv_multilead_joint_uncertainty__scripts__run_process_noise_identification_validation.py",
        "src__hbv_multilead_joint_uncertainty__scripts__run_synthetic_truth_validation.py",
    }.issubset(snapshot_names)
    with np.load(output / "evidence.npz", allow_pickle=False) as evidence:
        assert evidence["truth_joint_candidate_indices"].shape == (3, 9)
        assert evidence["method_assimilation_probabilities"].shape == (1, 3, 5, 6, 9)


def test_evidence_directory_finalization_retries_a_transient_windows_lock(
    tmp_path, monkeypatch
):
    from hbv_multilead_joint_uncertainty.scripts import (
        run_three_stage_switching_validation as runner,
    )

    source = tmp_path / "evidence.incomplete"
    target = tmp_path / "evidence"
    source.mkdir()
    original_replace = Path.replace
    calls = []

    def fail_once_then_replace(path, destination):
        calls.append((path, destination))
        if len(calls) == 1:
            raise PermissionError(5, "transient lock")
        return original_replace(path, destination)

    monkeypatch.setattr(Path, "replace", fail_once_then_replace)
    monkeypatch.setattr(runner.time, "sleep", lambda _: None)

    runner._replace_directory_with_retries(source, target, attempts=3, delay_seconds=0.01)

    assert len(calls) == 2
    assert target.is_dir()
    assert not source.exists()


def test_output_must_be_disjoint_from_every_protected_path(tmp_path):
    from hbv_multilead_joint_uncertainty.scripts import (
        run_three_stage_switching_validation as runner,
    )

    protected = tmp_path / "protected"
    protected.mkdir()

    with pytest.raises(ValueError, match="overlap"):
        runner._validate_output_is_disjoint_from_protected_paths(
            protected / "new_evidence", (protected,)
        )
    with pytest.raises(ValueError, match="overlap"):
        runner._validate_output_is_disjoint_from_protected_paths(
            tmp_path, (protected,)
        )

    runner._validate_output_is_disjoint_from_protected_paths(
        tmp_path / "separate", (protected,)
    )
