#!/bin/bash
# Read-only status snapshot for the unique v2r5 preparation job.
# This auxiliary command writes nothing remotely and submits no Slurm job.
set -o pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r5_20260901
JOB_ID=217817
JOB_ID_FILE="${ROOT}/status/preparation_job_id.txt"
STDOUT="${ROOT}/logs/prepare-${JOB_ID}.out"
STDERR="${ROOT}/logs/prepare-${JOB_ID}.err"
RESULTS_ROOT="${ROOT}/bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"

echo "=== SNAPSHOT TIME ==="
date --iso-8601=seconds 2>&1 || date 2>&1
hostname -s 2>&1

echo "=== SLURM STATE ==="
sacct -j "${JOB_ID}" -n -P \
  --format=JobIDRaw,JobName,Partition,State,ExitCode,NodeList,Elapsed,Start,End 2>&1 || true
squeue -j "${JOB_ID}" -o '%.18i %.30j %.10P %.10T %.24R %.10M %.20S' 2>&1 || true
sstat -j "${JOB_ID}.batch" --format=JobID,AveCPU,AveRSS,MaxRSS,MaxVMSize -P 2>&1 || true

echo "=== FROZEN JOB RECORD ==="
if [[ -f "${JOB_ID_FILE}" && ! -L "${JOB_ID_FILE}" ]]; then
  stat -c '%n|type=%F|mode=%a|links=%h|size=%s|mtime=%Y' "${JOB_ID_FILE}" 2>&1 || true
  printf 'JOB_ID_FILE_CONTENT='
  tr -d '\r\n' < "${JOB_ID_FILE}" 2>&1 || true
  printf '\n'
else
  echo "JOB_ID_FILE_MISSING_OR_IRREGULAR"
fi

echo "=== PREPARATION LOGS ==="
for item in "${STDOUT}" "${STDERR}"; do
  if [[ -f "${item}" && ! -L "${item}" ]]; then
    stat -c '%n|type=%F|mode=%a|links=%h|size=%s|mtime=%Y' "${item}" 2>&1 || true
    echo "LOG_SHA256=$(sha256sum "${item}" | awk '{print $1}')"
    echo "--- tail $(basename "${item}") ---"
    tail -n 100 "${item}" 2>&1 || true
  else
    echo "LOG_ABSENT_OR_IRREGULAR|${item}"
  fi
done

echo "=== PREPARATION OUTPUT SNAPSHOT ==="
for item in \
  "${ROOT}/runtime_v2r5" \
  "${ROOT}/status/PREPARATION_FAILED.json" \
  "${ROOT}/status/initial_bundle_verification.json" \
  "${ROOT}/status/staged_training_sources.json" \
  "${ROOT}/status/preparation_probe.json" \
  "${ROOT}/status/hpc_technical_admission.json" \
  "${ROOT}/status/preparation.lock" \
  "${ROOT}/status/training_submission.lock" \
  "${ROOT}/status/training_job_id.txt"; do
  if [[ -e "${item}" || -L "${item}" ]]; then
    stat -c 'PRESENT|%n|type=%F|mode=%a|links=%h|size=%s|mtime=%Y' "${item}" 2>&1 || true
  else
    echo "ABSENT|${item}"
  fi
done

echo "=== PENDING ROOT SNAPSHOT ==="
shopt -s nullglob
pending=("${ROOT}"/runtime_v2r5.pending.* "${ROOT}"/status/staged_training_sources.pending-*)
shopt -u nullglob
if [[ "${#pending[@]}" -eq 0 ]]; then
  echo "NO_PENDING_ROOTS"
else
  for item in "${pending[@]}"; do
    stat -c 'PRESENT|%n|type=%F|mode=%a|links=%h|size=%s|mtime=%Y' "${item}" 2>&1 || true
  done
fi

echo "=== FORMAL-EVALUATION HOLD SNAPSHOT ==="
for name in selection evaluation independent formal_evaluation formal_evaluation_independent; do
  item="${RESULTS_ROOT}/${name}"
  if [[ -e "${item}" || -L "${item}" ]]; then
    echo "PRESENT|${item}"
  else
    echo "ABSENT|${item}"
  fi
done

echo "TUKF09_455_V2R5_PREPARATION_JOB_READ_ONLY_SNAPSHOT_COMPLETED"
