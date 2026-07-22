import hashlib
import json
import subprocess
import sys
from pathlib import Path

import numpy as np
import pandas as pd


sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

import hbv_joint_uncertainty.imm as imm_module  # noqa: E402
import hbv_multilead_joint_uncertainty as multilead  # noqa: E402
import hbv_multilead_joint_uncertainty.scripts.run_state_interaction_validation as interaction_runner  # noqa: E402
from hbv_joint_uncertainty.preflight import build_transition_matrix  # noqa: E402


def _factorial_transition(stay: float = 0.98) -> np.ndarray:
    factor = build_transition_matrix(3, stay)
    return np.kron(factor, factor)


def _manual_full_interaction(states, covariances, transition, probabilities):
    prior = transition.T @ probabilities
    mixed_states = np.empty_like(states)
    mixed_covariances = np.empty_like(covariances)
    weights = np.empty((len(states), len(states)), dtype=np.float64)
    for destination in range(len(states)):
        conditional = transition[:, destination] * probabilities / prior[destination]
        weights[destination] = conditional
        mean = conditional @ states
        covariance = np.zeros_like(covariances[0])
        for source in range(len(states)):
            difference = states[source] - mean
            covariance += conditional[source] * (
                covariances[source] + np.outer(difference, difference)
            )
        mixed_states[destination] = mean
        mixed_covariances[destination] = covariance
    return prior, weights, mixed_states, mixed_covariances


def _mixture_moments(probabilities, states, covariances):
    mean = probabilities @ states
    covariance = np.zeros_like(covariances[0])
    for probability, state, candidate_covariance in zip(
        probabilities, states, covariances
    ):
        difference = state - mean
        covariance += probability * (
            candidate_covariance + np.outer(difference, difference)
        )
    return mean, covariance


def test_full_state_interaction_matches_independent_conditional_moments():
    interact = getattr(imm_module, "interact_model_states", None)
    assert callable(interact), "interact_model_states is not implemented"
    rng = np.random.default_rng(91001)
    states = rng.normal(size=(9, 15))
    matrices = rng.normal(size=(9, 15, 15))
    covariances = np.asarray(
        [matrix @ matrix.T / 15.0 + np.eye(15) * 0.01 for matrix in matrices]
    )
    probabilities = np.arange(1.0, 10.0)
    probabilities /= probabilities.sum()
    transition = _factorial_transition()
    expected = _manual_full_interaction(
        states, covariances, transition, probabilities
    )

    result = interact(
        states=states,
        covariances=covariances,
        transition_matrix=transition,
        current_probabilities=probabilities,
        parameter_groups=tuple(index // 3 for index in range(9)),
        interaction_mode="full",
    )

    np.testing.assert_allclose(result.prior_probabilities, expected[0], rtol=0.0, atol=1e-15)
    np.testing.assert_allclose(result.conditional_weights, expected[1], rtol=0.0, atol=1e-15)
    np.testing.assert_allclose(result.mixed_states, expected[2], rtol=0.0, atol=1e-14)
    np.testing.assert_allclose(result.mixed_covariances, expected[3], rtol=0.0, atol=1e-13)
    original_mean, original_covariance = _mixture_moments(
        probabilities, states, covariances
    )
    mixed_mean, mixed_covariance = _mixture_moments(
        result.prior_probabilities, result.mixed_states, result.mixed_covariances
    )
    np.testing.assert_allclose(mixed_mean, original_mean, rtol=0.0, atol=1e-14)
    np.testing.assert_allclose(mixed_covariance, original_covariance, rtol=0.0, atol=1e-13)


def test_grouped_and_no_interaction_are_explicit_nonconserving_diagnostics():
    interact = getattr(imm_module, "interact_model_states", None)
    assert callable(interact), "interact_model_states is not implemented"
    transition = _factorial_transition()
    parameter_probabilities = np.asarray([0.8, 0.15, 0.05])
    process_probabilities = np.asarray([0.1, 0.2, 0.7])
    probabilities = np.outer(parameter_probabilities, process_probabilities).reshape(-1)
    states = np.zeros((9, 15), dtype=np.float64)
    states[:, 0] = np.repeat(np.asarray([0.0, 5.0, 10.0]), 3)
    covariances = np.repeat(np.eye(15, dtype=np.float64)[None, :, :] * 0.01, 9, axis=0)
    groups = tuple(index // 3 for index in range(9))
    original_mean, _ = _mixture_moments(probabilities, states, covariances)

    errors = {}
    for mode in ("full", "parameter_grouped", "none"):
        mode_probabilities = probabilities.copy()
        mode_states = states.copy()
        mode_covariances = covariances.copy()
        for _ in range(30):
            result = interact(
                states=mode_states,
                covariances=mode_covariances,
                transition_matrix=transition,
                current_probabilities=mode_probabilities,
                parameter_groups=groups,
                interaction_mode=mode,
            )
            mode_probabilities = result.prior_probabilities
            mode_states = result.mixed_states
            mode_covariances = result.mixed_covariances
        final_mean, _ = _mixture_moments(
            mode_probabilities, mode_states, mode_covariances
        )
        errors[mode] = abs(float(final_mean[0] - original_mean[0]))

    assert errors["full"] <= 1e-12
    assert errors["parameter_grouped"] >= 1.0
    assert errors["none"] >= 1.0


def test_randomized_state_interaction_validation_matches_independent_reference():
    validate = getattr(multilead, "run_state_interaction_validation", None)
    assert callable(validate), "run_state_interaction_validation is not implemented"
    result = validate(
        trial_seeds=(92001, 92002, 92003),
        steps=6,
        transition_matrix=_factorial_transition(),
        parameter_groups=tuple(index // 3 for index in range(9)),
    )

    assert result.production_probabilities.shape == (3, 7, 9)
    assert result.production_states.shape == (3, 7, 9, 15)
    assert result.production_covariances.shape == (3, 7, 9, 15, 15)
    assert result.reference_probabilities.shape == (3, 7, 9)
    assert result.reference_states.shape == (3, 7, 9, 15)
    assert result.reference_covariances.shape == (3, 7, 9, 15, 15)
    assert result.production_combined_means.shape == (3, 7, 15)
    assert result.production_combined_covariances.shape == (3, 7, 15, 15)
    np.testing.assert_allclose(
        result.production_probabilities,
        result.reference_probabilities,
        rtol=0.0,
        atol=1e-15,
    )
    np.testing.assert_allclose(
        result.production_states, result.reference_states, rtol=0.0, atol=1e-13
    )
    np.testing.assert_allclose(
        result.production_covariances,
        result.reference_covariances,
        rtol=0.0,
        atol=1e-11,
    )
    initial_means = result.production_combined_means[:, :1]
    initial_covariances = result.production_combined_covariances[:, :1]
    np.testing.assert_allclose(
        result.production_combined_means,
        np.repeat(initial_means, 7, axis=1),
        rtol=0.0,
        atol=1e-12,
    )
    np.testing.assert_allclose(
        result.production_combined_covariances,
        np.repeat(initial_covariances, 7, axis=1),
        rtol=0.0,
        atol=1e-10,
    )


def test_state_interaction_validation_is_deterministic_and_prefix_causal():
    arguments = {
        "trial_seeds": (93001, 93002),
        "transition_matrix": _factorial_transition(),
        "parameter_groups": tuple(index // 3 for index in range(9)),
    }
    short = multilead.run_state_interaction_validation(steps=3, **arguments)
    full = multilead.run_state_interaction_validation(steps=8, **arguments)
    repeated = multilead.run_state_interaction_validation(steps=8, **arguments)

    np.testing.assert_array_equal(
        short.production_probabilities, full.production_probabilities[:, :4]
    )
    np.testing.assert_array_equal(short.production_states, full.production_states[:, :4])
    np.testing.assert_array_equal(
        short.production_covariances, full.production_covariances[:, :4]
    )
    np.testing.assert_array_equal(full.production_states, repeated.production_states)
    assert full.counterexample_modes == ("full", "parameter_grouped", "none")
    assert full.counterexample_combined_means.shape == (3, 9, 15)
    original = full.counterexample_combined_means[:, 0, 0]
    final = full.counterexample_combined_means[:, -1, 0]
    assert abs(float(final[0] - original[0])) <= 1e-12
    assert abs(float(final[1] - original[1])) > 0.1
    assert abs(float(final[2] - original[2])) > 0.1


def test_saved_numeric_finiteness_gate_checks_every_numeric_array():
    check = getattr(interaction_runner, "_saved_numeric_finiteness", None)
    assert callable(check), "_saved_numeric_finiteness is not implemented"
    arrays = {
        "finite_float": np.asarray([1.0, 2.0]),
        "finite_integer": np.asarray([1, 2], dtype=np.int64),
        "omitted_before": np.asarray([0.0, np.nan]),
        "labels": np.asarray(["a", "b"]),
    }

    result = check(arrays)

    assert result["numeric_array_names"] == [
        "finite_float",
        "finite_integer",
        "omitted_before",
    ]
    assert result["nonfinite_numeric_array_names"] == ["omitted_before"]
    assert result["all_numeric_arrays_finite"] is False


def test_interacting_estimator_documentation_names_all_modes_and_default():
    documentation = imm_module.InteractingMultipleModel.__doc__ or ""
    assert "full" in documentation
    assert "parameter_grouped" in documentation
    assert "none" in documentation
    assert "parameter_grouped" in documentation and "default" in documentation


def test_state_interaction_runner_saves_registered_reproducible_evidence(tmp_path):
    repo_root = Path(__file__).resolve().parents[1]
    parameter_names = [
        "parTT",
        "parCFMAX",
        "parCFR",
        "parCWH",
        "parFC",
        "parBETA",
        "parLP",
        "parK0",
        "parK1",
        "parUZL",
        "parPERC",
        "parK2",
        "lag_time",
    ]
    center = np.asarray(
        [0.0, 3.2, 0.04, 0.1, 250.0, 2.1, 0.7, 0.2, 0.06, 18.0, 1.2, 0.015, 10.0]
    )
    parameter_ids = ["parameter_0", "parameter_1", "parameter_2"]
    parameter_path = tmp_path / "parameter_vectors.csv"
    pd.DataFrame(
        [
            {
                "basin_id": "test_source",
                "parameter_id": parameter_id,
                **{
                    name: value
                    for name, value in zip(
                        parameter_names, center + np.eye(3, 13)[index] * 0.01
                    )
                },
            }
            for index, parameter_id in enumerate(parameter_ids)
        ]
    ).to_csv(parameter_path, index=False)
    state_names = ["SNOWPACK", "MELTWATER", "SM", "SUZ", "SLZ"] + [
        f"qraw_t_minus_{index}" for index in range(10)
    ]
    process_ids = ["process_0", "process_1", "process_2"]
    process_path = tmp_path / "process_noise_covariances.csv"
    process_rows = []
    for index, process_id in enumerate(process_ids):
        diagonal = np.zeros(15)
        diagonal[:5] = 10.0 ** (index - 5)
        process_rows.append(
            {
                "basin_id": "test_source",
                "process_id": process_id,
                "variance_scale": 10.0 ** (index - 5),
                **{
                    f"variance_{name}": value
                    for name, value in zip(state_names, diagonal)
                },
            }
        )
    pd.DataFrame(process_rows).to_csv(process_path, index=False)
    config = {
        "experiment_id": "state_interaction_validation_test_v01",
        "parameter_source": {
            "path": str(parameter_path),
            "sha256": hashlib.sha256(parameter_path.read_bytes()).hexdigest(),
            "source_basin_id": "test_source",
            "parameter_ids": parameter_ids,
        },
        "process_noise_source": {
            "path": str(process_path),
            "sha256": hashlib.sha256(process_path.read_bytes()).hexdigest(),
            "source_basin_id": "test_source",
            "process_ids": process_ids,
        },
        "factor_stay_probability": 0.98,
        "trial_seeds": [94001, 94002],
        "steps": 5,
        "causal_prefix_steps": 2,
        "state_scales": [100.0, 5.0, 200.0, 20.0, 100.0, *([5.0] * 10)],
        "gates": {
            "production_reference_probability_maximum_absolute_error": 1e-15,
            "production_reference_weight_maximum_absolute_error": 1e-15,
            "production_reference_state_maximum_absolute_error": 1e-12,
            "production_reference_covariance_maximum_absolute_error": 1e-9,
            "full_combined_mean_conservation_maximum_absolute_error": 1e-11,
            "full_combined_covariance_conservation_maximum_absolute_error": 1e-8,
            "minimum_candidate_covariance_eigenvalue": -1e-9,
            "conditional_weight_sum_maximum_absolute_error": 1e-15,
            "causal_prefix_maximum_absolute_error": 0.0,
            "counterexample_full_mean_drift_maximum_absolute_error": 1e-12,
            "counterexample_full_covariance_drift_maximum_absolute_error": 1e-10,
            "counterexample_grouped_mean_drift_minimum_absolute_error": 0.1,
            "counterexample_none_mean_drift_minimum_absolute_error": 0.1,
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
        / "run_state_interaction_validation.py"
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
    resource = json.loads((output_dir / "resource_preflight.json").read_text(encoding="utf-8"))
    checksums = json.loads((output_dir / "checksums.json").read_text(encoding="utf-8"))
    certificate = json.loads(
        (output_dir / "moment_conservation_certificate.json").read_text(encoding="utf-8")
    )
    with np.load(output_dir / "evidence.npz") as arrays:
        actual_array_bytes = sum(arrays[name].nbytes for name in arrays.files)
        numeric_array_count = sum(
            np.issubdtype(arrays[name].dtype, np.number) for name in arrays.files
        )
        assert arrays["production_states"].shape == (2, 6, 9, 15)
        assert arrays["production_covariances"].shape == (2, 6, 9, 15, 15)
        assert arrays["counterexample_combined_means"].shape == (3, 6, 15)
    assert summary["status"] == "passed"
    assert summary["candidate_count"] == 9
    assert summary["state_dimension"] == 15
    assert summary["gate_pass"] is True
    assert summary["saved_numeric_array_count"] == numeric_array_count == 24
    assert summary["nonfinite_saved_numeric_array_names"] == []
    assert summary["gate_values"]["all_saved_numeric_arrays_finite"] is True
    assert certificate["passed"] is True
    assert resource["expected_evidence_array_bytes"] == actual_array_bytes
    assert resource["safe_to_run"] is True
    assert resource["execution_parallelism"] == 1
    assert json.loads(registry_path.read_text(encoding="utf-8")) == json.loads(
        (output_dir / "registry_entry.json").read_text(encoding="utf-8")
    )
    assert set(checksums) == {
        path.relative_to(output_dir).as_posix()
        for path in output_dir.rglob("*")
        if path.is_file() and path.name != "checksums.json"
    }
