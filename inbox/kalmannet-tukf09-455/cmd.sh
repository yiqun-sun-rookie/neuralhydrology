#!/bin/bash
# Materialize one new read-only 911-file training-source capsule from the sole
# byte-exact remote candidate. Existing data and experiment roots are read only.
# This command submits no job and never accesses formal-evaluation arrays.
set -eo pipefail
umask 077

V2R3_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r3_20260901
PROJECT_ROOT="${V2R3_ROOT}/bundle/kalmannet"
SOURCE_ROOT=/data1/home/sunyiq/adv531/data/camels_us
CAPSULE_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v1_20260901
PENDING_ROOT="${CAPSULE_ROOT}.pending.seq43"
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
COMMAND_SHA256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1

[[ -x "${PYTHON}" ]] || { echo "FATAL: bootstrap Python is unavailable" >&2; exit 1; }
[[ -d "${PROJECT_ROOT}" && ! -L "${PROJECT_ROOT}" ]] || { echo "FATAL: frozen v2r3 project is unavailable or linked" >&2; exit 1; }
[[ -d "${SOURCE_ROOT}" && ! -L "${SOURCE_ROOT}" ]] || { echo "FATAL: source root is unavailable or linked" >&2; exit 1; }
[[ ! -e "${CAPSULE_ROOT}" && ! -L "${CAPSULE_ROOT}" ]] || { echo "FATAL: final capsule root already exists" >&2; exit 1; }
[[ ! -e "${PENDING_ROOT}" && ! -L "${PENDING_ROOT}" ]] || { echo "FATAL: pending capsule root already exists" >&2; exit 1; }

"${PYTHON}" -B - "${PROJECT_ROOT}" "${SOURCE_ROOT}" "${PENDING_ROOT}" "${CAPSULE_ROOT}" "${COMMAND_SHA256}" <<'PY'
from __future__ import annotations

import ctypes
from hashlib import sha256
import importlib.util
import json
import os
from pathlib import Path
import stat
import sys

project = Path(sys.argv[1])
source_root = Path(sys.argv[2])
pending_root = Path(sys.argv[3])
final_root = Path(sys.argv[4])
command_sha256 = sys.argv[5]
if len(command_sha256) != 64 or any(character not in "0123456789abcdef" for character in command_sha256):
    raise RuntimeError("mailbox command SHA-256 is invalid")
data_relative = Path("data/camels_us")
evidence_relative = Path("evidence")
pending_data = pending_root / data_relative
pending_evidence = pending_root / evidence_relative
manifest_relative = evidence_relative / "source_capsule_manifest.json"
manifest_sha_relative = evidence_relative / "source_capsule_manifest.sha256"

stage_path = project / "hpc/tukf09_455_basin_revision_a800_exclusive_v2r3/stage_and_train.py"
spec = importlib.util.spec_from_file_location("tukf09_stage_v2r3_capsule", stage_path)
assert spec is not None and spec.loader is not None
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)
config = stage.load_execution_config()
basins, records = stage._expected_stage_records(
    project_root=project,
    source_root=source_root,
    config=config,
)
if len(basins) != 455 or len(records) != 911:
    raise RuntimeError("frozen source population is not 455 basins and 911 files")
raw_manifest_relative = str(config["data_staging"]["raw_source_manifest"])
raw_manifest_path = project.joinpath(*raw_manifest_relative.split("/"))
raw_manifest_info = os.lstat(raw_manifest_path)
if stat.S_ISLNK(raw_manifest_info.st_mode) or not stat.S_ISREG(raw_manifest_info.st_mode):
    raise RuntimeError("frozen raw source manifest is linked or non-regular")
raw_manifest_sha = stage.sha256_file(raw_manifest_path)

def require_absent(path: Path, *, label: str) -> None:
    try:
        os.lstat(path)
    except FileNotFoundError:
        return
    raise RuntimeError(f"{label} already exists: {path}")

def require_direct_directory(path: Path, *, label: str) -> os.stat_result:
    info = os.lstat(path)
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise RuntimeError(f"{label} is linked or not a directory: {path}")
    return info

def require_direct_regular(path: Path, *, label: str) -> os.stat_result:
    info = os.lstat(path)
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        raise RuntimeError(f"{label} is linked, non-regular, or multiply linked: {path}")
    return info

def fsync_directory(path: Path) -> None:
    descriptor = os.open(path, os.O_RDONLY | getattr(os, "O_DIRECTORY", 0))
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)

def rename_noreplace(source: Path, destination: Path) -> None:
    # login4 is x86_64 Linux. Use the renameat2 system call directly because
    # its old glibc may not export a wrapper; RENAME_NOREPLACE makes publication
    # atomically fail if any target appeared after the earlier absence checks.
    if os.name != "posix" or os.uname().machine != "x86_64":
        raise RuntimeError("atomic no-replace publication requires x86_64 Linux")
    libc = ctypes.CDLL(None, use_errno=True)
    syscall = libc.syscall
    syscall.restype = ctypes.c_long
    result = syscall(
        ctypes.c_long(316),
        ctypes.c_int(-100),
        ctypes.c_char_p(os.fsencode(source)),
        ctypes.c_int(-100),
        ctypes.c_char_p(os.fsencode(destination)),
        ctypes.c_uint(1),
    )
    if result != 0:
        error_number = ctypes.get_errno()
        raise OSError(error_number, os.strerror(error_number), str(destination))

def exclusive_write_bytes(path: Path, payload: bytes, *, mode: int = 0o600) -> None:
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    flags |= getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(path, flags, mode)
    try:
        with os.fdopen(descriptor, "wb", closefd=False) as handle:
            handle.write(payload)
            handle.flush()
            os.fsync(handle.fileno())
    finally:
        os.close(descriptor)

def copy_verified_bytes(source: Path, destination: Path, *, size: int, digest: str) -> dict[str, object]:
    before = require_direct_regular(source, label="resolved source file")
    actual_source_sha = stage.sha256_file(source)
    if before.st_size != size or actual_source_sha != digest:
        raise RuntimeError(f"source file differs from frozen manifest: {source}")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    flags |= getattr(os, "O_NOFOLLOW", 0)
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
    after = require_direct_regular(source, label="resolved source file after copy")
    if (
        before.st_dev != after.st_dev
        or before.st_ino != after.st_ino
        or before.st_size != after.st_size
        or before.st_mtime_ns != after.st_mtime_ns
    ):
        raise RuntimeError(f"source file changed during copy: {source}")
    destination_info = require_direct_regular(destination, label="capsule file")
    destination_sha = stage.sha256_file(destination)
    if copied != size or destination_info.st_size != size or destination_sha != digest:
        raise RuntimeError(f"capsule copy differs from frozen manifest: {destination}")
    if before.st_dev == destination_info.st_dev and before.st_ino == destination_info.st_ino:
        raise RuntimeError(f"capsule file aliases its source: {destination}")
    os.chmod(destination, 0o444)
    return {
        "source_device": before.st_dev,
        "source_inode": before.st_ino,
        "source_mode": stat.filemode(before.st_mode),
        "source_mtime_ns": before.st_mtime_ns,
        "destination_device": destination_info.st_dev,
        "destination_inode": destination_info.st_ino,
    }

require_absent(final_root, label="final capsule root")
require_absent(pending_root, label="pending capsule root")
source_root_info = require_direct_directory(source_root, label="candidate source root")
os.mkdir(pending_root, 0o700)
os.makedirs(pending_data, mode=0o700, exist_ok=False)
os.mkdir(pending_evidence, 0o700)

file_records: list[dict[str, object]] = []
source_route_resolutions = {
    name: str((source_root / name).resolve(strict=True))
    for name in ("basin_mean_forcing", "camels_attributes_v2.0", "usgs_streamflow")
}
expected_total_bytes = 0
for relative, expected in sorted(records.items()):
    expected_size = int(expected["size_bytes"])
    expected_sha = str(expected["sha256"])
    expected_total_bytes += expected_size
    routed_source = source_root.joinpath(*relative.split("/"))
    resolved_source = routed_source.resolve(strict=True)
    try:
        resolved_source.relative_to(Path("/data1/home/sunyiq"))
    except ValueError as error:
        raise RuntimeError(f"resolved source escapes the user-owned data tree: {resolved_source}") from error
    destination = pending_data.joinpath(*relative.split("/"))
    destination.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    provenance = copy_verified_bytes(
        resolved_source,
        destination,
        size=expected_size,
        digest=expected_sha,
    )
    file_records.append({
        "relative_path": relative,
        "size_bytes": expected_size,
        "sha256": expected_sha,
        "source_routed_path": str(routed_source),
        "source_resolved_path": str(resolved_source),
        **provenance,
    })

if expected_total_bytes != 464_792_200:
    raise RuntimeError("frozen 911-file byte total changed")

# Independently verify the complete materialized surface and ensure no extra
# data files or links entered the new capsule data root.
actual_files: list[Path] = []
actual_links: list[Path] = []
actual_directories: list[Path] = []
for directory, names, filenames in os.walk(pending_data, topdown=True, followlinks=False):
    directory_path = Path(directory)
    require_direct_directory(directory_path, label="capsule data directory")
    actual_directories.append(directory_path)
    for name in list(names):
        candidate = directory_path / name
        info = os.lstat(candidate)
        if stat.S_ISLNK(info.st_mode):
            actual_links.append(candidate)
    for name in filenames:
        candidate = directory_path / name
        info = os.lstat(candidate)
        if stat.S_ISLNK(info.st_mode):
            actual_links.append(candidate)
        else:
            actual_files.append(candidate)
if actual_links:
    raise RuntimeError(f"capsule contains links: {actual_links[:3]}")
if len(actual_files) != 911:
    raise RuntimeError(f"capsule data file count is {len(actual_files)}, not 911")

verified_total_bytes = 0
for relative, expected in sorted(records.items()):
    path = pending_data.joinpath(*relative.split("/"))
    info = require_direct_regular(path, label="final capsule verification file")
    digest = stage.sha256_file(path)
    expected_size = int(expected["size_bytes"])
    expected_sha = str(expected["sha256"])
    if info.st_size != expected_size or digest != expected_sha:
        raise RuntimeError(f"final capsule verification failed: {relative}")
    verified_total_bytes += info.st_size
if verified_total_bytes != 464_792_200:
    raise RuntimeError("verified capsule byte total changed")

identity_payload = [
    {"relative_path": row["relative_path"], "size_bytes": row["size_bytes"], "sha256": row["sha256"]}
    for row in file_records
]
identity_sha = sha256(
    json.dumps(identity_payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
).hexdigest()
manifest = {
    "schema_version": "tukf09_455_training_source_capsule_v1",
    "purpose": "read_only_training_validation_source_only_no_formal_evaluation",
    "scientific_identity": config["scientific_identity"],
    "raw_source_manifest_relative_path": raw_manifest_relative,
    "raw_source_manifest_size": raw_manifest_info.st_size,
    "raw_source_manifest_sha256": raw_manifest_sha,
    "source_candidate_audit_mailbox_sequence": 42,
    "source_candidate_audit_result_commit": "a844f835dc6ec9531f784960652f98a925a671da",
    "source_candidate_audit_result_size": 1276,
    "source_candidate_audit_result_sha256": "dd019ad7461afa51d0f2553febade2cf296aad5fb471b26c771d56e5221ba65c",
    "capsule_deployment_mailbox_sequence": 43,
    "capsule_deployment_command_sha256": command_sha256,
    "source_root": str(source_root),
    "source_root_device": source_root_info.st_dev,
    "source_root_inode": source_root_info.st_ino,
    "source_root_mode": stat.filemode(source_root_info.st_mode),
    "source_route_resolutions": source_route_resolutions,
    "capsule_root": str(final_root),
    "capsule_data_root": str(final_root / data_relative),
    "ordered_basin_count": len(basins),
    "file_count": len(file_records),
    "total_bytes": verified_total_bytes,
    "data_identity_sha256": identity_sha,
    "copy_mode": "python_exclusive_buffered_ordinary_byte_copy_with_fsync",
    "publication_mode": "linux_renameat2_rename_noreplace_after_complete_verification",
    "source_route_parent_links_were_materialized_as_direct_directories": True,
    "destination_symbolic_link_count": 0,
    "destination_hard_link_count_above_one": 0,
    "formal_evaluation_array_reads": 0,
    "formal_evaluation_predictions": 0,
    "formal_evaluation_metrics": 0,
    "formal_evaluation_outputs": 0,
    "files": file_records,
}
manifest_bytes = (json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
manifest_path = pending_root / manifest_relative
manifest_sha_path = pending_root / manifest_sha_relative
exclusive_write_bytes(manifest_path, manifest_bytes)
manifest_sha = sha256(manifest_bytes).hexdigest()
exclusive_write_bytes(manifest_sha_path, (manifest_sha + "  source_capsule_manifest.json\n").encode("ascii"))
os.chmod(manifest_path, 0o444)
os.chmod(manifest_sha_path, 0o444)

# Make every new directory read-only before publication, fsyncing children and
# parents bottom-up. The pre-existing source and experiment roots are untouched.
all_directories = [Path(directory) for directory, _names, _files in os.walk(pending_root, topdown=False, followlinks=False)]
for directory in all_directories:
    fsync_directory(directory)
    os.chmod(directory, 0o555)
fsync_directory(pending_root.parent)
require_absent(final_root, label="final capsule root immediately before publication")
rename_noreplace(pending_root, final_root)
fsync_directory(final_root.parent)

final_data = final_root / data_relative
final_manifest = final_root / manifest_relative
final_manifest_sha = final_root / manifest_sha_relative
require_direct_directory(final_root, label="published capsule root")
require_direct_directory(final_data, label="published capsule data root")
final_links: list[str] = []
final_data_files: list[str] = []
final_evidence_files: list[str] = []
for directory, names, filenames in os.walk(final_root, topdown=True, followlinks=False):
    directory_path = Path(directory)
    directory_info = require_direct_directory(directory_path, label="published capsule directory")
    if stat.S_IMODE(directory_info.st_mode) != 0o555:
        raise RuntimeError(f"published capsule directory is not read-only: {directory_path}")
    for name in names:
        candidate = directory_path / name
        if stat.S_ISLNK(os.lstat(candidate).st_mode):
            final_links.append(str(candidate))
    for name in filenames:
        candidate = directory_path / name
        info = os.lstat(candidate)
        if stat.S_ISLNK(info.st_mode):
            final_links.append(str(candidate))
            continue
        require_direct_regular(candidate, label="published capsule tree file")
        if stat.S_IMODE(info.st_mode) != 0o444:
            raise RuntimeError(f"published capsule file is not read-only: {candidate}")
        relative_to_final = candidate.relative_to(final_root)
        if relative_to_final.parts[:2] == ("data", "camels_us"):
            final_data_files.append(relative_to_final.as_posix())
        elif relative_to_final.parts[:1] == ("evidence",):
            final_evidence_files.append(relative_to_final.as_posix())
        else:
            raise RuntimeError(f"unexpected file outside data or evidence: {relative_to_final}")
if final_links:
    raise RuntimeError(f"published capsule contains links: {final_links[:3]}")
if len(final_data_files) != 911:
    raise RuntimeError(f"published capsule data file count is {len(final_data_files)}, not 911")
if sorted(final_evidence_files) != sorted([manifest_relative.as_posix(), manifest_sha_relative.as_posix()]):
    raise RuntimeError(f"published capsule evidence surface changed: {final_evidence_files}")
if stage.sha256_file(final_manifest) != manifest_sha:
    raise RuntimeError("published capsule manifest hash changed")
if final_manifest_sha.read_text(encoding="ascii") != manifest_sha + "  source_capsule_manifest.json\n":
    raise RuntimeError("published capsule manifest hash record changed")

published_total = 0
published_count = 0
for relative, expected in sorted(records.items()):
    path = final_data.joinpath(*relative.split("/"))
    info = require_direct_regular(path, label="published capsule file")
    if info.st_size != int(expected["size_bytes"]) or stage.sha256_file(path) != str(expected["sha256"]):
        raise RuntimeError(f"published capsule file changed: {relative}")
    published_count += 1
    published_total += info.st_size
if published_count != 911 or published_total != 464_792_200:
    raise RuntimeError("published capsule count or byte total changed")

print("CAPSULE_ROOT=" + str(final_root))
print("CAPSULE_DATA_ROOT=" + str(final_data))
print("CAPSULE_FILE_COUNT=911")
print("CAPSULE_TOTAL_BYTES=464792200")
print("CAPSULE_DATA_IDENTITY_SHA256=" + identity_sha)
print("CAPSULE_MANIFEST_SIZE=" + str(len(manifest_bytes)))
print("CAPSULE_MANIFEST_SHA256=" + manifest_sha)
print("CAPSULE_DEPLOYMENT_COMMAND_SHA256=" + command_sha256)
print("CAPSULE_SYMBOLIC_LINK_COUNT=0")
print("CAPSULE_HARD_LINK_COUNT_ABOVE_ONE=0")
print("FORMAL_EVALUATION_ARRAY_READS=0")
print("TUKF09_455_TRAINING_SOURCE_CAPSULE_V1_911_OF_911_PASS")
PY
