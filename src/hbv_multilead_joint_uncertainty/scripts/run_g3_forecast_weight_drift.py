"""Run and freeze the G3 follow-up on forecast-phase weight drift.

Reproduces the frozen G3 ideal-gate truths bit-for-bit (same config sources and
seeds -> deterministic), verifies the reproduced full-interaction forecast equals
the sealed gate evidence (cross-check; neither the gate nor the phase-2 verdict is
touched -- only the identical truths are reused), then compares the drifting and
frozen forecast-combination weights for the no-interaction and full-interaction
methods and seals RMSE / paired block-bootstrap verdicts / weight-decay medians.

Design freeze: docs/plans/2026-07-24-g3-forecast-weight-drift-design.md
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import sys
from pathlib import Path

import numpy as np

REPO_ROOT = Path(__file__).resolve().parents[3]
if str(REPO_ROOT / "src") not in sys.path:
    sys.path.insert(0, str(REPO_ROOT / "src"))

from hbv_multilead_joint_uncertainty.forecast_weight_drift import (  # noqa: E402
    compare_forecast_weight_drift,
    summarize_forecast_weight_drift,
)
from hbv_multilead_joint_uncertainty.methods import build_method_definitions  # noqa: E402
from hbv_multilead_joint_uncertainty.scripts.run_g3_phase2_interaction_value import (  # noqa: E402
    _cross_check_against_gate,
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
    _sha256,
    _validate_output_is_disjoint_from_protected_paths,
    _validated_blocks,
)
from hbv_multilead_joint_uncertainty.three_stage_switching_validation import (  # noqa: E402
    run_three_stage_switching_validation,
)

_SOURCE_FILES = (
    "src/hbv_multilead_joint_uncertainty/forecast_weight_drift.py",
    "src/hbv_multilead_joint_uncertainty/scripts/run_g3_forecast_weight_drift.py",
    "src/hbv_multilead_joint_uncertainty/interaction_value_comparison.py",
    "src/hbv_multilead_joint_uncertainty/three_stage_switching_validation.py",
    "src/hbv_multilead_joint_uncertainty/methods.py",
    "src/hbv_multilead_joint_uncertainty/forecast.py",
    "src/hbv_joint_uncertainty/imm.py",
    "src/hbv_joint_uncertainty/sigma_filter.py",
    "test/test_hbv_forecast_weight_drift.py",
)


def _source_snapshot(root: Path, destination: Path) -> None:
    destination.mkdir(parents=True, exist_ok=False)
    import shutil

    seen: set[str] = set()
    for configured in _SOURCE_FILES:
        source = (root / configured).resolve()
        if not source.is_file():
            raise FileNotFoundError(f"source snapshot file is missing: {configured}")
        if source.name in seen:
            raise ValueError(f"duplicate snapshot basename: {source.name}")
        seen.add(source.name)
        shutil.copy2(source, destination / source.name)


def _evidence_arrays(driver: dict) -> dict:
    arrays = {
        "methods": np.asarray(driver["methods"]),
        "variants": np.asarray(driver["variants"]),
        "leads": np.asarray(driver["leads"], dtype=np.int64),
        "block_ids": np.asarray(driver["block_ids"]),
        "assimilation_days": np.asarray(driver["assimilation_days"], dtype=np.int64),
        "stage_boundaries": np.asarray(driver["stage_boundaries"], dtype=np.int64),
        "truth_forecasts": driver["truth_forecasts"],
        "true_candidate_labels": np.asarray(driver["true_candidate_labels"], dtype=np.int64),
        "oracle_forecast": driver["oracle_forecasts"],
        "oracle_squared_error": driver["oracle_squared_errors"],
    }
    for method in driver["methods"]:
        for variant in driver["variants"]:
            arrays[f"forecast_{method}_{variant}"] = driver["forecasts"][(method, variant)]
            arrays[f"squared_error_{method}_{variant}"] = driver["squared_errors"][
                (method, variant)
            ]
        arrays[f"forecast_weights_{method}"] = driver["forecast_weights"][method]
        arrays[f"final_posterior_weights_{method}"] = driver["final_posterior_weights"][method]
    return arrays


def _summary_json(driver: dict, statistics: dict) -> dict:
    methods = list(driver["methods"])
    variants = list(driver["variants"])

    def floats(values):
        return [float(value) for value in np.atleast_1d(values)]

    return {
        "leads": [int(value) for value in driver["leads"]],
        "rmse": {
            f"{method}_{variant}": floats(statistics["rmse"][(method, variant)])
            for method in methods
            for variant in variants
        },
        "oracle_rmse": floats(statistics["oracle_rmse"]),
        "paired_frozen_minus_drifting": {
            method: {
                "mean": floats(statistics["paired_frozen_minus_drifting"][method]["mean"]),
                "ci_low": floats(statistics["paired_frozen_minus_drifting"][method]["ci_low"]),
                "ci_high": floats(statistics["paired_frozen_minus_drifting"][method]["ci_high"]),
            }
            for method in methods
        },
        "verdict": {method: list(statistics["verdict"][method]) for method in methods},
        "frozen_minus_oracle_rmse": {
            method: floats(statistics["frozen_minus_oracle_rmse"][method]) for method in methods
        },
        "drifting_minus_oracle_rmse": {
            method: floats(statistics["drifting_minus_oracle_rmse"][method])
            for method in methods
        },
        "true_candidate_weight_medians": {
            method: {
                "final_assimilation_day": float(
                    statistics["true_candidate_weight_medians"][method]["final_assimilation_day"]
                ),
                "per_lead": floats(
                    statistics["true_candidate_weight_medians"][method]["per_lead"]
                ),
            }
            for method in methods
        },
        "full_drifting_matches_frozen_runner": bool(
            driver["full_drifting_matches_frozen_runner"]
        ),
    }


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
    blocks = _validated_blocks(config)
    started_at = dt.datetime.now(dt.timezone.utc).isoformat()
    protected_paths = tuple(
        (root / str(value)).resolve() for value in config.get("protected_paths", ())
    )
    _validate_output_is_disjoint_from_protected_paths(output, protected_paths)
    _validate_output_is_disjoint_from_protected_paths(incomplete, protected_paths)
    adaptation = int(config["decision_rules"]["adaptation_days_excluded_per_stage"])
    preregistration = {
        "frozen_before_execution": True,
        "experiment_id": config["experiment_id"],
        "scenario": config["scenario"],
        "hypotheses": config["hypotheses"],
        "bootstrap": config["bootstrap"],
        "adaptation_days_excluded_per_stage": adaptation,
        "config_sha256": config_hash,
        "started_at_utc": started_at,
        "output_directory": str(output),
    }
    _atomic_json_write(preregistration_path, preregistration)

    parameter_vectors, parameter_csv, parameter_hash = _load_parameter_vectors(root, config)
    process_covariances, process_scales, process_csv, process_hash = _load_process_covariances(
        root, config
    )
    observation_std, observation_csv, observation_hash = _load_observation_noise(root, config)
    resource = _resource_preflight(config, root)
    protected_before = _protected_hashes(root, config.get("protected_paths", ()))
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
        process_noise_seeds=tuple(int(value["process_noise_seed"]) for value in blocks),
        observation_noise_seeds=tuple(int(value["observation_noise_seed"]) for value in blocks),
        warmup_days=int(config["forcing"]["warmup_days"]),
        stage_lengths=tuple(int(value) for value in config["stage_lengths"]),
        lead_days=tuple(int(value) for value in config["lead_days"]),
        initial_covariance_fraction=float(config["initial_covariance_fraction"]),
        observation_standard_deviation=observation_std,
        factor_transition_stay_probability=stay,
    )

    cross_check = _cross_check_against_gate(root, config, result)
    driver = compare_forecast_weight_drift(result, definitions, observation_std, stay)
    statistics = summarize_forecast_weight_drift(
        driver,
        bootstrap_replicates=int(config["bootstrap"]["replicates"]),
        bootstrap_seed=int(config["bootstrap"]["seed"]),
    )
    arrays = _evidence_arrays(driver)
    summary_body = _summary_json(driver, statistics)

    incomplete.mkdir(parents=True, exist_ok=False)
    (incomplete / "config_snapshot.json").write_bytes(config_bytes)
    (incomplete / "preregistration.json").write_bytes(preregistration_path.read_bytes())
    _json_write(incomplete / "resource_preflight.json", resource)
    _json_write(incomplete / "cross_check.json", cross_check)
    _json_write(incomplete / "environment.json", _environment(root, started_at))
    (incomplete / "parameter_vectors.csv").write_bytes(parameter_csv)
    (incomplete / "process_noise_covariances.csv").write_bytes(process_csv)
    (incomplete / "observation_noise.csv").write_bytes(observation_csv)
    np.savez_compressed(incomplete / "evidence.npz", **arrays)
    _source_snapshot(root, incomplete / "source_snapshot")

    protected_after = _protected_hashes(root, config.get("protected_paths", ()))
    protected_unchanged = protected_before == protected_after
    cross_check_ok = (not cross_check["performed"]) or bool(cross_check["passed"])
    runner_match = bool(driver["full_drifting_matches_frozen_runner"])
    integrity_passed = bool(protected_unchanged and cross_check_ok and runner_match)

    summary = {
        "experiment_id": config["experiment_id"],
        "scenario": config["scenario"],
        "integrity_status": "passed" if integrity_passed else "failed",
        "cross_check_performed": cross_check["performed"],
        "cross_check_passed": bool(cross_check.get("passed", False)) if cross_check["performed"] else None,
        "full_drifting_matches_frozen_runner": runner_match,
        "protected_artifacts_unchanged": protected_unchanged,
        "parameter_snapshot_sha256": parameter_hash,
        "process_snapshot_sha256": process_hash,
        "observation_snapshot_sha256": observation_hash,
        "config_sha256": config_hash,
        "scope_limit": config["scope_limit"],
        "result": summary_body,
    }
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
        raise RuntimeError("protected-artifact, cross-check or runner-match integrity gate failed")
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
