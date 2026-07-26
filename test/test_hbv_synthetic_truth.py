import sys
import json
import hashlib
import subprocess
from pathlib import Path
from types import SimpleNamespace

import numpy as np


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

import hbv_multilead_joint_uncertainty as multilead  # noqa: E402
from hbv_joint_uncertainty.hbv_adapter import simulate_adapter  # noqa: E402
from hbv_multilead_joint_uncertainty.scripts import (  # noqa: E402
    run_synthetic_truth_validation as synthetic_truth_runner,
)


PARAMETERS = {
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
    "lag_time": 10.0,
}


def _forcing(days: int = 365, seed: int = 314159) -> np.ndarray:
    rng = np.random.default_rng(seed)
    rain = rng.gamma(0.8, 4.0, size=days)
    angle = np.linspace(0.0, 2.0 * np.pi, days)
    potential_evaporation = np.maximum(0.0, 2.0 + np.sin(angle))
    temperature = 4.0 + 12.0 * np.sin(angle - np.pi / 2.0)
    return np.column_stack((rain, potential_evaporation, temperature)).astype(np.float64)


def test_independent_truth_replay_matches_fifteen_state_adapter():
    generate = getattr(multilead, "generate_reference_truth", None)
    assert callable(generate), "generate_reference_truth is not implemented"
    forcing = _forcing()
    truth = generate(forcing, PARAMETERS)
    adapter_discharge, adapter_states = simulate_adapter(
        forcing[:, 0], forcing[:, 1], forcing[:, 2], PARAMETERS
    )

    assert truth.forcing.shape == (365, 3)
    assert truth.states.shape == (365, 15)
    assert truth.discharge.shape == (365,)
    assert truth.raw_discharge.shape == (365,)
    assert np.all(np.isfinite(truth.states))
    assert np.all(np.isfinite(truth.discharge))
    assert np.max(np.abs(truth.states - adapter_states)) <= 1e-8
    assert np.max(np.abs(truth.discharge - adapter_discharge)) <= 1e-8


def test_reference_truth_keeps_exact_newest_first_routing_memory():
    generate = getattr(multilead, "generate_reference_truth", None)
    assert callable(generate), "generate_reference_truth is not implemented"
    truth = generate(_forcing(20), PARAMETERS)

    expected = np.zeros((20, 10), dtype=np.float64)
    for day in range(20):
        start = max(0, day - 9)
        history = truth.raw_discharge[start:day + 1][::-1]
        expected[day, :len(history)] = history
    np.testing.assert_array_equal(truth.states[:, 5:], expected)


def test_reference_truth_does_not_call_adapter_transition_or_observation(monkeypatch):
    generate = getattr(multilead, "generate_reference_truth", None)
    assert callable(generate), "generate_reference_truth is not implemented"
    import hbv_joint_uncertainty.hbv_adapter as adapter

    def forbidden(*args, **kwargs):
        raise AssertionError("independent truth generation called the adapter path")

    monkeypatch.setattr(adapter, "advance_state", forbidden)
    monkeypatch.setattr(adapter, "routed_discharge", forbidden)
    truth = generate(_forcing(30), PARAMETERS)
    assert truth.states.shape == (30, 15)
    assert truth.discharge.shape == (30,)


def test_dependency_manifest_handles_unreadable_pip_stderr(monkeypatch):
    captured = {}

    def failed_pip_freeze(*args, **kwargs):
        captured.update(kwargs)
        return SimpleNamespace(returncode=1, stdout=None, stderr=None)

    monkeypatch.setattr(synthetic_truth_runner.subprocess, "run", failed_pip_freeze)

    _, _, pip_freeze, pip_freeze_error = synthetic_truth_runner._dependency_manifests()

    assert pip_freeze.startswith(
        "# Generated from installed distribution metadata because pip freeze failed."
    )
    assert pip_freeze_error == ""
    assert captured["encoding"] == "utf-8"
    assert captured["errors"] == "replace"


def test_validation_runner_writes_atomic_reproducible_evidence(tmp_path):
    repo_root = Path(__file__).resolve().parents[1]
    config = {
        "experiment_id": "synthetic_truth_test_v01",
        "forcing": {"days": 365, "seed": 314159, "rain_shape": 0.8, "rain_scale": 4.0},
        "parameters": PARAMETERS,
        "thresholds": {"state_maximum_absolute_error": 1e-8, "discharge_maximum_absolute_error": 1e-8},
        "protected_paths": ["src/hbv_joint_uncertainty/hbv_adapter.py"],
    }
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")
    output_dir = tmp_path / config["experiment_id"]
    registry_path = tmp_path / "registry" / f"{config['experiment_id']}.json"
    script = (
        repo_root
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "scripts"
        / "run_synthetic_truth_validation.py"
    )

    completed = subprocess.run(
        [
            sys.executable,
            str(script),
            "--repo-root",
            str(repo_root),
            "--config",
            str(config_path),
            "--output-dir",
            str(output_dir),
            "--registry-path",
            str(registry_path),
        ],
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
        encoding="utf-8",
        errors="replace",
    )
    assert completed.returncode == 0, completed.stderr
    assert not output_dir.with_name(output_dir.name + ".incomplete").exists()

    summary = json.loads((output_dir / "summary.json").read_text(encoding="utf-8"))
    registry = json.loads((output_dir / "registry_entry.json").read_text(encoding="utf-8"))
    external_registry = json.loads(registry_path.read_text(encoding="utf-8"))
    checksums = json.loads((output_dir / "checksums.json").read_text(encoding="utf-8"))
    environment = json.loads((output_dir / "environment.json").read_text(encoding="utf-8"))
    installed_packages = json.loads((output_dir / "installed_packages.json").read_text(encoding="utf-8"))
    conda_packages = json.loads((output_dir / "conda_packages.json").read_text(encoding="utf-8"))
    integrity = json.loads((output_dir / "protected_artifact_integrity.json").read_text(encoding="utf-8"))
    arrays = np.load(output_dir / "evidence.npz")
    assert summary["status"] == "passed"
    assert summary["state_maximum_absolute_error"] <= 1e-8
    assert summary["discharge_maximum_absolute_error"] <= 1e-8
    assert summary["reference_routing_shift_exact"] is True
    assert summary["adapter_routing_shift_exact"] is True
    assert summary["routing_memory_cross_path_maximum_absolute_error"] <= 1e-8
    assert registry["experiment_id"] == config["experiment_id"]
    assert registry["status"] == "passed"
    assert external_registry == registry
    assert environment["python_version"]
    assert environment["numpy_version"]
    assert environment["llvmlite_version"]
    assert environment["execution_command"]
    assert environment["environment_variables"]["DISABLE_NUMBA"] is None
    assert integrity["status"] == "unchanged"
    assert integrity["before"] == integrity["after"]
    assert any(item["name"].lower() == "numpy" for item in installed_packages)
    assert any(item["name"].lower() == "numpy" for item in conda_packages)
    assert "numpy==" in (output_dir / "pip_freeze.txt").read_text(encoding="utf-8").lower()
    assert arrays["reference_states"].shape == (365, 15)
    assert arrays["adapter_states"].shape == (365, 15)
    assert set(checksums) == {
        "config_snapshot.json",
        "conda_packages.json",
        "evidence.npz",
        "environment.json",
        "git_status.txt",
        "installed_packages.json",
        "pip_freeze.txt",
        "protected_artifact_integrity.json",
        "registry_entry.json",
        "source_snapshot/__init__.py",
        "source_snapshot/hbv_adapter.py",
        "source_snapshot/hbv_lite_numpy.py",
        "source_snapshot/run_synthetic_truth_validation.py",
        "source_snapshot/synthetic_truth.py",
        "source_snapshot/test_hbv_synthetic_truth.py",
        "summary.json",
    }


def test_validation_runner_recovers_missing_external_registry_without_recompute(tmp_path):
    repo_root = Path(__file__).resolve().parents[1]
    config = {
        "experiment_id": "synthetic_truth_registry_recovery_v01",
        "forcing": {"days": 12, "seed": 271828, "rain_shape": 0.8, "rain_scale": 4.0},
        "parameters": PARAMETERS,
        "thresholds": {"state_maximum_absolute_error": 1e-8, "discharge_maximum_absolute_error": 1e-8},
        "protected_paths": [],
    }
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")
    output_dir = tmp_path / config["experiment_id"]
    blocker = tmp_path / "blocked_registry_parent"
    blocker.write_text("not a directory", encoding="utf-8")
    registry_path = blocker / f"{config['experiment_id']}.json"
    script = (
        repo_root
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "scripts"
        / "run_synthetic_truth_validation.py"
    )
    command = [
        sys.executable,
        str(script),
        "--repo-root",
        str(repo_root),
        "--config",
        str(config_path),
        "--output-dir",
        str(output_dir),
        "--registry-path",
        str(registry_path),
    ]

    first = subprocess.run(
        command,
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
        encoding="utf-8",
        errors="replace",
    )
    assert first.returncode != 0
    assert output_dir.exists()
    evidence_hash = hashlib.sha256((output_dir / "evidence.npz").read_bytes()).hexdigest()

    blocker.unlink()
    second = subprocess.run(
        command,
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
        encoding="utf-8",
        errors="replace",
    )
    assert second.returncode == 0, second.stderr
    assert registry_path.exists()
    assert not registry_path.with_name(registry_path.name + ".incomplete").exists()
    assert hashlib.sha256((output_dir / "evidence.npz").read_bytes()).hexdigest() == evidence_hash
    internal = json.loads((output_dir / "registry_entry.json").read_text(encoding="utf-8"))
    external = json.loads(registry_path.read_text(encoding="utf-8"))
    assert external == internal


def test_registry_recovery_rejects_a_checksum_manifest_with_a_missing_required_entry(tmp_path):
    repo_root = Path(__file__).resolve().parents[1]
    config = {
        "experiment_id": "synthetic_truth_incomplete_manifest_v01",
        "forcing": {"days": 12, "seed": 161803, "rain_shape": 0.8, "rain_scale": 4.0},
        "parameters": PARAMETERS,
        "thresholds": {"state_maximum_absolute_error": 1e-8, "discharge_maximum_absolute_error": 1e-8},
        "protected_paths": [],
    }
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")
    output_dir = tmp_path / config["experiment_id"]
    registry_path = tmp_path / "registry" / f"{config['experiment_id']}.json"
    script = (
        repo_root
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "scripts"
        / "run_synthetic_truth_validation.py"
    )
    command = [
        sys.executable,
        str(script),
        "--repo-root",
        str(repo_root),
        "--config",
        str(config_path),
        "--output-dir",
        str(output_dir),
        "--registry-path",
        str(registry_path),
    ]
    first = subprocess.run(
        command,
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
        encoding="utf-8",
        errors="replace",
    )
    assert first.returncode == 0, first.stderr

    registry_path.unlink()
    checksums_path = output_dir / "checksums.json"
    checksums = json.loads(checksums_path.read_text(encoding="utf-8"))
    checksums.pop("evidence.npz")
    checksums_path.write_text(json.dumps(checksums), encoding="utf-8")
    (output_dir / "evidence.npz").unlink()

    recovered = subprocess.run(
        command,
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
        encoding="utf-8",
        errors="replace",
    )
    assert recovered.returncode != 0
    assert "required evidence manifest" in recovered.stderr
    assert not registry_path.exists()


def test_single_filter_validation_compares_state_and_one_day_flow_errors():
    validate = getattr(multilead, "run_single_filter_state_validation", None)
    assert callable(validate), "run_single_filter_state_validation is not implemented"
    forcing = _forcing(180)
    truth = multilead.generate_reference_truth(forcing, PARAMETERS)
    result = validate(
        forcing=forcing,
        truth_states=truth.states,
        truth_discharge=truth.discharge,
        parameters=PARAMETERS,
        start_days=(60, 90),
        duration_days=20,
        perturbation_scales=(20.0, 5.0, 25.0, 10.0, 10.0),
        perturbation_seed=20260717,
        observation_standard_deviation=0.05,
    )

    assert result.start_days.tolist() == [60, 90]
    assert result.open_loop_states.shape == (2, 20, 15)
    assert result.filtered_states.shape == (2, 20, 15)
    assert result.truth_states.shape == (2, 20, 15)
    assert result.open_loop_one_day_predictions.shape == (2, 20)
    assert result.filtered_one_day_predictions.shape == (2, 20)
    assert result.truth_one_day_discharge.shape == (2, 20)
    assert result.open_loop_state_normalized_root_mean_square_error.shape == (2,)
    assert result.filtered_state_normalized_root_mean_square_error.shape == (2,)
    assert result.open_loop_one_day_root_mean_square_error.shape == (2,)
    assert result.filtered_one_day_root_mean_square_error.shape == (2,)
    assert np.all(np.isfinite(result.open_loop_states))
    assert np.all(np.isfinite(result.filtered_states))
    assert np.all(result.open_loop_state_normalized_root_mean_square_error > 0.0)
    assert np.all(result.open_loop_one_day_root_mean_square_error > 0.0)


def test_single_filter_validation_is_deterministic_for_a_fixed_perturbation_seed():
    validate = getattr(multilead, "run_single_filter_state_validation", None)
    assert callable(validate), "run_single_filter_state_validation is not implemented"
    forcing = _forcing(140)
    truth = multilead.generate_reference_truth(forcing, PARAMETERS)
    arguments = {
        "forcing": forcing,
        "truth_states": truth.states,
        "truth_discharge": truth.discharge,
        "parameters": PARAMETERS,
        "start_days": (60,),
        "duration_days": 20,
        "perturbation_scales": (20.0, 5.0, 25.0, 10.0, 10.0),
        "perturbation_seed": 20260717,
        "observation_standard_deviation": 0.05,
    }
    first = validate(**arguments)
    second = validate(**arguments)
    np.testing.assert_array_equal(first.filtered_states, second.filtered_states)
    np.testing.assert_array_equal(
        first.filtered_one_day_predictions, second.filtered_one_day_predictions
    )


def test_single_filter_one_day_forecast_does_not_read_target_discharge():
    forcing = _forcing(100)
    truth = multilead.generate_reference_truth(forcing, PARAMETERS)
    changed_target = truth.discharge.copy()
    changed_target[61] += 1000.0
    arguments = {
        "forcing": forcing,
        "truth_states": truth.states,
        "parameters": PARAMETERS,
        "start_days": (60,),
        "duration_days": 1,
        "perturbation_scales": (20.0, 5.0, 25.0, 10.0, 10.0),
        "perturbation_seed": 20260717,
        "observation_standard_deviation": 0.05,
    }
    original = multilead.run_single_filter_state_validation(
        truth_discharge=truth.discharge, **arguments
    )
    changed = multilead.run_single_filter_state_validation(
        truth_discharge=changed_target, **arguments
    )

    np.testing.assert_array_equal(
        original.filtered_one_day_predictions,
        changed.filtered_one_day_predictions,
    )
    np.testing.assert_array_equal(original.filtered_states, changed.filtered_states)
    assert changed.truth_one_day_discharge[0, 0] - original.truth_one_day_discharge[0, 0] == 1000.0


def test_single_filter_metrics_recompute_from_saved_arrays_and_process_covariance_is_zero():
    forcing = _forcing(100)
    truth = multilead.generate_reference_truth(forcing, PARAMETERS)
    scales = np.asarray((20.0, 5.0, 25.0, 10.0, 10.0))
    result = multilead.run_single_filter_state_validation(
        forcing=forcing,
        truth_states=truth.states,
        truth_discharge=truth.discharge,
        parameters=PARAMETERS,
        start_days=(60,),
        duration_days=5,
        perturbation_scales=scales,
        perturbation_seed=20260717,
        observation_standard_deviation=0.05,
    )

    open_state_error = (
        result.open_loop_states[:, :, :5] - result.truth_states[:, :, :5]
    ) / scales[None, None, :]
    filtered_state_error = (
        result.filtered_states[:, :, :5] - result.truth_states[:, :, :5]
    ) / scales[None, None, :]
    no_observation_state_error = (
        result.no_observation_filter_states[:, :, :5] - result.truth_states[:, :, :5]
    ) / scales[None, None, :]
    np.testing.assert_allclose(
        result.open_loop_state_normalized_root_mean_square_error,
        np.sqrt(np.mean(np.square(open_state_error), axis=(1, 2))),
    )
    np.testing.assert_allclose(
        result.filtered_state_normalized_root_mean_square_error,
        np.sqrt(np.mean(np.square(filtered_state_error), axis=(1, 2))),
    )
    np.testing.assert_allclose(
        result.no_observation_filter_state_normalized_root_mean_square_error,
        np.sqrt(np.mean(np.square(no_observation_state_error), axis=(1, 2))),
    )
    np.testing.assert_allclose(
        result.open_loop_one_day_root_mean_square_error,
        np.sqrt(
            np.mean(
                np.square(
                    result.open_loop_one_day_predictions - result.truth_one_day_discharge
                ),
                axis=1,
            )
        ),
    )
    np.testing.assert_allclose(
        result.filtered_one_day_root_mean_square_error,
        np.sqrt(
            np.mean(
                np.square(
                    result.filtered_one_day_predictions - result.truth_one_day_discharge
                ),
                axis=1,
            )
        ),
    )
    np.testing.assert_allclose(
        result.no_observation_filter_one_day_root_mean_square_error,
        np.sqrt(
            np.mean(
                np.square(
                    result.no_observation_filter_one_day_predictions
                    - result.truth_one_day_discharge
                ),
                axis=1,
            )
        ),
    )
    assert np.max(
        np.abs(result.no_observation_filter_states - result.open_loop_states)
    ) > 0.0
    np.testing.assert_array_equal(result.process_covariance, np.zeros((15, 15)))


def test_independent_single_filter_validation_uses_distinct_forcing_realizations():
    validate = getattr(multilead, "run_independent_single_filter_state_validation", None)
    assert callable(validate), "run_independent_single_filter_state_validation is not implemented"
    realization_ids = (314159, 271828, 161803)
    forcing = np.stack([_forcing(100, seed) for seed in realization_ids])
    truths = [multilead.generate_reference_truth(values, PARAMETERS) for values in forcing]
    result = validate(
        forcing_realizations=forcing,
        truth_state_realizations=np.stack([truth.states for truth in truths]),
        truth_discharge_realizations=np.stack([truth.discharge for truth in truths]),
        forcing_realization_ids=realization_ids,
        parameters=PARAMETERS,
        start_day=60,
        duration_days=5,
        perturbation_scales=(20.0, 5.0, 25.0, 10.0, 10.0),
        perturbation_seed=20260717,
        observation_standard_deviation=0.05,
    )

    assert result.forcing_realization_ids.tolist() == list(realization_ids)
    assert result.start_days.tolist() == [60, 60, 60]
    assert result.filtered_states.shape == (3, 5, 15)
    assert result.no_observation_filter_states.shape == (3, 5, 15)
    assert result.filtered_one_day_predictions.shape == (3, 5)
    np.testing.assert_array_equal(result.process_covariance, np.zeros((15, 15)))


def test_single_filter_runner_saves_a_complete_component_evidence_package(tmp_path):
    repo_root = Path(__file__).resolve().parents[1]
    config = {
        "experiment_id": "single_filter_state_test_v01",
        "forcing": {
            "days": 100,
            "seeds": [314159, 271828],
            "rain_shape": 0.8,
            "rain_scale": 4.0,
        },
        "parameters": PARAMETERS,
        "start_day": 60,
        "duration_days": 5,
        "perturbation_scales": [20.0, 5.0, 25.0, 10.0, 10.0],
        "perturbation_seed": 20260717,
        "observation_standard_deviation": 0.05,
        "bootstrap": {"replicates": 1000, "seed": 424242},
        "gates": {
            "state_median_change_percent_maximum": 1e9,
            "flow_median_change_percent_maximum": 1e9,
            "state_bootstrap_upper_percent_maximum": 1e9,
            "flow_bootstrap_upper_percent_maximum": 1e9,
        },
        "protected_paths": ["src/hbv_joint_uncertainty/hbv_adapter.py"],
    }
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")
    output_dir = tmp_path / config["experiment_id"]
    registry_path = tmp_path / "registry" / f"{config['experiment_id']}.json"
    script = (
        repo_root
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "scripts"
        / "run_single_filter_validation.py"
    )
    completed = subprocess.run(
        [
            sys.executable,
            str(script),
            "--repo-root",
            str(repo_root),
            "--config",
            str(config_path),
            "--output-dir",
            str(output_dir),
            "--registry-path",
            str(registry_path),
        ],
        cwd=repo_root,
        capture_output=True,
        text=True,
        check=False,
        encoding="utf-8",
        errors="replace",
    )
    assert completed.returncode == 0, completed.stderr
    summary = json.loads((output_dir / "summary.json").read_text(encoding="utf-8"))
    checksums = json.loads((output_dir / "checksums.json").read_text(encoding="utf-8"))
    arrays = np.load(output_dir / "evidence.npz")
    preregistration = json.loads(
        (output_dir / "preregistration.json").read_text(encoding="utf-8")
    )
    resource_preflight = json.loads(
        (output_dir / "resource_preflight.json").read_text(encoding="utf-8")
    )
    external_preregistration_path = registry_path.with_name(
        registry_path.stem + ".preregistered.json"
    )
    external_preregistration = json.loads(
        external_preregistration_path.read_text(encoding="utf-8")
    )
    assert summary["status"] == "passed"
    assert summary["trial_count"] == 2
    assert summary["trial_unit"] == "independent_forcing_realization"
    assert summary["primary_control"] == "same_filter_without_observation_updates"
    assert arrays["filtered_states"].shape == (2, 5, 15)
    assert arrays["no_observation_filter_states"].shape == (2, 5, 15)
    assert arrays["open_loop_states"].shape == (2, 5, 15)
    assert arrays["forcing"].shape == (2, 100, 3)
    np.testing.assert_array_equal(arrays["forcing_realization_ids"], [314159, 271828])
    np.testing.assert_array_equal(arrays["process_covariance"], np.zeros((15, 15)))
    assert preregistration == external_preregistration
    assert preregistration["status"] == "preregistered"
    assert preregistration["config_sha256"] == hashlib.sha256(config_path.read_bytes()).hexdigest()
    assert preregistration["registered_at"] <= summary["started_at"]
    assert resource_preflight["trial_count"] == 2
    assert resource_preflight["execution_parallelism"] == 1
    assert resource_preflight["available_physical_memory_bytes"] > (
        resource_preflight["estimated_additional_peak_memory_bytes"]
    )
    assert resource_preflight["safe_to_run"] is True
    assert json.loads(registry_path.read_text(encoding="utf-8")) == json.loads(
        (output_dir / "registry_entry.json").read_text(encoding="utf-8")
    )
    assert set(checksums) == {
        "conda_packages.json",
        "config_snapshot.json",
        "environment.json",
        "evidence.npz",
        "git_status.txt",
        "installed_packages.json",
        "pip_freeze.txt",
        "preregistration.json",
        "protected_artifact_integrity.json",
        "registry_entry.json",
        "resource_preflight.json",
        "source_snapshot/__init__.py",
        "source_snapshot/hbv_adapter.py",
        "source_snapshot/hbv_lite_numpy.py",
        "source_snapshot/preflight.py",
        "source_snapshot/run_single_filter_validation.py",
        "source_snapshot/run_synthetic_truth_validation.py",
        "source_snapshot/sigma_filter.py",
        "source_snapshot/single_filter_validation.py",
        "source_snapshot/synthetic_truth.py",
        "source_snapshot/test_hbv_joint_uncertainty_sigma_filter.py",
        "source_snapshot/test_hbv_synthetic_truth.py",
        "summary.json",
    }
