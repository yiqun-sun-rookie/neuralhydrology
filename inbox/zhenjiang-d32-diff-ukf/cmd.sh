#!/bin/bash
set -eo pipefail

ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828_r2"
PROJECT_ROOT="${ROOT}/run"
JOB_FILE="${ROOT}/jobs/formal_job_id.txt"
RUNNER="${PROJECT_ROOT}/scripts/modeling/zhenjiang_d32_gru_differentiable_ukf_runner_v1.py"
[ -f "${JOB_FILE}" ] || { echo "[FATAL] formal job identity is absent"; exit 1; }
JID="$(tr -d '\r\n' < "${JOB_FILE}")"
[[ "${JID}" =~ ^[0-9]+$ ]] || { echo "[FATAL] invalid formal job identifier"; exit 1; }

echo "FORMAL_ARRAY_JOB_ID=${JID}"
echo "QUERY_TIME=$(date -Is)"
echo "=== SQUEUE ==="
squeue -j "${JID}" -h -o '%i|%P|%j|%T|%M|%l|%R' || true
echo "=== SACCT ==="
sacct -j "${JID}" -P \
  --format=JobIDRaw,JobID,ArrayTaskID,JobName,Partition,State,ExitCode,ElapsedRaw,Start,End,NodeList,AllocTRES,MaxRSS || true

echo "=== FORMAL_ATTEMPTS ==="
has_complete=0
for experiment_id in ZHD32-DUKF-S17-V1 ZHD32-DUKF-S29-V1 ZHD32-DUKF-S43-V1; do
  attempt="${ROOT}/runs/formal/${experiment_id}/attempt_001"
  partial="${attempt}.partial"
  if [ -d "${attempt}" ]; then
    has_complete=1
    echo "COMPLETE_DIRECTORY|${experiment_id}|${attempt}"
    find "${attempt}" -maxdepth 1 -type f -printf '%s|%f\n' | sort
  elif [ -d "${partial}" ]; then
    echo "PARTIAL_DIRECTORY|${experiment_id}|${partial}"
    find "${partial}" -maxdepth 1 -type f -printf '%s|%f\n' | sort
    if [ -f "${partial}/training_history.csv" ]; then
      echo "TRAINING_HISTORY_PROGRESS|${experiment_id}"
      wc -l "${partial}/training_history.csv"
      tail -n 3 "${partial}/training_history.csv"
    fi
    if [ -f "${partial}/failure.json" ]; then
      echo "FAILURE_RECORD|${experiment_id}"
      sed -n '1,160p' "${partial}/failure.json"
    fi
  else
    echo "ABSENT|${experiment_id}"
  fi
done

if [ "${has_complete}" -eq 1 ]; then
  source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
  conda activate nh_final
  export PYTHONDONTWRITEBYTECODE=1
  export MKL_THREADING_LAYER=GNU
  export MKL_SERVICE_FORCE_INTEL=1
  export OMP_NUM_THREADS=1
  export MKL_NUM_THREADS=1
  export OPENBLAS_NUM_THREADS=1
  export NUMEXPR_NUM_THREADS=1
  cd "${PROJECT_ROOT}"
fi

echo "=== COMPLETED_OUTPUT_VERIFICATION ==="
for experiment_id in ZHD32-DUKF-S17-V1 ZHD32-DUKF-S29-V1 ZHD32-DUKF-S43-V1; do
  attempt="${ROOT}/runs/formal/${experiment_id}/attempt_001"
  [ -d "${attempt}" ] || continue
  echo "VERIFY_OUTPUT|${experiment_id}"
  python -u "${RUNNER}" --verify-output "${attempt}"
  python - "${experiment_id}" "${attempt}" <<'PY'
from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path
import sys

experiment_id = sys.argv[1]
attempt = Path(sys.argv[2])

def read_json(name: str):
    return json.loads((attempt / name).read_text(encoding="utf-8"))

manifest = read_json("completion_manifest.json")
selection = read_json("selection_validation_summary.json")
identity = read_json("run_identity.json")
data = read_json("data_identity.json")
with (attempt / "training_history.csv").open(
    "r", encoding="utf-8", newline=""
) as handle:
    history = list(csv.DictReader(handle))

counters = selection.get("test_target_counters")
if not isinstance(counters, dict) or any(
    type(value) is not int or value != 0 for value in counters.values()
):
    raise SystemExit("held-out target counter is not integer zero")
if selection.get("held_out_target_access") is not False:
    raise SystemExit("held-out target access flag changed")
if selection.get("scientific_conclusion_authorized") is not False:
    raise SystemExit("scientific conclusion flag changed")
if selection.get("backbone_state_sha256_before") != selection.get(
    "backbone_state_sha256_after"
):
    raise SystemExit("frozen backbone identity changed")
if data.get("last_loaded_target_time_beijing", "") > "2023-12-31T23:00:00+08:00":
    raise SystemExit("loaded target boundary exceeds pre-2024 scope")

summary = {
    "experiment_id": experiment_id,
    "completion_status": identity.get("completion_status"),
    "completed_utc": identity.get("completed_utc"),
    "manifest_status": manifest.get("status"),
    "manifest_file_count": manifest.get("file_count"),
    "manifest_sha256": hashlib.sha256(
        (attempt / "completion_manifest.json").read_bytes()
    ).hexdigest(),
    "best_epoch": selection.get("best_epoch"),
    "completed_epoch": selection.get("completed_epoch"),
    "best_validation_mae_m": selection.get("best_validation_mae_m"),
    "history_row_count": len(history),
    "last_history_row": history[-1] if history else None,
    "training_base_sample_count": data.get("training_base_sample_count"),
    "validation_base_sample_count": data.get("validation_base_sample_count"),
    "last_loaded_target_time_beijing": data.get(
        "last_loaded_target_time_beijing"
    ),
    "input_content_identity_count": len(data.get("input_content_identities", [])),
    "test_target_counters": counters,
    "held_out_target_access": selection.get("held_out_target_access"),
    "scientific_conclusion_authorized": selection.get(
        "scientific_conclusion_authorized"
    ),
    "backbone_unchanged": True,
}
print("COMPLETED_SUMMARY|" + json.dumps(summary, sort_keys=True))
PY
done

echo "=== FORMAL_LOG_TAILS ==="
for path in "${ROOT}"/logs/zhd32-dukf-formal-"${JID}"_*.out; do
  [ -f "${path}" ] || continue
  echo "--- ${path} ---"
  tail -n 35 "${path}"
done
for path in "${ROOT}"/logs/zhd32-dukf-formal-"${JID}"_*.err; do
  [ -f "${path}" ] || continue
  echo "--- ${path} ---"
  tail -n 80 "${path}"
done
