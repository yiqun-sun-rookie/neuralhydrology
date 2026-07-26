"""Run and freeze the G3 phase-2 four-arm interaction-value comparison.

Reproduces the frozen G3 ideal-gate truths bit-for-bit (same config sources and
seeds -> deterministic), verifies the reproduced full arm equals the sealed gate
evidence (cross-check; the gate verdict is never touched -- only the identical
truths are reused), then runs full/none/static/oracle on the primary family and
seals RMSE / paired block-bootstrap / identification / H1-H3 verdicts.

Design freeze: docs/plans/2026-07-23-g3-phase2-interaction-value-comparison-design.md
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

from hbv_multilead_joint_uncertainty.interaction_value_comparison import (  # noqa: E402
    compare_interaction_arms,
    summarize_interaction_value,
)
from hbv_multilead_joint_uncertainty.methods import build_method_definitions  # noqa: E402
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
    "src/hbv_multilead_joint_uncertainty/interaction_value_comparison.py",
    "src/hbv_multilead_joint_uncertainty/scripts/run_g3_phase2_interaction_value.py",
    "src/hbv_multilead_joint_uncertainty/three_stage_switching_validation.py",
    "src/hbv_multilead_joint_uncertainty/methods.py",
    "src/hbv_multilead_joint_uncertainty/forecast.py",
    "src/hbv_joint_uncertainty/imm.py",
    "src/hbv_joint_uncertainty/sigma_filter.py",
    "test/test_hbv_interaction_value_comparison.py",
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


def _cross_check_against_gate(root: Path, config: dict, result) -> dict:
    reference = config.get("gate_evidence_for_cross_check")
    if not reference:
        return {"performed": False}
    path = (root / str(reference["path"])).resolve()
    if not path.is_file() or _sha256(path) != str(reference["sha256"]):
        raise ValueError("gate evidence checksum mismatch")
    gate = np.load(path, allow_pickle=False)
    primary = result.schedule.primary_method_name
    primary_index = list(result.method_names).index(primary)
    gate_method_names = [str(value) for value in gate["method_names"]]
    gate_primary_index = gate_method_names.index(primary)
    prediction_match = np.array_equal(
        result.method_predictions[:, :, primary_index],
        gate["method_predictions"][:, :, gate_primary_index],
    )
    truth_match = np.array_equal(
        np.asarray(result.truth_forecast_discharge), gate["truth_forecast_discharge"]
    )
    observation_match = np.array_equal(
        np.asarray(result.observed_discharge), gate["observed_discharge"]
    )
    passed = bool(prediction_match and truth_match and observation_match)
    return {
        "performed": True,
        "gate_evidence_path": str(reference["path"]),
        "gate_evidence_sha256": str(reference["sha256"]),
        "primary_method_forecast_bit_identical": bool(prediction_match),
        "truth_forecast_bit_identical": bool(truth_match),
        "observed_discharge_bit_identical": bool(observation_match),
        "passed": passed,
    }


def _evidence_arrays(driver: dict) -> dict:
    arrays = {
        "arms": np.asarray(driver["arms"]),
        "leads": np.asarray(driver["leads"], dtype=np.int64),
        "block_ids": np.asarray(driver["block_ids"]),
        "assimilation_days": np.asarray(driver["assimilation_days"], dtype=np.int64),
        "stage_boundaries": np.asarray(driver["stage_boundaries"], dtype=np.int64),
        "truth_forecasts": driver["truth_forecasts"],
        "true_candidate_labels": np.asarray(
            driver["true_candidate_labels"], dtype=np.int64
        ),
    }
    for arm in driver["arms"]:
        arrays[f"forecast_{arm}"] = driver["forecasts"][arm]
        arrays[f"squared_error_{arm}"] = driver["squared_errors"][arm]
    for arm in ("full", "none"):
        arrays[f"probabilities_{arm}"] = driver["probabilities"][arm]
    has_candidate_forecasts = "none_candidate_forecasts" in driver
    has_selected_indices = "highest_posterior_candidate_indices" in driver
    if has_candidate_forecasts != has_selected_indices:
        raise ValueError(
            "highest-posterior evidence requires candidates and selected indices"
        )
    if has_candidate_forecasts:
        arrays["forecast_none_candidates"] = np.asarray(
            driver["none_candidate_forecasts"], dtype=np.float64
        )
        arrays["highest_posterior_candidate_indices"] = np.asarray(
            driver["highest_posterior_candidate_indices"], dtype=np.int64
        )
    return arrays


def _summary_json(driver: dict, statistics: dict) -> dict:
    leads = [int(value) for value in driver["leads"]]

    def paired(entry):
        return {
            "mean": [float(v) for v in entry["mean"]],
            "ci_low": [float(v) for v in entry["ci_low"]],
            "ci_high": [float(v) for v in entry["ci_high"]],
        }

    return {
        "leads": leads,
        "rmse": {arm: [float(v) for v in statistics["rmse"][arm]] for arm in driver["arms"]},
        "oracle_ratio": {
            arm: [float(v) for v in statistics["oracle_ratio"][arm]]
            for arm in driver["arms"]
        },
        "paired_full_minus_none": paired(statistics["paired_full_minus_none"]),
        "paired_none_minus_static": paired(statistics["paired_none_minus_static"]),
        "identification": {
            "full_stage_median_true_probability": [
                float(v) for v in statistics["identification"]["full_stage_median_true_probability"]
            ],
            "none_stage_median_true_probability": [
                float(v) for v in statistics["identification"]["none_stage_median_true_probability"]
            ],
            "h1_full_ge_none_all_stages": bool(
                statistics["identification"]["h1_full_ge_none_all_stages"]
            ),
        },
        "h2_full_le_none_le_static": bool(statistics["h2_full_le_none_le_static"]),
        "h3_full_closer_to_oracle_than_static": bool(
            statistics["h3_full_closer_to_oracle_than_static"]
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
    driver = compare_interaction_arms(result, definitions, observation_std, stay)
    statistics = summarize_interaction_value(
        driver,
        bootstrap_replicates=int(config["bootstrap"]["replicates"]),
        bootstrap_seed=int(config["bootstrap"]["seed"]),
        adaptation_days=adaptation,
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
    integrity_passed = bool(protected_unchanged and cross_check_ok)

    summary = {
        "experiment_id": config["experiment_id"],
        "scenario": config["scenario"],
        "integrity_status": "passed" if integrity_passed else "failed",
        "cross_check_performed": cross_check["performed"],
        "cross_check_passed": bool(cross_check.get("passed", False)) if cross_check["performed"] else None,
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
