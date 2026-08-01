"""Run one supervised candidate on real packages: train, predict, score.

This is a reduced walkthrough, not a full loop. Its purpose is to prove that the
independent resource supervisor starts before the candidate, verifies process ownership,
records samples, and can request a controlled stop.

Example
-------
python src/unified_autoresearch/scripts/run_supervised_real_walkthrough.py \
    --package-root runs/unified_autoresearch/development_packages_real_v1 \
    --output-root runs/unified_autoresearch/supervised_walkthrough_real_v1
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import psutil


MODULE_ROOT = Path(__file__).resolve().parents[1]
SRC_ROOT = MODULE_ROOT.parent
REPO_ROOT = SRC_ROOT.parent
if str(SRC_ROOT) not in sys.path:
    sys.path.insert(0, str(SRC_ROOT))

from unified_autoresearch.candidates.catalog import REFERENCE_CATEGORIES, materialize_reference_candidate  # noqa: E402
from unified_autoresearch.evaluation.scoring import score_development_predictions  # noqa: E402
from unified_autoresearch.runtime.descriptor import load_and_validate_candidate_descriptor  # noqa: E402
from unified_autoresearch.runtime.layout import create_run_layout  # noqa: E402
from unified_autoresearch.runtime.orchestrator import run_registered_candidate  # noqa: E402
from unified_autoresearch.runtime.resources import ResourceSnapshot  # noqa: E402


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _enable_monitor(descriptor_path: Path, candidate_root: Path, reason: str):
    value = json.loads(descriptor_path.read_text(encoding="utf-8"))
    value["resources"]["independent_monitor_enabled"] = True
    value["resources"]["monitor_reason"] = reason
    descriptor_path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return load_and_validate_candidate_descriptor(descriptor_path, candidate_root=candidate_root)


def _monitor_report(log_root: Path) -> dict:
    log_path = log_root / "resource-monitor.jsonl"
    if not log_path.is_file():
        return {"sample_count": 0}
    records = [json.loads(line) for line in log_path.read_text(encoding="utf-8").splitlines() if line]
    return {
        "sample_count": len(records),
        "run_id": records[0]["run_id"] if records else None,
        "sample_index_is_contiguous": [record["sample_index"] for record in records] == list(range(len(records))),
        "minimum_system_available_memory_gb": min((record["system_available_memory_gb"] for record in records), default=None),
        "maximum_process_memory_gb": max((record["process_memory_gb"] for record in records), default=None),
        "minimum_free_disk_gb": min((record["free_disk_gb"] for record in records), default=None),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--package-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--category", choices=REFERENCE_CATEGORIES, default="conceptual_rainfall_runoff")
    parser.add_argument("--protocol", choices=("forward", "reverse"), default="forward")
    parser.add_argument("--sample-interval-seconds", type=float, default=0.5)
    arguments = parser.parse_args(argv)

    packages = arguments.package_root.resolve()
    root = arguments.output_root.resolve()
    if root.exists():
        raise FileExistsError(root)
    root.mkdir(parents=True)

    memory = psutil.virtual_memory()
    disk = psutil.disk_usage(str(REPO_ROOT))
    snapshot = ResourceSnapshot(
        available_cpu_cores=psutil.cpu_count(logical=True),
        available_gpu_count=0,
        available_memory_gb=memory.available / 2**30,
        free_disk_gb=disk.free / 2**30,
    )

    materialized = materialize_reference_candidate(
        category=arguments.category,
        output_root=root / "candidate",
    )
    descriptor = _enable_monitor(
        materialized.descriptor_path,
        materialized.source_root,
        "supervised real-data walkthrough; short task sampled at a task-specific interval",
    )

    manifest_path = packages / "PACKAGE_MANIFEST.json"
    common = {
        "repo_root": REPO_ROOT,
        "descriptor": descriptor,
        "code_paths": [materialized.source_root],
        "configuration_paths": [materialized.descriptor_path, manifest_path],
        "dependency_paths": [materialized.descriptor_path],
        "data_manifest_paths": [manifest_path],
        "resource_snapshot": snapshot,
        "monitor_sample_interval_seconds": arguments.sample_interval_seconds,
    }
    protocol = arguments.protocol
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
    train = run_registered_candidate(
        layout=train_layout,
        mode="train",
        run_id=f"{descriptor.candidate_id}-{protocol}-train",
        **common,
    )

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
    predict = run_registered_candidate(
        layout=predict_layout,
        mode="predict",
        run_id=predict_run_id,
        **common,
    )

    score = score_development_predictions(
        package_root=packages,
        expected_package_manifest_sha256=_sha256(manifest_path),
        candidate_id=descriptor.candidate_id,
        category=arguments.category,
        registered_run_id=predict_run_id,
        protocol_name=protocol,
        predictions_path=predict_layout.output_root / "predictions.parquet",
        output_path=root / "development-score.json",
    )

    report = {
        "schema_version": "supervised_walkthrough_v1",
        "category": arguments.category,
        "protocol": protocol,
        "sample_interval_seconds": arguments.sample_interval_seconds,
        "train_status": train.runtime_result.status,
        "predict_status": predict.runtime_result.status,
        "train_monitor": _monitor_report(train_layout.log_root),
        "predict_monitor": _monitor_report(predict_layout.log_root),
        "controlled_stop_requested": {
            "train": (train_layout.control_root / "STOP_REQUEST.json").is_file(),
            "predict": (predict_layout.control_root / "STOP_REQUEST.json").is_file(),
        },
        "scored_basin_count": len(score["basin_metrics"]),
        "scored_row_count": score["row_count"],
        "baseline_outperformance_claimed": False,
        "sealed_final_evaluation_read_or_scored": False,
    }
    (root / "WALKTHROUGH_SUMMARY.json").write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
