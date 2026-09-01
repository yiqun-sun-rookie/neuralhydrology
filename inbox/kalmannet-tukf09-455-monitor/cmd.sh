#!/bin/bash
# Read-only snapshot of the long-running v2r5 offline-input acquisition.
# This auxiliary channel writes nothing remotely and submits no Slurm job.
set -o pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r5_20260901
PENDING="${ROOT}/offline_inputs_v2r5.pending.attempt001"
FINAL="${ROOT}/offline_inputs_v2r5"
LOCK="${ROOT}/status/offline_inputs_download.lock"
RESULTS_ROOT="${ROOT}/bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"

echo "=== SNAPSHOT TIME ==="
date --iso-8601=seconds 2>&1 || date 2>&1
hostname -s 2>&1

echo "=== MATCHING USER PROCESSES ==="
ps -u "${USER}" -o pid=,ppid=,etimes=,state=,args= 2>&1 | \
  awk -v root="${ROOT}" 'index($0, root) && $0 !~ /awk -v root=/' || true

echo "=== ACQUISITION PATHS ==="
for item in "${LOCK}" "${PENDING}" "${FINAL}"; do
  if [[ -e "${item}" || -L "${item}" ]]; then
    stat -c '%n|type=%F|mode=%a|links=%h|size=%s|mtime=%Y' "${item}" 2>&1 || true
  else
    echo "ABSENT|${item}"
  fi
done

echo "=== PENDING FILE CLOSURE ==="
if [[ -d "${PENDING}" && ! -L "${PENDING}" ]]; then
  du -sb "${PENDING}" 2>&1 || true
  find "${PENDING}/wheelhouse" "${PENDING}/sourcehouse" -maxdepth 1 -type f \
    -printf '%p|size=%s|mtime=%T@\n' 2>&1 | LC_ALL=C sort || true
  echo "PENDING_FILE_COUNT=$(find "${PENDING}" -type f 2>/dev/null | wc -l)"
else
  echo "PENDING_DIRECTORY_NOT_PRESENT"
fi

echo "=== FINAL PUBLICATION SUMMARY ==="
if [[ -d "${FINAL}" && ! -L "${FINAL}" ]]; then
  du -sb "${FINAL}" 2>&1 || true
  if [[ -f "${FINAL}/manifest.json" && ! -L "${FINAL}/manifest.json" ]]; then
    echo "FINAL_MANIFEST_SIZE=$(stat -c '%s' "${FINAL}/manifest.json")"
    echo "FINAL_MANIFEST_SHA256=$(sha256sum "${FINAL}/manifest.json" | awk '{print $1}')"
  fi
else
  echo "FINAL_DIRECTORY_NOT_PRESENT"
fi

echo "=== DOWNSTREAM ZERO-OUTPUT SNAPSHOT ==="
for item in \
  "${ROOT}/runtime_v2r5" \
  "${ROOT}/status/PREPARATION_FAILED.json" \
  "${ROOT}/status/initial_bundle_verification.json" \
  "${ROOT}/status/staged_training_sources.json" \
  "${ROOT}/status/preparation_probe.json" \
  "${ROOT}/status/hpc_technical_admission.json" \
  "${ROOT}/status/preparation.lock" \
  "${ROOT}/status/preparation_job_id.txt" \
  "${ROOT}/status/training_submission.lock" \
  "${ROOT}/status/training_job_id.txt"; do
  if [[ -e "${item}" || -L "${item}" ]]; then
    echo "PRESENT|${item}"
  else
    echo "ABSENT|${item}"
  fi
done
for name in selection evaluation independent formal_evaluation formal_evaluation_independent; do
  item="${RESULTS_ROOT}/${name}"
  if [[ -e "${item}" || -L "${item}" ]]; then
    echo "PRESENT|${item}"
  else
    echo "ABSENT|${item}"
  fi
done

echo "TUKF09_455_V2R5_OFFLINE_INPUT_ACQUISITION_READ_ONLY_SNAPSHOT_COMPLETED"
