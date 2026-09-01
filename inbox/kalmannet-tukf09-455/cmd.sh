#!/bin/bash
# Publish a new read-only 911-file source capsule under an exclusively created
# root. Exact READY.json plus root mode 0555 is the validity gate on this NFS;
# changing the root from 0700 to 0555 is the final atomic publication step.
# The preserved v1 pending capsule is read only; no job or evaluation is run.
set -eo pipefail
umask 077

V1_PENDING=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v1_20260901.pending.seq43
V1_DATA="${V1_PENDING}/data/camels_us"
V1_MANIFEST="${V1_PENDING}/evidence/source_capsule_manifest.json"
V2_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v2_20260901
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
COMMAND_SHA256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1

[[ -d "${V1_PENDING}" && ! -L "${V1_PENDING}" ]] || { echo "FATAL: preserved v1 pending root is absent or linked" >&2; exit 1; }
[[ -d "${V1_DATA}" && ! -L "${V1_DATA}" ]] || { echo "FATAL: preserved v1 data root is absent or linked" >&2; exit 1; }
[[ -f "${V1_MANIFEST}" && ! -L "${V1_MANIFEST}" ]] || { echo "FATAL: preserved v1 manifest is absent or linked" >&2; exit 1; }
[[ ! -e "${V2_ROOT}" && ! -L "${V2_ROOT}" ]] || { echo "FATAL: v2 capsule root already exists" >&2; exit 1; }
[[ -x "${PYTHON}" ]] || { echo "FATAL: bootstrap Python is unavailable" >&2; exit 1; }

"${PYTHON}" -B - "${V1_PENDING}" "${V1_DATA}" "${V1_MANIFEST}" "${V2_ROOT}" "${COMMAND_SHA256}" <<'PY'
from __future__ import annotations

from hashlib import sha256
import json
import os
from pathlib import Path
import stat
import sys

source_capsule_root = Path(sys.argv[1])
source_data_root = Path(sys.argv[2])
source_manifest_path = Path(sys.argv[3])
capsule_root = Path(sys.argv[4])
command_sha256 = sys.argv[5]
data_relative = Path("data/camels_us")
evidence_relative = Path("evidence")
data_root = capsule_root / data_relative
evidence_root = capsule_root / evidence_relative
manifest_relative = evidence_relative / "source_capsule_manifest.json"
manifest_sha_relative = evidence_relative / "source_capsule_manifest.sha256"
ready_relative = evidence_relative / "READY.json"

expected_v1_manifest_size = 626974
expected_v1_manifest_sha = "2b0347a897dfadfa46d89e6c6643669deba9bbf681a4ba5e71cb891e09a710e2"
expected_data_identity_sha = "dd238eebc1696f73f9eee7adf924913ff5a912c8f795f8998255e87408b760da"
if len(command_sha256) != 64 or any(character not in "0123456789abcdef" for character in command_sha256):
    raise RuntimeError("mailbox command SHA-256 is invalid")

def require_absent(path: Path, *, label: str) -> None:
    try:
        os.lstat(path)
    except FileNotFoundError:
        return
    raise RuntimeError(f"{label} already exists: {path}")

def direct_directory(path: Path, *, label: str, mode: int | None = None) -> os.stat_result:
    info = os.lstat(path)
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise RuntimeError(f"{label} is linked or non-directory: {path}")
    if mode is not None and stat.S_IMODE(info.st_mode) != mode:
        raise RuntimeError(f"{label} mode is not {oct(mode)}: {path}")
    return info

def direct_file(path: Path, *, label: str, mode: int | None = None) -> os.stat_result:
    info = os.lstat(path)
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        raise RuntimeError(f"{label} is linked, non-regular, or multiply linked: {path}")
    if mode is not None and stat.S_IMODE(info.st_mode) != mode:
        raise RuntimeError(f"{label} mode is not {oct(mode)}: {path}")
    return info

def digest(path: Path) -> str:
    value = sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(4 * 1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()

def fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)

def fsync_file(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)

def exclusive_write(path: Path, payload: bytes) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags, 0o600)
    try:
        with os.fdopen(descriptor, "wb", closefd=False) as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
    finally:
        os.close(descriptor)

def copy_verified(source: Path, destination: Path, *, size: int, expected_sha: str) -> dict[str, object]:
    before = direct_file(source, label="v1 source file", mode=0o444)
    if before.st_size != size or digest(source) != expected_sha:
        raise RuntimeError(f"v1 source file differs: {source}")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(destination, flags, 0o600)
    copied = 0
    try:
        with source.open("rb") as input_handle, os.fdopen(descriptor, "wb", closefd=False) as output_handle:
            for block in iter(lambda: input_handle.read(4 * 1024 * 1024), b""):
                output_handle.write(block)
                copied += len(block)
            output_handle.flush()
            os.fsync(output_handle.fileno())
    finally:
        os.close(descriptor)
    after = direct_file(source, label="v1 source file after copy", mode=0o444)
    if (
        before.st_dev != after.st_dev
        or before.st_ino != after.st_ino
        or before.st_size != after.st_size
        or before.st_mtime_ns != after.st_mtime_ns
    ):
        raise RuntimeError(f"v1 source file changed while copying: {source}")
    destination_info = direct_file(destination, label="v2 capsule file", mode=0o600)
    if copied != size or destination_info.st_size != size or digest(destination) != expected_sha:
        raise RuntimeError(f"v2 capsule file differs after copy: {destination}")
    if before.st_dev == destination_info.st_dev and before.st_ino == destination_info.st_ino:
        raise RuntimeError(f"v2 capsule file aliases v1 source: {destination}")
    os.chmod(destination, 0o444)
    fsync_file(destination)
    return {
        "source_device": before.st_dev,
        "source_inode": before.st_ino,
        "source_mtime_ns": before.st_mtime_ns,
        "destination_device": destination_info.st_dev,
        "destination_inode": destination_info.st_ino,
    }

require_absent(capsule_root, label="v2 capsule root")
direct_directory(source_capsule_root, label="preserved v1 pending root", mode=0o555)
direct_directory(source_data_root, label="preserved v1 data root", mode=0o555)
source_manifest_info = direct_file(source_manifest_path, label="preserved v1 manifest", mode=0o444)
source_manifest_bytes = source_manifest_path.read_bytes()
if source_manifest_info.st_size != expected_v1_manifest_size or sha256(source_manifest_bytes).hexdigest() != expected_v1_manifest_sha:
    raise RuntimeError("preserved v1 manifest differs from sequence 44 evidence")
source_manifest = json.loads(source_manifest_bytes)
if (
    source_manifest.get("schema_version") != "tukf09_455_training_source_capsule_v1"
    or source_manifest.get("file_count") != 911
    or source_manifest.get("total_bytes") != 464792200
    or source_manifest.get("data_identity_sha256") != expected_data_identity_sha
):
    raise RuntimeError("preserved v1 manifest identity differs")
source_records = source_manifest.get("files")
if not isinstance(source_records, list) or len(source_records) != 911:
    raise RuntimeError("preserved v1 manifest file records differ")

records: dict[str, dict[str, object]] = {}
for record in source_records:
    if not isinstance(record, dict):
        raise RuntimeError("v1 file record is not an object")
    relative = str(record.get("relative_path", ""))
    parts = Path(relative).parts
    if not relative or Path(relative).is_absolute() or ".." in parts or relative in records:
        raise RuntimeError(f"unsafe or duplicate v1 path: {relative}")
    records[relative] = record

# os.mkdir is an atomic no-clobber reservation on this NFS. The root remains
# invalid until the exact READY.json and read-only modes pass every gate below.
os.mkdir(capsule_root, 0o700)
os.makedirs(data_root, mode=0o700, exist_ok=False)
os.mkdir(evidence_root, 0o700)

file_records: list[dict[str, object]] = []
copied_total = 0
for relative, record in sorted(records.items()):
    expected_size = int(record["size_bytes"])
    expected_sha = str(record["sha256"])
    source = source_data_root.joinpath(*relative.split("/"))
    destination = data_root.joinpath(*relative.split("/"))
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    provenance = copy_verified(source, destination, size=expected_size, expected_sha=expected_sha)
    copied_total += expected_size
    file_records.append({
        "relative_path": relative,
        "size_bytes": expected_size,
        "sha256": expected_sha,
        "source_path": str(source),
        **provenance,
    })
if len(file_records) != 911 or copied_total != 464792200:
    raise RuntimeError("v2 copied count or byte total differs")

identity_rows = [
    {"relative_path": row["relative_path"], "size_bytes": row["size_bytes"], "sha256": row["sha256"]}
    for row in file_records
]
identity_sha = sha256(
    json.dumps(identity_rows, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
).hexdigest()
if identity_sha != expected_data_identity_sha:
    raise RuntimeError("v2 data identity differs from v1 and sequence 44")

manifest = {
    "schema_version": "tukf09_455_training_source_capsule_v2",
    "purpose": "read_only_training_validation_source_only_no_formal_evaluation",
    "scientific_identity": source_manifest["scientific_identity"],
    "raw_source_manifest_relative_path": source_manifest["raw_source_manifest_relative_path"],
    "raw_source_manifest_size": source_manifest["raw_source_manifest_size"],
    "raw_source_manifest_sha256": source_manifest["raw_source_manifest_sha256"],
    "source_capsule_v1_pending_root": str(source_capsule_root),
    "source_capsule_v1_manifest_size": expected_v1_manifest_size,
    "source_capsule_v1_manifest_sha256": expected_v1_manifest_sha,
    "source_capsule_v1_forensics_mailbox_sequence": 44,
    "source_capsule_v1_forensics_result_commit": "d0763cc84443825f4c850607104567c8881a4bbb",
    "source_capsule_v1_forensics_result_size": 1086,
    "source_capsule_v1_forensics_result_sha256": "01cbb87426d3faae7c1dee70cc1692aea961862669720f2a9cf2394399d2e9db",
    "capsule_deployment_mailbox_sequence": 45,
    "capsule_deployment_command_sha256": command_sha256,
    "capsule_root": str(capsule_root),
    "capsule_data_root": str(data_root),
    "ordered_basin_count": 455,
    "file_count": 911,
    "total_bytes": copied_total,
    "data_identity_sha256": identity_sha,
    "copy_mode": "python_exclusive_buffered_ordinary_byte_copy_with_fsync",
    "publication_mode": "exclusive_root_reservation_then_exact_ready_json_then_root_mode_0555_final_gate",
    "destination_symbolic_link_count": 0,
    "destination_hard_link_count_above_one": 0,
    "formal_evaluation_array_reads": 0,
    "formal_evaluation_predictions": 0,
    "formal_evaluation_metrics": 0,
    "formal_evaluation_outputs": 0,
    "files": file_records,
}
manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
manifest_path = capsule_root / manifest_relative
manifest_sha_path = capsule_root / manifest_sha_relative
exclusive_write(manifest_path, manifest_bytes)
manifest_sha = sha256(manifest_bytes).hexdigest()
exclusive_write(manifest_sha_path, (manifest_sha + "  source_capsule_manifest.json\n").encode("ascii"))
os.chmod(manifest_path, 0o444)
os.chmod(manifest_sha_path, 0o444)
fsync_file(manifest_path)
fsync_file(manifest_sha_path)

# Verify the complete pre-publication surface before creating READY.json.
verified_total = 0
for relative, record in sorted(records.items()):
    path = data_root.joinpath(*relative.split("/"))
    info = direct_file(path, label="v2 pre-ready file", mode=0o444)
    expected_size = int(record["size_bytes"])
    expected_sha = str(record["sha256"])
    if info.st_size != expected_size or digest(path) != expected_sha:
        raise RuntimeError(f"v2 pre-ready file differs: {relative}")
    verified_total += info.st_size
if verified_total != 464792200:
    raise RuntimeError("v2 pre-ready byte total differs")

# Freeze every data directory before READY. The evidence directory and capsule
# root deliberately remain 0700, so no READY file can be valid until the final
# root-mode transition after its exact payload is durable.
pre_ready_directories = [
    Path(directory)
    for directory, _names, _files in os.walk(data_root, topdown=False, followlinks=False)
]
pre_ready_directories.append(data_root.parent)
for directory in pre_ready_directories:
    os.chmod(directory, 0o555)
    fsync_directory(directory)

ready = {
    "schema_version": "tukf09_455_training_source_capsule_ready_v2",
    "status": "READY",
    "capsule_root": str(capsule_root),
    "capsule_data_root": str(data_root),
    "manifest_relative_path": manifest_relative.as_posix(),
    "manifest_size": len(manifest_bytes),
    "manifest_sha256": manifest_sha,
    "data_file_count": 911,
    "data_total_bytes": verified_total,
    "data_identity_sha256": identity_sha,
    "deployment_mailbox_sequence": 45,
    "deployment_command_sha256": command_sha256,
    "validity_gate": "exact_ready_json_and_manifest_and_911_files_and_all_directories_mode_0555",
    "required_capsule_root_mode": "0555",
    "required_all_directory_mode": "0555",
    "required_all_file_mode": "0444",
    "formal_evaluation_array_reads": 0,
    "formal_evaluation_predictions": 0,
    "formal_evaluation_metrics": 0,
    "formal_evaluation_outputs": 0,
}
ready_bytes = (json.dumps(ready, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
ready_path = capsule_root / ready_relative
exclusive_write(ready_path, ready_bytes)
ready_sha = sha256(ready_bytes).hexdigest()
os.chmod(ready_path, 0o444)
fsync_file(ready_path)

# No content is written after READY. Freeze evidence, then change the capsule
# root to 0555 last; that last metadata transition is the publication instant.
os.chmod(evidence_root, 0o555)
fsync_directory(evidence_root)
os.chmod(capsule_root, 0o555)
fsync_directory(capsule_root)
fsync_directory(capsule_root.parent)

tree_files: list[Path] = []
tree_links: list[Path] = []
tree_directories: list[Path] = []
for directory, names, filenames in os.walk(capsule_root, topdown=True, followlinks=False):
    directory_path = Path(directory)
    direct_directory(directory_path, label="published v2 directory", mode=0o555)
    tree_directories.append(directory_path)
    for name in names:
        candidate = directory_path / name
        if stat.S_ISLNK(os.lstat(candidate).st_mode):
            tree_links.append(candidate)
    for name in filenames:
        candidate = directory_path / name
        info = os.lstat(candidate)
        if stat.S_ISLNK(info.st_mode):
            tree_links.append(candidate)
            continue
        direct_file(candidate, label="published v2 file", mode=0o444)
        tree_files.append(candidate)
if tree_links:
    raise RuntimeError(f"published v2 capsule contains links: {tree_links[:3]}")
expected_files = {
    (data_relative / Path(relative)).as_posix()
    for relative in records
}
expected_files.update({manifest_relative.as_posix(), manifest_sha_relative.as_posix(), ready_relative.as_posix()})
actual_files = {path.relative_to(capsule_root).as_posix() for path in tree_files}
if actual_files != expected_files:
    raise RuntimeError("published v2 surface is not exactly 911 data plus 3 evidence files")
expected_directories = {".", "data", "data/camels_us", "evidence"}
for relative in records:
    cursor = data_relative / Path(relative)
    for parent in cursor.parents:
        if parent == Path("."):
            break
        expected_directories.add(parent.as_posix())
actual_directories = {
    "." if path == capsule_root else path.relative_to(capsule_root).as_posix()
    for path in tree_directories
}
if actual_directories != expected_directories:
    raise RuntimeError("published v2 directory surface contains missing or extra directories")
if digest(manifest_path) != manifest_sha:
    raise RuntimeError("published v2 manifest changed")
if manifest_sha_path.read_text(encoding="ascii") != manifest_sha + "  source_capsule_manifest.json\n":
    raise RuntimeError("published v2 manifest hash record changed")
if ready_path.read_bytes() != ready_bytes or digest(ready_path) != ready_sha:
    raise RuntimeError("published v2 READY gate changed")

published_total = 0
for relative, record in sorted(records.items()):
    path = data_root.joinpath(*relative.split("/"))
    info = direct_file(path, label="published v2 data file", mode=0o444)
    if info.st_size != int(record["size_bytes"]) or digest(path) != str(record["sha256"]):
        raise RuntimeError(f"published v2 data file changed: {relative}")
    published_total += info.st_size
if published_total != 464792200:
    raise RuntimeError("published v2 byte total changed")

print("CAPSULE_ROOT=" + str(capsule_root))
print("CAPSULE_DATA_ROOT=" + str(data_root))
print("CAPSULE_DATA_FILE_COUNT=911")
print("CAPSULE_EVIDENCE_FILE_COUNT=3")
print("CAPSULE_TOTAL_BYTES=464792200")
print("CAPSULE_DATA_IDENTITY_SHA256=" + identity_sha)
print("CAPSULE_MANIFEST_SIZE=" + str(len(manifest_bytes)))
print("CAPSULE_MANIFEST_SHA256=" + manifest_sha)
print("CAPSULE_READY_SIZE=" + str(len(ready_bytes)))
print("CAPSULE_READY_SHA256=" + ready_sha)
print("CAPSULE_DEPLOYMENT_COMMAND_SHA256=" + command_sha256)
print("CAPSULE_DIRECTORY_COUNT=" + str(len(tree_directories)))
print("CAPSULE_SYMBOLIC_LINK_COUNT=0")
print("CAPSULE_HARD_LINK_COUNT_ABOVE_ONE=0")
print("FORMAL_EVALUATION_ARRAY_READS=0")
print("TUKF09_455_TRAINING_SOURCE_CAPSULE_V2_READY_911_OF_911_PASS")
PY
