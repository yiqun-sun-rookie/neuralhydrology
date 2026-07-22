import hashlib
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import pytest


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

import hbv_multilead_joint_uncertainty as multilead  # noqa: E402
from hbv_joint_uncertainty.imm import normalize_log_weights  # noqa: E402


CENTER = {
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


def _parameter_vectors():
    low_storage = dict(CENTER)
    low_storage.update({"parFC": 150.0, "parBETA": 1.4, "lag_time": 6.0})
    fast_response = dict(CENTER)
    fast_response.update({"parK0": 0.5, "parK1": 0.15, "parK2": 0.04})
    return {
        "low_storage": low_storage,
        "center": dict(CENTER),
        "fast_response": fast_response,
    }


def _forcing(days: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    rain = rng.gamma(0.8, 4.0, size=days)
    angle = np.linspace(0.0, 2.0 * np.pi, days)
    potential_evaporation = np.maximum(0.0, 2.0 + np.sin(angle))
    temperature = 4.0 + 12.0 * np.sin(angle - np.pi / 2.0)
    return np.column_stack((rain, potential_evaporation, temperature))


def _arguments(duration_days: int = 5):
    realization_ids = np.asarray([101, 102, 103])
    return {
        "forcing_realizations": np.stack([_forcing(70, seed) for seed in realization_ids]),
        "forcing_realization_ids": realization_ids,
        "parameter_vectors": _parameter_vectors(),
        "true_parameter_ids": ("low_storage", "center", "fast_response"),
        "start_day": 40,
        "duration_days": duration_days,
        "initial_covariance_fraction": 0.001,
        "observation_standard_deviation": 0.05,
    }


def test_parameter_identification_tracks_three_complete_vectors_without_interaction():
    validate = getattr(multilead, "run_parameter_identification_validation", None)
    assert callable(validate), "run_parameter_identification_validation is not implemented"
    result = validate(**_arguments())

    assert result.parameter_ids == ("low_storage", "center", "fast_response")
    assert result.true_parameter_ids == ("low_storage", "center", "fast_response")
    assert result.forcing_realization_ids.tolist() == [101, 102, 103]
    assert result.posterior_probabilities.shape == (3, 5, 3)
    assert result.candidate_log_likelihoods.shape == (3, 5, 3)
    assert result.candidate_prior_discharge.shape == (3, 5, 3)
    assert result.candidate_posterior_states.shape == (3, 5, 3, 15)
    assert result.truth_discharge.shape == (3, 5)
    np.testing.assert_allclose(
        result.posterior_probabilities.sum(axis=2), np.ones((3, 5)), rtol=0.0, atol=1e-12
    )
    assert np.all(result.posterior_probabilities >= 0.0)
    np.testing.assert_array_equal(result.process_covariance, np.zeros((15, 15)))


def test_parameter_probabilities_equal_cumulative_likelihood_normalization():
    result = multilead.run_parameter_identification_validation(**_arguments())
    cumulative = np.cumsum(result.candidate_log_likelihoods, axis=1)
    expected = np.empty_like(result.posterior_probabilities)
    for trial in range(cumulative.shape[0]):
        for day in range(cumulative.shape[1]):
            expected[trial, day] = normalize_log_weights(cumulative[trial, day])
    np.testing.assert_allclose(result.posterior_probabilities, expected, rtol=0.0, atol=1e-15)


def test_parameter_identification_first_day_does_not_depend_on_later_discharge():
    one_day = multilead.run_parameter_identification_validation(**_arguments(duration_days=1))
    five_days = multilead.run_parameter_identification_validation(**_arguments(duration_days=5))
    np.testing.assert_array_equal(
        one_day.posterior_probabilities[:, 0], five_days.posterior_probabilities[:, 0]
    )
    np.testing.assert_array_equal(
        one_day.candidate_prior_discharge[:, 0], five_days.candidate_prior_discharge[:, 0]
    )


def test_parameter_identification_is_deterministic_and_rejects_unknown_truth_label():
    first = multilead.run_parameter_identification_validation(**_arguments())
    second = multilead.run_parameter_identification_validation(**_arguments())
    np.testing.assert_array_equal(first.posterior_probabilities, second.posterior_probabilities)
    arguments = _arguments()
    arguments["true_parameter_ids"] = ("low_storage", "missing", "fast_response")
    with pytest.raises(ValueError, match="unknown true parameter"):
        multilead.run_parameter_identification_validation(**arguments)


def test_parameter_identification_runner_saves_registered_reproducible_evidence(tmp_path):
    repo_root = Path(__file__).resolve().parents[1]
    source_path = tmp_path / "parameter_vectors.csv"
    rows = []
    for parameter_id, parameters in _parameter_vectors().items():
        rows.append({"basin_id": "test_source", "parameter_id": parameter_id, **parameters})
    pd.DataFrame(rows).to_csv(source_path, index=False)
    source_hash = hashlib.sha256(source_path.read_bytes()).hexdigest()
    config = {
        "experiment_id": "parameter_identification_test_v01",
        "parameter_source": {
            "path": str(source_path),
            "sha256": source_hash,
            "source_basin_id": "test_source",
            "parameter_ids": ["low_storage", "center", "fast_response"],
        },
        "forcing": {
            "days": 70,
            "seeds": [101, 102, 103],
            "true_parameter_ids": ["low_storage", "center", "fast_response"],
            "rain_shape": 0.8,
            "rain_scale": 4.0,
        },
        "start_day": 40,
        "duration_days": 5,
        "terminal_window_days": 2,
        "initial_covariance_fraction": 0.001,
        "observation_standard_deviation": 0.05,
        "bootstrap": {"replicates": 1000, "seed": 424242},
        "gates": {
            "correct_classification_count_minimum": 0,
            "correct_classification_count_per_parameter_minimum": 0,
            "median_terminal_true_probability_minimum": 0.0,
            "terminal_true_probability_bootstrap_lower_minimum": 0.0,
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
        / "run_parameter_identification_validation.py"
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
    )

    assert completed.returncode == 0, completed.stderr
    summary = json.loads((output_dir / "summary.json").read_text(encoding="utf-8"))
    preregistration = json.loads(
        (output_dir / "preregistration.json").read_text(encoding="utf-8")
    )
    resource = json.loads((output_dir / "resource_preflight.json").read_text(encoding="utf-8"))
    checksums = json.loads((output_dir / "checksums.json").read_text(encoding="utf-8"))
    arrays = np.load(output_dir / "evidence.npz")
    assert summary["status"] == "passed"
    assert summary["trial_count"] == 3
    assert summary["parameter_count"] == 3
    assert summary["interaction_mode"] == "none"
    assert summary["process_covariance"] == "zero"
    assert arrays["posterior_probabilities"].shape == (3, 5, 3)
    assert arrays["candidate_posterior_states"].shape == (3, 5, 3, 15)
    np.testing.assert_array_equal(arrays["process_covariance"], np.zeros((15, 15)))
    assert preregistration["config_sha256"] == hashlib.sha256(config_path.read_bytes()).hexdigest()
    assert preregistration["registered_at"] <= summary["started_at"]
    assert resource["execution_parallelism"] == 1
    assert resource["safe_to_run"] is True
    assert hashlib.sha256((output_dir / "parameter_vectors.csv").read_bytes()).hexdigest() == (
        summary["selected_parameter_snapshot_sha256"]
    )
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
        "parameter_vectors.csv",
        "pip_freeze.txt",
        "preregistration.json",
        "protected_artifact_integrity.json",
        "registry_entry.json",
        "resource_preflight.json",
        "source_snapshot/__init__.py",
        "source_snapshot/hbv_adapter.py",
        "source_snapshot/hbv_lite_numpy.py",
        "source_snapshot/imm.py",
        "source_snapshot/parameter_identification_validation.py",
        "source_snapshot/preflight.py",
        "source_snapshot/run_parameter_identification_validation.py",
        "source_snapshot/run_synthetic_truth_validation.py",
        "source_snapshot/sigma_filter.py",
        "source_snapshot/synthetic_truth.py",
        "source_snapshot/test_hbv_parameter_identification_validation.py",
        "summary.json",
    }
