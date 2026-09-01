#!/bin/bash
set -o pipefail

ROOT="/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r2"
R1_STAGING="/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r1.staging"
IDS_CSV="217803,217804,217805,217806,217807,217808,217809,217810"
IDS_SPACE="217803 217804 217805 217806 217807 217808 217809 217810"

printf '=== SNAPSHOT_TIME ===\n'
date -Is

printf '=== SQUEUE ===\n'
squeue -j "${IDS_CSV}" -o '%i|%j|%T|%P|%N|%M|%l|%R' || true

printf '=== START_ESTIMATE ===\n'
squeue --start -j '217809' -o '%i|%j|%T|%S|%R' 2>&1 || true

printf '=== PRIORITY_DETAIL ===\n'
sprio -j '217809' 2>&1 || true

printf '=== SACCT ===\n'
sacct -j "${IDS_CSV}" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList -P -n || true

printf '=== SCONTROL_DEPENDENCIES ===\n'
for job_id in ${IDS_SPACE}; do
  scontrol show job -o "${job_id}" 2>&1 | sed -n 's/.*JobId=\([^ ]*\).*JobState=\([^ ]*\).*Reason=\([^ ]*\).*Dependency=\([^ ]*\).*/JOB|\1|STATE=\2|REASON=\3|DEPENDENCY=\4/p' || true
done

printf '=== REGISTERED_OUTPUTS_AND_FAILURE_EVIDENCE ===\n'
for seed in 17 29 43; do
  for relative in \
    "runs/base_smoke/s${seed}/attempt_001" \
    "runs/base/s${seed}/attempt_001" \
    "runs/observation_head_smoke/s${seed}/attempt_001" \
    "runs/observation_head/s${seed}/attempt_001" \
    "runs/filter_real_batch_smoke/s${seed}/attempt_001" \
    "runs/filter/s${seed}/attempt_001"
  do
    path="${ROOT}/${relative}"
    if [ -d "${path}" ]; then
      printf 'PUBLISHED|%s\n' "${path}"
      for evidence in "${path}/completion_manifest.json" "${path}/failure.json" "${path}/failure_manifest.json"; do
        [ -f "${evidence}" ] || continue
        stat -c 'FILE|%n|bytes=%s|mtime=%y' "${evidence}" || true
        tail -n 80 "${evidence}" || true
      done
    elif [ -d "${path}.partial" ]; then
      printf 'PARTIAL|%s\n' "${path}.partial"
      find "${path}.partial" -maxdepth 1 -type f -printf 'PARTIAL_FILE|%f|bytes=%s|mtime=%TY-%Tm-%TdT%TH:%TM:%TS%Tz\n' 2>/dev/null | sort || true
    else
      printf 'ABSENT|%s\n' "${path}"
    fi
  done
done
for relative in \
  "runs/development_evaluation_smoke/attempt_001" \
  "evidence/development_2023/evaluation/attempt_001" \
  "evidence/development_2023/independent_audit/attempt_001"
do
  path="${ROOT}/${relative}"
  if [ -d "${path}" ]; then
    printf 'PUBLISHED|%s\n' "${path}"
    for evidence in "${path}/completion_manifest.json" "${path}/failure.json" "${path}/failure_manifest.json"; do
      [ -f "${evidence}" ] || continue
      stat -c 'FILE|%n|bytes=%s|mtime=%y' "${evidence}" || true
      tail -n 80 "${evidence}" || true
    done
  elif [ -d "${path}.partial" ]; then
    printf 'PARTIAL|%s\n' "${path}.partial"
    find "${path}.partial" -maxdepth 1 -type f -printf 'PARTIAL_FILE|%f|bytes=%s|mtime=%TY-%Tm-%TdT%TH:%TM:%TS%Tz\n' 2>/dev/null | sort || true
  else
    printf 'ABSENT|%s\n' "${path}"
  fi
done

printf '=== BASE_OUTPUT_DEEP_VERIFICATION ===\n'
python - "${ROOT}" <<'PY' || true
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
expected_names = {
    "best_checkpoint.pt",
    "last_checkpoint.pt",
    "run_identity.json",
    "training_history.json",
    "completion_manifest.json",
}
for seed in (17, 29, 43):
    final = root / f"runs/base/s{seed}/attempt_001"
    partial = Path(f"{final}.partial")
    print(
        "BASE_PATH_STATE"
        f"|seed={seed}|final={str(final.is_dir()).lower()}"
        f"|partial={str(partial.exists()).lower()}"
    )
    if not final.is_dir():
        continue
    entries = sorted(final.rglob("*"))
    files = [path for path in entries if path.is_file() and not path.is_symlink()]
    links = [path for path in entries if path.is_symlink()]
    directories = [path for path in entries if path.is_dir() and path != final]
    relative_names = {path.relative_to(final).as_posix() for path in files}
    print(
        "BASE_FILE_SET"
        f"|seed={seed}|ordinary_files={len(files)}|links={len(links)}"
        f"|subdirectories={len(directories)}"
        f"|exact={str(relative_names == expected_names).lower()}"
        f"|names={','.join(sorted(relative_names))}"
    )
    manifest_path = final / "completion_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    registered = manifest.get("files", {})
    all_registered_match = True
    for path in files:
        relative = path.relative_to(final).as_posix()
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        row = registered.get(relative)
        matches = (
            relative == "completion_manifest.json"
            or (
                isinstance(row, dict)
                and row.get("byte_count") == path.stat().st_size
                and row.get("sha256") == digest
            )
        )
        if relative != "completion_manifest.json":
            all_registered_match = all_registered_match and matches
        print(
            "BASE_FILE"
            f"|seed={seed}|name={relative}|bytes={path.stat().st_size}"
            f"|sha256={digest}|registered_match={str(matches).lower()}"
        )
    print(
        "BASE_MANIFEST_CHECK"
        f"|seed={seed}|status={manifest.get('status')}"
        f"|registered_files={len(registered)}"
        f"|all_registered_match={str(all_registered_match).lower()}"
    )
    identity = json.loads((final / "run_identity.json").read_text(encoding="utf-8"))
    audit = identity.get("data_access_audit", {})
    periods = audit.get("target_rows_by_period", {})
    forbidden_fields = (
        "development_feature_bytes_read",
        "development_feature_rows_parsed",
        "development_feature_values_loaded",
        "development_target_bytes_read",
        "development_target_rows_parsed",
        "development_target_values_loaded",
        "heldout_target_bytes_read",
        "heldout_target_rows_parsed",
        "heldout_target_values_loaded",
        "boundary_target_bytes_read",
        "boundary_target_rows_parsed",
        "boundary_target_values_loaded",
    )
    forbidden_values = {name: audit.get(name) for name in forbidden_fields}
    forbidden_zero = all(type(value) is int and value == 0 for value in forbidden_values.values())
    total_prefix_bytes = sum(audit.get("bytes_read_by_path", {}).values())
    print(
        "BASE_IDENTITY"
        f"|seed={seed}|task_id={identity.get('task_id')}|stage={identity.get('stage')}"
        f"|registered_output_path={identity.get('registered_output_path')}"
        f"|registry_sha256={identity.get('registry_sha256')}"
        f"|input_manifest_sha256={identity.get('training_selection_input_manifest_sha256')}"
    )
    print(
        "BASE_ACCESS_AUDIT"
        f"|seed={seed}|opened_paths={len(audit.get('opened_paths', []))}"
        f"|prefix_bytes={total_prefix_bytes}"
        f"|target_rows_by_period={json.dumps(periods, sort_keys=True, separators=(',', ':'))}"
        f"|astronomical_tide_model_open_count={audit.get('astronomical_tide_model_open_count')}"
        f"|forbidden_counters_integer_zero={str(forbidden_zero).lower()}"
    )
PY

printf '=== LOG_TAILS_AND_ERROR_SCAN ===\n'
for job_id in ${IDS_SPACE}; do
  for file in "${ROOT}/logs/"*"${job_id}"*.out "${ROOT}/logs/"*"${job_id}"*.err; do
    [ -f "${file}" ] || continue
    stat -c 'LOG|%n|bytes=%s|mtime=%y' "${file}" || true
    tail -n 60 "${file}" || true
    printf '%s\n' "--- ERROR_SCAN ${file}"
    grep -nEi 'traceback|fatal|failed|error|exception|cuda out of memory|no such file|assertionerror|runtimeerror|nan|inf' "${file}" | tail -n 30 || true
  done
done

printf '=== SAFETY_SENTINELS ===\n'
if [ -d "${R1_STAGING}" ]; then
  stat -c 'R1_STAGING_PRESERVED=true|type=%F|bytes=%s|mtime=%y|path=%n' "${R1_STAGING}" || true
else
  echo 'R1_STAGING_PRESERVED=false'
fi
[ -d "${ROOT}" ] && echo 'R2_ROOT_PRESENT=true' || echo 'R2_ROOT_PRESENT=false'
python - "${ROOT}" <<'PY' || true
from __future__ import annotations
import json
from pathlib import Path
import sys

root = Path(sys.argv[1])
registry = json.loads(
    (root / "run/docs/records/ZHENJIANG_SIX_SOURCE_FOUR_TARGET_D32_GRU_DIFFERENTIABLE_UKF_V1_REGISTRY.json").read_text(encoding="utf-8")
)
input_manifest = json.loads(
    (root / "inputs/pre2024-four-target-v1/four_target_input_manifest.json").read_text(encoding="utf-8")
)
heldout_authorized = registry["authorization"]["heldout_2024_target_access_authorized"]
boundary_bytes = input_manifest["boundary_target_bytes_read"]
heldout_bytes = input_manifest["heldout_2024_target_bytes_read"]
later_bytes = input_manifest["later_than_2023_bytes_read"]
print(f"HELDOUT_2024_TARGET_ACCESS_AUTHORIZED={str(heldout_authorized).lower()}")
print(f"BOUNDARY_TARGET_BYTES_READ={boundary_bytes}")
print(f"HELDOUT_2024_TARGET_BYTES_READ={heldout_bytes}")
print(f"LATER_THAN_2023_BYTES_READ={later_bytes}")
if heldout_authorized is False and boundary_bytes == heldout_bytes == later_bytes == 0:
    print("TARGET_ACCESS_SAFETY_CHECK=PASS")
else:
    print("TARGET_ACCESS_SAFETY_CHECK=VIOLATION")
PY

printf '=== SNAPSHOT_END ===\n'
date -Is
exit 0
