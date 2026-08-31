#!/bin/bash
# Read-only 911-file audit of the sole remote CAMELS-US candidate root whose
# three previously mismatching forcing files match the frozen source manifest.
# No scheduler submission, process control, write, or formal-evaluation access.
set -eo pipefail
umask 077

V2R3_ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r3_20260901
PROJECT_ROOT="${V2R3_ROOT}/bundle/kalmannet"
CANDIDATE_ROOT=/data1/home/sunyiq/adv531/data/camels_us
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1

[[ -x "${PYTHON}" ]] || { echo "FATAL: bootstrap Python is unavailable" >&2; exit 1; }
[[ -d "${PROJECT_ROOT}" && ! -L "${PROJECT_ROOT}" ]] || { echo "FATAL: frozen v2r3 project is unavailable or linked" >&2; exit 1; }
[[ -d "${CANDIDATE_ROOT}" && ! -L "${CANDIDATE_ROOT}" ]] || { echo "FATAL: candidate root is unavailable or linked" >&2; exit 1; }

"${PYTHON}" -B - "${PROJECT_ROOT}" "${CANDIDATE_ROOT}" <<'PY'
from __future__ import annotations

from collections import Counter
from hashlib import sha256
import importlib.util
import json
import os
from pathlib import Path
import stat
import sys

project = Path(sys.argv[1])
source = Path(sys.argv[2])
stage_path = project / "hpc/tukf09_455_basin_revision_a800_exclusive_v2r3/stage_and_train.py"
spec = importlib.util.spec_from_file_location("tukf09_stage_v2r3_candidate_audit", stage_path)
assert spec is not None and spec.loader is not None
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)
config = stage.load_execution_config()
basins, records = stage._expected_stage_records(
    project_root=project,
    source_root=source,
    config=config,
)
assert len(basins) == 455
assert len(records) == 911

root_info = os.lstat(source)
if stat.S_ISLNK(root_info.st_mode) or not stat.S_ISDIR(root_info.st_mode):
    raise RuntimeError("candidate root is not a direct directory")

# Every required parent below the candidate root must itself be a direct
# directory. This prevents a file from passing while traversing a linked route.
required_parents: set[Path] = set()
for relative in records:
    cursor = source
    for part in Path(relative).parts[:-1]:
        cursor = cursor / part
        required_parents.add(cursor)

irregular_parents: list[dict[str, object]] = []
for parent in sorted(required_parents, key=lambda value: str(value)):
    try:
        info = os.lstat(parent)
    except FileNotFoundError:
        irregular_parents.append({"path": str(parent), "reason": "missing"})
        continue
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
        irregular_parents.append({
            "path": str(parent),
            "reason": "linked_or_not_directory",
            "mode": stat.filemode(info.st_mode),
        })

mismatches: list[dict[str, object]] = []
exact_count = 0
actual_total_bytes = 0
expected_total_bytes = 0
kind_counts: Counter[str] = Counter()
for relative, expected in sorted(records.items()):
    expected_size = int(expected["size_bytes"])
    expected_sha = str(expected["sha256"])
    expected_total_bytes += expected_size
    path = source.joinpath(*relative.split("/"))
    row: dict[str, object] = {
        "path": relative,
        "expected_size": expected_size,
        "expected_sha256": expected_sha,
    }
    try:
        info = os.lstat(path)
    except FileNotFoundError:
        row["reason"] = "missing"
        kind_counts["missing"] += 1
        mismatches.append(row)
        continue
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        row.update({
            "reason": "irregular",
            "actual_size": info.st_size,
            "link_count": info.st_nlink,
            "mode": stat.filemode(info.st_mode),
        })
        kind_counts["irregular"] += 1
        mismatches.append(row)
        continue
    actual_size = info.st_size
    actual_sha = stage.sha256_file(path)
    actual_total_bytes += actual_size
    if actual_size == expected_size and actual_sha == expected_sha:
        exact_count += 1
        continue
    reason = "size_and_sha256" if actual_size != expected_size else "sha256_only"
    row.update({"reason": reason, "actual_size": actual_size, "actual_sha256": actual_sha})
    kind_counts[reason] += 1
    mismatches.append(row)

canonical = json.dumps(mismatches, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
summary = {
    "actual_total_bytes_for_regular_files": actual_total_bytes,
    "candidate_root": str(source),
    "candidate_root_device": root_info.st_dev,
    "candidate_root_inode": root_info.st_ino,
    "candidate_root_mode": stat.filemode(root_info.st_mode),
    "exact_file_count": exact_count,
    "expected_file_count": len(records),
    "expected_total_bytes": expected_total_bytes,
    "formal_evaluation_array_reads": 0,
    "irregular_parent_count": len(irregular_parents),
    "mismatch_count": len(mismatches),
    "mismatch_identity_sha256": sha256(canonical).hexdigest(),
    "mismatch_kind_counts": dict(sorted(kind_counts.items())),
    "ordered_basin_count": len(basins),
    "required_parent_directory_count": len(required_parents),
}
print("SUMMARY=" + json.dumps(summary, ensure_ascii=False, sort_keys=True))
print("IRREGULAR_PARENTS=" + json.dumps(irregular_parents, ensure_ascii=False, sort_keys=True))
print("MISMATCH_RECORDS_BEGIN")
for row in mismatches:
    print(json.dumps(row, ensure_ascii=False, sort_keys=True))
print("MISMATCH_RECORDS_END")

passed = (
    exact_count == 911
    and expected_total_bytes == 464_792_200
    and actual_total_bytes == 464_792_200
    and not irregular_parents
    and not mismatches
)
if not passed:
    raise RuntimeError("candidate source root did not pass the frozen 911-file gate")
print("TUKF09_455_V2R4_REMOTE_CANDIDATE_SOURCE_911_OF_911_PASS")
PY
