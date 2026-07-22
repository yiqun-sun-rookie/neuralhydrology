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
import hbv_multilead_joint_uncertainty.synthetic_truth as synthetic_truth  # noqa: E402
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


def _forcing(days: int, seed: int) -> np.ndarray:
    rng = np.random.default_rng(seed)
    rain = rng.gamma(0.8, 4.0, size=days)
    angle = np.linspace(0.0, 2.0 * np.pi, days)
    potential_evaporation = np.maximum(0.0, 2.0 + np.sin(angle))
    temperature = 4.0 + 12.0 * np.sin(angle - np.pi / 2.0)
    return np.column_stack((rain, potential_evaporation, temperature))


def _covariance(scale: float) -> np.ndarray:
    diagonal = np.zeros(15, dtype=np.float64)
    diagonal[:5] = scale * np.asarray([4.0, 1.0, 9.0, 2.0, 16.0])
    return np.diag(diagonal)


def _arguments(duration_days: int = 5):
    process_ids = ("process_low", "process_middle", "process_high")
    forcing = _forcing(70, 101)
    return {
        "forcing_realizations": np.stack([forcing, forcing, forcing]),
        "trial_ids": ("block_1:process_low", "block_1:process_middle", "block_1:process_high"),
        "forcing_block_ids": ("block_1", "block_1", "block_1"),
        "parameter_vector": dict(CENTER),
        "process_covariances": {
            process_ids[0]: _covariance(1e-5),
            process_ids[1]: _covariance(1e-4),
            process_ids[2]: _covariance(1e-3),
        },
        "true_process_noise_ids": process_ids,
        "process_noise_seeds": (201, 201, 201),
        "observation_noise_seeds": (301, 301, 301),
        "start_day": 40,
        "duration_days": duration_days,
        "initial_covariance_fraction": 0.001,
        "observation_standard_deviation": 0.05,
    }


def test_process_noise_identification_uses_exactly_three_fixed_covariances():
    validate = getattr(multilead, "run_process_noise_identification_validation", None)
    assert callable(validate), "run_process_noise_identification_validation is not implemented"
    result = validate(**_arguments())

    assert result.process_noise_ids == ("process_low", "process_middle", "process_high")
    assert result.true_process_noise_ids == result.process_noise_ids
    assert result.trial_ids == (
        "block_1:process_low",
        "block_1:process_middle",
        "block_1:process_high",
    )
    assert result.forcing_block_ids == ("block_1", "block_1", "block_1")
    assert result.posterior_probabilities.shape == (3, 5, 3)
    assert result.candidate_log_likelihoods.shape == (3, 5, 3)
    assert result.candidate_prior_discharge.shape == (3, 5, 3)
    assert result.candidate_innovation_variances.shape == (3, 5, 3)
    assert result.candidate_posterior_states.shape == (3, 5, 3, 15)
    assert result.truth_states.shape == (3, 5, 15)
    assert result.truth_deterministic_states.shape == (3, 5, 15)
    assert result.truth_process_perturbations.shape == (3, 5, 15)
    assert result.truth_projection_adjustments.shape == (3, 5, 15)
    assert result.truth_discharge.shape == (3, 5)
    assert result.observed_discharge.shape == (3, 5)
    assert result.process_covariances.shape == (3, 15, 15)
    np.testing.assert_array_equal(result.process_covariances[:, 5:, :], 0.0)
    np.testing.assert_array_equal(result.process_covariances[:, :, 5:], 0.0)
    np.testing.assert_allclose(
        result.posterior_probabilities.sum(axis=2), np.ones((3, 5)), rtol=0.0, atol=1e-12
    )


def test_process_truth_and_observations_reconstruct_from_saved_random_draws():
    arguments = _arguments()
    result = multilead.run_process_noise_identification_validation(**arguments)
    advance_reference_state = getattr(synthetic_truth, "advance_reference_state", None)
    project_reference_state = getattr(synthetic_truth, "project_reference_state", None)
    reference_routed_discharge = getattr(synthetic_truth, "reference_routed_discharge", None)
    assert callable(advance_reference_state), "independent reference transition is not implemented"
    assert callable(project_reference_state), "independent reference projection is not implemented"
    assert callable(reference_routed_discharge), "independent reference observation is not implemented"
    previous = result.initial_truth_states.copy()
    for day in range(5):
        for trial in range(3):
            rain, pet, temperature = arguments["forcing_realizations"][trial, 40 + day]
            deterministic = advance_reference_state(
                previous[trial], rain, pet, temperature, CENTER
            )
            unprojected = deterministic + result.truth_process_perturbations[trial, day]
            expected = project_reference_state(unprojected, CENTER)
            np.testing.assert_array_equal(
                result.truth_deterministic_states[trial, day], deterministic
            )
            np.testing.assert_array_equal(result.truth_states[trial, day], expected)
            np.testing.assert_array_equal(
                result.truth_projection_adjustments[trial, day], expected - unprojected
            )
            assert result.truth_discharge[trial, day] == reference_routed_discharge(
                expected, CENTER["lag_time"]
            )
            previous[trial] = expected
    expected_observation = (
        result.truth_discharge
        + arguments["observation_standard_deviation"] * result.observation_standard_normals
    )
    np.testing.assert_array_equal(result.observed_discharge, expected_observation)
    for trial, true_id in enumerate(result.true_process_noise_ids):
        index = result.process_noise_ids.index(true_id)
        scale = np.sqrt(np.diag(result.process_covariances[index]))
        np.testing.assert_array_equal(
            result.truth_process_perturbations[trial],
            result.process_standard_normals[trial] * scale,
        )


def test_process_probabilities_equal_cumulative_likelihood_normalization():
    result = multilead.run_process_noise_identification_validation(**_arguments())
    cumulative = np.cumsum(result.candidate_log_likelihoods, axis=1)
    expected = np.empty_like(result.posterior_probabilities)
    for trial in range(cumulative.shape[0]):
        for day in range(cumulative.shape[1]):
            expected[trial, day] = normalize_log_weights(cumulative[trial, day])
    np.testing.assert_allclose(result.posterior_probabilities, expected, rtol=0.0, atol=1e-15)


def test_process_identification_is_causal_deterministic_and_validates_covariances():
    one_day = multilead.run_process_noise_identification_validation(**_arguments(duration_days=1))
    five_days = multilead.run_process_noise_identification_validation(**_arguments(duration_days=5))
    np.testing.assert_array_equal(
        one_day.posterior_probabilities[:, 0], five_days.posterior_probabilities[:, 0]
    )
    np.testing.assert_array_equal(one_day.truth_states[:, 0], five_days.truth_states[:, 0])
    repeated = multilead.run_process_noise_identification_validation(**_arguments())
    np.testing.assert_array_equal(five_days.truth_states, repeated.truth_states)
    np.testing.assert_array_equal(five_days.posterior_probabilities, repeated.posterior_probabilities)

    bad = _arguments()
    bad["process_covariances"] = dict(bad["process_covariances"])
    wrong = bad["process_covariances"]["process_low"].copy()
    wrong[0, 1] = wrong[1, 0] = 1e-8
    bad["process_covariances"]["process_low"] = wrong
    with pytest.raises(ValueError, match="diagonal"):
        multilead.run_process_noise_identification_validation(**bad)

    bad = _arguments()
    bad["process_covariances"] = dict(bad["process_covariances"])
    wrong = bad["process_covariances"]["process_low"].copy()
    wrong[5, 5] = 1e-8
    bad["process_covariances"]["process_low"] = wrong
    with pytest.raises(ValueError, match="routing-memory"):
        multilead.run_process_noise_identification_validation(**bad)


def test_process_identification_runner_saves_registered_reproducible_evidence(tmp_path):
    repo_root = Path(__file__).resolve().parents[1]
    parameter_path = tmp_path / "parameter_vectors.csv"
    pd.DataFrame([{"basin_id": "test_source", "parameter_id": "trained_center", **CENTER}]).to_csv(
        parameter_path, index=False
    )
    process_path = tmp_path / "process_noise_covariances.csv"
    process_rows = []
    state_names = ["SNOWPACK", "MELTWATER", "SM", "SUZ", "SLZ"] + [
        f"qraw_t_minus_{index}" for index in range(10)
    ]
    for process_id, covariance in _arguments()["process_covariances"].items():
        process_rows.append(
            {
                "basin_id": "test_source",
                "process_id": process_id,
                **{
                    f"variance_{name}": value
                    for name, value in zip(state_names, np.diag(covariance))
                },
            }
        )
    pd.DataFrame(process_rows).to_csv(process_path, index=False)
    observation_path = tmp_path / "observation_noise.csv"
    pd.DataFrame(
        [{"basin_id": "test_source", "standard_deviation_mm_day": 0.05}]
    ).to_csv(observation_path, index=False)

    config = {
        "experiment_id": "process_noise_identification_test_v01",
        "parameter_source": {
            "path": str(parameter_path),
            "sha256": hashlib.sha256(parameter_path.read_bytes()).hexdigest(),
            "source_basin_id": "test_source",
            "parameter_id": "trained_center",
        },
        "process_noise_source": {
            "path": str(process_path),
            "sha256": hashlib.sha256(process_path.read_bytes()).hexdigest(),
            "source_basin_id": "test_source",
            "process_ids": ["process_low", "process_middle", "process_high"],
        },
        "observation_noise_source": {
            "path": str(observation_path),
            "sha256": hashlib.sha256(observation_path.read_bytes()).hexdigest(),
            "source_basin_id": "test_source",
        },
        "forcing": {"days": 70, "rain_shape": 0.8, "rain_scale": 4.0},
        "matched_blocks": [
            {
                "block_id": "block_1",
                "forcing_seed": 101,
                "process_noise_seed": 201,
                "observation_noise_seed": 301,
            },
            {
                "block_id": "block_2",
                "forcing_seed": 102,
                "process_noise_seed": 202,
                "observation_noise_seed": 302,
            },
        ],
        "start_day": 40,
        "duration_days": 5,
        "terminal_window_days": 2,
        "initial_covariance_fraction": 0.001,
        "bootstrap": {"replicates": 1000, "seed": 424242, "unit": "matched_block"},
        "gates": {
            "correct_classification_count_minimum": 0,
            "correct_classification_count_per_process_minimum": 0,
            "median_terminal_true_probability_minimum": 0.0,
            "matched_block_accuracy_bootstrap_lower_minimum": 0.0,
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
        / "run_process_noise_identification_validation.py"
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
    assert summary["trial_count"] == 6
    assert summary["matched_block_count"] == 2
    assert summary["process_noise_candidate_count"] == 3
    assert summary["interaction_mode"] == "none"
    assert summary["bootstrap_unit"] == "matched_block"
    assert summary["truth_transition_implementation"] == "independent_reference_one_day_simulator"
    assert summary["independent_truth_transition_maximum_adapter_difference"] <= 1e-12
    assert summary["independent_truth_observation_maximum_adapter_difference"] <= 1e-12
    assert set(summary["truth_projection_event_count_by_state"]) == {
        "SNOWPACK",
        "MELTWATER",
        "SM",
        "SUZ",
        "SLZ",
    }
    assert summary["negative_observation_count"] >= 0
    assert arrays["posterior_probabilities"].shape == (6, 5, 3)
    assert arrays["process_covariances"].shape == (3, 15, 15)
    assert arrays["truth_process_perturbations"].shape == (6, 5, 15)
    assert preregistration["config_sha256"] == hashlib.sha256(config_path.read_bytes()).hexdigest()
    assert preregistration["registered_at"] <= summary["started_at"]
    assert resource["execution_parallelism"] == 1
    assert resource["safe_to_run"] is True
    assert json.loads(registry_path.read_text(encoding="utf-8")) == json.loads(
        (output_dir / "registry_entry.json").read_text(encoding="utf-8")
    )
    assert set(checksums) == {
        path.relative_to(output_dir).as_posix()
        for path in output_dir.rglob("*")
        if path.is_file() and path.name != "checksums.json"
    }


def test_grouped_probability_bootstrap_resamples_whole_matched_blocks():
    from hbv_multilead_joint_uncertainty.scripts import (  # noqa: E402
        run_process_noise_identification_validation as runner,
    )

    grouped = getattr(runner, "_bootstrap_grouped_median_interval", None)
    assert callable(grouped), "matched-block probability bootstrap is not implemented"
    values = np.asarray([0.1, 0.2, 0.3, 0.7, 0.8, 0.9], dtype=np.float64)
    group_ids = np.asarray(["a", "a", "a", "b", "b", "b"])
    replicates = 2000
    seed = 919191
    actual = grouped(values, group_ids, replicates, seed)

    rng = np.random.default_rng(seed)
    sampled_groups = rng.integers(0, 2, size=(replicates, 2))
    grouped_values = values.reshape(2, 3)
    statistics = np.median(grouped_values[sampled_groups].reshape(replicates, 6), axis=1)
    expected = tuple(float(value) for value in np.quantile(statistics, [0.025, 0.975]))
    assert actual == expected
