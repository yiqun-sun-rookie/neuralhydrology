"""Highest-posterior forecast inference and evidence-package contracts."""

import copy
import hashlib
import importlib
import json
import sys
from pathlib import Path

import numpy as np
import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

ARMS_MODULE = "hbv_multilead_joint_uncertainty.interaction_value_comparison"
RUNNER_MODULE = (
    "hbv_multilead_joint_uncertainty.scripts."
    "run_g3_corrected_forecast_comparison"
)
HISTORICAL_RUNNER_MODULE = (
    "hbv_multilead_joint_uncertainty.scripts."
    "run_three_stage_switching_validation"
)
HISTORICAL_METHODS = ("full", "none", "static", "oracle")
FIVE_METHODS = (
    "full",
    "none",
    "highest_posterior",
    "static",
    "oracle",
)


def _synthetic_driver(include_highest_posterior=True):
    shape = (4, 1, 3)
    squared_errors = {
        "full": np.full(shape, 3.0, dtype=np.float64),
        "none": np.full(shape, 4.0, dtype=np.float64),
        "static": np.full(shape, 5.0, dtype=np.float64),
        "oracle": np.full(shape, 2.0, dtype=np.float64),
    }
    arms = HISTORICAL_METHODS
    if include_highest_posterior:
        highest = np.empty(shape, dtype=np.float64)
        highest[:, :, 0] = 1.0
        highest[:, :, 1] = 9.0
        highest[:, :, 2] = np.asarray([1.0, 9.0, 1.0, 9.0])[:, None]
        squared_errors["highest_posterior"] = highest
        arms = FIVE_METHODS
    probabilities = np.full((4, 1, 2, 2), 0.5, dtype=np.float64)
    return {
        "arms": arms,
        "leads": np.asarray([1, 3, 7], dtype=np.int64),
        "squared_errors": squared_errors,
        "probabilities": {
            "full": probabilities.copy(),
            "none": probabilities.copy(),
        },
        "true_candidate_labels": np.zeros((1, 2), dtype=np.int64),
        "stage_boundaries": [(0, 2)],
    }


def test_summary_adds_paired_highest_posterior_inference_and_classification():
    arms = importlib.import_module(ARMS_MODULE)
    runner = importlib.import_module(RUNNER_MODULE)
    driver = _synthetic_driver(include_highest_posterior=True)

    statistics = arms.summarize_interaction_value(
        driver,
        bootstrap_replicates=2000,
        bootstrap_seed=3308757,
        adaptation_days=0,
    )
    paired = statistics["paired_highest_posterior_minus_none"]
    expected = arms._block_bootstrap_ci(
        arms.paired_block_difference(driver, "highest_posterior", "none"),
        2000,
        3308757,
    )
    for key, value in zip(("mean", "ci_low", "ci_high"), expected):
        np.testing.assert_array_equal(paired[key], value)
    np.testing.assert_allclose(
        statistics["rmse"]["highest_posterior"],
        np.asarray([1.0, 3.0, np.sqrt(5.0)]),
    )
    np.testing.assert_allclose(
        statistics["oracle_ratio"]["highest_posterior"],
        np.asarray([1.0, 3.0, np.sqrt(5.0)]) / np.sqrt(2.0),
    )
    np.testing.assert_allclose(
        paired["mean"], np.asarray([-3.0, 5.0, 1.0]), rtol=0.0, atol=0.0
    )
    assert paired["ci_high"][0] < 0.0
    assert paired["ci_low"][1] > 0.0
    assert paired["ci_low"][2] <= 0.0 <= paired["ci_high"][2]

    result = runner._result_summary(driver, statistics)
    assert (
        runner._classify_highest_posterior_interval(0.0, 0.0)
        == "no_detectable_difference"
    )
    assert result["highest_posterior_minus_none_classification"] == [
        "improves",
        "harms",
        "no_detectable_difference",
    ]
    assert "highest_posterior" in result["rmse"]
    assert "highest_posterior" in result["oracle_ratio"]


def test_historical_summary_has_no_highest_posterior_fields():
    arms = importlib.import_module(ARMS_MODULE)
    runner = importlib.import_module(RUNNER_MODULE)
    driver = _synthetic_driver(include_highest_posterior=False)

    statistics = arms.summarize_interaction_value(
        driver,
        bootstrap_replicates=200,
        bootstrap_seed=3308757,
        adaptation_days=0,
    )
    result = runner._result_summary(driver, statistics)

    assert "paired_highest_posterior_minus_none" not in statistics
    assert "paired_highest_posterior_minus_none" not in result
    assert "highest_posterior_minus_none_classification" not in result
    assert tuple(result["rmse"]) == HISTORICAL_METHODS
    assert set(result) == {
        "leads",
        "rmse",
        "oracle_ratio",
        "paired_full_minus_none",
        "paired_none_minus_static",
        "full_minus_none_classification",
        "identification",
    }


def test_comparison_methods_config_is_explicit_and_backward_compatible():
    runner = importlib.import_module(RUNNER_MODULE)

    assert runner._highest_posterior_enabled({}) is False
    assert (
        runner._highest_posterior_enabled(
            {"comparison_methods": list(HISTORICAL_METHODS)}
        )
        is False
    )
    assert (
        runner._highest_posterior_enabled(
            {"comparison_methods": list(FIVE_METHODS)}
        )
        is True
    )
    with pytest.raises(ValueError, match="comparison_methods"):
        runner._highest_posterior_enabled(
            {"comparison_methods": ["none", "highest_posterior"]}
        )
    invalid_values = (
        None,
        {
            "full": True,
            "none": True,
            "static": True,
            "oracle": True,
        },
    )
    for invalid in invalid_values:
        with pytest.raises(ValueError, match="comparison_methods"):
            runner._highest_posterior_enabled(
                {"comparison_methods": invalid}
            )


def test_runner_refuses_existing_output_before_reading_config(tmp_path):
    runner = importlib.import_module(RUNNER_MODULE)
    output = tmp_path / "existing_output"
    output.mkdir()

    with pytest.raises(FileExistsError, match="overwrite"):
        runner.run(REPO_ROOT, tmp_path / "missing_config.json", output)


def test_runner_rejects_protected_overlap_before_preregistration(tmp_path):
    runner = importlib.import_module(RUNNER_MODULE)
    source = (
        REPO_ROOT
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "configs"
        / "g3_corrected_forecast_param_switch_v01.json"
    )
    config = json.loads(source.read_text(encoding="utf-8"))
    config["experiment_id"] = "g3_overlap_guard_test"
    config["comparison_methods"] = list(FIVE_METHODS)
    config["protected_paths"] = ["docs/plans"]
    config_path = tmp_path / "overlap_config.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")
    output = REPO_ROOT / "docs" / "plans" / config["experiment_id"]
    preregistration = output.with_name(output.name + ".preregistered.json")
    assert not output.exists()
    assert not preregistration.exists()

    with pytest.raises(ValueError, match="overlap"):
        runner.run(REPO_ROOT, config_path, output)

    assert not preregistration.exists()


def _smoke_config(config):
    configured = copy.deepcopy(config)
    configured["matched_blocks"] = configured["matched_blocks"][:1]
    configured["forcing"]["warmup_days"] = 8
    configured["forcing"]["reference_total_days"] = 17
    configured["stage_lengths"] = [2, 2, 2]
    configured["lead_days"] = [1, 3]
    configured["bootstrap"]["replicates"] = 100
    configured["decision_rules"]["adaptation_days_excluded_per_stage"] = 1
    configured["protected_paths"] = []
    return configured


def _prepare_replay_reference(tmp_path):
    historical_runner = importlib.import_module(HISTORICAL_RUNNER_MODULE)
    config_dir = (
        REPO_ROOT / "src" / "hbv_multilead_joint_uncertainty" / "configs"
    )
    corrected_source = config_dir / "g3_corrected_forecast_param_switch_v01.json"
    corrected = _smoke_config(
        json.loads(corrected_source.read_text(encoding="utf-8"))
    )

    reference_source = config_dir / "g3_ideal_gate_param_switch_v01.json"
    reference = _smoke_config(
        json.loads(reference_source.read_text(encoding="utf-8"))
    )
    reference["experiment_id"] = "g3_highest_posterior_reference_test"
    reference_config = tmp_path / "reference_config.json"
    reference_config.write_text(json.dumps(reference), encoding="utf-8")
    reference_output = tmp_path / reference["experiment_id"]
    historical_runner.run(REPO_ROOT, reference_config, reference_output)
    evidence = reference_output / "evidence.npz"
    return corrected, evidence


def test_opt_in_package_seals_shared_candidates_indices_and_paired_result(tmp_path):
    runner = importlib.import_module(RUNNER_MODULE)
    config, reference_evidence = _prepare_replay_reference(tmp_path)
    config["experiment_id"] = "g3_highest_posterior_packaging_test"
    config["comparison_methods"] = list(FIVE_METHODS)
    config["sealed_evidence_for_replay_check"] = {
        "path": str(reference_evidence),
        "sha256": hashlib.sha256(reference_evidence.read_bytes()).hexdigest(),
    }
    protected_relative = (
        "docs/plans/2026-07-26-g3-highest-posterior-forecast-design.md"
    )
    config["protected_paths"] = [protected_relative]
    protected_path = REPO_ROOT / protected_relative
    protected_before = protected_path.read_bytes()
    config_path = tmp_path / "highest_posterior_config.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")
    output = tmp_path / config["experiment_id"]

    summary = runner.run(REPO_ROOT, config_path, output)

    assert summary["integrity_status"] == "passed"
    assert summary["protected_artifacts_unchanged"] is True
    assert summary["comparison_methods"] == list(FIVE_METHODS)
    assert protected_path.read_bytes() == protected_before
    result = summary["result"]
    assert "paired_highest_posterior_minus_none" in result
    assert len(result["highest_posterior_minus_none_classification"]) == 2
    assert "highest_posterior" in result["rmse"]
    assert "highest_posterior" in result["oracle_ratio"]

    with np.load(output / "evidence.npz", allow_pickle=False) as evidence:
        required = {
            "forecast_none_candidates",
            "highest_posterior_candidate_indices",
            "forecast_highest_posterior",
            "squared_error_highest_posterior",
        }
        assert required <= set(evidence.files)
        final_probabilities = evidence["probabilities_none"][:, :, -1, :]
        candidates = evidence["forecast_none_candidates"]
        selected_indices = evidence["highest_posterior_candidate_indices"]
        np.testing.assert_array_equal(
            selected_indices, np.argmax(final_probabilities, axis=-1)
        )
        selected = np.empty_like(evidence["forecast_highest_posterior"])
        for block, truth in np.ndindex(selected_indices.shape):
            selected[block, truth] = candidates[
                block, truth, :, selected_indices[block, truth]
            ]
        np.testing.assert_array_equal(
            evidence["forecast_highest_posterior"], selected
        )
        weighted = np.einsum(
            "btc,btlc->btl", final_probabilities, candidates
        )
        np.testing.assert_allclose(
            evidence["forecast_none"], weighted, rtol=0.0, atol=1e-12
        )

    preregistration = json.loads(
        (output / "preregistration.json").read_text(encoding="utf-8")
    )
    assert preregistration["comparison_methods"] == list(FIVE_METHODS)
    with pytest.raises(FileExistsError, match="overwrite"):
        runner.run(REPO_ROOT, config_path, output)
