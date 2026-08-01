"""Exercise checkpoint recovery and compare it with a clean deterministic run."""

from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
from typing import Any

from unified_autoresearch.candidates.catalog import materialize_reference_candidate
from unified_autoresearch.runtime.checkpoints import verify_checkpoint
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


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with open(_io_path(path), "rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _inside(repo: Path, path: str | Path) -> Path:
    resolved = Path(path).resolve()
    try:
        resolved.relative_to(repo)
    except ValueError as error:
        raise ValueError(f"development recovery path is outside the repository: {resolved}") from error
    return resolved


def _write_json_exclusive(path: Path, value: dict[str, Any]) -> None:
    content = (json.dumps(value, indent=2, sort_keys=True, allow_nan=False) + "\n").encode("utf-8")
    descriptor = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o444)
    with os.fdopen(descriptor, "wb") as stream:
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())


def _artifact_manifest(root: Path) -> list[dict[str, Any]]:
    files = [
        Path(os.path.join(directory, filename))
        for directory, _, filenames in os.walk(_io_path(root))
        for filename in filenames
    ]
    return [
        {
            "path": _path_from_io_path(str(path)).relative_to(root).as_posix(),
            "bytes": os.stat(_io_path(path)).st_size,
            "sha256": _sha256_file(path),
        }
        for path in sorted(files, key=lambda item: _path_from_io_path(str(item)).relative_to(root).as_posix())
    ]


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


def run_recovery_reproducibility_cycle(
    *,
    repo_root: str | Path,
    package_root: str | Path,
    expected_package_manifest_sha256: str,
    category: str,
    output_root: str | Path,
    resource_snapshot: ResourceSnapshot,
) -> dict[str, Any]:
    """Checkpoint one forward training run, resume it, and compare a clean rerun."""
    repo = Path(repo_root).resolve()
    if not (repo / ".git").exists():
        raise ValueError("development recovery requires a Git repository root")
    packages = _inside(repo, package_root)
    manifest_path = packages / "PACKAGE_MANIFEST.json"
    if _sha256_file(manifest_path) != expected_package_manifest_sha256:
        raise ValueError("development package manifest differs from the frozen digest")
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    if manifest.get("schema_version") != "development_packages_v1" or manifest.get("protocols") != [
        "forward",
        "reverse",
    ]:
        raise ValueError("development package manifest is not the frozen two-protocol package")

    root = _inside(repo, output_root)
    if root.exists():
        raise FileExistsError(root)
    root.mkdir(parents=True)
    materialized = materialize_reference_candidate(
        category=category,
        output_root=root / "candidate-source",
    )
    descriptor = materialized.descriptor
    train_root = packages / "forward" / "train"
    train_inputs = {
        "train_features.parquet": train_root / "train_features.parquet",
        "train_targets.parquet": train_root / "train_targets.parquet",
        "static_attributes.json": train_root / "static_attributes.json",
    }
    common_arguments = {
        "repo_root": repo,
        "descriptor": descriptor,
        "mode": "train",
        "code_paths": [materialized.source_root],
        "configuration_paths": [materialized.descriptor_path, manifest_path],
        "dependency_paths": [materialized.descriptor_path],
        "data_manifest_paths": [manifest_path],
        "resource_snapshot": resource_snapshot,
    }

    interrupted_layout = create_run_layout(
        root / "runs" / "forward-checkpoint",
        descriptor=descriptor,
        candidate_source_root=materialized.source_root,
        mode="train",
        input_sources=train_inputs,
    )
    _write_json_exclusive(
        interrupted_layout.control_root / "STOP_REQUEST.json",
        {"schema_version": "stop_request_v1", "reason": "deterministic recovery verification"},
    )
    interrupted = run_registered_candidate(
        layout=interrupted_layout,
        run_id=f"{descriptor.candidate_id}-forward-checkpoint",
        **common_arguments,
    )
    if interrupted.runtime_result.status != "checkpointed" or interrupted.runtime_result.checkpoint_path is None:
        raise RuntimeError("interrupted training did not publish a checkpoint")
    checkpoint = verify_checkpoint(
        interrupted.runtime_result.checkpoint_path,
        expected_candidate_id=descriptor.candidate_id,
    )

    resumed_layout = create_run_layout(
        root / "runs" / "forward-resume",
        descriptor=descriptor,
        candidate_source_root=materialized.source_root,
        mode="train",
        input_sources=train_inputs,
    )
    resumed = run_registered_candidate(
        layout=resumed_layout,
        run_id=f"{descriptor.candidate_id}-forward-resume",
        resume_checkpoint=checkpoint.path,
        **common_arguments,
    )
    clean_layout = create_run_layout(
        root / "runs" / "forward-clean",
        descriptor=descriptor,
        candidate_source_root=materialized.source_root,
        mode="train",
        input_sources=train_inputs,
    )
    clean = run_registered_candidate(
        layout=clean_layout,
        run_id=f"{descriptor.candidate_id}-forward-clean",
        **common_arguments,
    )
    if resumed.runtime_result.status != "succeeded" or clean.runtime_result.status != "succeeded":
        raise RuntimeError("resumed and clean training must both succeed")

    resumed_model = resumed_layout.output_root / "model_artifacts" / "model.json"
    clean_model = clean_layout.output_root / "model_artifacts" / "model.json"
    resumed_bytes = resumed_model.read_bytes()
    clean_bytes = clean_model.read_bytes()
    if resumed_bytes != clean_bytes:
        raise RuntimeError("resumed training model differs from the clean deterministic run")
    mounted_checkpoint = resumed.runtime_result.resume_checkpoint_path
    if mounted_checkpoint is None:
        raise RuntimeError("resumed training did not record its mounted checkpoint")
    mounted_record = verify_checkpoint(mounted_checkpoint, expected_candidate_id=descriptor.candidate_id)
    if mounted_record.root_sha256 != checkpoint.root_sha256:
        raise RuntimeError("mounted resume checkpoint differs from the published checkpoint")

    runs = {
        "interrupted": _run_record(root, interrupted),
        "resumed": _run_record(root, resumed),
        "clean": _run_record(root, clean),
    }
    summary = {
        "schema_version": "development_recovery_cycle_v1",
        "candidate_id": descriptor.candidate_id,
        "category": descriptor.category,
        "protocol": "forward",
        "package_manifest_sha256": expected_package_manifest_sha256,
        "registered_run_count": len(runs),
        "interrupted_status": interrupted.runtime_result.status,
        "resumed_status": resumed.runtime_result.status,
        "clean_status": clean.runtime_result.status,
        "checkpoint_id": checkpoint.checkpoint_id,
        "checkpoint_root_sha256": checkpoint.root_sha256,
        "checkpoint_path": checkpoint.path.relative_to(root).as_posix(),
        "mounted_checkpoint_root_sha256": mounted_record.root_sha256,
        "resumed_model_path": resumed_model.relative_to(root).as_posix(),
        "clean_model_path": clean_model.relative_to(root).as_posix(),
        "resumed_model_sha256": hashlib.sha256(resumed_bytes).hexdigest(),
        "clean_model_sha256": hashlib.sha256(clean_bytes).hexdigest(),
        "model_bytes_equal": True,
        "runs": runs,
        "artifact_manifest": _artifact_manifest(root),
        "sealed_final_evaluation_read_or_scored": False,
        "fair_benchmark_scoring_program_run": False,
        "formal_basin_search_run": False,
    }
    _write_json_exclusive(root / "RECOVERY_SUMMARY.json", summary)
    return summary
