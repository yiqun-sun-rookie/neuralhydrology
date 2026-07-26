"""Run the corrected G3 multi-day forecast comparison.

The historical G3 truth and assimilation are replayed exactly. Forecast-derived
arrays are intentionally excluded from the replay gate because this experiment
uses the corrected contract: fixed posterior probabilities, identity model
transition, and no cross-candidate state mixing during forecasting.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import shutil
import sys
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.interaction_value_comparison import (  # noqa: E402
    compare_interaction_arms,
    summarize_interaction_value,
)
from hbv_multilead_joint_uncertainty.methods import build_method_definitions  # noqa: E402
from hbv_multilead_joint_uncertainty.scripts.run_g3_phase2_interaction_value import (  # noqa: E402
    _evidence_arrays,
)
from hbv_multilead_joint_uncertainty.scripts.run_three_stage_switching_validation import (  # noqa: E402
    _atomic_json_write,
    _environment,
    _forcing_blocks,
    _json_write,
    _load_observation_noise,
    _load_parameter_vectors,
    _load_process_covariances,
    _protected_hashes,
    _replace_directory_with_retries,
    _resource_preflight,
    _validate_output_is_disjoint_from_protected_paths,
    _validated_blocks,
)
from hbv_multilead_joint_uncertainty.three_stage_switching_validation import (  # noqa: E402
    run_three_stage_switching_validation,
)


_FORECAST_DERIVED_ARRAYS = frozenset(
    {
        "method_predictions",
        "method_candidate_predictions",
        "method_forecast_probabilities",
        "method_absolute_errors",
    }
)

_HISTORICAL_COMPARISON_METHODS = ("full", "none", "static", "oracle")
_HIGHEST_POSTERIOR_COMPARISON_METHODS = (
    "full",
    "none",
    "highest_posterior",
    "static",
    "oracle",
)


def _highest_posterior_enabled(config: dict) -> bool:
    """Validate the frozen comparison-method order and return the opt-in flag."""
    if "comparison_methods" not in config:
        return False
    configured = config["comparison_methods"]
    if not isinstance(configured, list) or any(
        not isinstance(method, str) for method in configured
    ):
        raise ValueError("comparison_methods must be a list of method names")
    methods = tuple(configured)
    if methods == _HISTORICAL_COMPARISON_METHODS:
        return False
    if methods == _HIGHEST_POSTERIOR_COMPARISON_METHODS:
        return True
    raise ValueError(
        "comparison_methods must equal the frozen historical or "
        "highest-posterior method order"
    )


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _candidate_id_matrix(candidate_ids, width: int) -> np.ndarray:
    matrix = np.full((len(candidate_ids), width), "", dtype="<U96")
    for row, values in enumerate(candidate_ids):
        if len(values) > width:
            raise ValueError("sealed candidate-id width is smaller than replayed candidates")
        matrix[row, : len(values)] = tuple(str(value) for value in values)
    return matrix


def _replay_arrays(result, candidate_width: int) -> dict[str, np.ndarray]:
    schedule = result.schedule
    return {
        "scenario": np.asarray(result.scenario),
        "block_ids": np.asarray(result.block_ids),
        "process_noise_seeds": np.asarray(result.process_noise_seeds),
        "observation_noise_seeds": np.asarray(result.observation_noise_seeds),
        "forcing_blocks": np.asarray(result.forcing_blocks),
        "warmup_days": np.asarray(result.warmup_days, dtype=np.int64),
        "stage_lengths": np.asarray(result.stage_lengths),
        "assimilation_days": np.asarray(result.assimilation_days, dtype=np.int64),
        "forecast_lead_days": np.asarray(result.forecast_lead_days),
        "method_names": np.asarray(result.method_names),
        "method_candidate_ids": _candidate_id_matrix(
            result.method_candidate_ids, candidate_width
        ),
        "method_candidate_counts": np.asarray(result.method_candidate_counts),
        "parameter_ids": np.asarray(result.parameter_ids),
        "process_ids": np.asarray(result.process_ids),
        "truth_joint_candidate_indices": np.asarray(
            schedule.joint_candidate_indices
        ),
        "truth_parameter_indices": np.asarray(schedule.parameter_indices),
        "truth_process_indices": np.asarray(schedule.process_indices),
        "truth_primary_candidate_indices": np.asarray(
            schedule.primary_candidate_indices
        ),
        "origin_joint_candidate_indices": np.asarray(
            schedule.origin_joint_candidate_indices
        ),
        "stage_start_days": np.asarray(schedule.stage_start_days),
        "stage_end_days": np.asarray(schedule.stage_end_days),
        "initial_parameter_states": np.asarray(result.initial_parameter_states),
        "initial_covariances": np.asarray(result.initial_covariances),
        "process_standard_normals": np.asarray(result.process_standard_normals),
        "observation_standard_normals": np.asarray(
            result.observation_standard_normals
        ),
        "truth_deterministic_states": np.asarray(
            result.truth_deterministic_states
        ),
        "truth_process_perturbations": np.asarray(
            result.truth_process_perturbations
        ),
        "truth_projection_adjustments": np.asarray(
            result.truth_projection_adjustments
        ),
        "truth_states": np.asarray(result.truth_states),
        "truth_discharge": np.asarray(result.truth_discharge),
        "observed_discharge": np.asarray(result.observed_discharge),
        "truth_forecast_discharge": np.asarray(result.truth_forecast_discharge),
        "method_assimilation_probabilities": np.asarray(
            result.method_assimilation_probabilities
        ),
        "method_assimilation_states": np.asarray(
            result.method_assimilation_states
        ),
        "method_origin_states": np.asarray(result.method_origin_states),
    }


def _cross_check_replay(root: Path, config: dict, result) -> dict:
    reference = config["sealed_evidence_for_replay_check"]
    path = (root / str(reference["path"])).resolve()
    if not path.is_file() or _sha256(path) != str(reference["sha256"]):
        raise ValueError("sealed evidence checksum mismatch")

    with np.load(path, allow_pickle=False) as sealed:
        candidate_width = int(sealed["method_candidate_ids"].shape[1])
        replay = _replay_arrays(result, candidate_width)
        missing = sorted(name for name in replay if name not in sealed.files)
        if missing:
            raise ValueError(f"sealed evidence is missing replay arrays: {missing}")
        mismatches = sorted(
            name
            for name, value in replay.items()
            if not np.array_equal(value, sealed[name])
        )

    return {
        "performed": True,
        "sealed_evidence_path": str(reference["path"]),
        "sealed_evidence_sha256": str(reference["sha256"]),
        "checked_arrays": sorted(replay),
        "forecast_derived_arrays_checked": False,
        "excluded_forecast_derived_arrays": sorted(_FORECAST_DERIVED_ARRAYS),
        "mismatches": mismatches,
        "passed": not mismatches,
    }


def _classify_paired_interval(lower: float, upper: float) -> str:
    if upper < 0.0:
        return "full_interaction_improves_forecast"
    if lower > 0.0:
        return "full_interaction_harms_forecast"
    return "no_detectable_difference"


def _classify_highest_posterior_interval(lower: float, upper: float) -> str:
    if upper < 0.0:
        return "improves"
    if lower > 0.0:
        return "harms"
    return "no_detectable_difference"


_SOURCE_FILES = (
    "src/hbv_multilead_joint_uncertainty/interaction_value_comparison.py",
    "src/hbv_multilead_joint_uncertainty/scripts/run_g3_corrected_forecast_comparison.py",
    "src/hbv_multilead_joint_uncertainty/scripts/run_g3_phase2_interaction_value.py",
    "src/hbv_multilead_joint_uncertainty/three_stage_switching_validation.py",
    "src/hbv_multilead_joint_uncertainty/methods.py",
    "src/hbv_multilead_joint_uncertainty/forecast.py",
    "src/hbv_joint_uncertainty/imm.py",
    "src/hbv_joint_uncertainty/sigma_filter.py",
    "test/test_hbv_corrected_forecast_comparison.py",
    "test/test_hbv_highest_posterior_forecast.py",
    "test/test_hbv_interaction_value_comparison.py",
    "test/test_hbv_forecast_frozen_transition.py",
)


def _source_snapshot(root: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=False)
    seen: set[str] = set()
    for configured in _SOURCE_FILES:
        source = (root / configured).resolve()
        if not source.is_file():
            raise FileNotFoundError(f"source snapshot file is missing: {configured}")
        if source.name in seen:
            raise ValueError(f"duplicate snapshot basename: {source.name}")
        seen.add(source.name)
        shutil.copy2(source, destination / source.name)


def _result_summary(driver: dict, statistics: dict) -> dict:
    def paired(entry: dict) -> dict:
        return {
            "mean": [float(value) for value in entry["mean"]],
            "ci_low": [float(value) for value in entry["ci_low"]],
            "ci_high": [float(value) for value in entry["ci_high"]],
        }

    full_minus_none = statistics["paired_full_minus_none"]
    classifications = [
        _classify_paired_interval(float(lower), float(upper))
        for lower, upper in zip(
            full_minus_none["ci_low"], full_minus_none["ci_high"]
        )
    ]
    result = {
        "leads": [int(value) for value in driver["leads"]],
        "rmse": {
            method: [float(value) for value in statistics["rmse"][method]]
            for method in driver["arms"]
        },
        "oracle_ratio": {
            method: [
                float(value) for value in statistics["oracle_ratio"][method]
            ]
            for method in driver["arms"]
        },
        "paired_full_minus_none": paired(full_minus_none),
        "paired_none_minus_static": paired(
            statistics["paired_none_minus_static"]
        ),
        "full_minus_none_classification": classifications,
        "identification": {
            "full_stage_median_true_probability": [
                float(value)
                for value in statistics["identification"][
                    "full_stage_median_true_probability"
                ]
            ],
            "none_stage_median_true_probability": [
                float(value)
                for value in statistics["identification"][
                    "none_stage_median_true_probability"
                ]
            ],
        },
    }
    if "paired_highest_posterior_minus_none" in statistics:
        highest_minus_none = statistics[
            "paired_highest_posterior_minus_none"
        ]
        result["paired_highest_posterior_minus_none"] = paired(
            highest_minus_none
        )
        result["highest_posterior_minus_none_classification"] = [
            _classify_highest_posterior_interval(float(lower), float(upper))
            for lower, upper in zip(
                highest_minus_none["ci_low"], highest_minus_none["ci_high"]
            )
        ]
    return result


def run(repo_root: Path, config_path: Path, output_dir: Path) -> dict:
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
    if output.name != str(config["experiment_id"]):
        raise ValueError("output directory name must equal experiment_id")
    highest_posterior_enabled = _highest_posterior_enabled(config)

    blocks = _validated_blocks(config)
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    protected_paths = tuple(
        (root / str(value)).resolve()
        for value in config.get("protected_paths", ())
    )
    _validate_output_is_disjoint_from_protected_paths(output, protected_paths)
    _validate_output_is_disjoint_from_protected_paths(incomplete, protected_paths)
    adaptation = int(
        config["decision_rules"]["adaptation_days_excluded_per_stage"]
    )
    preregistration = {
        "frozen_before_execution": True,
        "experiment_id": config["experiment_id"],
        "scenario": config["scenario"],
        "forecast_contract": config["forecast_contract"],
        "hypotheses": config["hypotheses"],
        "decision_rules": config["decision_rules"],
        "bootstrap": config["bootstrap"],
        "config_sha256": config_hash,
        "started_at_utc": started_at,
        "output_directory": str(output),
    }
    if highest_posterior_enabled:
        preregistration["comparison_methods"] = list(
            config["comparison_methods"]
        )
    _atomic_json_write(preregistration_path, preregistration)

    parameter_vectors, parameter_csv, parameter_hash = _load_parameter_vectors(
        root, config
    )
    process_covariances, process_scales, process_csv, process_hash = (
        _load_process_covariances(root, config)
    )
    observation_std, observation_csv, observation_hash = _load_observation_noise(
        root, config
    )
    resource = _resource_preflight(config, root)
    protected_before = _protected_hashes(
        root, config.get("protected_paths", ())
    )
    forcing = _forcing_blocks(config, blocks)
    stay = float(config["factor_transition_stay_probability"])
    selected_process = str(config["process_noise_source"]["selected_process_id"])
    definitions = build_method_definitions(
        parameter_vectors, process_scales, process_covariances, selected_process
    )
    result = run_three_stage_switching_validation(
        forcing_blocks=forcing,
        block_ids=tuple(str(value["block_id"]) for value in blocks),
        parameter_vectors=parameter_vectors,
        process_scales=process_scales,
        process_covariances=process_covariances,
        selected_process_id=selected_process,
        scenario=str(config["scenario"]),
        process_noise_seeds=tuple(
            int(value["process_noise_seed"]) for value in blocks
        ),
        observation_noise_seeds=tuple(
            int(value["observation_noise_seed"]) for value in blocks
        ),
        warmup_days=int(config["forcing"]["warmup_days"]),
        stage_lengths=tuple(int(value) for value in config["stage_lengths"]),
        lead_days=tuple(int(value) for value in config["lead_days"]),
        initial_covariance_fraction=float(config["initial_covariance_fraction"]),
        observation_standard_deviation=observation_std,
        factor_transition_stay_probability=stay,
    )

    replay_check = _cross_check_replay(root, config, result)
    if not replay_check["passed"]:
        raise RuntimeError(
            "truth or assimilation replay mismatch: "
            + ", ".join(replay_check["mismatches"])
        )

    comparison_options = (
        {"include_highest_posterior": True}
        if highest_posterior_enabled
        else {}
    )
    driver = compare_interaction_arms(
        result, definitions, observation_std, stay, **comparison_options
    )
    statistics = summarize_interaction_value(
        driver,
        bootstrap_replicates=int(config["bootstrap"]["replicates"]),
        bootstrap_seed=int(config["bootstrap"]["seed"]),
        adaptation_days=adaptation,
    )
    arrays = _evidence_arrays(driver)
    result_summary = _result_summary(driver, statistics)

    incomplete.mkdir(parents=True, exist_ok=False)
    (incomplete / "config_snapshot.json").write_bytes(config_bytes)
    (incomplete / "preregistration.json").write_bytes(
        preregistration_path.read_bytes()
    )
    _json_write(incomplete / "resource_preflight.json", resource)
    _json_write(incomplete / "replay_check.json", replay_check)
    _json_write(incomplete / "environment.json", _environment(root, started_at))
    (incomplete / "parameter_vectors.csv").write_bytes(parameter_csv)
    (incomplete / "process_noise_covariances.csv").write_bytes(process_csv)
    (incomplete / "observation_noise.csv").write_bytes(observation_csv)
    np.savez_compressed(incomplete / "evidence.npz", **arrays)
    _source_snapshot(root, incomplete / "source_snapshot")

    protected_after = _protected_hashes(
        root, config.get("protected_paths", ())
    )
    protected_unchanged = protected_before == protected_after
    integrity_passed = bool(replay_check["passed"] and protected_unchanged)
    summary = {
        "experiment_id": config["experiment_id"],
        "scenario": config["scenario"],
        "integrity_status": "passed" if integrity_passed else "failed",
        "replay_check_passed": bool(replay_check["passed"]),
        "protected_artifacts_unchanged": protected_unchanged,
        "forecast_contract": config["forecast_contract"],
        "parameter_snapshot_sha256": parameter_hash,
        "process_snapshot_sha256": process_hash,
        "observation_snapshot_sha256": observation_hash,
        "config_sha256": config_hash,
        "scope_limit": config["scope_limit"],
        "result": result_summary,
    }
    if highest_posterior_enabled:
        summary["comparison_methods"] = list(config["comparison_methods"])
    _json_write(incomplete / "summary.json", summary)
    _json_write(
        incomplete / "protected_artifact_integrity.json",
        {
            "configured_paths": config.get("protected_paths", ()),
            "before": protected_before,
            "after_evidence_writes": protected_after,
            "status": "unchanged" if protected_unchanged else "changed",
        },
    )
    checksums = {
        path.relative_to(incomplete).as_posix(): _sha256(path)
        for path in sorted(incomplete.rglob("*"))
        if path.is_file() and path.name != "checksums.json"
    }
    _json_write(incomplete / "checksums.json", checksums)
    if not integrity_passed:
        raise RuntimeError("protected-artifact or replay integrity gate failed")
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
