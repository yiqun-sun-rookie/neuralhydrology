"""Corrected G3 forecast comparison integrity and decision contracts."""

import copy
import hashlib
import importlib
import json
import sys
from pathlib import Path
from types import SimpleNamespace

import numpy as np
import pytest

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "src"))

MODULE = (
    "hbv_multilead_joint_uncertainty.scripts."
    "run_g3_corrected_forecast_comparison"
)


def _fake_result():
    schedule = SimpleNamespace(
        joint_candidate_indices=np.asarray([[0, 1]], dtype=np.int64),
        parameter_indices=np.asarray([[0, 1]], dtype=np.int64),
        process_indices=np.asarray([[2, 2]], dtype=np.int64),
        primary_candidate_indices=np.asarray([[0, 1]], dtype=np.int64),
        origin_joint_candidate_indices=np.asarray([1], dtype=np.int64),
        stage_start_days=np.asarray([0, 1], dtype=np.int64),
        stage_end_days=np.asarray([1, 2], dtype=np.int64),
    )
    return SimpleNamespace(
        scenario="parameter_switch",
        schedule=schedule,
        block_ids=("block_01",),
        process_noise_seeds=np.asarray([101], dtype=np.int64),
        observation_noise_seeds=np.asarray([201], dtype=np.int64),
        forcing_blocks=np.arange(9, dtype=np.float64).reshape(1, 3, 3),
        warmup_days=1,
        stage_lengths=np.asarray([1, 1], dtype=np.int64),
        assimilation_days=2,
        forecast_lead_days=np.asarray([1], dtype=np.int64),
        method_names=("open_loop", "parameter_only"),
        method_candidate_ids=(("open_loop",), ("left", "right")),
        method_candidate_counts=np.asarray([1, 2], dtype=np.int64),
        parameter_ids=("left", "center", "right"),
        process_ids=("small", "medium", "large"),
        initial_parameter_states=np.arange(45, dtype=np.float64).reshape(1, 3, 15),
        initial_covariances=np.eye(15, dtype=np.float64)[None, :, :],
        process_standard_normals=np.arange(30, dtype=np.float64).reshape(1, 2, 15),
        observation_standard_normals=np.asarray([[0.1, -0.2]], dtype=np.float64),
        truth_deterministic_states=np.arange(30, dtype=np.float64).reshape(1, 1, 2, 15),
        truth_process_perturbations=np.zeros((1, 1, 2, 15), dtype=np.float64),
        truth_projection_adjustments=np.zeros((1, 1, 2, 15), dtype=np.float64),
        truth_states=np.arange(30, dtype=np.float64).reshape(1, 1, 2, 15),
        truth_discharge=np.asarray([[[1.0, 2.0]]], dtype=np.float64),
        observed_discharge=np.asarray([[[1.1, 1.9]]], dtype=np.float64),
        truth_forecast_discharge=np.asarray([[[2.5]]], dtype=np.float64),
        method_assimilation_probabilities=np.asarray(
            [[[[[1.0, 0.0], [1.0, 0.0]], [[0.6, 0.4], [0.3, 0.7]]]]],
            dtype=np.float64,
        ),
        method_assimilation_states=np.arange(60, dtype=np.float64).reshape(1, 1, 2, 2, 15),
        method_origin_states=np.arange(30, dtype=np.float64).reshape(1, 1, 2, 15),
        method_predictions=np.asarray([[[[9.0], [8.0]]]], dtype=np.float64),
        method_candidate_predictions=np.asarray(
            [[[[[9.0, 0.0]], [[7.0, 8.0]]]]], dtype=np.float64
        ),
        method_forecast_probabilities=np.asarray(
            [[[[[1.0, 0.0]], [[0.3, 0.7]]]]], dtype=np.float64
        ),
        method_absolute_errors=np.asarray([[[[6.5], [5.5]]]], dtype=np.float64),
    )


def _reference_arrays(result):
    candidate_ids = np.full((2, 2), "", dtype="<U16")
    candidate_ids[0, 0] = "open_loop"
    candidate_ids[1] = ("left", "right")
    return {
        "scenario": np.asarray(result.scenario),
        "block_ids": np.asarray(result.block_ids),
        "process_noise_seeds": result.process_noise_seeds,
        "observation_noise_seeds": result.observation_noise_seeds,
        "forcing_blocks": result.forcing_blocks,
        "warmup_days": np.asarray(result.warmup_days, dtype=np.int64),
        "stage_lengths": result.stage_lengths,
        "assimilation_days": np.asarray(result.assimilation_days, dtype=np.int64),
        "forecast_lead_days": result.forecast_lead_days,
        "method_names": np.asarray(result.method_names),
        "method_candidate_ids": candidate_ids,
        "method_candidate_counts": result.method_candidate_counts,
        "parameter_ids": np.asarray(result.parameter_ids),
        "process_ids": np.asarray(result.process_ids),
        "truth_joint_candidate_indices": result.schedule.joint_candidate_indices,
        "truth_parameter_indices": result.schedule.parameter_indices,
        "truth_process_indices": result.schedule.process_indices,
        "truth_primary_candidate_indices": result.schedule.primary_candidate_indices,
        "origin_joint_candidate_indices": result.schedule.origin_joint_candidate_indices,
        "stage_start_days": result.schedule.stage_start_days,
        "stage_end_days": result.schedule.stage_end_days,
        "initial_parameter_states": result.initial_parameter_states,
        "initial_covariances": result.initial_covariances,
        "process_standard_normals": result.process_standard_normals,
        "observation_standard_normals": result.observation_standard_normals,
        "truth_deterministic_states": result.truth_deterministic_states,
        "truth_process_perturbations": result.truth_process_perturbations,
        "truth_projection_adjustments": result.truth_projection_adjustments,
        "truth_states": result.truth_states,
        "truth_discharge": result.truth_discharge,
        "observed_discharge": result.observed_discharge,
        "truth_forecast_discharge": result.truth_forecast_discharge,
        "method_assimilation_probabilities": result.method_assimilation_probabilities,
        "method_assimilation_states": result.method_assimilation_states,
        "method_origin_states": result.method_origin_states,
        # Forecast-derived arrays deliberately differ and must not enter the replay gate.
        "method_predictions": np.zeros_like(result.method_predictions),
        "method_candidate_predictions": np.zeros_like(result.method_candidate_predictions),
        "method_forecast_probabilities": np.zeros_like(result.method_forecast_probabilities),
        "method_absolute_errors": np.zeros_like(result.method_absolute_errors),
    }


def _write_reference(tmp_path, result):
    path = tmp_path / "sealed_evidence.npz"
    np.savez_compressed(path, **_reference_arrays(result))
    return path, hashlib.sha256(path.read_bytes()).hexdigest()


def test_replay_gate_accepts_exact_assimilation_and_ignores_historical_forecast(tmp_path):
    module = importlib.import_module(MODULE)
    result = _fake_result()
    path, digest = _write_reference(tmp_path, result)
    config = {
        "sealed_evidence_for_replay_check": {
            "path": path.name,
            "sha256": digest,
        }
    }

    check = module._cross_check_replay(tmp_path, config, result)

    assert check["passed"] is True
    assert check["mismatches"] == []
    assert check["forecast_derived_arrays_checked"] is False
    assert "method_assimilation_states" in check["checked_arrays"]
    assert "method_predictions" not in check["checked_arrays"]


def test_replay_gate_rejects_any_assimilation_mismatch(tmp_path):
    module = importlib.import_module(MODULE)
    result = _fake_result()
    path, digest = _write_reference(tmp_path, result)
    result.method_assimilation_states[0, 0, 1, 1, 3] += 1.0
    config = {
        "sealed_evidence_for_replay_check": {
            "path": path.name,
            "sha256": digest,
        }
    }

    check = module._cross_check_replay(tmp_path, config, result)

    assert check["passed"] is False
    assert check["mismatches"] == ["method_assimilation_states"]


def test_replay_gate_rejects_reference_checksum_mismatch(tmp_path):
    module = importlib.import_module(MODULE)
    result = _fake_result()
    path, _ = _write_reference(tmp_path, result)
    config = {
        "sealed_evidence_for_replay_check": {
            "path": path.name,
            "sha256": "0" * 64,
        }
    }

    with pytest.raises(ValueError, match="checksum mismatch"):
        module._cross_check_replay(tmp_path, config, result)


@pytest.mark.parametrize(
    ("lower", "upper", "expected"),
    (
        (-2.0, -0.1, "full_interaction_improves_forecast"),
        (0.1, 2.0, "full_interaction_harms_forecast"),
        (-0.1, 0.1, "no_detectable_difference"),
        (0.0, 0.0, "no_detectable_difference"),
    ),
)
def test_paired_interval_classification_is_frozen(lower, upper, expected):
    module = importlib.import_module(MODULE)
    assert module._classify_paired_interval(lower, upper) == expected


def test_packaged_corrected_run_replays_assimilation_and_seals_new_evidence(tmp_path):
    module = importlib.import_module(MODULE)
    historical_runner = importlib.import_module(
        "hbv_multilead_joint_uncertainty.scripts."
        "run_three_stage_switching_validation"
    )
    source = (
        REPO_ROOT
        / "src"
        / "hbv_multilead_joint_uncertainty"
        / "configs"
        / "g3_corrected_forecast_param_switch_v01.json"
    )
    base = json.loads(source.read_text(encoding="utf-8"))
    base["matched_blocks"] = base["matched_blocks"][:1]
    base["forcing"]["warmup_days"] = 8
    base["forcing"]["reference_total_days"] = 17
    base["stage_lengths"] = [2, 2, 2]
    base["lead_days"] = [1, 3]
    base["bootstrap"]["replicates"] = 100
    base["decision_rules"]["adaptation_days_excluded_per_stage"] = 1
    base["protected_paths"] = []

    reference_source = source.with_name("g3_ideal_gate_param_switch_v01.json")
    reference_config = json.loads(reference_source.read_text(encoding="utf-8"))
    reference_config["experiment_id"] = "g3_corrected_forecast_reference_test"
    reference_config["matched_blocks"] = reference_config["matched_blocks"][:1]
    reference_config["forcing"]["warmup_days"] = 8
    reference_config["forcing"]["reference_total_days"] = 17
    reference_config["stage_lengths"] = [2, 2, 2]
    reference_config["lead_days"] = [1, 3]
    reference_config["bootstrap"]["replicates"] = 100
    reference_config["decision_rules"]["adaptation_days_excluded_per_stage"] = 1
    reference_config["protected_paths"] = []
    reference_config_path = tmp_path / "reference_config.json"
    reference_config_path.write_text(
        json.dumps(reference_config), encoding="utf-8"
    )
    reference_output = tmp_path / reference_config["experiment_id"]
    historical_runner.run(REPO_ROOT, reference_config_path, reference_output)
    reference_evidence = reference_output / "evidence.npz"

    config = copy.deepcopy(base)
    config["experiment_id"] = "g3_corrected_forecast_packaging_test"
    config["comparison_methods"] = ["full", "none", "static", "oracle"]
    config["sealed_evidence_for_replay_check"] = {
        "path": str(reference_evidence),
        "sha256": hashlib.sha256(reference_evidence.read_bytes()).hexdigest(),
    }
    config_path = tmp_path / "corrected_config.json"
    config_path.write_text(json.dumps(config), encoding="utf-8")
    output = tmp_path / config["experiment_id"]

    summary = module.run(REPO_ROOT, config_path, output)

    assert summary["integrity_status"] == "passed"
    assert summary["replay_check_passed"] is True
    assert summary["forecast_contract"] == base["forecast_contract"]
    assert len(summary["result"]["full_minus_none_classification"]) == 2
    assert "comparison_methods" not in summary
    assert set(summary["result"]) == {
        "leads",
        "rmse",
        "oracle_ratio",
        "paired_full_minus_none",
        "paired_none_minus_static",
        "full_minus_none_classification",
        "identification",
    }
    preregistration = json.loads(
        (output / "preregistration.json").read_text(encoding="utf-8")
    )
    assert "comparison_methods" not in preregistration
    with np.load(output / "evidence.npz", allow_pickle=False) as evidence:
        assert tuple(str(value) for value in evidence["arms"]) == (
            "full",
            "none",
            "static",
            "oracle",
        )
        assert not {
            "forecast_highest_posterior",
            "squared_error_highest_posterior",
            "forecast_none_candidates",
            "highest_posterior_candidate_indices",
        } & set(evidence.files)
    assert (output / "evidence.npz").is_file()
    assert (output / "checksums.json").is_file()
    assert (output / "replay_check.json").is_file()
    assert not output.with_name(output.name + ".incomplete").exists()
