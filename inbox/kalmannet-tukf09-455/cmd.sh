#!/bin/bash
# Independent read-only post-publication audit of source capsule v2. This
# command does not submit a job, mutate a file, train, predict, score, or read
# any formal-evaluation array.
set -euo pipefail
umask 077

CAPSULE_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v2_20260901
V1_PENDING_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_training_source_capsule_v1_20260901.pending.seq43
V2R3_PROJECT_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r3_20260901/bundle/kalmannet
RAW_MANIFEST="${V2R3_PROJECT_ROOT}/artifacts/tukf09_455_basin_zero_validation_target_variance_revision_v1/preflight/raw_source_manifest.sha256.json"
POPULATION_REGISTRY="${V2R3_PROJECT_ROOT}/artifacts/tukf09_455_basin_zero_validation_target_variance_revision_v1/preflight/population_registry.json"
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
COMMAND_SHA256="$(sha256sum "${BASH_SOURCE[0]}" | awk '{print $1}')"
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1

[[ -x "${PYTHON}" ]] || { echo "FATAL: bootstrap Python is unavailable" >&2; exit 1; }
[[ -d "${CAPSULE_ROOT}" && ! -L "${CAPSULE_ROOT}" ]] || { echo "FATAL: capsule root is absent or linked" >&2; exit 1; }
[[ -f "${RAW_MANIFEST}" && ! -L "${RAW_MANIFEST}" ]] || { echo "FATAL: raw manifest is absent or linked" >&2; exit 1; }
[[ -f "${POPULATION_REGISTRY}" && ! -L "${POPULATION_REGISTRY}" ]] || { echo "FATAL: population registry is absent or linked" >&2; exit 1; }
FILESYSTEM_TYPE="$(stat --file-system --format=%T -- "${CAPSULE_ROOT}")"
[[ "${FILESYSTEM_TYPE}" == nfs* ]] || { echo "FATAL: capsule is not on NFS: ${FILESYSTEM_TYPE}" >&2; exit 1; }
echo "FILESYSTEM_TYPE=${FILESYSTEM_TYPE}"

"${PYTHON}" -B - "${CAPSULE_ROOT}" "${V1_PENDING_ROOT}" "${RAW_MANIFEST}" "${POPULATION_REGISTRY}" "${COMMAND_SHA256}" <<'PY'
from __future__ import annotations

from hashlib import sha256
import json
import os
from pathlib import Path, PurePosixPath
import stat
import sys
from typing import Any

capsule_root = Path(sys.argv[1])
v1_pending_root = Path(sys.argv[2])
raw_manifest_path = Path(sys.argv[3])
population_registry_path = Path(sys.argv[4])
audit_command_sha256 = sys.argv[5]
data_root = capsule_root / "data" / "camels_us"
manifest_path = capsule_root / "evidence" / "source_capsule_manifest.json"
manifest_sha_path = capsule_root / "evidence" / "source_capsule_manifest.sha256"
ready_path = capsule_root / "evidence" / "READY.json"

EXPECTED_MANIFEST_SIZE = 569601
EXPECTED_MANIFEST_SHA = "d5de91725d0da93f3aa4a234f5c103131fad8ef4b3c86f919236b9e42a318547"
EXPECTED_SHA_RECORD_SIZE = 95
EXPECTED_SHA_RECORD_SHA = "8725143e54efbb47aa73b8c960efee73aaf28fee85f54d331784d0373106ec69"
EXPECTED_READY_SIZE = 1236
EXPECTED_READY_SHA = "10331991ee26049554a3d18682c907bfb343877311ca053ac696ccfa1c6a8b93"
EXPECTED_DATA_COUNT = 911
EXPECTED_EVIDENCE_COUNT = 3
EXPECTED_TOTAL_FILE_COUNT = 914
EXPECTED_DIRECTORY_COUNT = 44
EXPECTED_DATA_TOTAL_BYTES = 464792200
EXPECTED_TREE_TOTAL_BYTES = 465363132
EXPECTED_DATA_IDENTITY = "dd238eebc1696f73f9eee7adf924913ff5a912c8f795f8998255e87408b760da"
EXPECTED_RAW_SIZE = 159995
EXPECTED_RAW_SHA = "a8b68a43490d5192e2f9340a40aae56c95cfc77037e81bf559ac887a21bbae0d"
EXPECTED_RAW_AGGREGATE = "970ac27630a46ef7c72308fd9f57ec51c6861d48a56fd250efe5eeb0176c0729"
EXPECTED_PARENT_RAW_SHA = "85ee1210f09f6665ad92b877105d3c68d79f53189938488bfc3edcbc23939903"
EXPECTED_POPULATION_SIZE = 35088
EXPECTED_POPULATION_SHA = "38d5d11851a4a46df8456065fa75d052f76723705f603afb26534121236b00df"
EXPECTED_BASIN_SHA = "38987bce45fa38ff68f5b067db17e8cb3212d98fecdd106f57d268a130ee8fbd"
EXPECTED_TOPOGRAPHY = "camels_attributes_v2.0/camels_topo.txt"
EXPECTED_TOPOGRAPHY_SIZE = 38677
EXPECTED_TOPOGRAPHY_SHA = "b64ca9923bcaccf21dde33137903797919e8d6732edd7849f8534e0ddcbec8e8"
ZERO_KEYS = (
    "formal_evaluation_array_reads",
    "formal_evaluation_predictions",
    "formal_evaluation_metrics",
    "formal_evaluation_outputs",
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def signature(info: os.stat_result) -> tuple[int, ...]:
    return (
        info.st_dev,
        info.st_ino,
        info.st_mode,
        info.st_nlink,
        info.st_size,
        info.st_mtime_ns,
        info.st_ctime_ns,
    )


def direct_directory(path: Path, label: str) -> os.stat_result:
    info = os.lstat(path)
    require(not stat.S_ISLNK(info.st_mode) and stat.S_ISDIR(info.st_mode), f"{label} is linked or non-directory: {path}")
    require(stat.S_IMODE(info.st_mode) == 0o555, f"{label} mode changed: {path}")
    return info


def direct_file(path: Path, label: str, mode: int | None = 0o444) -> os.stat_result:
    info = os.lstat(path)
    require(not stat.S_ISLNK(info.st_mode) and stat.S_ISREG(info.st_mode) and info.st_nlink == 1, f"{label} is linked, irregular, or multiply linked: {path}")
    if mode is not None:
        require(stat.S_IMODE(info.st_mode) == mode, f"{label} mode changed: {path}")
    return info


def digest_stable(path: Path, label: str, size: int, expected: str, mode: int | None = 0o444) -> tuple[os.stat_result, str]:
    before = direct_file(path, label, mode)
    require(before.st_size == size, f"{label} size changed: {path}")
    value = sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(4 * 1024 * 1024), b""):
            value.update(block)
    after = direct_file(path, label + " after read", mode)
    require(signature(before) == signature(after), f"{label} changed while read: {path}")
    actual = value.hexdigest()
    require(actual == expected, f"{label} SHA-256 changed: {path}")
    return after, actual


def read_json_verified(path: Path, label: str, size: int, expected: str, mode: int | None = 0o444) -> tuple[dict[str, Any], bytes]:
    digest_stable(path, label, size, expected, mode)
    before = os.lstat(path)
    raw = path.read_bytes()
    after = os.lstat(path)
    require(signature(before) == signature(after) and len(raw) == size and sha256(raw).hexdigest() == expected, f"{label} changed during JSON read")
    value = json.loads(raw)
    require(isinstance(value, dict), f"{label} is not a JSON object")
    return value, raw


require(len(audit_command_sha256) == 64 and all(c in "0123456789abcdef" for c in audit_command_sha256), "audit command SHA-256 is invalid")
root_before = direct_directory(capsule_root, "capsule root")
direct_directory(data_root, "capsule data root")
direct_directory(capsule_root / "evidence", "capsule evidence root")

manifest, manifest_bytes = read_json_verified(manifest_path, "capsule manifest", EXPECTED_MANIFEST_SIZE, EXPECTED_MANIFEST_SHA)
ready, ready_bytes = read_json_verified(ready_path, "capsule READY", EXPECTED_READY_SIZE, EXPECTED_READY_SHA)
sha_record_info, _ = digest_stable(manifest_sha_path, "manifest SHA record", EXPECTED_SHA_RECORD_SIZE, EXPECTED_SHA_RECORD_SHA)
require(manifest_sha_path.read_bytes() == (EXPECTED_MANIFEST_SHA + "  source_capsule_manifest.json\n").encode("ascii"), "manifest SHA record text changed")
raw_manifest, raw_bytes = read_json_verified(raw_manifest_path, "frozen raw manifest", EXPECTED_RAW_SIZE, EXPECTED_RAW_SHA, None)
population, population_bytes = read_json_verified(population_registry_path, "frozen population registry", EXPECTED_POPULATION_SIZE, EXPECTED_POPULATION_SHA, None)

manifest_expected = {
    "schema_version": "tukf09_455_training_source_capsule_v2",
    "purpose": "read_only_training_validation_source_only_no_formal_evaluation",
    "raw_source_manifest_relative_path": "artifacts/tukf09_455_basin_zero_validation_target_variance_revision_v1/preflight/raw_source_manifest.sha256.json",
    "raw_source_manifest_size": EXPECTED_RAW_SIZE,
    "raw_source_manifest_sha256": EXPECTED_RAW_SHA,
    "source_capsule_v1_pending_root": os.fspath(v1_pending_root),
    "source_capsule_v1_manifest_size": 626974,
    "source_capsule_v1_manifest_sha256": "2b0347a897dfadfa46d89e6c6643669deba9bbf681a4ba5e71cb891e09a710e2",
    "source_capsule_v1_forensics_mailbox_sequence": 44,
    "source_capsule_v1_forensics_result_commit": "d0763cc84443825f4c850607104567c8881a4bbb",
    "source_capsule_v1_forensics_result_size": 1086,
    "source_capsule_v1_forensics_result_sha256": "01cbb87426d3faae7c1dee70cc1692aea961862669720f2a9cf2394399d2e9db",
    "capsule_deployment_mailbox_sequence": 45,
    "capsule_deployment_command_sha256": "5956de9ae96f5db93b0e86d69f0b2ce26394c59931e08acde890c0620bbf3cd9",
    "capsule_root": os.fspath(capsule_root),
    "capsule_data_root": os.fspath(data_root),
    "ordered_basin_count": 455,
    "file_count": EXPECTED_DATA_COUNT,
    "total_bytes": EXPECTED_DATA_TOTAL_BYTES,
    "data_identity_sha256": EXPECTED_DATA_IDENTITY,
    "copy_mode": "python_exclusive_buffered_ordinary_byte_copy_with_fsync",
    "publication_mode": "exclusive_root_reservation_then_exact_ready_json_then_root_mode_0555_final_gate",
    "destination_symbolic_link_count": 0,
    "destination_hard_link_count_above_one": 0,
}
for key, expected in manifest_expected.items():
    require(manifest.get(key) == expected, f"manifest field changed: {key}")
expected_science = {
    "scientific_contract": {"path": "configs/tukf09_455_basin_zero_validation_target_variance_revision_v1.json", "sha256": "7710594dcc5cce7f087cb70492a6f827c3925a98ea7fa051d26c5ef1660304e1"},
    "formal_training_execution": {"path": "configs/tukf09_455_basin_zero_validation_target_variance_formal_training_execution_v1.json", "sha256": "0daf464f6bb1cfc11f04806b7caf5195ea42c3aef8187d8248474993ca108319"},
    "independent_preflight_final_manifest": {"path": "artifacts/tukf09_455_basin_zero_validation_target_variance_revision_v1/preflight/independent/manifest.final.sha256.json", "sha256": "f7e0a3f0708d0498cbaeaa77a044687f20d017ffa316170cd4770fc920b144aa"},
    "filter_migration_final_manifest": {"path": "artifacts/tukf09_455_basin_zero_validation_target_variance_revision_v1/filter_migration_v1/independent/manifest.final.sha256.json", "sha256": "029521f6c35980ce40fb0afeb14e2734042734c73f6ed0a33a5c0040311c3eb5"},
    "all_scope_authorization": {"path": "artifacts/tukf09_455_basin_zero_validation_target_variance_revision_v1/authorizations/all_scope_authorization.json", "sha256": "941ed64cb5d1c60e5525188e431bff69645d0b215e54d3939d5510ae63d2fb97"},
    "original_training_admission": {"path": "artifacts/tukf09_455_basin_zero_validation_target_variance_revision_v1/training_admission/training_admission.json", "file_sha256": "6ba3cdd742fc2bdf039c51afc75485c8292f0b999d7fe426cb2ccf69057c1b79", "record_sha256": "ca43f2ba9e35b47c76808da925508e75770bc00a37f2a89ba1dcf060017531b4"},
    "local_filter_installation_final_manifest": {"path": "results/tukf09_455_basin_zero_validation_target_variance_revision_v1/control/filter_rebinding/independent/manifest.final.sha256.json", "sha256": "b378ffbfde4d24ded8fbb42fdf10fef59eb04100c93879a41b4d538ae36f6ba0"},
    "ordered_basin_count": 455,
    "ordered_basin_newline_sha256": EXPECTED_BASIN_SHA,
    "ordered_basin_compact_json_sha256": "75ef2cee206fb15ee3f31ae0bbfcf594661c5ccdda0b28de9ff65634332c8902",
    "excluded_basins": ["08202700"],
}
require(manifest.get("scientific_identity") == expected_science, "capsule scientific identity changed")

ready_expected = {
    "schema_version": "tukf09_455_training_source_capsule_ready_v2",
    "status": "READY",
    "capsule_root": os.fspath(capsule_root),
    "capsule_data_root": os.fspath(data_root),
    "manifest_relative_path": "evidence/source_capsule_manifest.json",
    "manifest_size": EXPECTED_MANIFEST_SIZE,
    "manifest_sha256": EXPECTED_MANIFEST_SHA,
    "data_file_count": EXPECTED_DATA_COUNT,
    "data_total_bytes": EXPECTED_DATA_TOTAL_BYTES,
    "data_identity_sha256": EXPECTED_DATA_IDENTITY,
    "deployment_mailbox_sequence": 45,
    "deployment_command_sha256": "5956de9ae96f5db93b0e86d69f0b2ce26394c59931e08acde890c0620bbf3cd9",
    "validity_gate": "exact_ready_json_and_manifest_and_911_files_and_all_directories_mode_0555",
    "required_capsule_root_mode": "0555",
    "required_all_directory_mode": "0555",
    "required_all_file_mode": "0444",
}
for key, expected in ready_expected.items():
    require(ready.get(key) == expected, f"READY field changed: {key}")
for label, document in (("manifest", manifest), ("READY", ready)):
    for key in ZERO_KEYS:
        require(type(document.get(key)) is int and document[key] == 0, f"{label} evaluation count changed: {key}")

require(raw_manifest.get("schema_version") == "tukf09_455_basin_inherited_raw_source_manifest_v1", "raw manifest schema changed")
require(raw_manifest.get("experiment_id") == "TUKF09_455_BASIN_ZERO_VALIDATION_TARGET_VARIANCE_REVISION_V1", "raw manifest experiment changed")
require(raw_manifest.get("file_count") == 1020, "raw manifest file count changed")
require(raw_manifest.get("aggregate_sha256") == EXPECTED_RAW_AGGREGATE, "raw manifest aggregate changed")
require(raw_manifest.get("derived_from_parent_file_sha256") == EXPECTED_PARENT_RAW_SHA, "raw manifest parent binding changed")
raw_files = raw_manifest.get("files")
require(isinstance(raw_files, dict) and len(raw_files) == 1020, "raw manifest records changed")
eligible = population.get("eligible")
require(isinstance(eligible, list) and len(eligible) == 455 and len(set(eligible)) == 455, "population registry eligible list changed")
require(population.get("eligible_ordered_newline_utf8_sha256") == EXPECTED_BASIN_SHA, "population registry recorded basin hash changed")
require(sha256("".join(f"{basin}\n" for basin in eligible).encode("ascii")).hexdigest() == EXPECTED_BASIN_SHA, "population registry ordered basin bytes changed")
require(population.get("eligible_compact_json_sha256") == "75ef2cee206fb15ee3f31ae0bbfcf594661c5ccdda0b28de9ff65634332c8902", "population registry compact basin hash changed")
require(population.get("validation_metric_undefined") == ["08202700"] and "08202700" not in eligible, "zero-variance basin exclusion changed")

rows = manifest.get("files")
require(isinstance(rows, list) and len(rows) == EXPECTED_DATA_COUNT, "capsule manifest records changed")
records: dict[str, dict[str, Any]] = {}
forcing_basins: set[str] = set()
streamflow_basins: set[str] = set()
raw_bound = 0
topography_bound = 0
for record in rows:
    require(isinstance(record, dict), "capsule record is not an object")
    relative = record.get("relative_path")
    size = record.get("size_bytes")
    value = record.get("sha256")
    require(isinstance(relative, str) and relative, "capsule path is invalid")
    pure = PurePosixPath(relative)
    require(not pure.is_absolute() and ".." not in pure.parts and "\\" not in relative and pure.as_posix() == relative and relative not in records, f"unsafe or duplicate capsule path: {relative}")
    require(type(size) is int and size > 0, f"invalid capsule size: {relative}")
    require(isinstance(value, str) and len(value) == 64 and all(c in "0123456789abcdef" for c in value), f"invalid capsule SHA: {relative}")
    expected_source = v1_pending_root / "data" / "camels_us"
    expected_source = expected_source.joinpath(*pure.parts)
    require(record.get("source_path") == os.fspath(expected_source), f"v1 source binding changed: {relative}")
    if relative == EXPECTED_TOPOGRAPHY:
        require(size == EXPECTED_TOPOGRAPHY_SIZE and value == EXPECTED_TOPOGRAPHY_SHA, "topography identity changed")
        topography_bound += 1
    else:
        raw = raw_files.get(relative)
        require(isinstance(raw, dict) and raw.get("size_bytes") == size and raw.get("sha256") == value, f"raw binding changed: {relative}")
        raw_bound += 1
        name = pure.name
        if relative.startswith("basin_mean_forcing/maurer/") and name.endswith("_lump_maurer_forcing_leap.txt"):
            forcing_basins.add(name.split("_", 1)[0])
        elif relative.startswith("usgs_streamflow/") and name.endswith("_streamflow_qc.txt"):
            streamflow_basins.add(name.split("_", 1)[0])
        else:
            raise RuntimeError(f"unexpected capsule data class: {relative}")
    records[relative] = record
require([row["relative_path"] for row in rows] == sorted(records), "capsule record order changed")
require(raw_bound == 910 and topography_bound == 1, "raw or topography binding count changed")
require(forcing_basins == streamflow_basins and len(forcing_basins) == 455, "forcing and streamflow basin populations differ")
require(set(eligible) == forcing_basins, "capsule basin set differs from the frozen ordered population")
identity_rows = [{"relative_path": name, "size_bytes": records[name]["size_bytes"], "sha256": records[name]["sha256"]} for name in sorted(records)]
identity = sha256(json.dumps(identity_rows, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()
require(identity == EXPECTED_DATA_IDENTITY, "capsule data identity changed")

actual_files: dict[str, os.stat_result] = {}
actual_directories: set[str] = set()
symbolic_links = 0
hard_links = 0
for directory, names, filenames in os.walk(capsule_root, topdown=True, followlinks=False):
    directory_path = Path(directory)
    direct_directory(directory_path, "capsule directory")
    actual_directories.add("." if directory_path == capsule_root else directory_path.relative_to(capsule_root).as_posix())
    for name in names:
        info = os.lstat(directory_path / name)
        if stat.S_ISLNK(info.st_mode):
            symbolic_links += 1
        else:
            require(stat.S_ISDIR(info.st_mode), f"non-directory in directory position: {directory_path / name}")
    for name in filenames:
        path = directory_path / name
        info = os.lstat(path)
        if stat.S_ISLNK(info.st_mode):
            symbolic_links += 1
            continue
        if stat.S_ISREG(info.st_mode) and info.st_nlink > 1:
            hard_links += 1
        actual_files[path.relative_to(capsule_root).as_posix()] = direct_file(path, "capsule file")
require(symbolic_links == 0 and hard_links == 0, "capsule contains symbolic or multiple hard links")
expected_files = {f"data/camels_us/{name}" for name in records}
expected_files.update({"evidence/source_capsule_manifest.json", "evidence/source_capsule_manifest.sha256", "evidence/READY.json"})
require(set(actual_files) == expected_files and len(actual_files) == EXPECTED_TOTAL_FILE_COUNT, "capsule file surface changed")
expected_directories = {".", "data", "data/camels_us", "evidence"}
for relative in records:
    cursor = PurePosixPath("data/camels_us") / PurePosixPath(relative)
    for parent in cursor.parents:
        if parent == PurePosixPath("."):
            break
        expected_directories.add(parent.as_posix())
require(actual_directories == expected_directories and len(actual_directories) == EXPECTED_DIRECTORY_COUNT, "capsule directory surface changed")

data_total = 0
for relative, record in sorted(records.items()):
    path = data_root.joinpath(*PurePosixPath(relative).parts)
    info, _ = digest_stable(path, "capsule data file", record["size_bytes"], record["sha256"])
    require(info.st_dev == record.get("destination_device") and info.st_ino == record.get("destination_inode"), f"destination inode changed: {relative}")
    data_total += info.st_size
require(data_total == EXPECTED_DATA_TOTAL_BYTES, "capsule data byte total changed")
tree_total = sum(info.st_size for info in actual_files.values())
require(tree_total == EXPECTED_TREE_TOTAL_BYTES, "capsule tree byte total changed")
root_after = direct_directory(capsule_root, "capsule root after audit")
require(root_before.st_dev == root_after.st_dev and root_before.st_ino == root_after.st_ino and root_before.st_mtime_ns == root_after.st_mtime_ns, "capsule root changed during audit")

summary = {
    "audit_command_sha256": audit_command_sha256,
    "capsule_root": os.fspath(capsule_root),
    "data_file_count": EXPECTED_DATA_COUNT,
    "evidence_file_count": EXPECTED_EVIDENCE_COUNT,
    "total_file_count": EXPECTED_TOTAL_FILE_COUNT,
    "directory_count": EXPECTED_DIRECTORY_COUNT,
    "data_total_bytes": data_total,
    "tree_total_bytes": tree_total,
    "data_identity_sha256": identity,
    "manifest_size": len(manifest_bytes),
    "manifest_sha256": EXPECTED_MANIFEST_SHA,
    "manifest_sha_record_size": sha_record_info.st_size,
    "manifest_sha_record_sha256": EXPECTED_SHA_RECORD_SHA,
    "ready_size": len(ready_bytes),
    "ready_sha256": EXPECTED_READY_SHA,
    "raw_source_manifest_size": len(raw_bytes),
    "raw_source_manifest_sha256": EXPECTED_RAW_SHA,
    "population_registry_size": len(population_bytes),
    "population_registry_sha256": EXPECTED_POPULATION_SHA,
    "raw_manifest_bound_file_count": raw_bound,
    "topography_bound_file_count": topography_bound,
    "ordered_basin_count": len(forcing_basins),
    "ordered_basin_newline_sha256": EXPECTED_BASIN_SHA,
    "symbolic_link_count": symbolic_links,
    "hard_link_count_above_one": hard_links,
    "formal_evaluation_array_reads": 0,
    "formal_evaluation_predictions": 0,
    "formal_evaluation_metrics": 0,
    "formal_evaluation_outputs": 0,
}
print("SUMMARY=" + json.dumps(summary, ensure_ascii=False, sort_keys=True))
print("CAPSULE_ROOT=" + os.fspath(capsule_root))
print("CAPSULE_DATA_FILE_COUNT=911")
print("CAPSULE_EVIDENCE_FILE_COUNT=3")
print("CAPSULE_TOTAL_FILE_COUNT=914")
print("CAPSULE_DIRECTORY_COUNT=44")
print("CAPSULE_DATA_TOTAL_BYTES=464792200")
print("CAPSULE_TREE_TOTAL_BYTES=465363132")
print("CAPSULE_DATA_IDENTITY_SHA256=" + identity)
print("CAPSULE_MANIFEST_SIZE=569601")
print("CAPSULE_MANIFEST_SHA256=" + EXPECTED_MANIFEST_SHA)
print("CAPSULE_MANIFEST_SHA_RECORD_SIZE=95")
print("CAPSULE_MANIFEST_SHA_RECORD_SHA256=" + EXPECTED_SHA_RECORD_SHA)
print("CAPSULE_READY_SIZE=1236")
print("CAPSULE_READY_SHA256=" + EXPECTED_READY_SHA)
print("ORIGINAL_RAW_MANIFEST_SIZE=159995")
print("ORIGINAL_RAW_MANIFEST_SHA256=" + EXPECTED_RAW_SHA)
print("ORIGINAL_RAW_MANIFEST_BOUND_FILE_COUNT=910")
print("POPULATION_REGISTRY_SIZE=35088")
print("POPULATION_REGISTRY_SHA256=" + EXPECTED_POPULATION_SHA)
print("TOPOGRAPHY_BOUND_FILE_COUNT=1")
print("ORDERED_BASIN_COUNT=455")
print("ORDERED_BASIN_NEWLINE_SHA256=" + EXPECTED_BASIN_SHA)
print("CAPSULE_SYMBOLIC_LINK_COUNT=0")
print("CAPSULE_HARD_LINK_COUNT_ABOVE_ONE=0")
print("FORMAL_EVALUATION_ARRAY_READS=0")
print("FORMAL_EVALUATION_PREDICTIONS=0")
print("FORMAL_EVALUATION_METRICS=0")
print("FORMAL_EVALUATION_OUTPUTS=0")
print("AUDIT_COMMAND_SHA256=" + audit_command_sha256)
print("TUKF09_455_TRAINING_SOURCE_CAPSULE_V2_POST_PUBLICATION_READ_ONLY_AUDIT_911_OF_911_PASS")
PY
