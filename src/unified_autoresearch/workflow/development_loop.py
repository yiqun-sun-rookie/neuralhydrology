"""Run all four reference candidates through both frozen development protocols."""

from __future__ import annotations

import hashlib
import json
import math
import os
from pathlib import Path
from typing import Any

from unified_autoresearch.candidates.catalog import REFERENCE_CATEGORIES, materialize_reference_candidate
from unified_autoresearch.evaluation.scoring import (
    score_development_predictions,
    summarize_candidate_development_scores,
)
from unified_autoresearch.runtime.descriptor import (
    CandidateDescriptor,
    load_and_validate_candidate_descriptor,
)
from unified_autoresearch.runtime.layout import create_run_layout
from unified_autoresearch.runtime.orchestrator import RegisteredRuntimeResult, run_registered_candidate
from unified_autoresearch.runtime.resources import ResourceSnapshot


def _io_path(path: str | Path) -> str:
    raw = str(path)
    if os.name == "nt" and raw.startswith("\\\\?\\"):
        return raw
    absolute = str(Path(path).resolve())
    if os.name != "nt":
        return absolute
    if absolute.startswith("\\\\"):
        return "\\\\?\\UNC\\" + absolute[2:]
    return "\\\\?\\" + absolute


def _path_from_io_path(path: str) -> Path:
    if os.name != "nt":
        return Path(path)
    if path.startswith("\\\\?\\UNC\\"):
        return Path("\\\\" + path[8:])
    if path.startswith("\\\\?\\"):
        return Path(path[4:])
    return Path(path)


def _sha256_file(path: str | Path) -> str:
    digest = hashlib.sha256()
    with open(_io_path(path), "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _write_json_exclusive(path: Path, value: dict[str, Any]) -> None:
    content = (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n").encode("utf-8")
    os.makedirs(_io_path(path.parent), exist_ok=True)
    descriptor = os.open(_io_path(path), os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())


def _inside(repo: Path, path: str | Path) -> Path:
    resolved = Path(path).resolve()
    try:
        resolved.relative_to(repo)
    except ValueError as error:
        raise ValueError(f"development loop path is outside the repository: {resolved}") from error
    return resolved


def _artifact_manifest(root: Path) -> list[dict[str, Any]]:
    files = [
        Path(os.path.join(directory, filename))
        for directory, _, filenames in os.walk(_io_path(root))
        for filename in filenames
    ]
    entries = []
    for physical in sorted(
        files,
        key=lambda item: _path_from_io_path(str(item)).relative_to(root).as_posix(),
    ):
        logical = _path_from_io_path(str(physical))
        entries.append(
            {
                "path": logical.relative_to(root).as_posix(),
                "bytes": os.stat(_io_path(physical)).st_size,
                "sha256": _sha256_file(physical),
            }
        )
    return entries


def _validate_package(package_root: Path, expected_manifest_sha256: str) -> tuple[Path, dict[str, Any]]:
    manifest_path = package_root / "PACKAGE_MANIFEST.json"
    if _sha256_file(manifest_path) != expected_manifest_sha256:
        raise ValueError("development package manifest differs from the frozen digest")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schema_version") != "development_packages_v1" or manifest.get("protocols") != [
        "forward",
        "reverse",
    ]:
        raise ValueError("development package is not the frozen two-protocol package")
    expected_files = manifest.get("files")
    if not isinstance(expected_files, dict):
        raise ValueError("development package file manifest is invalid")
    actual = {
        path.relative_to(package_root).as_posix(): _sha256_file(path)
        for path in package_root.rglob("*")
        if path.is_file() and path != manifest_path
    }
    if actual != expected_files:
        raise ValueError("development package file set or hash mismatch")
    return manifest_path, manifest


def _enable_candidate_monitor(descriptor_path: Path, candidate_root: Path, reason: str) -> CandidateDescriptor:
    """Rewrite the materialized descriptor to declare independent supervision, then reload it.

    The descriptor file lives inside the candidate source root, so this must run before the
    run layout copies that tree; every registered run then materializes the enabled descriptor.
    """
    value = json.loads(descriptor_path.read_text(encoding="utf-8"))
    value["resources"]["independent_monitor_enabled"] = True
    value["resources"]["monitor_reason"] = reason
    descriptor_path.write_text(
        json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n",
        encoding="utf-8",
    )
    return load_and_validate_candidate_descriptor(descriptor_path, candidate_root=candidate_root)


def _run_record(root: Path, result: RegisteredRuntimeResult) -> dict[str, Any]:
    return {
        "run_id": result.run_id,
        "run_root": result.fingerprint_path.parent.relative_to(root).as_posix(),
        "status": result.runtime_result.status,
        "process_exit_code": result.runtime_result.process_exit_code,
        "normalized_exit_code": result.runtime_result.exit_code,
        "denied_event_count": result.runtime_result.denied_event_count,
        "fingerprint_root_sha256": result.fingerprint["root_sha256"],
    }


def run_full_development_loop(
    *,
    repo_root: str | Path,
    package_root: str | Path,
    expected_package_manifest_sha256: str,
    output_root: str | Path,
    resource_snapshot: ResourceSnapshot,
    monitor_sample_interval_seconds: float | None = None,
    monitor_reason: str | None = None,
) -> dict[str, Any]:
    """Produce four candidates times eight basin cells without opening sealed evaluation data.

    When ``monitor_sample_interval_seconds`` is given, every registered run is launched under
    an independent resource supervisor sampled at that interval; when it is ``None`` the loop is
    byte-for-byte identical to the unsupervised path. Supervisor logs are live resource telemetry
    and therefore legitimately differ between otherwise-deterministic runs.
    """
    monitor_enabled = monitor_sample_interval_seconds is not None
    if monitor_enabled and not (monitor_reason and monitor_reason.strip()):
        raise ValueError("a supervised development loop requires a non-empty monitor reason")
    repo = Path(repo_root).resolve()
    if not (repo / ".git").exists():
        raise ValueError("full development loop requires a Git repository root")
    packages = _inside(repo, package_root)
    manifest_path, package_manifest = _validate_package(packages, expected_package_manifest_sha256)
    root = _inside(repo, output_root)
    if root.exists():
        raise FileExistsError(root)
    root.mkdir(parents=True)

    candidate_results: dict[str, Any] = {}
    cells: list[dict[str, Any]] = []
    registered_run_count = 0
    score_report_count = 0
    for category in REFERENCE_CATEGORIES:
        materialized = materialize_reference_candidate(
            category=category,
            output_root=root / "candidates" / category,
        )
        if monitor_enabled:
            descriptor = _enable_candidate_monitor(
                materialized.descriptor_path,
                materialized.source_root,
                monitor_reason,
            )
        else:
            descriptor = materialized.descriptor
        protocol_results: dict[str, Any] = {}
        score_paths: dict[str, Path] = {}
        predict_run_ids: dict[str, str] = {}
        for protocol in ("forward", "reverse"):
            train_source = packages / protocol / "train"
            train_layout = create_run_layout(
                root / "runs" / category / protocol / "train",
                descriptor=descriptor,
                candidate_source_root=materialized.source_root,
                mode="train",
                input_sources={
                    "train_features.parquet": train_source / "train_features.parquet",
                    "train_targets.parquet": train_source / "train_targets.parquet",
                    "static_attributes.json": train_source / "static_attributes.json",
                },
            )
            train_run_id = f"{descriptor.candidate_id}-{protocol}-train"
            common = {
                "repo_root": repo,
                "descriptor": descriptor,
                "code_paths": [materialized.source_root],
                "configuration_paths": [materialized.descriptor_path, manifest_path],
                "dependency_paths": [materialized.descriptor_path],
                "data_manifest_paths": [manifest_path],
                "resource_snapshot": resource_snapshot,
                "monitor_sample_interval_seconds": monitor_sample_interval_seconds,
            }
            train_result = run_registered_candidate(
                layout=train_layout,
                mode="train",
                run_id=train_run_id,
                **common,
            )
            if train_result.runtime_result.status != "succeeded":
                raise RuntimeError(f"development training failed: {category}/{protocol}")

            predict_source = packages / protocol / "predict"
            predict_layout = create_run_layout(
                root / "runs" / category / protocol / "predict",
                descriptor=descriptor,
                candidate_source_root=materialized.source_root,
                mode="predict",
                input_sources={
                    "predict_features.parquet": predict_source / "predict_features.parquet",
                    "static_attributes.json": predict_source / "static_attributes.json",
                    "model_artifacts": train_layout.output_root / "model_artifacts",
                },
            )
            predict_run_id = f"{descriptor.candidate_id}-{protocol}-predict"
            predict_result = run_registered_candidate(
                layout=predict_layout,
                mode="predict",
                run_id=predict_run_id,
                **common,
            )
            if predict_result.runtime_result.status != "succeeded":
                raise RuntimeError(f"development prediction failed: {category}/{protocol}")

            predictions_path = predict_layout.output_root / "predictions.parquet"
            score_path = root / "scores" / category / f"{protocol}.json"
            score = score_development_predictions(
                package_root=packages,
                expected_package_manifest_sha256=expected_package_manifest_sha256,
                candidate_id=descriptor.candidate_id,
                category=category,
                registered_run_id=predict_run_id,
                protocol_name=protocol,
                predictions_path=predictions_path,
                output_path=score_path,
            )
            if len(score["basin_metrics"]) != 8 or any(
                not math.isfinite(float(value)) for value in score["basin_metrics"].values()
            ):
                raise RuntimeError("development scoring did not produce eight finite basin metrics")
            protocol_results[protocol] = {
                "train_run_id": train_run_id,
                "train_run_root": train_layout.root.relative_to(root).as_posix(),
                "train": _run_record(root, train_result),
                "predict_run_id": predict_run_id,
                "predict_run_root": predict_layout.root.relative_to(root).as_posix(),
                "predict": _run_record(root, predict_result),
                "predictions_path": predictions_path.relative_to(root).as_posix(),
                "score_path": score_path.relative_to(root).as_posix(),
                "score_sha256": _sha256_file(score_path),
            }
            score_paths[protocol] = score_path
            predict_run_ids[protocol] = predict_run_id
            registered_run_count += 2
            score_report_count += 1

        summary_path = root / "summaries" / f"{category}.json"
        candidate_summary = summarize_candidate_development_scores(
            candidate_id=descriptor.candidate_id,
            category=category,
            registered_run_ids=predict_run_ids,
            expected_package_manifest_sha256=expected_package_manifest_sha256,
            score_paths=score_paths,
            output_path=summary_path,
        )
        if candidate_summary["cell_count"] != 8:
            raise RuntimeError("candidate development summary must contain eight basin cells")
        for cell in candidate_summary["cells"]:
            normalized = {
                "candidate_id": descriptor.candidate_id,
                "category": category,
                **cell,
            }
            if any(
                not math.isfinite(float(normalized[name]))
                for name in ("forward_nse", "reverse_nse", "mean_nse")
            ):
                raise RuntimeError("development cell metrics must be finite")
            cells.append(normalized)
        candidate_results[category] = {
            "candidate_id": descriptor.candidate_id,
            "source_root": materialized.source_root.relative_to(root).as_posix(),
            "descriptor_path": materialized.descriptor_path.relative_to(root).as_posix(),
            "protocols": protocol_results,
            "summary_path": summary_path.relative_to(root).as_posix(),
            "summary_sha256": _sha256_file(summary_path),
        }

    if registered_run_count != 16 or score_report_count != 8 or len(cells) != 32:
        raise RuntimeError("full development loop cardinality mismatch")
    if len({(cell["category"], cell["basin"]) for cell in cells}) != 32:
        raise RuntimeError("full development loop cells are not unique")

    result = {
        "schema_version": "full_development_loop_v1",
        "package_manifest_sha256": expected_package_manifest_sha256,
        "source_manifest_sha256": package_manifest["source_manifest_sha256"],
        "candidate_count": len(candidate_results),
        "protocol_count": 2,
        "registered_run_count": registered_run_count,
        "score_report_count": score_report_count,
        "cell_count": len(cells),
        "independent_monitor_enabled": monitor_enabled,
        "monitor_sample_interval_seconds": monitor_sample_interval_seconds,
        "candidates": candidate_results,
        "cells": cells,
        "artifact_manifest": _artifact_manifest(root),
        # Self-declared intent markers, recorded for transparency. They are NOT verification:
        # the independent checker recounts denied access from each run's raw access log rather
        # than trusting these constants (see scripts/verify_supervised_real_loops.py).
        "sealed_final_evaluation_read_or_scored": False,
        "fair_benchmark_scoring_program_run": False,
        "formal_basin_search_run": False,
        "baseline_outperformance_claimed": False,
    }
    _write_json_exclusive(root / "LOOP_SUMMARY.json", result)
    return result
