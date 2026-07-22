"""Package the matched assimilation-duration identification boundary."""

from __future__ import annotations

import argparse
import datetime as dt
import json
import shutil
from pathlib import Path

import numpy as np
import pandas as pd
import psutil

from hbv_multilead_joint_uncertainty.scripts.run_joint_method_validation import (
    _verify_complete_output,
)
from hbv_multilead_joint_uncertainty.scripts.run_synthetic_truth_validation import (
    _json_write,
    _protected_hashes,
    _sha256,
)


REQUIRED_FILES = frozenset(
    {
        "config_snapshot.json",
        "decision.json",
        "duration_identification.csv",
        "duration_method_metrics.csv",
        "input_evidence_integrity.json",
        "prefix_integrity.json",
        "preregistration.json",
        "protected_artifact_integrity.json",
        "resource_preflight.json",
        "source_snapshot/run_assimilation_duration_boundary.py",
        "source_snapshot/test_hbv_assimilation_duration_boundary.py",
        "summary.json",
    }
)


def _mapping_digest(values: dict[str, str]) -> str:
    import hashlib

    payload = json.dumps(values, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def _verify_existing(output: Path, expected_config: dict) -> dict:
    checksums = json.loads((output / "checksums.json").read_text(encoding="utf-8"))
    if set(checksums) != REQUIRED_FILES:
        raise ValueError("assimilation-boundary evidence manifest mismatch")
    actual = {
        path.relative_to(output).as_posix()
        for path in output.rglob("*")
        if path.is_file()
    }
    if actual != REQUIRED_FILES | {"checksums.json"}:
        raise ValueError("assimilation-boundary evidence file set mismatch")
    for relative, expected in checksums.items():
        if _sha256(output / relative) != expected:
            raise ValueError(f"assimilation-boundary checksum mismatch: {relative}")
    if json.loads((output / "config_snapshot.json").read_text(encoding="utf-8")) != expected_config:
        raise ValueError("assimilation-boundary config snapshot mismatch")
    return json.loads((output / "summary.json").read_text(encoding="utf-8"))


def _recalculate_identification(probabilities: np.ndarray) -> dict[str, float]:
    values = np.asarray(probabilities, dtype=np.float64)
    if values.shape[1:] != (9, 9):
        raise ValueError("joint origin probabilities must have shape (blocks, 9, 9)")
    candidate_truth = np.arange(9)[None, :]
    parameter_truth = np.repeat(np.arange(3), 3)[None, :]
    process_truth = np.tile(np.arange(3), 3)[None, :]
    grid = values.reshape(values.shape[0], 9, 3, 3)
    parameter_marginals = grid.sum(axis=3)
    process_marginals = grid.sum(axis=2)
    trial_indices = np.arange(9)
    true_candidates = values[:, trial_indices, trial_indices]
    true_parameters = np.empty((values.shape[0], 9), dtype=np.float64)
    true_processes = np.empty_like(true_parameters)
    for truth in range(9):
        true_parameters[:, truth] = parameter_marginals[
            :, truth, parameter_truth[0, truth]
        ]
        true_processes[:, truth] = process_marginals[
            :, truth, process_truth[0, truth]
        ]
    return {
        "joint_candidate_argmax_accuracy": float(
            np.mean(np.argmax(values, axis=2) == candidate_truth)
        ),
        "joint_parameter_argmax_accuracy": float(
            np.mean(np.argmax(parameter_marginals, axis=2) == parameter_truth)
        ),
        "joint_process_argmax_accuracy": float(
            np.mean(np.argmax(process_marginals, axis=2) == process_truth)
        ),
        "median_joint_true_candidate_probability": float(np.median(true_candidates)),
        "median_joint_true_parameter_probability": float(np.median(true_parameters)),
        "median_joint_true_process_probability": float(np.median(true_processes)),
    }


def _identification_passes(values: dict[str, float], rules: dict) -> bool:
    return bool(
        values["joint_candidate_argmax_accuracy"]
        >= float(rules["joint_candidate_argmax_accuracy_minimum"])
        and values["joint_parameter_argmax_accuracy"]
        >= float(rules["joint_parameter_argmax_accuracy_minimum"])
        and values["joint_process_argmax_accuracy"]
        >= float(rules["joint_process_argmax_accuracy_minimum"])
        and values["median_joint_true_candidate_probability"]
        >= float(rules["median_joint_true_candidate_probability_minimum"])
    )


def run(repo_root: Path, config_path: Path, output_dir: Path) -> dict:
    root = repo_root.resolve()
    config_file = config_path.resolve()
    output = output_dir.resolve()
    incomplete = output.with_name(output.name + ".incomplete")
    config = json.loads(config_file.read_text(encoding="utf-8"))
    if output.name != str(config["experiment_id"]):
        raise ValueError("output directory name must equal experiment_id")
    if output.exists():
        if incomplete.exists():
            raise FileExistsError("refusing completed evidence with an incomplete sibling")
        return _verify_existing(output, config)
    if incomplete.exists():
        raise FileExistsError("refusing to overwrite incomplete boundary evidence")

    conditions = sorted(config["conditions"], key=lambda value: int(value["assimilation_days"]))
    durations = [int(value["assimilation_days"]) for value in conditions]
    if durations != sorted(set(durations)) or len(durations) < 2:
        raise ValueError("conditions must contain at least two unique increasing durations")
    if durations != [int(value) for value in config["fixed_boundaries"]["assimilation_days_tested"]]:
        raise ValueError("condition durations differ from the frozen boundary")

    protected_before = _protected_hashes(root, config["protected_paths"])
    input_records = []
    loaded = []
    total_numeric_bytes = 0
    for condition in conditions:
        condition_config_path = (root / condition["config_path"]).resolve()
        evidence_path = (root / condition["evidence_path"]).resolve()
        condition_config = json.loads(condition_config_path.read_text(encoding="utf-8"))
        summary, _ = _verify_complete_output(evidence_path, condition_config)
        if summary["status"] != "passed":
            raise ValueError(f"input condition did not pass integrity: {condition['experiment_id']}")
        if int(summary["assimilation_days"]) != int(condition["assimilation_days"]):
            raise ValueError("input assimilation duration mismatch")
        manifest = json.loads((evidence_path / "checksums.json").read_text(encoding="utf-8"))
        resource = json.loads((evidence_path / "resource_preflight.json").read_text(encoding="utf-8"))
        total_numeric_bytes += int(resource["expected_saved_numeric_array_bytes"])
        input_records.append(
            {
                "experiment_id": condition["experiment_id"],
                "assimilation_days": int(condition["assimilation_days"]),
                "config_path": str(condition_config_path),
                "config_sha256": _sha256(condition_config_path),
                "evidence_path": str(evidence_path),
                "manifest_file_count": len(manifest),
                "manifest_sha256": _sha256(evidence_path / "checksums.json"),
                "all_manifest_files_verified": True,
            }
        )
        loaded.append((condition_config, evidence_path))

    reserve = int(config["resource_rule"]["task_specific_reserve_bytes"])
    estimated_additional_peak = 3 * total_numeric_bytes
    required = estimated_additional_peak + reserve
    available = int(psutil.virtual_memory().available)
    resource_preflight = {
        "input_saved_numeric_array_bytes": total_numeric_bytes,
        "estimated_additional_peak_memory_bytes": estimated_additional_peak,
        "task_specific_reserve_bytes": reserve,
        "task_specific_required_available_bytes": required,
        "available_physical_memory_bytes": available,
        "headroom_after_requirement_bytes": available - required,
        "available_to_required_ratio": float(available / required),
        "execution_parallelism": int(config["resource_rule"]["execution_parallelism"]),
        "universal_memory_threshold_used": False,
        "safe_to_run": bool(available >= required),
    }
    if not resource_preflight["safe_to_run"]:
        raise MemoryError("insufficient task-specific memory headroom for boundary aggregation")

    baseline_config, baseline_path = loaded[-1]
    matched_names = tuple(str(value) for value in config["matched_prefix_arrays"])
    prefix_records = []
    with np.load(baseline_path / "evidence.npz") as baseline_saved:
        baseline = {name: baseline_saved[name].copy() for name in matched_names}
    identification_rows = []
    metrics_frames = []
    for index, ((condition_config, evidence_path), duration) in enumerate(zip(loaded, durations)):
        with np.load(evidence_path / "evidence.npz") as saved:
            identification = _recalculate_identification(
                saved["joint_origin_probabilities"]
            )
            if index < len(loaded) - 1:
                for name in matched_names:
                    short = saved[name]
                    long = baseline[name]
                    if name == "forcing_blocks":
                        expected = long[:, : short.shape[1]]
                    elif name in {"process_standard_normals", "observation_standard_normals"}:
                        expected = long[:, : short.shape[1]]
                    else:
                        expected = long[:, :, : short.shape[2]]
                    prefix_records.append(
                        {
                            "assimilation_days": duration,
                            "array": name,
                            "exact": bool(np.array_equal(short, expected)),
                        }
                    )
        reported = json.loads(
            (evidence_path / "condition_decisions.json").read_text(encoding="utf-8")
        )
        for key, value in identification.items():
            if not np.isclose(value, reported["identification"][key], rtol=0.0, atol=1e-15):
                raise ValueError(f"reported identification mismatch for {duration} days: {key}")
        effective = _identification_passes(identification, condition_config["decision_rules"])
        if effective is not bool(reported["joint_identification_effective"]):
            raise ValueError(f"reported identification decision mismatch for {duration} days")
        identification_rows.append(
            {
                "assimilation_days": duration,
                **identification,
                "identification_effective": effective,
            }
        )
        metrics = pd.read_csv(evidence_path / "method_metrics.csv")
        metrics.insert(0, "assimilation_days", duration)
        metrics_frames.append(metrics)

    all_prefixes_exact = bool(all(record["exact"] for record in prefix_records))
    if not all_prefixes_exact:
        raise ValueError("assimilation conditions do not share exact evidence prefixes")
    effective_values = [bool(value["identification_effective"]) for value in identification_rows]
    boundary_candidates = [
        durations[index]
        for index, effective in enumerate(effective_values)
        if effective and all(effective_values[index:])
    ]
    sufficient = bool(boundary_candidates)
    decision = {
        "identification_sufficient_within_tested_range": sufficient,
        "shortest_consistently_sufficient_assimilation_days": (
            int(boundary_candidates[0]) if sufficient else None
        ),
        "longest_tested_assimilation_days": int(durations[-1]),
        "not_sufficient_through_assimilation_days": (
            None if sufficient else int(durations[-1])
        ),
        "untested_longer_durations_remain_unknown": not sufficient,
        "condition_passes": [
            {"assimilation_days": duration, "identification_effective": effective}
            for duration, effective in zip(durations, effective_values)
        ],
        "decision_rule": config["decision_rule"],
        "interpretation": (
            "The preregistered joint-identification rule was not reached through forty-five "
            "matched assimilation days; this is a bounded failure result, not evidence that "
            "longer untested durations cannot succeed."
            if not sufficient
            else "The shortest tested duration that passed and remained passed at every longer tested duration defines the tested boundary."
        ),
    }
    protected_after = _protected_hashes(root, config["protected_paths"])
    protected_unchanged = protected_before == protected_after
    status = "passed" if protected_unchanged and all_prefixes_exact else "failed"
    prefix_integrity = {
        "baseline_assimilation_days": int(durations[-1]),
        "comparisons_checked": len(prefix_records),
        "all_exact": all_prefixes_exact,
        "comparisons": prefix_records,
    }
    protected_integrity = {
        "configured_paths": config["protected_paths"],
        "file_count": len(protected_before),
        "before_sha256": _mapping_digest(protected_before),
        "after_sha256": _mapping_digest(protected_after),
        "status": "unchanged" if protected_unchanged else "changed",
    }
    started_finished = dt.datetime.now(dt.timezone.utc).isoformat()
    preregistration = {
        "experiment_id": config["experiment_id"],
        "purpose": config["purpose"],
        "conditions": config["conditions"],
        "decision_rule": config["decision_rule"],
        "fixed_boundaries": config["fixed_boundaries"],
        "scope_limit": config["scope_limit"],
        "packaged_at": started_finished,
    }
    summary = {
        "experiment_id": config["experiment_id"],
        "status": status,
        "assimilation_days_tested": durations,
        "all_input_evidence_verified": True,
        "all_matched_prefixes_exact": all_prefixes_exact,
        "input_condition_count": len(conditions),
        "identification_sufficient_within_tested_range": sufficient,
        "longest_tested_assimilation_days": int(durations[-1]),
        "protected_artifacts_unchanged": protected_unchanged,
        "scope_limit": config["scope_limit"],
    }

    incomplete.mkdir(parents=True)
    try:
        _json_write(incomplete / "config_snapshot.json", config)
        _json_write(incomplete / "preregistration.json", preregistration)
        _json_write(incomplete / "input_evidence_integrity.json", {"conditions": input_records})
        _json_write(incomplete / "resource_preflight.json", resource_preflight)
        _json_write(incomplete / "prefix_integrity.json", prefix_integrity)
        _json_write(incomplete / "decision.json", decision)
        _json_write(incomplete / "protected_artifact_integrity.json", protected_integrity)
        _json_write(incomplete / "summary.json", summary)
        pd.DataFrame(identification_rows).to_csv(
            incomplete / "duration_identification.csv", index=False
        )
        pd.concat(metrics_frames, ignore_index=True).to_csv(
            incomplete / "duration_method_metrics.csv", index=False
        )
        snapshot = incomplete / "source_snapshot"
        snapshot.mkdir()
        shutil.copy2(Path(__file__).resolve(), snapshot / "run_assimilation_duration_boundary.py")
        shutil.copy2(
            root / "test" / "test_hbv_assimilation_duration_boundary.py",
            snapshot / "test_hbv_assimilation_duration_boundary.py",
        )
        evidence_paths = sorted(path for path in incomplete.rglob("*") if path.is_file())
        checksums = {
            path.relative_to(incomplete).as_posix(): _sha256(path)
            for path in evidence_paths
        }
        if set(checksums) != REQUIRED_FILES:
            raise ValueError("assimilation-boundary package file set mismatch")
        _json_write(incomplete / "checksums.json", checksums)
        incomplete.replace(output)
    except Exception:
        if incomplete.exists():
            shutil.rmtree(incomplete)
        raise
    if status != "passed":
        raise RuntimeError("assimilation-duration boundary failed integrity")
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", required=True, type=Path)
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    run(args.repo_root, args.config, args.output_dir)


if __name__ == "__main__":
    main()
