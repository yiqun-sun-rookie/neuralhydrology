"""Run one declared candidate through both frozen development protocols.

This is deliberately not a search. The candidate is named before the run, it is the only one
executed, and nothing here proposes or ranks alternatives. The frozen four-candidate loop in
:mod:`unified_autoresearch.workflow.development_loop` is left untouched because its outputs are
frozen evidence; this path takes its basin count from the package manifest instead of assuming
eight, so the same code serves 8, 64, or 531 basins.
"""

from __future__ import annotations

import math
from pathlib import Path
from typing import Any

from unified_autoresearch.evaluation.scoring import (
    score_development_predictions,
    summarize_candidate_development_scores,
)
from unified_autoresearch.runtime.layout import create_run_layout
from unified_autoresearch.runtime.orchestrator import run_registered_candidate
from unified_autoresearch.runtime.resources import ResourceSnapshot
from unified_autoresearch.workflow.development_loop import (
    _artifact_manifest,
    _enable_candidate_monitor,
    _inside,
    _run_record,
    _sha256_file,
    _validate_package,
    _write_json_exclusive,
)


def run_single_candidate_development(
    *,
    repo_root: str | Path,
    package_root: str | Path,
    expected_package_manifest_sha256: str,
    materialize,
    output_root: str | Path,
    resource_snapshot: ResourceSnapshot,
    monitor_sample_interval_seconds: float | None = None,
    monitor_reason: str | None = None,
) -> dict[str, Any]:
    """Train and predict one candidate on both protocols, then score every frozen basin."""
    monitor_enabled = monitor_sample_interval_seconds is not None
    if monitor_enabled and not (monitor_reason and monitor_reason.strip()):
        raise ValueError("a supervised candidate run requires a non-empty monitor reason")
    repo = Path(repo_root).resolve()
    if not (repo / ".git").exists():
        raise ValueError("a candidate development run requires a Git repository root")
    packages = _inside(repo, package_root)
    manifest_path, package_manifest = _validate_package(packages, expected_package_manifest_sha256)
    basins = [str(basin).zfill(8) for basin in package_manifest["basins"]]
    root = _inside(repo, output_root)
    if root.exists():
        raise FileExistsError(root)
    root.mkdir(parents=True)

    # Fingerprinting requires every code path inside the repository, so the candidate tree is
    # materialized under this run's own root rather than supplied from outside.
    materialized = materialize(output_root=root / "candidate")
    if monitor_enabled:
        descriptor = _enable_candidate_monitor(
            materialized.descriptor_path, materialized.source_root, monitor_reason
        )
    else:
        descriptor = materialized.descriptor
    category = descriptor.category

    protocol_results: dict[str, Any] = {}
    score_paths: dict[str, Path] = {}
    predict_run_ids: dict[str, str] = {}
    registered_run_count = 0
    for protocol in ("forward", "reverse"):
        train_source = packages / protocol / "train"
        train_layout = create_run_layout(
            root / "runs" / protocol / "train",
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
            layout=train_layout, mode="train", run_id=train_run_id, **common
        )
        if train_result.runtime_result.status != "succeeded":
            raise RuntimeError(f"candidate training failed: {protocol}")

        predict_source = packages / protocol / "predict"
        predict_layout = create_run_layout(
            root / "runs" / protocol / "predict",
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
            layout=predict_layout, mode="predict", run_id=predict_run_id, **common
        )
        if predict_result.runtime_result.status != "succeeded":
            raise RuntimeError(f"candidate prediction failed: {protocol}")

        predictions_path = predict_layout.output_root / "predictions.parquet"
        score_path = root / "scores" / f"{protocol}.json"
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
        if set(score["basin_metrics"]) != set(basins) or any(
            not math.isfinite(float(value)) for value in score["basin_metrics"].values()
        ):
            raise RuntimeError("scoring did not produce a finite metric for every frozen basin")
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

    summary_path = root / "summaries" / f"{descriptor.candidate_id}.json"
    candidate_summary = summarize_candidate_development_scores(
        candidate_id=descriptor.candidate_id,
        category=category,
        registered_run_ids=predict_run_ids,
        expected_package_manifest_sha256=expected_package_manifest_sha256,
        score_paths=score_paths,
        output_path=summary_path,
    )
    if candidate_summary["cell_count"] != len(basins):
        raise RuntimeError("candidate summary must contain one cell per frozen basin")
    cells = []
    for cell in candidate_summary["cells"]:
        normalized = {"candidate_id": descriptor.candidate_id, "category": category, **cell}
        if any(
            not math.isfinite(float(normalized[name])) for name in ("forward_nse", "reverse_nse", "mean_nse")
        ):
            raise RuntimeError("candidate cell metrics must be finite")
        cells.append(normalized)

    result = {
        "schema_version": "single_candidate_development_v1",
        "candidate_id": descriptor.candidate_id,
        "category": category,
        "package_manifest_sha256": expected_package_manifest_sha256,
        "source_manifest_sha256": package_manifest["source_manifest_sha256"],
        "basin_count": len(basins),
        "protocol_count": 2,
        "registered_run_count": registered_run_count,
        "score_report_count": len(score_paths),
        "cell_count": len(cells),
        "independent_monitor_enabled": monitor_enabled,
        "monitor_sample_interval_seconds": monitor_sample_interval_seconds,
        "protocols": protocol_results,
        "summary_path": summary_path.relative_to(root).as_posix(),
        "summary_sha256": _sha256_file(summary_path),
        "cells": cells,
        "artifact_manifest": _artifact_manifest(root),
        # Self-declared intent markers, recorded for transparency. They are NOT verification.
        "sealed_final_evaluation_read_or_scored": False,
        "fair_benchmark_scoring_program_run": False,
        "formal_basin_search_run": False,
        "baseline_outperformance_claimed": False,
    }
    _write_json_exclusive(root / "CANDIDATE_SUMMARY.json", result)
    return result
