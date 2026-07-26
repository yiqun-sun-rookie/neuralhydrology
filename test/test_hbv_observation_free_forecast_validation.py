import sys
import json
from pathlib import Path

import numpy as np
import pytest


REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.methods import MethodCandidate  # noqa: E402
from hbv_multilead_joint_uncertainty.observation_free_forecast_validation import (  # noqa: E402
    run_observation_free_forecast_validation,
)
from hbv_multilead_joint_uncertainty.scripts.run_observation_free_forecast_validation import (  # noqa: E402
    run as run_packaged_validation,
)


IDENTITY_FORECAST_CONTRACT = {
    "candidate_probabilities": "fixed_at_final_assimilation_posterior",
    "model_transition": "identity",
    "cross_candidate_state_mixing": False,
}


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


def _candidates():
    definitions = []
    for parameter_index, parameter_id in enumerate(("low", "center", "high")):
        parameters = BASE_PARAMETERS.copy()
        parameters["parFC"] += 20.0 * (parameter_index - 1)
        parameters["parK1"] += 0.01 * (parameter_index - 1)
        for process_index, process_id in enumerate(("small", "medium", "large")):
            diagonal = np.zeros(15, dtype=np.float64)
            diagonal[:5] = (10.0 ** process_index) * np.asarray(
                [1e-3, 1e-5, 1e-3, 1e-4, 1e-3], dtype=np.float64
            )
            definitions.append(
                MethodCandidate(
                    candidate_id=f"{parameter_id}__{process_id}",
                    parameter_id=parameter_id,
                    process_id=process_id,
                    process_scale=10.0 ** (-4 + process_index),
                    parameters=parameters,
                    process_covariance=np.diag(diagonal),
                )
            )
    return tuple(definitions)


def _forcing():
    realizations = []
    for seed in (7101, 7102):
        rng = np.random.default_rng(seed)
        days = 19
        angle = np.linspace(0.0, 2.0 * np.pi, days)
        realizations.append(
            np.column_stack(
                (
                    rng.gamma(0.8, 4.0, size=days),
                    np.maximum(0.0, 2.0 + np.sin(angle)),
                    4.0 + 12.0 * np.sin(angle - np.pi / 2.0),
                )
            )
        )
    return np.asarray(realizations, dtype=np.float64)


def _run():
    covariance_diagonal = np.square(
        np.asarray([1.0, 0.1, 2.0, 0.5, 1.0, *([0.05] * 10)], dtype=np.float64)
    )
    return run_observation_free_forecast_validation(
        trial_seeds=(7101, 7102),
        forcing_realizations=_forcing(),
        warmup_days=12,
        forecast_days=7,
        candidates=_candidates(),
        initial_covariance=np.diag(covariance_diagonal),
        initial_probabilities=np.asarray(
            [0.03, 0.04, 0.08, 0.07, 0.31, 0.12, 0.05, 0.10, 0.20],
            dtype=np.float64,
        ),
        observation_standard_deviation=0.05,
    )


def test_nine_candidate_forecast_matches_independent_seven_day_reference():
    result = _run()

    assert result.production_candidate_states.shape == (2, 7, 9, 15)
    assert result.reference_candidate_covariances.shape == (2, 7, 9, 15, 15)
    np.testing.assert_allclose(
        result.production_probabilities,
        result.reference_probabilities,
        rtol=0.0,
        atol=2e-15,
    )
    np.testing.assert_allclose(
        result.production_candidate_states,
        result.reference_candidate_states,
        rtol=0.0,
        atol=2e-10,
    )
    np.testing.assert_allclose(
        result.production_candidate_covariance_diagonals,
        np.diagonal(result.reference_candidate_covariances, axis1=-2, axis2=-1),
        rtol=0.0,
        atol=2e-8,
    )
    np.testing.assert_allclose(
        result.production_candidate_predictions,
        result.reference_candidate_predictions,
        rtol=0.0,
        atol=2e-10,
    )
    np.testing.assert_allclose(
        result.production_combined_predictions,
        result.reference_combined_predictions,
        rtol=0.0,
        atol=2e-10,
    )


def test_forecast_probabilities_stay_fixed_and_source_bank_is_immutable():
    result = _run()

    expected = np.broadcast_to(
        result.initial_probabilities,
        result.production_probabilities.shape,
    )
    np.testing.assert_allclose(
        result.production_probabilities,
        expected,
        rtol=0.0,
        atol=2e-15,
    )
    assert result.maximum_source_state_mutation == 0.0
    assert result.maximum_source_covariance_mutation == 0.0
    assert result.maximum_source_probability_mutation == 0.0
    np.testing.assert_array_equal(
        result.source_candidate_states_after_forecasts,
        result.initial_candidate_states,
    )
    np.testing.assert_array_equal(
        result.source_candidate_covariances_after_forecasts,
        result.initial_candidate_covariances,
    )
    np.testing.assert_array_equal(
        result.source_probabilities_after_forecasts,
        np.repeat(result.initial_probabilities[None, :], 2, axis=0),
    )


def test_one_three_seven_day_selection_and_three_day_prefix_are_bitwise_exact():
    result = _run()
    selected = np.asarray([0, 2, 6], dtype=np.int64)

    np.testing.assert_array_equal(
        result.production_selected_combined_predictions,
        result.production_combined_predictions[:, selected],
    )
    np.testing.assert_array_equal(
        result.production_selected_probabilities,
        result.production_probabilities[:, selected],
    )
    np.testing.assert_array_equal(
        result.production_three_day_combined_predictions,
        result.production_combined_predictions[:, :3],
    )
    np.testing.assert_array_equal(
        result.production_three_day_candidate_states,
        result.production_candidate_states[:, :3],
    )


@pytest.mark.parametrize("version", ("v01", "v02"))
def test_packaged_validation_rejects_historical_forecast_contract_before_work(
    tmp_path,
    version,
):
    source = (
        REPO_ROOT
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "configs"
        / f"observation_free_forecast_validation_{version}.json"
    )
    config = json.loads(source.read_text(encoding="utf-8"))
    config["experiment_id"] = f"obsolete_forecast_contract_{version}"
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")

    with pytest.raises(ValueError, match="identity forecast contract"):
        run_packaged_validation(
            REPO_ROOT,
            config_path,
            tmp_path / config["experiment_id"],
            tmp_path / f"registry_{version}.json",
        )


def test_packaged_validation_records_exact_resource_and_evidence_manifests(tmp_path):
    source = (
        REPO_ROOT
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "configs"
        / "observation_free_forecast_validation_v03.json"
    )
    config = json.loads(source.read_text(encoding="utf-8"))
    config["experiment_id"] = "observation_free_forecast_validation_test"
    config["trial_seeds"] = [960001]
    config["forcing"]["warmup_days"] = 8
    config_path = tmp_path / "config.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")
    output = tmp_path / config["experiment_id"]
    registry = tmp_path / "registry.json"

    summary = run_packaged_validation(REPO_ROOT, config_path, output, registry)

    assert summary["status"] == "passed"
    resource = json.loads((output / "resource_preflight.json").read_text(encoding="utf-8"))
    assert summary["forecast_contract"] == IDENTITY_FORECAST_CONTRACT
    checksums = json.loads((output / "checksums.json").read_text(encoding="utf-8"))
    with np.load(output / "evidence.npz") as arrays:
        numeric_bytes = sum(
            arrays[name].nbytes
            for name in arrays.files
            if np.issubdtype(arrays[name].dtype, np.number)
        )
        np.testing.assert_array_equal(
            arrays["source_candidate_states_after_forecasts"],
            arrays["initial_candidate_states"],
        )
        np.testing.assert_array_equal(
            arrays["source_candidate_covariances_after_forecasts"],
            arrays["initial_candidate_covariances"],
        )
    assert resource["expected_saved_numeric_array_bytes"] == numeric_bytes
    assert resource["safe_to_run"] is True
    assert resource["execution_parallelism"] == 1
    assert set(checksums) == {
        path.relative_to(output).as_posix()
        for path in output.rglob("*")
        if path.is_file() and path.name != "checksums.json"
    }
