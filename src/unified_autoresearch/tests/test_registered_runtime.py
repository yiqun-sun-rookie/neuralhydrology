import hashlib
import io
import json
import subprocess
from pathlib import Path

import pytest


def _prediction_parquet_bytes() -> bytes:
    import pyarrow as pa
    import pyarrow.parquet as pq

    stream = io.BytesIO()
    pq.write_table(
        pa.table({"basin": ["01013500"], "date": ["2000-01-01"], "qsim": [1.25]}),
        stream,
    )
    return stream.getvalue()


def _prepare_registered_prediction(tmp_path: Path, *, predict_source: str | None = None):
    from unified_autoresearch.runtime.descriptor import load_and_validate_candidate_descriptor
    from unified_autoresearch.runtime.layout import create_run_layout

    repo = tmp_path / "repo"
    repo.mkdir()
    subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.email", "test@example.invalid"], cwd=repo, check=True)
    subprocess.run(["git", "config", "user.name", "Test User"], cwd=repo, check=True)
    (repo / ".gitignore").write_text("runs/\n", encoding="utf-8")
    (repo / "code-version.txt").write_text("registered-runtime-v1\n", encoding="utf-8")
    (repo / "configuration.json").write_text("{}\n", encoding="utf-8")
    (repo / "requirements.txt").write_text("# no candidate dependencies\n", encoding="utf-8")
    (repo / "data-manifest.txt").write_text("synthetic-inputs-only\n", encoding="utf-8")

    candidate_root = repo / "candidate-source"
    candidate_root.mkdir()
    (candidate_root / "train.py").write_text("pass\n", encoding="utf-8")
    prediction_bytes = _prediction_parquet_bytes()
    if predict_source is None:
        predict_source = (
            "from pathlib import Path\n"
            "import os\n"
            f"payload = {prediction_bytes!r}\n"
            "(Path(os.environ['UNIFIED_OUTPUT_ROOT']) / 'predictions.parquet').write_bytes(payload)\n"
        )
    (candidate_root / "predict.py").write_text(predict_source, encoding="utf-8")
    descriptor_value = {
        "schema_version": "candidate_descriptor_v1",
        "candidate_id": "registered-candidate-001",
        "category": "custom_python",
        "entrypoint": {"train": "train.py", "predict": "predict.py"},
        "dependencies": [],
        "allowed_reads": {
            "train": ["train_features.parquet", "train_targets.parquet", "static_attributes.json"],
            "predict": ["predict_features.parquet", "static_attributes.json", "model_artifacts"],
        },
        "outputs": {"train": ["model_artifacts"], "predict": ["predictions.parquet"]},
        "seed": 29,
        "resources": {
            "cpu_cores": 1,
            "gpu_count": 0,
            "estimated_peak_memory_gb": 0.1,
            "memory_safety_reserve_gb": 0.1,
            "estimated_output_gb": 0.01,
            "disk_safety_reserve_gb": 0.1,
            "independent_monitor_enabled": False,
            "monitor_reason": "short registered runtime integration test",
        },
        "checkpoint": {"supported": True, "staging_dir": "checkpoint_staging", "keep": "all"},
        "resume": {"supported": True},
    }
    descriptor_path = repo / "candidate.json"
    descriptor_path.write_text(json.dumps(descriptor_value), encoding="utf-8")

    inputs = repo / "synthetic-inputs"
    inputs.mkdir()
    (inputs / "predict_features.parquet").write_text("synthetic-features", encoding="utf-8")
    (inputs / "static_attributes.json").write_text("{}\n", encoding="utf-8")
    (inputs / "model_artifacts").mkdir()
    (inputs / "model_artifacts" / "model.bin").write_bytes(b"synthetic-model")

    subprocess.run(["git", "add", "."], cwd=repo, check=True)
    subprocess.run(["git", "commit", "-q", "-m", "fixture"], cwd=repo, check=True)

    descriptor = load_and_validate_candidate_descriptor(descriptor_path, candidate_root=candidate_root)
    layout = create_run_layout(
        repo / "runs" / "registered-run-001",
        descriptor=descriptor,
        candidate_source_root=candidate_root,
        mode="predict",
        input_sources={name: inputs / name for name in descriptor.allowed_reads["predict"]},
    )
    return repo, descriptor, layout


def test_registered_candidate_run_appends_real_lifecycle_and_final_fingerprint(tmp_path):
    from unified_autoresearch.registry.store import Registry
    from unified_autoresearch.runtime.orchestrator import run_registered_candidate
    from unified_autoresearch.runtime.resources import ResourceSnapshot

    repo, descriptor, layout = _prepare_registered_prediction(tmp_path)
    unrelated = repo / "unrelated-progress.md"
    unrelated.write_text("state before registered run\n", encoding="utf-8")

    result = run_registered_candidate(
        repo_root=repo,
        descriptor=descriptor,
        layout=layout,
        mode="predict",
        run_id="registered-run-001",
        code_paths=[repo / "code-version.txt"],
        configuration_paths=[repo / "configuration.json"],
        dependency_paths=[repo / "requirements.txt"],
        data_manifest_paths=[repo / "data-manifest.txt"],
        resource_snapshot=ResourceSnapshot(
            available_cpu_cores=4,
            available_gpu_count=0,
            available_memory_gb=4.0,
            free_disk_gb=10.0,
        ),
    )

    assert result.runtime_result.status == "succeeded"
    assert result.fingerprint_path == layout.root / "fingerprint.json"
    assert result.fingerprint_path.is_file()
    registry = Registry(
        result.registry_path,
        scheduler_lock_path=result.scheduler_lock_path,
        receipt_dir=result.receipt_dir,
    )
    records = registry.records()
    assert [record["record_type"] for record in records] == [
        "candidate",
        "experiment",
        "state",
        "state",
        "state",
        "state",
        "fingerprint",
        "state",
    ]
    assert registry.current_state("registered-run-001") == "succeeded"
    assert registry.verify() == {"record_count": 8, "failure_count": 0, "failures": []}
    assert len(list(result.receipt_dir.glob("*.json"))) == 8
    assert not result.scheduler_lock_path.exists()

    artifact_paths = {entry["path"] for entry in result.fingerprint["details"]["artifacts"]}
    expected_outputs = {
        path.relative_to(repo).as_posix() for path in layout.output_root.rglob("*") if path.is_file()
    }
    expected_logs = {
        path.relative_to(repo).as_posix() for path in layout.log_root.rglob("*") if path.is_file()
    }
    assert expected_outputs
    assert len(expected_logs) == 9
    assert expected_outputs | expected_logs <= artifact_paths
    raw_diff = layout.log_root / "git-diff.bin"
    raw_status = layout.log_root / "git-status.bin"
    assert hashlib.sha256(raw_diff.read_bytes()).hexdigest() == result.fingerprint["details"][
        "uncommitted_diff"
    ]["git_diff_sha256"]
    assert hashlib.sha256(raw_status.read_bytes()).hexdigest() == result.fingerprint["details"][
        "uncommitted_diff"
    ]["git_status_sha256"]
    untracked_manifest = result.fingerprint["details"]["uncommitted_diff"]["untracked_manifest"]
    assert unrelated.relative_to(repo).as_posix() not in {entry["path"] for entry in untracked_manifest}
    unrelated.write_text("state after registered run\n", encoding="utf-8")
    for entry in untracked_manifest:
        replay_path = repo / entry["path"]
        assert replay_path.stat().st_size == entry["bytes"]
        assert hashlib.sha256(replay_path.read_bytes()).hexdigest() == entry["sha256"]
    expected_inputs = {
        path.relative_to(repo).as_posix() for path in layout.input_root.rglob("*") if path.is_file()
    }
    data_manifest_paths = {entry["path"] for entry in result.fingerprint["details"]["data_manifest"]}
    assert expected_inputs <= data_manifest_paths
    fingerprint_records = registry.records(record_type="fingerprint", subject_id="registered-run-001/final")
    assert len(fingerprint_records) == 1
    assert json.loads(fingerprint_records[0]["payload_json"])["root_sha256"] == result.fingerprint["root_sha256"]


@pytest.mark.parametrize(
    ("predict_source", "expected_status", "expected_exit_code"),
    [
        ("raise RuntimeError('synthetic candidate failure')\n", "runtime_failure", 1),
        ("pass\n", "contract_failure", 2),
    ],
    ids=("runtime-failure", "contract-failure"),
)
def test_registered_candidate_failure_is_fingerprinted_and_marked_failed(
    tmp_path, predict_source, expected_status, expected_exit_code
):
    from unified_autoresearch.registry.store import Registry
    from unified_autoresearch.runtime.orchestrator import run_registered_candidate
    from unified_autoresearch.runtime.resources import ResourceSnapshot

    repo, descriptor, layout = _prepare_registered_prediction(
        tmp_path,
        predict_source=predict_source,
    )

    result = run_registered_candidate(
        repo_root=repo,
        descriptor=descriptor,
        layout=layout,
        mode="predict",
        run_id="registered-run-001",
        code_paths=[repo / "code-version.txt"],
        configuration_paths=[repo / "configuration.json"],
        dependency_paths=[repo / "requirements.txt"],
        data_manifest_paths=[repo / "data-manifest.txt"],
        resource_snapshot=ResourceSnapshot(
            available_cpu_cores=4,
            available_gpu_count=0,
            available_memory_gb=4.0,
            free_disk_gb=10.0,
        ),
    )

    assert result.runtime_result.status == expected_status
    assert result.runtime_result.exit_code == expected_exit_code
    registry = Registry(
        result.registry_path,
        scheduler_lock_path=result.scheduler_lock_path,
        receipt_dir=result.receipt_dir,
    )
    assert registry.current_state("registered-run-001") == "failed"
    assert registry.verify() == {"record_count": 8, "failure_count": 0, "failures": []}
    assert result.fingerprint_path.is_file()
    artifact_paths = {entry["path"] for entry in result.fingerprint["details"]["artifacts"]}
    expected_logs = {
        path.relative_to(repo).as_posix() for path in layout.log_root.rglob("*") if path.is_file()
    }
    assert len(expected_logs) == 9
    assert expected_logs <= artifact_paths


def test_registered_candidate_checkpoint_is_fingerprinted_and_marked_checkpointed(tmp_path):
    from unified_autoresearch.registry.store import Registry
    from unified_autoresearch.runtime.orchestrator import run_registered_candidate
    from unified_autoresearch.runtime.resources import ResourceSnapshot

    checkpoint_source = """import hashlib
import json
import os
from pathlib import Path

root = Path(os.environ["UNIFIED_CHECKPOINT_STAGING_ROOT"])
payload = b"registered-checkpoint-state"
(root / "model.bin").write_bytes(payload)
request = {
    "schema_version": "checkpoint_request_v1",
    "checkpoint_id": "registered-checkpoint-0001",
    "candidate_id": "registered-candidate-001",
    "mode": "predict",
    "parent_checkpoint_id": None,
    "files": {"model.bin": hashlib.sha256(payload).hexdigest()},
}
(root / "CHECKPOINT_REQUEST.json").write_text(json.dumps(request), encoding="utf-8")
raise SystemExit(75)
"""
    repo, descriptor, layout = _prepare_registered_prediction(tmp_path, predict_source=checkpoint_source)

    result = run_registered_candidate(
        repo_root=repo,
        descriptor=descriptor,
        layout=layout,
        mode="predict",
        run_id="registered-run-001",
        code_paths=[repo / "code-version.txt"],
        configuration_paths=[repo / "configuration.json"],
        dependency_paths=[repo / "requirements.txt"],
        data_manifest_paths=[repo / "data-manifest.txt"],
        resource_snapshot=ResourceSnapshot(
            available_cpu_cores=4,
            available_gpu_count=0,
            available_memory_gb=4.0,
            free_disk_gb=10.0,
        ),
    )

    assert result.runtime_result.status == "checkpointed"
    assert result.runtime_result.exit_code == 75
    registry = Registry(
        result.registry_path,
        scheduler_lock_path=result.scheduler_lock_path,
        receipt_dir=result.receipt_dir,
    )
    assert registry.current_state("registered-run-001") == "checkpointed"
    assert registry.verify() == {"record_count": 8, "failure_count": 0, "failures": []}
    checkpoint_files = {
        path.relative_to(repo).as_posix() for path in layout.checkpoints_root.rglob("*") if path.is_file()
    }
    artifact_paths = {entry["path"] for entry in result.fingerprint["details"]["artifacts"]}
    assert len(checkpoint_files) == 3
    assert checkpoint_files <= artifact_paths


def test_registered_candidate_prelaunch_exception_is_fingerprinted_and_marked_failed(tmp_path):
    from unified_autoresearch.registry.store import Registry
    from unified_autoresearch.runtime.orchestrator import run_registered_candidate
    from unified_autoresearch.runtime.resources import ResourceCapacityError, ResourceSnapshot

    repo, descriptor, layout = _prepare_registered_prediction(tmp_path)

    with pytest.raises(ResourceCapacityError):
        run_registered_candidate(
            repo_root=repo,
            descriptor=descriptor,
            layout=layout,
            mode="predict",
            run_id="registered-run-001",
            code_paths=[repo / "code-version.txt"],
            configuration_paths=[repo / "configuration.json"],
            dependency_paths=[repo / "requirements.txt"],
            data_manifest_paths=[repo / "data-manifest.txt"],
            resource_snapshot=ResourceSnapshot(
                available_cpu_cores=0,
                available_gpu_count=0,
                available_memory_gb=0.0,
                free_disk_gb=0.0,
            ),
        )

    registry_root = layout.root / "registry"
    registry = Registry(
        registry_root / "registry.sqlite",
        scheduler_lock_path=registry_root / "scheduler.lock",
        receipt_dir=registry_root / "receipts",
    )
    assert registry.current_state("registered-run-001") == "failed"
    assert registry.verify() == {"record_count": 8, "failure_count": 0, "failures": []}
    assert not registry.scheduler_lock_path.exists()
    fingerprint_path = layout.root / "fingerprint.json"
    fingerprint = json.loads(fingerprint_path.read_text(encoding="utf-8"))
    error_path = layout.log_root / "orchestration-error.json"
    error = json.loads(error_path.read_text(encoding="utf-8"))
    assert error["error_type"] == "ResourceCapacityError"
    artifact_paths = {entry["path"] for entry in fingerprint["details"]["artifacts"]}
    expected_logs = {
        path.relative_to(repo).as_posix() for path in layout.log_root.rglob("*") if path.is_file()
    }
    assert expected_logs <= artifact_paths


def test_registered_resume_input_is_bound_by_final_fingerprint(tmp_path):
    import hashlib

    from unified_autoresearch.runtime.checkpoints import promote_staged_checkpoint
    from unified_autoresearch.runtime.orchestrator import run_registered_candidate
    from unified_autoresearch.runtime.resources import ResourceSnapshot

    prediction_bytes = _prediction_parquet_bytes()
    predict_source = (
        "from pathlib import Path\n"
        "import os\n"
        "resume = Path(os.environ['UNIFIED_RESUME_CHECKPOINT'])\n"
        "assert (resume / 'model.bin').read_bytes() == b'resume-state'\n"
        f"payload = {prediction_bytes!r}\n"
        "(Path(os.environ['UNIFIED_OUTPUT_ROOT']) / 'predictions.parquet').write_bytes(payload)\n"
    )
    repo, descriptor, layout = _prepare_registered_prediction(tmp_path, predict_source=predict_source)
    staging = repo / "resume-staging"
    staging.mkdir()
    payload = b"resume-state"
    (staging / "model.bin").write_bytes(payload)
    request = {
        "schema_version": "checkpoint_request_v1",
        "checkpoint_id": "resume-checkpoint-0001",
        "candidate_id": descriptor.candidate_id,
        "mode": "predict",
        "parent_checkpoint_id": None,
        "files": {"model.bin": hashlib.sha256(payload).hexdigest()},
    }
    (staging / "CHECKPOINT_REQUEST.json").write_text(json.dumps(request), encoding="utf-8")
    published = repo / "published-checkpoints"
    published.mkdir()
    checkpoint = promote_staged_checkpoint(staging, published)

    result = run_registered_candidate(
        repo_root=repo,
        descriptor=descriptor,
        layout=layout,
        mode="predict",
        run_id="registered-run-001",
        code_paths=[repo / "code-version.txt"],
        configuration_paths=[repo / "configuration.json"],
        dependency_paths=[repo / "requirements.txt"],
        data_manifest_paths=[repo / "data-manifest.txt"],
        resume_checkpoint=checkpoint.path,
        resource_snapshot=ResourceSnapshot(
            available_cpu_cores=4,
            available_gpu_count=0,
            available_memory_gb=4.0,
            free_disk_gb=10.0,
        ),
    )

    assert result.runtime_result.status == "succeeded"
    mounted_resume = layout.root / "resume_checkpoint"
    expected_resume = {
        path.relative_to(repo).as_posix() for path in mounted_resume.rglob("*") if path.is_file()
    }
    data_manifest_paths = {entry["path"] for entry in result.fingerprint["details"]["data_manifest"]}
    assert len(expected_resume) == 3
    assert expected_resume <= data_manifest_paths
