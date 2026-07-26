"""Package the frozen state-path by final-weight forecast diagnostic."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import shutil
import sys
from collections.abc import Mapping
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_joint_uncertainty.hbv_adapter import PARAMETER_NAMES  # noqa: E402
from hbv_multilead_joint_uncertainty.methods import build_method_definitions  # noqa: E402
from hbv_multilead_joint_uncertainty.scripts.run_three_stage_switching_validation import (  # noqa: E402
    _atomic_json_write,
    _environment,
    _json_write,
    _load_observation_noise,
    _load_parameter_vectors,
    _load_process_covariances,
    _protected_hashes,
    _replace_directory_with_retries,
    _resource_preflight,
    _validate_output_is_disjoint_from_protected_paths,
)
from hbv_multilead_joint_uncertainty.state_weight_factorial_diagnostic import (  # noqa: E402
    compare_state_weight_factorial,
    summarize_state_weight_factorial,
)

_IDEAL_REQUIRED_ARRAYS = frozenset({
    "block_ids", "forcing_blocks", "warmup_days", "assimilation_days",
    "forecast_lead_days", "initial_parameter_states", "initial_covariances",
    "observed_discharge", "truth_forecast_discharge",
    "truth_primary_candidate_indices", "method_names", "method_candidate_ids",
    "method_candidate_counts", "parameter_ids", "process_ids",
    "parameter_vectors", "process_covariances", "observation_standard_deviation",
})
_REFERENCE_REQUIRED_ARRAYS = frozenset({
    "block_ids", "leads", "assimilation_days", "true_candidate_labels",
    "truth_forecasts", "probabilities_full", "probabilities_none",
    "forecast_none_candidates", "forecast_full", "forecast_none",
})

# This runner owns its dependency manifest and preserves relative paths.
_SOURCE_FILES = (
    "src/hbv_multilead_joint_uncertainty/state_weight_factorial_diagnostic.py",
    "src/hbv_multilead_joint_uncertainty/scripts/run_g3_state_weight_factorial.py",
    "test/test_hbv_state_weight_factorial_diagnostic.py",
    "src/hbv_multilead_joint_uncertainty/methods.py",
    "src/hbv_multilead_joint_uncertainty/forecast.py",
    "src/hbv_joint_uncertainty/candidates.py",
    "src/hbv_joint_uncertainty/hbv_adapter.py",
    "src/hbv_joint_uncertainty/preflight.py",
    "src/hbv_joint_uncertainty/imm.py",
    "src/hbv_joint_uncertainty/sigma_filter.py",
    "src/scl_hydro/hbv_lite_numpy.py",
    "src/hbv_multilead_joint_uncertainty/scripts/run_three_stage_switching_validation.py",
    "src/hbv_multilead_joint_uncertainty/scripts/run_model_probability_validation.py",
    "src/hbv_multilead_joint_uncertainty/scripts/run_process_noise_identification_validation.py",
    "src/hbv_multilead_joint_uncertainty/scripts/run_synthetic_truth_validation.py",
    "src/hbv_multilead_joint_uncertainty/three_stage_switching_validation.py",
    "src/hbv_multilead_joint_uncertainty/model_probability_validation.py",
    "src/hbv_multilead_joint_uncertainty/process_noise_identification_validation.py",
    "src/hbv_multilead_joint_uncertainty/synthetic_truth.py",
)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _load_sealed_archive(root, reference, required_arrays, label):
    if not isinstance(reference, Mapping) or not {"path", "sha256"} <= set(reference):
        raise ValueError(f"{label} must define path and sha256")
    path = (root / str(reference["path"])).resolve()
    if not path.is_file() or _sha256(path) != str(reference["sha256"]):
        raise ValueError(f"{label} checksum mismatch")
    with np.load(path, allow_pickle=False) as archive:
        missing = sorted(required_arrays - set(archive.files))
        if missing:
            raise ValueError(f"{label} is missing arrays: {missing}")
        arrays = {name: archive[name].copy() for name in archive.files}
    return path, arrays


def _as_unique_strings(value, name):
    raw = np.asarray(value)
    if raw.ndim != 1 or raw.size == 0:
        raise ValueError(f"{name} must be a nonempty identifier vector")
    values = np.asarray([str(item) for item in raw], dtype=str)
    if any(not item for item in values) or len(set(values)) != len(values):
        raise ValueError(f"{name} must contain unique nonempty identifiers")
    return values


def _scalar_integer(value, name):
    raw = np.asarray(value)
    if raw.ndim != 0 or np.issubdtype(raw.dtype, np.bool_):
        raise ValueError(f"{name} must be an integer scalar")
    numeric = float(raw)
    if not np.isfinite(numeric) or numeric != int(numeric):
        raise ValueError(f"{name} must be an integer scalar")
    return int(numeric)


def _maximum_absolute_error(left, right):
    left_array, right_array = np.asarray(left), np.asarray(right)
    if left_array.shape != right_array.shape:
        return float("inf")
    if left_array.size == 0:
        return 0.0
    if np.issubdtype(left_array.dtype, np.number) and np.issubdtype(right_array.dtype, np.number):
        return float(np.max(np.abs(left_array.astype(np.float64) - right_array.astype(np.float64))))
    return 0.0 if np.array_equal(left_array, right_array) else float("inf")


def _exact_check(name, actual, expected):
    actual_array, expected_array = np.asarray(actual), np.asarray(expected)
    result = {
        "contract": "array_equal",
        "maximum_absolute_error": _maximum_absolute_error(actual_array, expected_array),
        "passed": bool(np.array_equal(actual_array, expected_array)),
    }
    if not result["passed"]:
        raise ValueError(f"{name} identity mismatch")
    return result


def _tolerance_check(name, actual, expected):
    actual_array = np.asarray(actual, dtype=np.float64)
    expected_array = np.asarray(expected, dtype=np.float64)
    result = {
        "contract": "rtol=0,atol=1e-12",
        "maximum_absolute_error": _maximum_absolute_error(actual_array, expected_array),
        "passed": bool(actual_array.shape == expected_array.shape and np.allclose(actual_array, expected_array, rtol=0.0, atol=1e-12)),
    }
    if not result["passed"]:
        raise RuntimeError(f"{name} cross-check failed; maximum error={result['maximum_absolute_error']}")
    return result


def _parameter_array(parameter_vectors, parameter_ids):
    try:
        return np.asarray([[float(parameter_vectors[str(identifier)][name]) for name in PARAMETER_NAMES] for identifier in parameter_ids], dtype=np.float64)
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError("parameter_vectors do not match the sealed parameter contract") from error


def _process_covariance_array(process_covariances, process_ids):
    try:
        return np.asarray([process_covariances[str(identifier)] for identifier in process_ids], dtype=np.float64)
    except (KeyError, TypeError, ValueError) as error:
        raise ValueError("process_covariances do not match the sealed process contract") from error


def _primary_candidate_ids(ideal, method_name):
    method_names = np.asarray(ideal["method_names"]).astype(str)
    if method_names.ndim != 1 or len(set(method_names)) != len(method_names):
        raise ValueError("method_names must be a unique vector")
    matches = np.flatnonzero(method_names == str(method_name))
    if len(matches) != 1:
        raise ValueError("primary_candidate_method_name must identify exactly one sealed method")
    row = int(matches[0])
    counts = np.asarray(ideal["method_candidate_counts"])
    identifiers = np.asarray(ideal["method_candidate_ids"]).astype(str)
    if counts.shape != method_names.shape or identifiers.ndim != 2:
        raise ValueError("sealed method candidate metadata has invalid shapes")
    count = _scalar_integer(counts[row], "primary method candidate count")
    if count <= 0 or count > identifiers.shape[1]:
        raise ValueError("primary method candidate count is outside the sealed width")
    return _as_unique_strings(identifiers[row, :count], "primary candidate_ids")


def _ordered_primary_candidates(methods, primary_method_name, sealed_candidate_ids):
    if primary_method_name not in methods:
        raise ValueError("primary_candidate_method_name is absent from built definitions")
    by_identifier = {}
    for candidate in tuple(methods[primary_method_name]):
        identifier = str(candidate.candidate_id)
        if not identifier or identifier in by_identifier:
            raise ValueError("built primary candidate identifiers must be unique")
        by_identifier[identifier] = candidate
    if set(by_identifier) != set(sealed_candidate_ids):
        raise ValueError("built primary candidate_ids differ from the sealed candidate order")
    ordered = tuple(by_identifier[str(identifier)] for identifier in sealed_candidate_ids)
    parameter_ids = np.asarray([str(candidate.parameter_id) for candidate in ordered], dtype=str)
    return ordered, parameter_ids


def _sealed_driver_inputs(ideal, candidate_ids):
    return {
        "block_ids": np.asarray(ideal["block_ids"]).copy(),
        "forcing_blocks": np.asarray(ideal["forcing_blocks"]).copy(),
        "warmup_days": _scalar_integer(ideal["warmup_days"], "warmup_days"),
        "assimilation_days": _scalar_integer(ideal["assimilation_days"], "assimilation_days"),
        "forecast_lead_days": np.asarray(ideal["forecast_lead_days"]).copy(),
        "initial_parameter_states": np.asarray(ideal["initial_parameter_states"]).copy(),
        "initial_covariances": np.asarray(ideal["initial_covariances"]).copy(),
        "observed_discharge": np.asarray(ideal["observed_discharge"]).copy(),
        "truth_forecast_discharge": np.asarray(ideal["truth_forecast_discharge"]).copy(),
        "truth_primary_candidate_indices": np.asarray(ideal["truth_primary_candidate_indices"]).copy(),
        "parameter_ids": np.asarray(ideal["parameter_ids"]).copy(),
        "candidate_ids": candidate_ids.copy(),
    }


def _validate_reference_identity(ideal, reference):
    checks = {
        "block_ids": _exact_check("block_ids", reference["block_ids"], ideal["block_ids"]),
        "forecast_lead_days": _exact_check("forecast_lead_days", reference["leads"], ideal["forecast_lead_days"]),
        "assimilation_days": _exact_check("assimilation_days", reference["assimilation_days"], ideal["assimilation_days"]),
        "truth_forecasts": _exact_check("truth_forecasts", reference["truth_forecasts"], ideal["truth_forecast_discharge"]),
    }
    days = _scalar_integer(ideal["assimilation_days"], "assimilation_days")
    labels = np.asarray(ideal["truth_primary_candidate_indices"])
    if labels.ndim != 2 or labels.shape[1] < days:
        raise ValueError("truth_primary_candidate_indices do not cover assimilation")
    checks["true_candidate_labels"] = _exact_check(
        "true_candidate_labels", reference["true_candidate_labels"], labels[:, :days]
    )
    return checks


def _validate_reference_shapes(ideal, reference, candidate_count):
    truth = np.asarray(ideal["truth_forecast_discharge"])
    if truth.ndim != 3:
        raise ValueError("truth_forecast_discharge must be a block by truth by lead array")
    blocks, truths, leads = truth.shape
    days = _scalar_integer(ideal["assimilation_days"], "assimilation_days")
    expected = {
        "probabilities_full": (blocks, truths, days, candidate_count),
        "probabilities_none": (blocks, truths, days, candidate_count),
        "forecast_none_candidates": (blocks, truths, leads, candidate_count),
        "forecast_full": (blocks, truths, leads),
        "forecast_none": (blocks, truths, leads),
    }
    for name, shape in expected.items():
        values = np.asarray(reference[name])
        if values.shape != shape or not np.all(np.isfinite(values)):
            raise ValueError(f"sealed forecast reference {name} has invalid shape or values")


def _computed_cross_checks(driver, reference, candidate_ids, candidate_parameter_ids, ideal):
    checks = {
        "new_truth_forecasts": _exact_check("new truth_forecasts", driver["truth_forecasts"], reference["truth_forecasts"]),
        "new_probabilities_full": _exact_check("new probabilities_full", driver["probabilities_full"], reference["probabilities_full"]),
        "new_probabilities_none": _exact_check("new probabilities_none", driver["probabilities_none"], reference["probabilities_none"]),
        "new_none_candidate_forecasts": _exact_check("new forecast_none_candidates", driver["candidate_forecasts_none"], reference["forecast_none_candidates"]),
        "new_candidate_ids": _exact_check("new candidate_ids", driver["candidate_ids"], candidate_ids),
        "new_parameter_ids": _exact_check("new parameter_ids", driver["parameter_ids"], ideal["parameter_ids"]),
        "new_block_ids": _exact_check("new block_ids", driver["block_ids"], ideal["block_ids"]),
        "new_forecast_lead_days": _exact_check("new forecast_lead_days", driver["forecast_lead_days"], ideal["forecast_lead_days"]),
    }
    days = _scalar_integer(ideal["assimilation_days"], "assimilation_days")
    labels = np.asarray(reference["true_candidate_labels"])
    checks["new_final_true_candidate_indices"] = _exact_check(
        "new final_true_candidate_indices", driver["final_true_candidate_indices"], labels[:, days - 1]
    )
    checks["new_final_true_candidate_ids"] = _exact_check(
        "new final_true_candidate_ids", driver["final_true_candidate_ids"], candidate_ids[labels[:, days - 1]]
    )
    full_internal = np.einsum(
        "btlc,btc->btl",
        np.asarray(driver["candidate_forecasts_full"], dtype=np.float64),
        np.asarray(driver["probabilities_full"], dtype=np.float64)[:, :, -1, :],
    )
    none_internal = np.einsum(
        "btlc,btc->btl",
        np.asarray(driver["candidate_forecasts_none"], dtype=np.float64),
        np.asarray(driver["probabilities_none"], dtype=np.float64)[:, :, -1, :],
    )
    checks["internal_full_combination"] = _tolerance_check(
        "internal full combination", driver["full_states_full_weights"], full_internal
    )
    checks["internal_none_combination"] = _tolerance_check(
        "internal none combination", driver["none_states_none_weights"], none_internal
    )
    checks["historical_full_combination"] = _tolerance_check(
        "historical full combination", driver["full_states_full_weights"], reference["forecast_full"]
    )
    checks["historical_none_combination"] = _tolerance_check(
        "historical none combination", driver["none_states_none_weights"], reference["forecast_none"]
    )
    checks["candidate_parameter_mapping"] = {
        "contract": "explicit_saved_mapping", "maximum_absolute_error": 0.0,
        "passed": bool(len(candidate_ids) == len(candidate_parameter_ids)),
    }
    if not checks["candidate_parameter_mapping"]["passed"]:
        raise RuntimeError("candidate_parameter_ids mapping length mismatch")
    return checks


def _source_snapshot(root, destination):
    destination.mkdir(parents=True, exist_ok=False)
    if len(_SOURCE_FILES) != len(set(_SOURCE_FILES)):
        raise ValueError("source snapshot manifest contains duplicate paths")
    for configured in _SOURCE_FILES:
        relative = Path(configured)
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"source snapshot path is not repository-relative: {configured}")
        source = (root / relative).resolve()
        if not source.is_file():
            raise FileNotFoundError(f"source snapshot file is missing: {configured}")
        target = destination / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)


def _flatten_arrays(prefix, value, output):
    if isinstance(value, Mapping):
        for key in sorted(value, key=str):
            child = f"{prefix}__{key}" if prefix else str(key)
            _flatten_arrays(child, value[key], output)
        return
    try:
        array = np.asarray(value)
    except (TypeError, ValueError) as error:
        raise ValueError(f"evidence value {prefix} cannot be stored in npz") from error
    if array.dtype == object:
        raise ValueError(f"evidence value {prefix} has an object dtype")
    output[prefix] = array.copy()


def _json_compatible(value):
    if isinstance(value, Mapping):
        return {str(key): _json_compatible(item) for key, item in value.items()}
    if isinstance(value, np.ndarray):
        return value.tolist()
    if isinstance(value, np.generic):
        return value.item()
    if isinstance(value, (tuple, list)):
        return [_json_compatible(item) for item in value]
    return value


def _statistics_summary(statistics):
    result = {}
    if "combination_rmse" in statistics:
        result["combination_rmse"] = _json_compatible(statistics["combination_rmse"])
    if "effects" in statistics:
        fields = ("mean", "ci_low", "ci_high", "baseline_mse", "equivalence_lower", "equivalence_upper", "classification")
        result["effects"] = {
            str(name): {field: _json_compatible(values[field]) for field in fields if field in values}
            for name, values in statistics["effects"].items()
        }
    if "wrong_candidate" in statistics:
        fields = ("displacement_ratio", "displacement_ratio_ci_low", "displacement_ratio_ci_high", "equivalent")
        result["wrong_candidate"] = {
            field: _json_compatible(statistics["wrong_candidate"][field])
            for field in fields if field in statistics["wrong_candidate"]
        }
    if "nonadditivity" in statistics:
        result["nonadditivity"] = {}
        for name in ("prediction", "squared_error"):
            if name in statistics["nonadditivity"]:
                result["nonadditivity"][name] = {
                    field: _json_compatible(statistics["nonadditivity"][name][field])
                    for field in ("mean", "ci_low", "ci_high")
                    if field in statistics["nonadditivity"][name]
                }
    return result


def run(repo_root: Path, config_path: Path, output_dir: Path) -> dict:
    """Run the diagnostic once and freeze an immutable evidence package."""
    root = repo_root.resolve()
    config_file = config_path.resolve()
    output = output_dir.resolve()
    incomplete = output.with_name(output.name + ".incomplete")
    preregistration_path = output.with_name(output.name + ".preregistered.json")
    if output.exists() or incomplete.exists() or preregistration_path.exists():
        raise FileExistsError("refusing to overwrite existing evidence")

    config_bytes = config_file.read_bytes()
    config_hash = hashlib.sha256(config_bytes).hexdigest()
    config = json.loads(config_bytes.decode("utf-8"))
    if output.name != str(config.get("experiment_id", "")):
        raise ValueError("output directory name must equal experiment_id")
    required_config = {
        "sealed_ideal_input_evidence", "sealed_forecast_reference_evidence",
        "primary_candidate_method_name", "parameter_source", "process_noise_source",
        "observation_noise_source", "factor_transition_stay_probability",
        "bootstrap", "resource_pilot", "protected_paths", "forecast_contract",
        "scope_limit",
    }
    missing_config = sorted(required_config - set(config))
    if missing_config:
        raise ValueError(f"configuration is missing fields: {missing_config}")

    protected_paths = tuple((root / str(value)).resolve() for value in config["protected_paths"])
    for candidate_output in (output, incomplete, preregistration_path):
        _validate_output_is_disjoint_from_protected_paths(candidate_output, protected_paths)

    ideal_path, ideal = _load_sealed_archive(
        root, config["sealed_ideal_input_evidence"], _IDEAL_REQUIRED_ARRAYS,
        "sealed_ideal_input_evidence",
    )
    reference_path, reference = _load_sealed_archive(
        root, config["sealed_forecast_reference_evidence"], _REFERENCE_REQUIRED_ARRAYS,
        "sealed_forecast_reference_evidence",
    )
    primary_method_name = str(config["primary_candidate_method_name"])
    candidate_ids = _primary_candidate_ids(ideal, primary_method_name)
    parameter_ids = _as_unique_strings(ideal["parameter_ids"], "parameter_ids")
    process_ids = _as_unique_strings(ideal["process_ids"], "process_ids")
    _validate_reference_shapes(ideal, reference, len(candidate_ids))

    identity_checks = _validate_reference_identity(ideal, reference)
    identity_checks["configured_parameter_ids"] = _exact_check(
        "configured parameter_ids",
        np.asarray(config["parameter_source"]["parameter_ids"]).astype(str),
        parameter_ids,
    )
    identity_checks["configured_process_ids"] = _exact_check(
        "configured process_ids",
        np.asarray(config["process_noise_source"]["process_ids"]).astype(str),
        process_ids,
    )

    parameter_vectors, parameter_csv, parameter_hash = _load_parameter_vectors(root, config)
    process_covariances, process_scales, process_csv, process_hash = _load_process_covariances(root, config)
    observation_std, observation_csv, observation_hash = _load_observation_noise(root, config)
    identity_checks["parameter_vectors_direct"] = _exact_check(
        "parameter_vectors", _parameter_array(parameter_vectors, parameter_ids), ideal["parameter_vectors"]
    )
    identity_checks["process_covariances_direct"] = _exact_check(
        "process_covariances", _process_covariance_array(process_covariances, process_ids), ideal["process_covariances"]
    )
    identity_checks["observation_standard_deviation_direct"] = _exact_check(
        "observation_standard_deviation", np.asarray(observation_std, dtype=np.float64), ideal["observation_standard_deviation"]
    )

    selected_process = str(config["process_noise_source"]["selected_process_id"])
    methods = build_method_definitions(parameter_vectors, process_scales, process_covariances, selected_process)
    ordered_candidates, candidate_parameter_ids = _ordered_primary_candidates(
        methods, primary_method_name, candidate_ids
    )
    if not set(candidate_parameter_ids) <= set(parameter_ids):
        raise ValueError("candidate_parameter_ids are outside the sealed parameter_ids")

    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    preregistration = {
        "frozen_before_execution": True,
        "experiment_id": config["experiment_id"],
        "scenario": config.get("scenario"),
        "forecast_contract": config["forecast_contract"],
        "scope_limit": config["scope_limit"],
        "bootstrap": config["bootstrap"],
        "sealed_ideal_input_evidence": config["sealed_ideal_input_evidence"],
        "sealed_forecast_reference_evidence": config["sealed_forecast_reference_evidence"],
        "primary_candidate_method_name": primary_method_name,
        "candidate_ids": candidate_ids.tolist(),
        "candidate_parameter_ids": candidate_parameter_ids.tolist(),
        "config_sha256": config_hash,
        "started_at_utc": started_at,
        "output_directory": str(output),
    }
    _atomic_json_write(preregistration_path, preregistration)

    resource = _resource_preflight(config, root)
    if not bool(resource.get("safe_to_run", False)):
        raise MemoryError("resource preflight reported safe_to_run=False")
    protected_before = _protected_hashes(root, config["protected_paths"])

    sealed_inputs = _sealed_driver_inputs(ideal, candidate_ids)
    driver = compare_state_weight_factorial(
        sealed_inputs,
        ordered_candidates,
        observation_std,
        float(config["factor_transition_stay_probability"]),
    )
    bootstrap = config["bootstrap"]
    statistics = summarize_state_weight_factorial(
        driver,
        int(bootstrap["replicates"]),
        int(bootstrap["seed"]),
        float(bootstrap["minimum_rmse_fraction"]),
    )
    computed_checks = _computed_cross_checks(
        driver, reference, candidate_ids, candidate_parameter_ids, ideal
    )
    cross_checks = {**identity_checks, **computed_checks}
    cross_checks["passed"] = bool(all(
        bool(entry["passed"])
        for entry in cross_checks.values()
        if isinstance(entry, Mapping) and "passed" in entry
    ))
    if not cross_checks["passed"]:
        raise RuntimeError("one or more evidence cross-checks failed")

    evidence = {}
    _flatten_arrays("driver", driver, evidence)
    _flatten_arrays("statistics", statistics, evidence)
    _flatten_arrays("identity", {
        "candidate_ids": candidate_ids,
        "candidate_parameter_ids": candidate_parameter_ids,
        "parameter_ids": parameter_ids,
        "process_ids": process_ids,
        "block_ids": ideal["block_ids"],
        "forecast_lead_days": ideal["forecast_lead_days"],
        "assimilation_days": ideal["assimilation_days"],
        "method_names": ideal["method_names"],
        "method_candidate_ids": ideal["method_candidate_ids"],
        "method_candidate_counts": ideal["method_candidate_counts"],
    }, evidence)
    _flatten_arrays("input_identity", {
        "sealed_ideal_input_evidence_path": str(config["sealed_ideal_input_evidence"]["path"]),
        "sealed_ideal_input_evidence_sha256": _sha256(ideal_path),
        "sealed_forecast_reference_evidence_path": str(config["sealed_forecast_reference_evidence"]["path"]),
        "sealed_forecast_reference_evidence_sha256": _sha256(reference_path),
        "parameter_vectors": ideal["parameter_vectors"],
        "process_covariances": ideal["process_covariances"],
        "observation_standard_deviation": ideal["observation_standard_deviation"],
    }, evidence)
    _flatten_arrays("cross_checks", cross_checks, evidence)

    incomplete.mkdir(parents=True, exist_ok=False)
    (incomplete / "config_snapshot.json").write_bytes(config_bytes)
    (incomplete / "preregistration.json").write_bytes(preregistration_path.read_bytes())
    _json_write(incomplete / "resource_preflight.json", resource)
    _json_write(incomplete / "cross_checks.json", cross_checks)
    _json_write(incomplete / "environment.json", _environment(root, started_at))
    (incomplete / "parameter_vectors.csv").write_bytes(parameter_csv)
    (incomplete / "process_noise_covariances.csv").write_bytes(process_csv)
    (incomplete / "observation_noise.csv").write_bytes(observation_csv)
    np.savez_compressed(incomplete / "evidence.npz", **evidence)
    _source_snapshot(root, incomplete / "source_snapshot")

    protected_after = _protected_hashes(root, config["protected_paths"])
    protected_unchanged = protected_before == protected_after
    integrity_passed = bool(cross_checks["passed"] and protected_unchanged)
    summary = {
        "experiment_id": config["experiment_id"],
        "scenario": config.get("scenario"),
        "integrity_status": "passed" if integrity_passed else "failed",
        "cross_checks_passed": bool(cross_checks["passed"]),
        "protected_artifacts_unchanged": protected_unchanged,
        "forecast_contract": config["forecast_contract"],
        "scope_limit": config["scope_limit"],
        "candidate_ids": candidate_ids.tolist(),
        "candidate_parameter_ids": candidate_parameter_ids.tolist(),
        "parameter_snapshot_sha256": parameter_hash,
        "process_snapshot_sha256": process_hash,
        "observation_snapshot_sha256": observation_hash,
        "sealed_ideal_input_evidence_sha256": _sha256(ideal_path),
        "sealed_forecast_reference_evidence_sha256": _sha256(reference_path),
        "config_sha256": config_hash,
        "result": _statistics_summary(statistics),
    }
    _json_write(incomplete / "summary.json", summary)
    _json_write(incomplete / "protected_artifact_integrity.json", {
        "configured_paths": config["protected_paths"],
        "before": protected_before,
        "after_evidence_writes": protected_after,
        "status": "unchanged" if protected_unchanged else "changed",
    })
    checksums = {
        path.relative_to(incomplete).as_posix(): _sha256(path)
        for path in sorted(incomplete.rglob("*"))
        if path.is_file() and path.name != "checksums.json"
    }
    _json_write(incomplete / "checksums.json", checksums)
    if not integrity_passed:
        raise RuntimeError("protected-artifact or cross-check integrity gate failed")
    _replace_directory_with_retries(incomplete, output)
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    arguments = parser.parse_args()
    summary = run(arguments.repo_root, arguments.config, arguments.output_dir)
    print(json.dumps(summary, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
