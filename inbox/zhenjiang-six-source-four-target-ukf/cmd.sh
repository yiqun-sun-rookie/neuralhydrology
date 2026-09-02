#!/bin/bash
set -o pipefail

JOB_ID="218505"
ORIGINAL_ROOT="/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r2"
ROOT="/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260902_recovery_attempt_002"
EVALUATION="${ROOT}/evidence/development_2023/evaluation/attempt_002"
AUDIT="${ROOT}/evidence/development_2023/independent_audit/attempt_002"

printf '=== SNAPSHOT_TIME ===\n'
date -Is
printf '=== SQUEUE ===\n'
squeue -j "${JOB_ID}" -o '%i|%j|%T|%P|%N|%M|%l|%R' 2>&1 || true
printf '=== SACCT ===\n'
sacct -j "${JOB_ID}" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList -P -n 2>&1 || true
printf '=== SCONTROL ===\n'
scontrol show job -o "${JOB_ID}" 2>&1 || true

printf '=== RECOVERY_PATH_STATE ===\n'
for path in "${EVALUATION}" "${EVALUATION}.partial" "${AUDIT}" "${AUDIT}.partial"; do
  if [ -d "${path}" ]; then
    printf 'DIRECTORY|%s\n' "${path}"
    find "${path}" -maxdepth 1 -type f -printf 'FILE|%f|bytes=%s|mtime=%TY-%Tm-%TdT%TH:%TM:%TS%Tz\n' 2>/dev/null | sort || true
  elif [ -e "${path}" ]; then
    printf 'NON_DIRECTORY|%s\n' "${path}"
  else
    printf 'ABSENT|%s\n' "${path}"
  fi
done

printf '=== LOGS ===\n'
for file in "${ROOT}/logs/development-recovery-attempt-002-${JOB_ID}.out" "${ROOT}/logs/development-recovery-attempt-002-${JOB_ID}.err"; do
  if [ -f "${file}" ]; then
    stat -c 'LOG|%n|bytes=%s|mtime=%y' "${file}" || true
    tail -n 160 "${file}" || true
  else
    printf 'LOG_ABSENT|%s\n' "${file}"
  fi
done

printf '=== COMPLETION_SUMMARY ===\n'
python - "${ROOT}" <<'PY' || true
from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path
import sys


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb", buffering=0) as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


root = Path(sys.argv[1])
evaluation = root / "evidence/development_2023/evaluation/attempt_002"
audit = root / "evidence/development_2023/independent_audit/attempt_002"
if evaluation.is_dir() and (evaluation / "completion_manifest.json").is_file():
    manifest_path = evaluation / "completion_manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    actual_files = sorted(path.name for path in evaluation.iterdir() if path.is_file())
    registered = manifest.get("files", [])
    registered_ok = all(
        (evaluation / row["name"]).is_file()
        and (evaluation / row["name"]).stat().st_size == row["byte_count"]
        and sha256(evaluation / row["name"]) == row["sha256"]
        for row in registered
    )
    print("EVALUATION_MANIFEST=" + json.dumps({
        "status": manifest.get("status"),
        "manifest_sha256": sha256(manifest_path),
        "actual_file_count": len(actual_files),
        "file_count_excluding_manifest": manifest.get("file_count_excluding_manifest"),
        "registered_files_match": registered_ok,
        "authorized_technical_recovery": manifest.get("authorized_technical_recovery"),
        "recovery_attempt_number": manifest.get("recovery_attempt_number"),
        "current_attempt_development_loader_call_count": manifest.get("current_attempt_development_loader_call_count"),
        "cumulative_development_loader_call_count": manifest.get("cumulative_development_loader_call_count"),
        "prior_failed_development_access_attempt_count": manifest.get("prior_failed_development_access_attempt_count"),
        "original_single_read_contract_satisfied": manifest.get("original_single_read_contract_satisfied"),
        "held_out_2024_target_access_count": manifest.get("held_out_2024_target_access_count"),
        "boundary_future_target_access_count": manifest.get("boundary_future_target_access_count"),
    }, sort_keys=True))
    for name in (
        "base_observation_head_qualification.json",
        "development_gate_decision.json",
        "bootstrap_summary.json",
    ):
        path = evaluation / name
        if path.is_file():
            print(name.upper() + "=" + json.dumps(json.loads(path.read_text(encoding="utf-8")), sort_keys=True))
    for name in (
        "analysis_realtime_observation_diagnostics.csv",
        "six_source_four_target_gain_matrix.csv",
        "reciprocal_direction_summary.csv",
    ):
        path = evaluation / name
        if path.is_file():
            with path.open("r", encoding="utf-8", newline="") as handle:
                rows = list(csv.DictReader(handle))
            print(name.upper() + "=" + json.dumps(rows, sort_keys=True))
else:
    print("EVALUATION_COMPLETE=false")

if audit.is_dir() and (audit / "completion_manifest.json").is_file():
    manifest_path = audit / "completion_manifest.json"
    report_path = audit / "independent_audit_report.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    report = json.loads(report_path.read_text(encoding="utf-8"))
    print("AUDIT_MANIFEST=" + json.dumps(manifest, sort_keys=True))
    print("AUDIT_REPORT=" + json.dumps(report, sort_keys=True))
    print("AUDIT_IDENTITIES=" + json.dumps({
        "manifest_sha256": sha256(manifest_path),
        "report_sha256": sha256(report_path),
        "actual_files": sorted(path.name for path in audit.iterdir() if path.is_file()),
    }, sort_keys=True))
else:
    print("AUDIT_COMPLETE=false")
PY

printf '=== ORIGINAL_R2_SAFETY ===\n'
for specification in \
  "704366cb22eef1d3acb58f4f0524a6e50d49ffa442afcf0fca498fbd21154cb8|${ORIGINAL_ROOT}/run/docs/records/ZHENJIANG_SIX_SOURCE_FOUR_TARGET_D32_GRU_DIFFERENTIABLE_UKF_V1_REGISTRY.json" \
  "badf3ee5f8cf3f0d9c5e5771b11385a45a6f22d6355fc43357bc44f2bd364c9e|${ORIGINAL_ROOT}/evidence/development_2023/evaluation/attempt_001.partial/development_access_started.json" \
  "bcd7cc658a9a1790f07cce392a9b60d9f3338b722af8520f2a20bb61998111c8|${ORIGINAL_ROOT}/logs/development-2023-217810.out" \
  "7ebac31811938324b27f10743850a0b32e981d1b8eb5f0dcc750ce089b60f185|${ORIGINAL_ROOT}/logs/development-2023-217810.err" \
  "f64e5ffcc47061d97f66e28e15ec45f7412b1d8a59455771180c4ef47eab9281|${ORIGINAL_ROOT}/run/scripts/analysis/zhenjiang_six_source_four_target_d32_gru_ukf_development_evaluation_v1.py"
do
  expected="${specification%%|*}"
  path="${specification#*|}"
  observed="$(sha256sum "${path}" 2>/dev/null | awk '{print $1}')"
  printf 'ORIGINAL_IDENTITY|match=%s|sha256=%s|path=%s\n' "$([ "${observed}" = "${expected}" ] && echo true || echo false)" "${observed}" "${path}"
done
[ ! -e "${ORIGINAL_ROOT}/evidence/development_2023/evaluation/attempt_001" ] && echo 'ORIGINAL_EVALUATION_FINAL_ABSENT=true' || echo 'ORIGINAL_EVALUATION_FINAL_ABSENT=false'
[ ! -e "${ORIGINAL_ROOT}/evidence/development_2023/independent_audit/attempt_001" ] && echo 'ORIGINAL_AUDIT_FINAL_ABSENT=true' || echo 'ORIGINAL_AUDIT_FINAL_ABSENT=false'
echo 'HELD_OUT_2024_TARGET_ACCESS_AUTHORIZED=false'
echo 'BOUNDARY_FUTURE_TARGET_ACCESS_AUTHORIZED=false'
printf '=== SNAPSHOT_END ===\n'
date -Is
exit 0
