import hashlib
import json
import os
import sqlite3
import subprocess
import sys
from pathlib import Path

import pytest


def _git(repo: Path, *args: str) -> bytes:
    return subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True).stdout


def _fixture_repo(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    (repo / "src" / "unified_autoresearch" / "protocols").mkdir(parents=True)
    (repo / "src" / "unified_autoresearch" / "selection").mkdir(parents=True)
    (repo / "src" / "fair_benchmark" / "frozen" / "bundle").mkdir(parents=True)
    files = {
        ".gitignore": "runs/\n",
        "src/unified_autoresearch/module.py": "VALUE = 1\n",
        "src/unified_autoresearch/protocols/development.json": '{"protocol": "development"}\n',
        "src/unified_autoresearch/selection/basins.json": '{"basins": ["a"]}\n',
        "src/fair_benchmark/frozen/track0_forcing_only_basins.txt": "a\n",
        "src/fair_benchmark/frozen/bundle/track0_statics.csv": "gauge_id,attr\na,1\n",
        "requirements-cpu.txt": "psutil\n",
        "setup.cfg": "[tool:pytest]\n",
    }
    for relative, content in files.items():
        path = repo / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
    _git(repo, "init")
    _git(repo, "config", "user.email", "test@example.invalid")
    _git(repo, "config", "user.name", "Test")
    _git(repo, "add", ".")
    _git(repo, "commit", "-m", "fixture")
    (repo / "src" / "unified_autoresearch" / "untracked.py").write_text("UNTRACKED = True\n", encoding="utf-8")
    return repo


def _commands() -> tuple[list[str], list[str]]:
    passing = [
        sys.executable,
        "-c",
        (
            "import pathlib,sys; "
            "p=pathlib.Path(sys.argv[1]); p.parent.mkdir(parents=True,exist_ok=True); "
            "p.write_text('<testsuite tests=\"1\" failures=\"0\"/>',encoding='utf-8'); "
            "extra=pathlib.Path(sys.argv[2])/'nested'/'unlisted-output.bin'; "
            "extra.parent.mkdir(parents=True,exist_ok=True); extra.write_bytes(b'covered')"
        ),
        "{junitxml}",
        "{artifact_root}",
    ]
    failing = [sys.executable, "-c", "raise SystemExit(7)"]
    return passing, failing


def _physical_files_long_path_safe(root: Path) -> set[str]:
    absolute = str(root.resolve())
    walk_root = f"\\\\?\\{absolute}" if os.name == "nt" else absolute
    files = set()
    for directory, _, names in os.walk(walk_root):
        for name in names:
            physical = str(Path(directory) / name)
            if os.name == "nt" and physical.startswith("\\\\?\\"):
                physical = physical[4:]
            files.add(Path(physical).relative_to(root).as_posix())
    return files


def _long_path(path: Path) -> str:
    absolute = str(path.resolve())
    return f"\\\\?\\{absolute}" if os.name == "nt" else absolute


def _remove_windows_write_deny(path: Path) -> None:
    if os.name != "nt":
        return
    identity = subprocess.run(["whoami"], check=True, capture_output=True, text=True).stdout.strip()
    subprocess.run(
        ["icacls", str(path), "/remove:d", identity, "/T", "/C", "/Q"],
        check=False,
        capture_output=True,
        text=True,
    )


def _build(
    repo: Path,
    *,
    command: list[str],
    run_name: str = "milestone1_repair1",
    additional_artifact_paths: tuple[Path, ...] = (),
):
    from unified_autoresearch.evidence_package import build_milestone1_repair1

    return build_milestone1_repair1(
        repo_root=repo,
        run_root=repo / "runs" / "unified_autoresearch" / run_name,
        snapshot_parent=repo / "runs" / "unified_autoresearch_audits",
        test_command=command,
        code_paths=[repo / "src" / "unified_autoresearch"],
        configuration_paths=[repo / "src" / "unified_autoresearch" / "protocols"],
        dependency_paths=[repo / "requirements-cpu.txt", repo / "setup.cfg"],
        data_manifest_paths=[
            repo / "src" / "unified_autoresearch" / "selection" / "basins.json",
            repo / "src" / "fair_benchmark" / "frozen" / "track0_forcing_only_basins.txt",
            repo / "src" / "fair_benchmark" / "frozen" / "bundle" / "track0_statics.csv",
        ],
        random_seeds=[20260717],
        additional_artifact_paths=additional_artifact_paths,
    )


def test_failed_test_command_leaves_final_root_absent(tmp_path):
    repo = _fixture_repo(tmp_path)
    _, failing = _commands()

    with pytest.raises(subprocess.CalledProcessError) as error:
        _build(repo, command=failing)

    assert error.value.returncode == 7
    assert not (repo / "runs" / "unified_autoresearch" / "milestone1_repair1").exists()


def test_build_fingerprints_and_snapshots_additional_registered_run_artifacts(tmp_path):
    repo = _fixture_repo(tmp_path)
    passing, _ = _commands()
    registered_probe = repo / "runs" / "registered-probe"
    registered_probe.mkdir(parents=True)
    (registered_probe / "fingerprint.json").write_text('{"probe": true}\n', encoding="utf-8")
    (registered_probe / "registry.sqlite").write_bytes(b"synthetic-registered-probe")
    deep_file = registered_probe / "deep-checkpoint" / ("x" * 150) / "CHECKPOINT_VERIFIED.json"
    if os.name == "nt":
        os.makedirs(_long_path(deep_file.parent), exist_ok=True)
        with open(_long_path(deep_file), "xb") as stream:
            stream.write(b"deep-checkpoint-verification")
        assert len(str(deep_file)) > 260
    else:
        deep_file.parent.mkdir(parents=True)
        deep_file.write_bytes(b"deep-checkpoint-verification")

    result = _build(
        repo,
        command=passing,
        additional_artifact_paths=(registered_probe,),
    )

    fingerprint = json.loads(Path(result["run_root"]).joinpath("fingerprint.json").read_text(encoding="utf-8"))
    artifact_paths = {entry["path"] for entry in fingerprint["details"]["artifacts"]}
    expected = {
        (registered_probe.relative_to(repo) / relative).as_posix()
        for relative in _physical_files_long_path_safe(registered_probe)
    }
    assert expected <= artifact_paths
    snapshot = Path(result["snapshot_root"])
    assert all(os.path.isfile(_long_path(snapshot / path)) for path in expected)


def test_build_seals_real_registry_artifact_root_and_readonly_snapshot(tmp_path):
    from unified_autoresearch.registry.fingerprint import validate_fingerprint
    from unified_autoresearch.registry.store import Registry

    repo = _fixture_repo(tmp_path)
    passing, _ = _commands()
    result = _build(repo, command=passing)
    run_root = Path(result["run_root"])
    snapshot = Path(result["snapshot_root"])

    fingerprint = json.loads((run_root / "fingerprint.json").read_text(encoding="utf-8"))
    validate_fingerprint(fingerprint)
    assert fingerprint["root_sha256"] == result["root_sha256"]

    artifact_root = run_root / "artifacts"
    actual_artifacts = {
        path.relative_to(repo).as_posix()
        for path in artifact_root.rglob("*")
        if path.is_file()
    }
    recorded_artifacts = {entry["path"] for entry in fingerprint["details"]["artifacts"]}
    assert recorded_artifacts == actual_artifacts
    assert any(path.endswith("nested/unlisted-output.bin") for path in recorded_artifacts)

    assert hashlib.sha256((artifact_root / "git-diff.bin").read_bytes()).hexdigest() == (
        fingerprint["details"]["uncommitted_diff"]["git_diff_sha256"]
    )
    assert hashlib.sha256((artifact_root / "git-status.bin").read_bytes()).hexdigest() == (
        fingerprint["details"]["uncommitted_diff"]["git_status_sha256"]
    )

    registry = Registry(
        run_root / "registry" / "registry.sqlite",
        scheduler_lock_path=run_root / "registry" / "scheduler.lock",
        receipt_dir=run_root / "registry" / "receipts",
    )
    assert registry.verify() == {"record_count": 8, "failure_count": 0, "failures": []}
    assert len(list((run_root / "registry" / "receipts").glob("*.json"))) == 8
    states = [json.loads(row["payload_json"]) for row in registry.records(record_type="state")]
    protected = [state for state in states if state["to_state"] in {"running", "succeeded"}]
    assert all(state["scheduler_lock"]["lock_path"] == str(registry.scheduler_lock_path) for state in protected)
    assert not registry.scheduler_lock_path.exists()

    snapshot_metadata = json.loads((snapshot / "SNAPSHOT.json").read_text(encoding="utf-8"))
    assert snapshot.name == f"m1_repair1_{result['root_sha256'][:16]}_clean"
    assert snapshot_metadata["fingerprint_root_sha256"] == result["root_sha256"]

    manifest_lines = (snapshot / "SNAPSHOT_MANIFEST.sha256").read_text(encoding="utf-8").splitlines()
    manifest_paths = {line.split(" *", 1)[1] for line in manifest_lines}
    physical_files = _physical_files_long_path_safe(snapshot)
    receipt_paths = {path for path in physical_files if "/registry/receipts/" in path}
    if os.name == "nt":
        assert receipt_paths
        assert all(len(str(snapshot / path)) > 260 for path in receipt_paths)
    assert manifest_paths == physical_files - {"SNAPSHOT_MANIFEST.sha256"}
    for line in manifest_lines:
        expected, relative = line.split(" *", 1)
        with open(_long_path(snapshot / relative), "rb") as stream:
            assert hashlib.sha256(stream.read()).hexdigest() == expected

    assert all(not (os.stat(_long_path(snapshot / relative)).st_mode & 0o222) for relative in physical_files)

    registry_hash = hashlib.sha256((run_root / "registry" / "registry.sqlite").read_bytes()).hexdigest()
    with pytest.raises(FileExistsError):
        _build(repo, command=passing)
    assert hashlib.sha256((run_root / "registry" / "registry.sqlite").read_bytes()).hexdigest() == registry_hash

    probes = [snapshot / "write-probe.tmp", snapshot / "src" / "unified_autoresearch" / "write-probe.tmp"]
    denied_probes = []
    try:
        for probe in probes:
            try:
                descriptor = os.open(_long_path(probe), os.O_WRONLY | os.O_CREAT | os.O_EXCL)
            except PermissionError:
                denied_probes.append(probe)
            else:
                os.close(descriptor)
                os.unlink(_long_path(probe))
    finally:
        _remove_windows_write_deny(snapshot)
    assert denied_probes == probes


def test_next_repair_round_has_distinct_registry_and_snapshot_identity(tmp_path):
    repo = _fixture_repo(tmp_path)
    passing, _ = _commands()

    result = _build(repo, command=passing, run_name="milestone1_repair2")

    run_root = Path(result["run_root"])
    snapshot = Path(result["snapshot_root"])
    metadata = json.loads((run_root / "RUN_METADATA.json").read_text(encoding="utf-8"))
    with sqlite3.connect(run_root / "registry" / "registry.sqlite") as connection:
        subjects = {row[0] for row in connection.execute("SELECT subject_id FROM records")}
    assert snapshot.name == f"m1_repair2_{result['root_sha256'][:16]}_clean"
    assert metadata["repair_round"] == "milestone1_repair2"
    assert any("milestone1-repair2" in subject for subject in subjects)


def test_milestone2_evidence_metadata_uses_milestone2_identity(tmp_path):
    repo = _fixture_repo(tmp_path)
    passing, _ = _commands()

    result = _build(repo, command=passing, run_name="milestone2_round1")

    metadata = json.loads((Path(result["run_root"]) / "RUN_METADATA.json").read_text(encoding="utf-8"))
    assert metadata["schema_version"] == "milestone2_evidence_run_v1"
    assert metadata["milestone"] == "milestone2"
    assert metadata["repair_round"] == "milestone2_round1"


def test_package_manifest_covers_receipts_under_a_deep_run_root(tmp_path):
    from unified_autoresearch.evidence_package import write_package_manifest

    repo = tmp_path / ("deep-" + "x" * 90)
    run_root = repo / "runs" / "unified_autoresearch" / "milestone1_repair3"
    receipt_dir = run_root / "registry" / "receipts"
    os.makedirs(_long_path(receipt_dir), exist_ok=True)
    for sequence in range(1, 9):
        receipt = receipt_dir / f"{sequence:020d}.{'a' * 32}.json"
        with open(_long_path(receipt), "wb") as stream:
            stream.write(f"receipt-{sequence}\n".encode("ascii"))
    with open(_long_path(run_root / "registry" / "registry.sqlite"), "wb") as stream:
        stream.write(b"registry")

    physical_before = _physical_files_long_path_safe(run_root)
    if os.name == "nt":
        receipt_paths = {path for path in physical_before if "/receipts/" in path}
        assert len(receipt_paths) == 8
        assert all(len(str(run_root / path)) > 260 for path in receipt_paths)

    manifest_path = write_package_manifest(repo_root=repo, run_root=run_root)
    with open(_long_path(manifest_path), "r", encoding="utf-8") as stream:
        manifest_paths = {line.split(" *", 1)[1] for line in stream.read().splitlines()}
    physical_after = _physical_files_long_path_safe(run_root)
    assert manifest_paths == {
        (run_root / relative).relative_to(repo).as_posix()
        for relative in physical_after - {"PACKAGE_MANIFEST.sha256"}
    }
