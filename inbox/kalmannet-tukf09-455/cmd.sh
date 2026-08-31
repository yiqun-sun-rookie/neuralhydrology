#!/bin/bash
# Read-only forensics for failed v2r3 preparation job 217185. This hashes only
# the 911 frozen training/validation source files; formal evaluation stays closed.
set -eo pipefail
umask 077

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r3_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
SOURCE_ROOT=/data1/home/sunyiq/neuralhydrology/data/camels_us
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
JOB_ID=217185
STDOUT="${ROOT}/logs/prepare-${JOB_ID}.out"
STDERR="${ROOT}/logs/prepare-${JOB_ID}.err"
EXPECTED_STDOUT_SHA=e295ac5a1c4665e6647d17b49f1c9e9b44bd2163e285d761ffed9ac6c5e464fe
EXPECTED_STDERR_SHA=5257ab7fe11700faf212e36084fefad510d3cefd76344d59f75745cfafeebda1
TARGET_RELATIVE=basin_mean_forcing/maurer/03/02108000_lump_maurer_forcing_leap.txt
EXPECTED_TARGET_SHA=1d7efcfdcf87cda0485a7f6442f7d85aaacaf0b33e0e1c01dddeb73896f26a1a
EXPECTED_TARGET_SIZE=627964
PYTHON=/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH="${PROJECT_ROOT}"

fail() {
  echo "FATAL: $*" >&2
  exit 1
}

echo "=== FROZEN FAILED JOB EVIDENCE ==="
sacct -j "${JOB_ID}" -n -P --format=JobIDRaw,JobName,Partition,State,ExitCode,NodeList,Elapsed,Start,End | \
  awk -F'|' -v id="${JOB_ID}" '$1==id {print; if ($2=="tukf09-455-v2r3-prepare" && $4=="FAILED" && $5=="1:0") ok=1} END {exit(ok ? 0 : 1)}' || fail "failed job identity changed"
for item in "${STDOUT}" "${STDERR}"; do
  [[ -f "${item}" && ! -L "${item}" && "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "failed job log is irregular: ${item}"
done
[[ "$(sha256sum "${STDOUT}" | awk '{print $1}')" = "${EXPECTED_STDOUT_SHA}" ]] || fail "failed preparation stdout changed"
[[ "$(sha256sum "${STDERR}" | awk '{print $1}')" = "${EXPECTED_STDERR_SHA}" ]] || fail "failed preparation stderr changed"
grep -F "RuntimeError: shared training source differs: ${TARGET_RELATIVE}" "${STDERR}" >/dev/null || fail "recorded failure boundary changed"

echo "=== PRESERVED V2R3 ROOT BOUNDARY ==="
for item in \
  "${ROOT}/offline_inputs_v2r3" \
  "${ROOT}/runtime_v2r3" \
  "${ROOT}/status/preparation_submission.lock"; do
  [[ -d "${item}" && ! -L "${item}" ]] || fail "required preserved directory is missing or linked: ${item}"
  echo "DIRECTORY=$(du -sb "${item}" | awk '{print $1}')|$(find "${item}" -type f | wc -l)|$(find "${item}" -type l | wc -l)|${item}"
done
for item in \
  "${ROOT}/status/deployment_summary.json" \
  "${ROOT}/status/allocation_probe_job_id.txt" \
  "${ROOT}/status/offline_inputs_download.lock" \
  "${ROOT}/status/preparation_job_id.txt" \
  "${ROOT}/status/preparation.lock" \
  "${ROOT}/status/initial_bundle_verification.json" \
  "${ROOT}/runtime_v2r3/evidence/private_runtime_manifest.json"; do
  [[ -f "${item}" && ! -L "${item}" && "$(stat -c '%h' "${item}")" -eq 1 ]] || fail "required preserved file is missing or irregular: ${item}"
  echo "FILE=$(stat -c '%s' "${item}")|$(sha256sum "${item}" | awk '{print $1}')|${item}"
done
for item in \
  "${ROOT}/status/staged_training_sources.json" \
  "${ROOT}/status/preparation_probe.json" \
  "${ROOT}/status/hpc_technical_admission.json" \
  "${ROOT}/status/training_submission.lock" \
  "${ROOT}/status/training_job_id.txt"; do
  [[ ! -e "${item}" && ! -L "${item}" ]] || fail "downstream evidence exists after failed preparation: ${item}"
done
for name in selection evaluation independent formal_evaluation formal_evaluation_independent; do
  [[ ! -e "${RESULTS_ROOT}/${name}" && ! -L "${RESULTS_ROOT}/${name}" ]] || fail "forbidden evaluation output exists: ${name}"
done
pending="${ROOT}/status/staged_training_sources.pending-${JOB_ID}"
if [[ -e "${pending}" || -L "${pending}" ]]; then
  [[ -d "${pending}" && ! -L "${pending}" ]] || fail "staged pending evidence is linked or irregular"
  echo "PENDING_STAGE_BYTES=$(du -sb "${pending}" | awk '{print $1}')"
  echo "PENDING_STAGE_FILES=$(find "${pending}" -type f | wc -l)"
  echo "PENDING_STAGE_SYMLINKS=$(find "${pending}" -type l | wc -l)"
else
  echo "PENDING_STAGE_ABSENT"
fi

echo "=== COMPLETE 911-FILE TRAINING-VALIDATION SOURCE HASH AUDIT ==="
"${PYTHON}" -B - "${PROJECT_ROOT}" "${SOURCE_ROOT}" "${TARGET_RELATIVE}" "${EXPECTED_TARGET_SHA}" "${EXPECTED_TARGET_SIZE}" <<'PY'
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
target_relative = sys.argv[3]
expected_target_sha = sys.argv[4]
expected_target_size = int(sys.argv[5])
stage_path = project / "hpc/tukf09_455_basin_revision_a800_exclusive_v2r3/stage_and_train.py"
spec = importlib.util.spec_from_file_location("tukf09_stage_v2r3_forensics", stage_path)
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
assert records[target_relative] == {
    "sha256": expected_target_sha,
    "size_bytes": expected_target_size,
}

mismatches: list[dict[str, object]] = []
exact = 0
actual_total_bytes = 0
expected_total_bytes = 0
kind_counts: Counter[str] = Counter()
prefix_counts: Counter[str] = Counter()
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
        prefix_counts[relative.split("/", 1)[0]] += 1
        mismatches.append(row)
        continue
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode) or info.st_nlink != 1:
        row.update({"reason": "irregular", "actual_size": info.st_size, "link_count": info.st_nlink})
        kind_counts["irregular"] += 1
        prefix_counts[relative.split("/", 1)[0]] += 1
        mismatches.append(row)
        continue
    actual_size = info.st_size
    actual_sha = stage.sha256_file(path)
    actual_total_bytes += actual_size
    if actual_size == expected_size and actual_sha == expected_sha:
        exact += 1
        continue
    reason = "size_and_sha256" if actual_size != expected_size else "sha256_only"
    row.update({"reason": reason, "actual_size": actual_size, "actual_sha256": actual_sha})
    kind_counts[reason] += 1
    prefix_counts[relative.split("/", 1)[0]] += 1
    mismatches.append(row)

canonical = json.dumps(mismatches, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
target_rows = [row for row in mismatches if row["path"] == target_relative]
assert len(target_rows) == 1
summary = {
    "actual_total_bytes_for_regular_files": actual_total_bytes,
    "exact_file_count": exact,
    "expected_file_count": len(records),
    "expected_total_bytes": expected_total_bytes,
    "formal_evaluation_array_reads": 0,
    "mismatch_count": len(mismatches),
    "mismatch_identity_sha256": sha256(canonical).hexdigest(),
    "mismatch_kind_counts": dict(sorted(kind_counts.items())),
    "mismatch_prefix_counts": dict(sorted(prefix_counts.items())),
    "ordered_basin_count": len(basins),
    "target_mismatch": target_rows[0],
}
print(json.dumps(summary, ensure_ascii=False, sort_keys=True))
print("MISMATCH_RECORDS_BEGIN")
for row in mismatches[:200]:
    print(json.dumps(row, ensure_ascii=False, sort_keys=True))
if len(mismatches) > 200:
    print(f"MISMATCH_RECORDS_TRUNCATED={len(mismatches) - 200}")
print("MISMATCH_RECORDS_END")

target_name = Path(target_relative).name
candidate_roots = [
    Path("/data1/home/sunyiq/neuralhydrology"),
    Path("/data1/home/sunyiq/data"),
    Path("/data1/home/sunyiq/datasets"),
    Path("/data1/home/sunyiq/camels"),
    Path("/data1/home/sunyiq/CAMELS"),
]
prune_exact = {".git", ".cache", "miniconda3", "__pycache__"}
candidates: list[dict[str, object]] = []
seen: set[Path] = set()
for candidate_root in candidate_roots:
    if not candidate_root.is_dir() or candidate_root in seen:
        continue
    seen.add(candidate_root)
    for directory, names, files in os.walk(candidate_root, followlinks=False):
        names[:] = [
            name for name in names
            if name not in prune_exact
            and not name.startswith(("runtime_v", "offline_inputs_v", "pysite"))
        ]
        if target_name not in files:
            continue
        candidate = Path(directory) / target_name
        info = os.lstat(candidate)
        if not stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode):
            continue
        digest = stage.sha256_file(candidate)
        candidates.append({
            "path": str(candidate),
            "sha256": digest,
            "size": info.st_size,
            "matches_expected": digest == expected_target_sha and info.st_size == expected_target_size,
        })
print("TARGET_NAME_CANDIDATES=" + json.dumps(sorted(candidates, key=lambda row: str(row["path"])), sort_keys=True))
PY

echo "=== TOP-LEVEL DATA-ROUTE DIRECTORY NAMES ==="
find /data1/home/sunyiq -mindepth 1 -maxdepth 2 -type d \
  \( -iname '*camels*' -o -iname '*data*' -o -iname 'neuralhydrology*' \) \
  -printf '%p\n' | LC_ALL=C sort
echo "TUKF09_455_A800_EXCLUSIVE_V2R3_PREPARATION_FAILURE_FORENSICS_COMPLETED_NO_RETRY"
