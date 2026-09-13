"""Build deterministic, immutable stage-A/B training packages without loading data."""
from __future__ import annotations

import argparse
import csv
import gzip
import hashlib
import io
import json
import os
import re
import tarfile
from pathlib import Path, PurePosixPath

from study_config import make_combos, remote_stage_root, validate_stage


HERE = Path(__file__).resolve().parent
PREVIOUS = HERE.parent / "wrr_finalist_replication_20260907"
SOURCE_ARCHIVE = PREVIOUS / "payload" / "replication.tar.gz"
SOURCE_EXTERNAL_MANIFEST = PREVIOUS / "PACKAGE_MANIFEST.json"
SOURCE_ARCHIVE_SHA256 = "266eab5e5f2b21b992d218aaede11abc6018c11a23c3c5c28a328bd5210a497e"
SOURCE_EXTERNAL_MANIFEST_SHA256 = "8e9aa0c3769c050c070c6f48f1faa41aab94994f1a0791e89e35b92a44a8181e"
BASE_CONFIG_SHA256 = "de3cdb625d849370ea6fcc8c911d2d62f0e5cdea16e9ac371e9d16cbe388dd64"
ORIGINAL_LAUNCHER_SHA256 = "c71621dca168a9f7a2b8c87e3f3d8a5bce392037c58ef6bbc1123c6cb09c2626"
EXPECTED_RUNTIME_SHA256 = "28be078ba0f5e2bd3a5db30669ef95b044e592e8dd8f090a7736d5aaf7e2c296"

EXPERIMENT_REL = "experiments/optimize_hyper_parameters/wrr_hp_extension_20260902"
BASE_CONFIG_MEMBER = f"repo/{EXPERIMENT_REL}/base_config.yaml"
ORIGINAL_LAUNCHER_MEMBER = f"repo/{EXPERIMENT_REL}/run_one_cell.py"
COMBOS_MEMBER = f"repo/{EXPERIMENT_REL}/combos.jsonl"
REGISTRY_MEMBER = f"repo/{EXPERIMENT_REL}/registry.csv"
SOURCE_MANIFEST_MEMBER = f"repo/{EXPERIMENT_REL}/source_manifest.json"
REPLACED_REPO_MEMBERS = {COMBOS_MEMBER, REGISTRY_MEMBER, SOURCE_MANIFEST_MEMBER}


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def canonical_json(value: object) -> bytes:
    return (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")


def _safe_member_name(name: str) -> str:
    if not isinstance(name, str) or not name or "\\" in name or re.match(r"^[A-Za-z]:", name):
        raise RuntimeError(f"unsafe archive member: {name!r}")
    if name.startswith("/") or any(part in ("", ".", "..") for part in name.split("/")):
        raise RuntimeError(f"unsafe archive member: {name!r}")
    pure = PurePosixPath(name)
    if pure.is_absolute():
        raise RuntimeError(f"unsafe archive member: {name!r}")
    return pure.as_posix()


def read_safe_tar_bytes(archive_bytes: bytes) -> dict[str, bytes]:
    files: dict[str, bytes] = {}
    seen: set[str] = set()
    try:
        with tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:gz") as archive:
            for member in archive.getmembers():
                name = _safe_member_name(member.name.rstrip("/") if member.isdir() else member.name)
                if name in seen:
                    raise RuntimeError(f"duplicate archive member: {name}")
                seen.add(name)
                if member.isdir():
                    continue
                if not member.isfile():
                    raise RuntimeError(f"archive may contain regular files and directories only: {name}")
                stream = archive.extractfile(member)
                if stream is None:
                    raise RuntimeError(f"unable to read archive member: {name}")
                files[name] = stream.read()
    except (tarfile.TarError, OSError) as exc:
        raise RuntimeError(f"invalid source archive: {exc}") from exc
    return files


def validate_static_files(files: dict[str, bytes], manifest: dict) -> None:
    expected = manifest.get("static_files")
    if not isinstance(expected, dict) or not expected:
        raise RuntimeError("external manifest has no static_files")
    if set(files) != set(expected):
        missing = sorted(set(expected) - set(files))
        extra = sorted(set(files) - set(expected))
        raise RuntimeError(f"static member set mismatch: missing={missing}, extra={extra}")
    for name, expected_hash in expected.items():
        _safe_member_name(name)
        actual = sha256_bytes(files[name])
        if actual != expected_hash:
            raise RuntimeError(f"static SHA-256 mismatch for {name}: expected {expected_hash}, got {actual}")


def validate_inner_source_hashes(files: dict[str, bytes], source_manifest: dict) -> None:
    expected = source_manifest.get("source_sha256")
    if not isinstance(expected, dict) or not expected:
        raise RuntimeError("inner source manifest has no source_sha256")
    expected_members = {f"repo/{rel}" for rel in expected}
    actual_members = {name for name in files if name.startswith("repo/") and name != SOURCE_MANIFEST_MEMBER}
    if actual_members != expected_members:
        missing = sorted(expected_members - actual_members)
        extra = sorted(actual_members - expected_members)
        raise RuntimeError(f"inner source member set mismatch: missing={missing}, extra={extra}")
    for rel, expected_hash in expected.items():
        _safe_member_name(rel)
        member = f"repo/{rel}"
        actual = sha256_bytes(files[member])
        if actual != expected_hash:
            raise RuntimeError(f"inner source SHA-256 mismatch for {rel}: expected {expected_hash}, got {actual}")


def load_and_validate_source_package(
    archive_path: Path = SOURCE_ARCHIVE,
    external_manifest_path: Path = SOURCE_EXTERNAL_MANIFEST,
) -> tuple[dict[str, bytes], dict]:
    if sha256_path(archive_path) != SOURCE_ARCHIVE_SHA256:
        raise RuntimeError("source archive SHA-256 mismatch")
    if sha256_path(external_manifest_path) != SOURCE_EXTERNAL_MANIFEST_SHA256:
        raise RuntimeError("source external manifest SHA-256 mismatch")
    manifest = json.loads(external_manifest_path.read_text(encoding="utf-8"))
    archive_bytes = archive_path.read_bytes()
    archive_control = manifest.get("archive", {})
    if archive_control.get("sha256") != SOURCE_ARCHIVE_SHA256 or archive_control.get("size_bytes") != len(archive_bytes):
        raise RuntimeError("source external manifest archive identity mismatch")
    files = read_safe_tar_bytes(archive_bytes)
    validate_static_files(files, manifest)
    packaged = manifest.get("packaged_source_manifest", {})
    if packaged.get("path") != SOURCE_MANIFEST_MEMBER:
        raise RuntimeError("source manifest path mismatch")
    if sha256_bytes(files[SOURCE_MANIFEST_MEMBER]) != packaged.get("sha256"):
        raise RuntimeError("source manifest SHA-256 mismatch")
    source_manifest = json.loads(files[SOURCE_MANIFEST_MEMBER])
    validate_inner_source_hashes(files, source_manifest)
    if sha256_bytes(files[BASE_CONFIG_MEMBER]) != BASE_CONFIG_SHA256:
        raise RuntimeError("base configuration SHA-256 mismatch")
    if sha256_bytes(files[ORIGINAL_LAUNCHER_MEMBER]) != ORIGINAL_LAUNCHER_SHA256:
        raise RuntimeError("original launcher SHA-256 mismatch")
    if sha256_bytes(files["expected_runtime.json"]) != EXPECTED_RUNTIME_SHA256:
        raise RuntimeError("expected runtime SHA-256 mismatch")
    return files, manifest


def combos_bytes(stage: str) -> bytes:
    lines = [json.dumps(row, sort_keys=True, separators=(",", ":")) for row in make_combos(stage)]
    return ("\n".join(lines) + "\n").encode("utf-8")


def registry_bytes(stage: str) -> bytes:
    output = io.StringIO(newline="")
    fields = (
        "run_id", "index", "role", "initial_learning_rate", "hidden_size", "num_layers",
        "in_out_mult", "seed", "effective_seed", "stage", "status",
    )
    writer = csv.DictWriter(output, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    for row in make_combos(stage):
        writer.writerow(
            {
                "run_id": row["run_id"],
                "index": row["index"],
                "role": row["role"],
                "initial_learning_rate": row["lr"],
                "hidden_size": row["hidden_size"],
                "num_layers": row["num_layers"],
                "in_out_mult": row["in_out_mult"],
                "seed": row["seed"],
                "effective_seed": row["effective_seed"],
                "stage": row["stage"],
                "status": "planned",
            }
        )
    return output.getvalue().encode("utf-8")


def _stage_source_manifest(original_bytes: bytes, stage: str, combos: bytes, registry: bytes) -> bytes:
    manifest = json.loads(original_bytes)
    replacements = {
        f"{EXPERIMENT_REL}/combos.jsonl": sha256_bytes(combos),
        f"{EXPERIMENT_REL}/registry.csv": sha256_bytes(registry),
    }
    for rel, new_hash in replacements.items():
        if rel not in manifest.get("source_sha256", {}):
            raise RuntimeError(f"replaceable source entry missing: {rel}")
        manifest["source_sha256"][rel] = new_hash
        if rel in manifest.get("overlay_sha256", {}):
            manifest["overlay_sha256"][rel] = new_hash
    manifest["built_at"] = "2026-09-08T00:00:00+08:00"
    manifest["derived_from_archive_sha256"] = SOURCE_ARCHIVE_SHA256
    manifest["derived_from_external_manifest_sha256"] = SOURCE_EXTERNAL_MANIFEST_SHA256
    manifest["model_selection_stage"] = stage
    manifest["notes"] = [
        "All archived repository numerical and base-configuration bytes are unchanged.",
        f"Only combos.jsonl, registry.csv, and this derived bookkeeping are replaced for stage {stage}.",
    ]
    return canonical_json(manifest)


def _deterministic_tar_gz(files: dict[str, bytes]) -> bytes:
    raw = io.BytesIO()
    with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w", format=tarfile.PAX_FORMAT) as archive:
            for name in sorted(files):
                _safe_member_name(name)
                info = tarfile.TarInfo(name)
                info.size = len(files[name])
                info.mtime = 0
                info.uid = info.gid = 0
                info.uname = info.gname = ""
                info.mode = 0o755 if name.endswith((".py", ".slurm", ".sh")) else 0o644
                archive.addfile(info, io.BytesIO(files[name]))
    return raw.getvalue()


def build_archive_bytes(stage: str) -> tuple[bytes, dict]:
    stage = validate_stage(stage)
    original, previous_manifest = load_and_validate_source_package()
    files = {name: data for name, data in original.items() if name.startswith("repo/")}
    combos = combos_bytes(stage)
    registry = registry_bytes(stage)
    files[COMBOS_MEMBER] = combos
    files[REGISTRY_MEMBER] = registry
    files[SOURCE_MANIFEST_MEMBER] = _stage_source_manifest(original[SOURCE_MANIFEST_MEMBER], stage, combos, registry)
    files["study_config.py"] = (HERE / "study_config.py").read_bytes()
    files["launch_once.py"] = (HERE / "launch_once.py").read_bytes()
    files["hpc_array.slurm"] = (HERE / f"hpc_stage_{stage}.slurm").read_bytes()
    files["expected_runtime.json"] = original["expected_runtime.json"]

    stage_source_manifest = json.loads(files[SOURCE_MANIFEST_MEMBER])
    validate_inner_source_hashes(files, stage_source_manifest)
    if sha256_bytes(files[BASE_CONFIG_MEMBER]) != BASE_CONFIG_SHA256:
        raise RuntimeError("base configuration changed during transformation")
    if sha256_bytes(files[ORIGINAL_LAUNCHER_MEMBER]) != ORIGINAL_LAUNCHER_SHA256:
        raise RuntimeError("original launcher changed during transformation")
    archive = _deterministic_tar_gz(files)
    static_files = {name: sha256_bytes(data) for name, data in sorted(files.items())}
    repo_count = len([name for name in original if name.startswith("repo/")])
    rows = make_combos(stage)
    manifest = {
        "schema_version": 1,
        "study": "neural_gain_model_selection",
        "stage": stage,
        "remote_family_root": remote_stage_root(stage).rsplit("/stages/", 1)[0],
        "remote_root": remote_stage_root(stage),
        "candidate_count": len(rows),
        "allowed_indices": list(range(len(rows))),
        "archive": {
            "relative_path": f"payload/stage_{stage}.tar.gz",
            "sha256": sha256_bytes(archive),
            "size_bytes": len(archive),
            "members_are_relative_to_stage_root": True,
        },
        "static_files": static_files,
        "packaged_source_manifest": {
            "path": SOURCE_MANIFEST_MEMBER,
            "sha256": static_files[SOURCE_MANIFEST_MEMBER],
        },
        "expected_runtime": {
            "path": "expected_runtime.json",
            "sha256": static_files["expected_runtime.json"],
            "provenance": "Exact bytes of expected_runtime.json from the validated source archive.",
        },
        "source_baseline": {
            "archive_path": str(SOURCE_ARCHIVE).replace("\\", "/"),
            "archive_sha256": SOURCE_ARCHIVE_SHA256,
            "external_manifest_path": str(SOURCE_EXTERNAL_MANIFEST).replace("\\", "/"),
            "external_manifest_sha256": SOURCE_EXTERNAL_MANIFEST_SHA256,
            "previous_packaged_source_manifest_sha256": previous_manifest["packaged_source_manifest"]["sha256"],
            "base_config_path": BASE_CONFIG_MEMBER,
            "base_config_sha256": BASE_CONFIG_SHA256,
            "original_launcher_path": ORIGINAL_LAUNCHER_MEMBER,
            "original_launcher_sha256": ORIGINAL_LAUNCHER_SHA256,
        },
        "source_preservation": {
            "original_repo_files": repo_count,
            "unchanged_repo_files": repo_count - len(REPLACED_REPO_MEMBERS),
            "replaced_metadata_members": sorted(REPLACED_REPO_MEMBERS),
        },
        "held_out_test_data_included": False,
        "training_performed_by_builder": False,
    }
    return archive, manifest


def _approved_outputs() -> set[Path]:
    return {
        (HERE / "payload" / "stage_A.tar.gz").resolve(),
        (HERE / "payload" / "stage_B.tar.gz").resolve(),
        (HERE / "STAGE_A_MANIFEST.json").resolve(),
        (HERE / "STAGE_B_MANIFEST.json").resolve(),
    }


def write_once_or_same(path: Path, data: bytes, *, allowed_paths: set[Path] | None = None) -> str:
    allowed = {candidate.resolve() for candidate in (allowed_paths if allowed_paths is not None else _approved_outputs())}
    resolved = path.resolve()
    if resolved not in allowed:
        raise RuntimeError(f"path is not an approved output: {path}")
    if os.path.lexists(path) and (path.is_symlink() or not path.is_file()):
        raise FileExistsError(f"refusing non-regular existing artifact: {path}")
    try:
        with path.open("xb") as stream:
            stream.write(data)
        return "created"
    except FileExistsError:
        if path.is_file() and not path.is_symlink() and path.read_bytes() == data:
            return "identical"
        raise FileExistsError(f"refusing to replace existing artifact with different bytes: {path}")


def _ensure_payload_directory() -> None:
    payload = HERE / "payload"
    if os.path.lexists(payload):
        if payload.is_symlink() or not payload.is_dir():
            raise RuntimeError("payload path must be a real directory")
    else:
        payload.mkdir()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--stage", choices=("A", "B", "both"), default="both")
    args = parser.parse_args()
    stages = ("A", "B") if args.stage == "both" else (args.stage,)
    built: list[tuple[str, bytes, dict]] = []
    for stage in stages:
        first_archive, first_manifest = build_archive_bytes(stage)
        second_archive, second_manifest = build_archive_bytes(stage)
        if first_archive != second_archive or first_manifest != second_manifest:
            raise RuntimeError(f"deterministic second build mismatch for stage {stage}")
        built.append((stage, first_archive, first_manifest))
    _ensure_payload_directory()
    results = []
    for stage, archive, manifest in built:
        archive_path = HERE / "payload" / f"stage_{stage}.tar.gz"
        manifest_path = HERE / f"STAGE_{stage}_MANIFEST.json"
        archive_status = write_once_or_same(archive_path, archive)
        manifest_status = write_once_or_same(manifest_path, canonical_json(manifest))
        results.append(
            {
                "stage": stage,
                "archive": str(archive_path),
                "sha256": manifest["archive"]["sha256"],
                "size_bytes": len(archive),
                "members": len(manifest["static_files"]),
                "archive_status": archive_status,
                "manifest_status": manifest_status,
            }
        )
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()

