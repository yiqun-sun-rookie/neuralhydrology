#!/bin/bash
# Read-only forensics for the source-capsule v1 publication failure. The
# complete pending tree is preserved; no scheduler, process, or data write.
set -eo pipefail
umask 077

CAPSULE_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v1_20260901
PENDING_ROOT="${CAPSULE_ROOT}.pending.seq43"
DATA_ROOT="${PENDING_ROOT}/data/camels_us"
MANIFEST="${PENDING_ROOT}/evidence/source_capsule_manifest.json"
MANIFEST_SHA_RECORD="${PENDING_ROOT}/evidence/source_capsule_manifest.sha256"
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1

[[ ! -e "${CAPSULE_ROOT}" && ! -L "${CAPSULE_ROOT}" ]] || { echo "FATAL: failed v1 final root unexpectedly exists" >&2; exit 1; }
[[ -d "${PENDING_ROOT}" && ! -L "${PENDING_ROOT}" ]] || { echo "FATAL: preserved v1 pending root is absent or linked" >&2; exit 1; }
[[ -x "${PYTHON}" ]] || { echo "FATAL: bootstrap Python is unavailable" >&2; exit 1; }

echo "FILESYSTEM_TYPE=$(stat -f -c '%T' "${PENDING_ROOT}")"
echo "PENDING_ROOT_BYTES=$(du -sb "${PENDING_ROOT}" | awk '{print $1}')"

"${PYTHON}" -B - "${PENDING_ROOT}" "${DATA_ROOT}" "${MANIFEST}" "${MANIFEST_SHA_RECORD}" <<'PY'
from __future__ import annotations

from hashlib import sha256
import json
import os
from pathlib import Path
import stat
import sys

pending_root = Path(sys.argv[1])
data_root = Path(sys.argv[2])
manifest_path = Path(sys.argv[3])
manifest_sha_record_path = Path(sys.argv[4])
expected_command_sha = "ee272c1b6e6b866c95740e27be3b668adbf6533bf0e08330b4ccc13b65eeaa44"
expected_result_43_sha = "edf53f26eabf50ac9a2a406558f80e44f4d5c9e768b467c5e47b31d7fdf5155e"

def direct_directory(path: Path) -> os.stat_result:
    info = os.lstat(path)
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        raise RuntimeError(f"directory is linked or non-directory: {path}")
    return info

def direct_file(path: Path) -> os.stat_result:
    info = os.lstat(path)
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        raise RuntimeError(f"file is linked, non-regular, or multiply linked: {path}")
    return info

def digest(path: Path) -> str:
    value = sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(4 * 1024 * 1024), b""):
            value.update(block)
    return value.hexdigest()

direct_directory(pending_root)
direct_directory(data_root)
manifest_info = direct_file(manifest_path)
manifest_sha_info = direct_file(manifest_sha_record_path)
manifest_bytes = manifest_path.read_bytes()
manifest_sha = sha256(manifest_bytes).hexdigest()
expected_record_text = manifest_sha + "  source_capsule_manifest.json\n"
if manifest_sha_record_path.read_text(encoding="ascii") != expected_record_text:
    raise RuntimeError("manifest SHA-256 record differs")
manifest = json.loads(manifest_bytes)

required_manifest_values = {
    "schema_version": "tukf09_455_training_source_capsule_v1",
    "purpose": "read_only_training_validation_source_only_no_formal_evaluation",
    "source_candidate_audit_mailbox_sequence": 42,
    "source_candidate_audit_result_commit": "a844f835dc6ec9531f784960652f98a925a671da",
    "source_candidate_audit_result_size": 1276,
    "source_candidate_audit_result_sha256": "dd019ad7461afa51d0f2553febade2cf296aad5fb471b26c771d56e5221ba65c",
    "capsule_deployment_mailbox_sequence": 43,
    "capsule_deployment_command_sha256": expected_command_sha,
    "ordered_basin_count": 455,
    "file_count": 911,
    "total_bytes": 464792200,
    "copy_mode": "python_exclusive_buffered_ordinary_byte_copy_with_fsync",
    "publication_mode": "linux_renameat2_rename_noreplace_after_complete_verification",
    "destination_symbolic_link_count": 0,
    "destination_hard_link_count_above_one": 0,
    "formal_evaluation_array_reads": 0,
    "formal_evaluation_predictions": 0,
    "formal_evaluation_metrics": 0,
    "formal_evaluation_outputs": 0,
}
for key, expected in required_manifest_values.items():
    if manifest.get(key) != expected:
        raise RuntimeError(f"manifest field differs: {key}")

records = manifest.get("files")
if not isinstance(records, list) or len(records) != 911:
    raise RuntimeError("manifest does not contain exactly 911 records")
record_by_relative: dict[str, dict[str, object]] = {}
for record in records:
    if not isinstance(record, dict):
        raise RuntimeError("manifest file record is not an object")
    relative = str(record.get("relative_path", ""))
    parts = Path(relative).parts
    if not relative or Path(relative).is_absolute() or ".." in parts or relative in record_by_relative:
        raise RuntimeError(f"unsafe or duplicate manifest path: {relative}")
    record_by_relative[relative] = record

tree_files: list[Path] = []
tree_links: list[Path] = []
tree_directories: list[Path] = []
for directory, names, filenames in os.walk(pending_root, topdown=True, followlinks=False):
    directory_path = Path(directory)
    info = direct_directory(directory_path)
    if stat.S_IMODE(info.st_mode) != 0o555:
        raise RuntimeError(f"pending directory mode is not 0555: {directory_path}")
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
        info = direct_file(candidate)
        if stat.S_IMODE(info.st_mode) != 0o444:
            raise RuntimeError(f"pending file mode is not 0444: {candidate}")
        tree_files.append(candidate)
if tree_links:
    raise RuntimeError(f"pending capsule contains links: {tree_links[:3]}")

expected_tree_files = {
    (Path("data/camels_us") / Path(relative)).as_posix()
    for relative in record_by_relative
}
expected_tree_files.update({
    "evidence/source_capsule_manifest.json",
    "evidence/source_capsule_manifest.sha256",
})
actual_tree_files = {path.relative_to(pending_root).as_posix() for path in tree_files}
if actual_tree_files != expected_tree_files:
    raise RuntimeError("pending capsule file surface differs from 911 data plus 2 evidence files")

verified_total = 0
identity_rows: list[dict[str, object]] = []
for relative, record in sorted(record_by_relative.items()):
    path = data_root.joinpath(*relative.split("/"))
    info = direct_file(path)
    expected_size = int(record["size_bytes"])
    expected_sha = str(record["sha256"])
    if info.st_size != expected_size or digest(path) != expected_sha:
        raise RuntimeError(f"pending capsule file differs: {relative}")
    verified_total += info.st_size
    identity_rows.append({"relative_path": relative, "size_bytes": expected_size, "sha256": expected_sha})
if verified_total != 464792200:
    raise RuntimeError("pending capsule byte total differs")
identity_sha = sha256(
    json.dumps(identity_rows, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
).hexdigest()
if manifest.get("data_identity_sha256") != identity_sha:
    raise RuntimeError("pending capsule data identity differs from its manifest")

summary = {
    "data_file_count": len(record_by_relative),
    "data_identity_sha256": identity_sha,
    "directory_count": len(tree_directories),
    "formal_evaluation_array_reads": 0,
    "formal_evaluation_metrics": 0,
    "formal_evaluation_outputs": 0,
    "formal_evaluation_predictions": 0,
    "manifest_sha256": manifest_sha,
    "manifest_size": manifest_info.st_size,
    "manifest_sha_record_size": manifest_sha_info.st_size,
    "pending_root": str(pending_root),
    "result_43_sha256": expected_result_43_sha,
    "symbolic_link_count": len(tree_links),
    "total_bytes": verified_total,
    "tree_file_count": len(tree_files),
}
print("SUMMARY=" + json.dumps(summary, ensure_ascii=False, sort_keys=True))
print("TUKF09_455_SOURCE_CAPSULE_V1_PENDING_911_OF_911_VERIFIED_PRESERVED_NO_RETRY")
PY
