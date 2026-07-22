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
import hbv_joint_uncertainty.imm as imm_module  # noqa: E402
from hbv_joint_uncertainty.preflight import build_transition_matrix  # noqa: E402


normalize_log_weights = imm_module.normalize_log_weights


PARAMETER_IDS = ("parameter_0", "parameter_1", "parameter_2")
PROCESS_IDS = ("process_0", "process_1", "process_2")
CANDIDATE_FACTORS = tuple(
    (parameter_id, process_id)
    for parameter_id in PARAMETER_IDS
    for process_id in PROCESS_IDS
)
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


def _factorial_transition(stay: float = 0.98) -> np.ndarray:
    factor = build_transition_matrix(3, stay)
    return np.kron(factor, factor)


def _arguments(days: int = 40):
    return {
        "trial_seeds": (801, 802, 803, 804),
        "days": days,
        "parameter_ids": PARAMETER_IDS,
        "process_ids": PROCESS_IDS,
        "candidate_factors": CANDIDATE_FACTORS,
        "transition_matrix": _factorial_transition(),
        "factor_emission_means": (-2.0, 0.0, 2.0),
        "emission_standard_deviation": 1.0,
    }


def test_factorial_transition_preserves_both_factor_switch_probabilities():
    transition = _factorial_transition()
    assert transition.shape == (9, 9)
    np.testing.assert_allclose(transition.sum(axis=1), 1.0, rtol=0.0, atol=1e-15)
    np.testing.assert_allclose(np.diag(transition), 0.9604, rtol=0.0, atol=1e-15)
    for source, (parameter_id, process_id) in enumerate(CANDIDATE_FACTORS):
        parameter_stay = sum(
            transition[source, destination]
            for destination, factors in enumerate(CANDIDATE_FACTORS)
            if factors[0] == parameter_id
        )
        process_stay = sum(
            transition[source, destination]
            for destination, factors in enumerate(CANDIDATE_FACTORS)
            if factors[1] == process_id
        )
        assert parameter_stay == pytest.approx(0.98, abs=1e-15)
        assert process_stay == pytest.approx(0.98, abs=1e-15)


def test_probability_helpers_match_direct_transition_and_bayes_update():
    predict_model_probabilities = getattr(imm_module, "predict_model_probabilities", None)
    update_model_probabilities = getattr(imm_module, "update_model_probabilities", None)
    assert callable(predict_model_probabilities), "probability prediction helper is not implemented"
    assert callable(update_model_probabilities), "probability update helper is not implemented"
    transition = _factorial_transition()
    current = np.asarray([0.02, 0.03, 0.05, 0.06, 0.09, 0.15, 0.12, 0.18, 0.30])
    current /= current.sum()
    log_likelihoods = np.linspace(-12.0, -4.0, 9)
    prior = predict_model_probabilities(transition, current)
    posterior = update_model_probabilities(prior, log_likelihoods)
    expected_prior = transition.T @ current
    expected_posterior = normalize_log_weights(np.log(expected_prior) + log_likelihoods)
    np.testing.assert_allclose(prior, expected_prior, rtol=0.0, atol=1e-15)
    np.testing.assert_allclose(posterior, expected_posterior, rtol=0.0, atol=1e-15)
    assert np.all(np.isfinite(posterior))
    assert np.all(posterior >= 0.0)
    assert posterior.sum() == pytest.approx(1.0, abs=1e-15)


def test_probability_validation_records_exact_causal_recursion_and_marginals():
    validate = getattr(multilead, "run_model_probability_validation", None)
    assert callable(validate), "run_model_probability_validation is not implemented"
    result = validate(**_arguments())
    assert result.candidate_factors == CANDIDATE_FACTORS
    assert result.true_candidate_indices.shape == (4, 40)
    assert result.observations.shape == (4, 40, 2)
    assert result.candidate_log_likelihoods.shape == (4, 40, 9)
    assert result.prior_probabilities.shape == (4, 40, 9)
    assert result.posterior_probabilities.shape == (4, 40, 9)
    assert result.parameter_prior_marginals.shape == (4, 40, 3)
    assert result.parameter_posterior_marginals.shape == (4, 40, 3)
    assert result.process_prior_marginals.shape == (4, 40, 3)
    assert result.process_posterior_marginals.shape == (4, 40, 3)
    np.testing.assert_allclose(
        result.posterior_probabilities.sum(axis=2), 1.0, rtol=0.0, atol=1e-15
    )
    reshaped_prior = result.prior_probabilities.reshape(4, 40, 3, 3)
    reshaped_posterior = result.posterior_probabilities.reshape(4, 40, 3, 3)
    np.testing.assert_array_equal(result.parameter_prior_marginals, reshaped_prior.sum(axis=3))
    np.testing.assert_array_equal(result.process_prior_marginals, reshaped_prior.sum(axis=2))
    np.testing.assert_array_equal(
        result.parameter_posterior_marginals, reshaped_posterior.sum(axis=3)
    )
    np.testing.assert_array_equal(
        result.process_posterior_marginals, reshaped_posterior.sum(axis=2)
    )
    for trial in range(4):
        np.testing.assert_allclose(
            result.prior_probabilities[trial, 0], np.full(9, 1.0 / 9.0), rtol=0.0, atol=0.0
        )
        for day in range(1, 40):
            expected = result.transition_matrix.T @ result.posterior_probabilities[trial, day - 1]
            expected /= expected.sum()
            np.testing.assert_allclose(
                result.prior_probabilities[trial, day], expected, rtol=0.0, atol=1e-15
            )


def test_probability_validation_is_deterministic_causal_and_handles_extreme_likelihoods():
    one_day = multilead.run_model_probability_validation(**_arguments(days=1))
    forty_days = multilead.run_model_probability_validation(**_arguments(days=40))
    np.testing.assert_array_equal(one_day.true_candidate_indices, forty_days.true_candidate_indices[:, :1])
    np.testing.assert_array_equal(one_day.observations, forty_days.observations[:, :1])
    np.testing.assert_array_equal(
        one_day.posterior_probabilities, forty_days.posterior_probabilities[:, :1]
    )
    repeated = multilead.run_model_probability_validation(**_arguments(days=40))
    np.testing.assert_array_equal(forty_days.posterior_probabilities, repeated.posterior_probabilities)
    update_model_probabilities = getattr(imm_module, "update_model_probabilities", None)
    assert callable(update_model_probabilities), "probability update helper is not implemented"
    extreme = update_model_probabilities(
        np.full(9, 1.0 / 9.0),
        np.asarray([-1e300, -1e250, -1e200, -1e150, -1e100, -1e50, -100.0, -10.0, 0.0]),
    )
    assert np.all(np.isfinite(extreme))
    assert extreme.sum() == pytest.approx(1.0, abs=1e-15)
    assert np.argmax(extreme) == 8


def test_observation_updated_probabilities_improve_proper_scores_over_transition_prior():
    result = multilead.run_model_probability_validation(**_arguments(days=365))
    row = np.arange(len(result.trial_seeds))[:, None]
    day = np.arange(365)[None, :]
    true = result.true_candidate_indices
    prior_true = result.prior_probabilities[row, day, true]
    posterior_true = result.posterior_probabilities[row, day, true]
    prior_log_loss = -np.mean(np.log(prior_true), axis=1)
    posterior_log_loss = -np.mean(np.log(posterior_true), axis=1)
    targets = np.eye(9)[true]
    prior_brier = np.mean(np.sum((result.prior_probabilities - targets) ** 2, axis=2), axis=1)
    posterior_brier = np.mean(
        np.sum((result.posterior_probabilities - targets) ** 2, axis=2), axis=1
    )
    assert np.all(posterior_log_loss < prior_log_loss)
    assert np.all(posterior_brier < prior_brier)


def test_model_probability_runner_saves_registered_reproducible_evidence(tmp_path):
    repo_root = Path(__file__).resolve().parents[1]
    parameter_path = tmp_path / "parameter_vectors.csv"
    parameter_rows = []
    for index, parameter_id in enumerate(PARAMETER_IDS):
        values = dict(CENTER)
        values["parFC"] += index
        parameter_rows.append({"basin_id": "test_source", "parameter_id": parameter_id, **values})
    pd.DataFrame(parameter_rows).to_csv(parameter_path, index=False)
    process_path = tmp_path / "process_noise_covariances.csv"
    state_names = ["SNOWPACK", "MELTWATER", "SM", "SUZ", "SLZ"] + [
        f"qraw_t_minus_{index}" for index in range(10)
    ]
    process_rows = []
    for index, process_id in enumerate(PROCESS_IDS):
        diagonal = np.zeros(15)
        diagonal[:5] = 10.0 ** (index - 5)
        process_rows.append(
            {
                "basin_id": "test_source",
                "process_id": process_id,
                "variance_scale": 10.0 ** (index - 5),
                **{f"variance_{name}": value for name, value in zip(state_names, diagonal)},
            }
        )
    pd.DataFrame(process_rows).to_csv(process_path, index=False)
    config = {
        "experiment_id": "model_probability_validation_test_v01",
        "parameter_source": {
            "path": str(parameter_path),
            "sha256": hashlib.sha256(parameter_path.read_bytes()).hexdigest(),
            "source_basin_id": "test_source",
            "parameter_ids": list(PARAMETER_IDS),
        },
        "process_noise_source": {
            "path": str(process_path),
            "sha256": hashlib.sha256(process_path.read_bytes()).hexdigest(),
            "source_basin_id": "test_source",
            "process_ids": list(PROCESS_IDS),
        },
        "factor_stay_probability": 0.98,
        "trial_seeds": [801, 802],
        "days": 20,
        "factor_emission_means": [-2.0, 0.0, 2.0],
        "emission_standard_deviation": 1.0,
        "extreme_log_likelihood_vector": [
            -1e300,
            -1e250,
            -1e200,
            -1e150,
            -1e100,
            -1e50,
            -100.0,
            -10.0,
            0.0,
        ],
        "bootstrap": {"replicates": 1000, "seed": 818181, "unit": "trial"},
        "gates": {
            "joint_log_loss_improved_trial_count_minimum": 0,
            "joint_brier_improved_trial_count_minimum": 0,
            "joint_posterior_accuracy_minimum": 0.0,
            "parameter_posterior_accuracy_minimum": 0.0,
            "process_posterior_accuracy_minimum": 0.0,
            "recursion_maximum_absolute_error": 1e-12,
            "factor_marginal_transition_maximum_absolute_error": 1e-12,
            "factorial_transition_contract_maximum_absolute_error": 1e-12,
            "posterior_factorization_maximum_absolute_error": 1e-12,
            "extreme_probability_normalization_absolute_error": 1e-15,
            "extreme_probability_reconstruction_maximum_absolute_error": 1e-15,
            "extreme_probability_expected_argmax": 8,
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
        / "run_model_probability_validation.py"
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
    preregistration = json.loads(
        (output_dir / "preregistration.json").read_text(encoding="utf-8")
    )
    checksums = json.loads((output_dir / "checksums.json").read_text(encoding="utf-8"))
    arrays = np.load(output_dir / "evidence.npz")
    assert summary["status"] == "passed"
    assert summary["candidate_count"] == 9
    assert summary["parameter_count"] == 3
    assert summary["process_noise_count"] == 3
    assert summary["joint_candidate_stay_probability"] == pytest.approx(0.9604, abs=1e-15)
    assert summary["factorial_transition_contract_maximum_absolute_error"] <= 1e-15
    assert summary["posterior_factorization_maximum_absolute_error"] <= 1e-12
    assert summary["gate_values"]["factorial_transition_contract_maximum_absolute_error"] <= 1e-15
    assert summary["gate_values"]["posterior_factorization_maximum_absolute_error"] <= 1e-12
    assert summary["gate_values"]["extreme_probability_all_finite"] is True
    assert summary["gate_values"]["extreme_probability_all_nonnegative"] is True
    assert summary["gate_values"]["extreme_probability_normalization_absolute_error"] <= 1e-15
    assert summary["gate_values"]["extreme_probability_reconstruction_maximum_absolute_error"] <= 1e-15
    assert summary["gate_values"]["extreme_probability_argmax"] == 8
    assert "switch_day_joint_prior_accuracy" in summary
    assert "switch_day_parameter_posterior_accuracy" in summary
    assert "switch_day_process_posterior_accuracy" in summary
    assert "non_switch_or_initial_day_joint_posterior_accuracy" in summary
    assert arrays["posterior_probabilities"].shape == (2, 20, 9)
    assert arrays["parameter_posterior_marginals"].shape == (2, 20, 3)
    assert arrays["process_posterior_marginals"].shape == (2, 20, 3)
    np.testing.assert_array_equal(
        arrays["extreme_log_likelihoods"], config["extreme_log_likelihood_vector"]
    )
    assert arrays["extreme_prior_probabilities"].shape == (9,)
    assert arrays["extreme_posterior_probabilities"].shape == (9,)
    assert np.all(np.isfinite(arrays["extreme_posterior_probabilities"]))
    assert int(np.argmax(arrays["extreme_posterior_probabilities"])) == 8
    assert preregistration["config_sha256"] == hashlib.sha256(config_path.read_bytes()).hexdigest()
    assert preregistration["registered_at"] <= summary["started_at"]
    assert resource["execution_parallelism"] == 1
    assert resource["safe_to_run"] is True
    assert resource["dynamic_float_values_per_trial_day"] == 50
    assert resource["dynamic_integer_values_per_trial_day"] == 1
    assert resource["dynamic_boolean_values_per_trial_day"] == 1
    expected_dynamic_bytes = 2 * 20 * (50 * 8 + 1 * 8 + 1)
    assert resource["dynamic_array_bytes"] == expected_dynamic_bytes
    assert resource["raw_numeric_array_bytes"] == (
        resource["dynamic_array_bytes"]
        + resource["static_array_bytes"]
        + resource["per_trial_score_array_bytes"]
    )
    assert json.loads(registry_path.read_text(encoding="utf-8")) == json.loads(
        (output_dir / "registry_entry.json").read_text(encoding="utf-8")
    )
    assert set(checksums) == {
        path.relative_to(output_dir).as_posix()
        for path in output_dir.rglob("*")
        if path.is_file() and path.name != "checksums.json"
    }
