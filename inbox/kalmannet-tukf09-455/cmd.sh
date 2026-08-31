#!/bin/bash
# Read-only status capture for the one authorized v2r1 A800 preparation job.
set -o pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r1_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
RESULTS_ROOT="${PROJECT_ROOT}/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"
JOB_ID=217163
PREPARE_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r1/probe_gpu.slurm"
EXPECTED_PREPARE_SCRIPT_SHA=c46b65d3f7200284d3fad1896570a8c0ea3c86d17538530261a87b0acafad350

echo "=== FIXED IDENTITY ==="
echo "REMOTE_ROOT=${ROOT}"
echo "PREPARATION_JOB_ID=${JOB_ID}"
if [[ -d "${ROOT}" && ! -L "${ROOT}" ]]; then
  echo "ROOT_STATUS=REGULAR_DIRECTORY"
else
  echo "ROOT_STATUS=MISSING_OR_LINKED"
fi
if [[ -f "${PREPARE_SCRIPT}" && ! -L "${PREPARE_SCRIPT}" ]]; then
  actual_sha=$(sha256sum "${PREPARE_SCRIPT}" | awk '{print $1}')
  echo "PREPARE_SCRIPT_SHA256=${actual_sha}"
  [[ "${actual_sha}" = "${EXPECTED_PREPARE_SCRIPT_SHA}" ]] && echo "PREPARE_SCRIPT_SHA_STATUS=MATCH" || echo "PREPARE_SCRIPT_SHA_STATUS=MISMATCH"
else
  echo "PREPARE_SCRIPT_SHA_STATUS=FILE_MISSING_OR_LINKED"
fi
if [[ -f "${ROOT}/status/preparation_job_id.txt" && ! -L "${ROOT}/status/preparation_job_id.txt" ]]; then
  printf 'PREPARATION_JOB_ID_FILE='
  tr -d '\r\n' < "${ROOT}/status/preparation_job_id.txt"
  printf '\n'
else
  echo "PREPARATION_JOB_ID_FILE=MISSING_OR_LINKED"
fi
if [[ -d "${ROOT}/status/preparation_submission.lock" && ! -L "${ROOT}/status/preparation_submission.lock" ]]; then
  stat -c 'SUBMISSION_LOCK=%n LINKS=%h MODE=%a MTIME=%y' "${ROOT}/status/preparation_submission.lock" 2>&1 || true
else
  echo "PREPARATION_SUBMISSION_LOCK=MISSING_OR_IRREGULAR"
fi

echo "=== SLURM QUEUE ==="
squeue -j "${JOB_ID}" -o '%.18i %.30j %.10P %.10T %.24R %.10M %.20S' 2>&1 || true

echo "=== SLURM ACCOUNTING ==="
sacct -j "${JOB_ID}" -n -P --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,NodeList,Start,End 2>&1 || true

echo "=== EXACT STANDARD OUTPUT ==="
OUT_PATH="${ROOT}/logs/prepare-${JOB_ID}.out"
if [[ -f "${OUT_PATH}" && ! -L "${OUT_PATH}" ]]; then
  stat -c 'STDOUT_SIZE_BYTES=%s STDOUT_LINKS=%h STDOUT_MODE=%a' "${OUT_PATH}" 2>&1 || true
  sha256sum "${OUT_PATH}" 2>&1 || true
  cat "${OUT_PATH}"
else
  echo "PREPARATION_STDOUT=ABSENT"
fi

echo "=== EXACT STANDARD ERROR ==="
ERR_PATH="${ROOT}/logs/prepare-${JOB_ID}.err"
if [[ -f "${ERR_PATH}" && ! -L "${ERR_PATH}" ]]; then
  stat -c 'STDERR_SIZE_BYTES=%s STDERR_LINKS=%h STDERR_MODE=%a' "${ERR_PATH}" 2>&1 || true
  sha256sum "${ERR_PATH}" 2>&1 || true
  cat "${ERR_PATH}"
else
  echo "PREPARATION_STDERR=ABSENT"
fi

echo "=== ALLOWED PREPARATION ARTIFACT STATUS ==="
for item in \
  "${ROOT}/status/initial_bundle_verification.json" \
  "${ROOT}/runtime_v2r1/evidence/private_runtime_manifest.json" \
  "${ROOT}/status/staged_training_sources.json" \
  "${RESULTS_ROOT}/control/filter_rebinding/independent/manifest.final.sha256.json" \
  "${ROOT}/status/preparation_probe.json" \
  "${ROOT}/status/hpc_technical_admission.json"; do
  if [[ -f "${item}" && ! -L "${item}" ]]; then
    stat -c 'ARTIFACT=%n SIZE_BYTES=%s LINKS=%h MODE=%a' "${item}" 2>&1 || true
    sha256sum "${item}" 2>&1 || true
  elif [[ -e "${item}" || -L "${item}" ]]; then
    echo "ARTIFACT_IRREGULAR=${item}"
  else
    echo "ARTIFACT_ABSENT=${item}"
  fi
done
for item in "${ROOT}/runtime_v2r1" "${RESULTS_ROOT}"; do
  if [[ -d "${item}" && ! -L "${item}" ]]; then
    echo "DIRECTORY_PRESENT=${item}"
  elif [[ -e "${item}" || -L "${item}" ]]; then
    echo "DIRECTORY_IRREGULAR=${item}"
  else
    echo "DIRECTORY_ABSENT=${item}"
  fi
done
for pattern in "${ROOT}/runtime_v2r1.pending.*" "${ROOT}/status/staged_training_sources.pending-*"; do
  matches=$(compgen -G "${pattern}" || true)
  if [[ -n "${matches}" ]]; then
    printf 'PENDING_PATH=%s\n' ${matches}
  else
    echo "PENDING_PATH_ABSENT=${pattern}"
  fi
done

echo "=== FORMAL EVALUATION HOLD ==="
for name in selection evaluation formal_evaluation; do
  if [[ -e "${RESULTS_ROOT}/${name}" || -L "${RESULTS_ROOT}/${name}" ]]; then
    echo "FORBIDDEN_OUTPUT_PRESENT=${name}"
  else
    echo "FORBIDDEN_OUTPUT_ABSENT=${name}"
  fi
done
echo "TUKF09_455_A800_EXCLUSIVE_V2R1_PREPARATION_READONLY_STATUS_CAPTURED"
