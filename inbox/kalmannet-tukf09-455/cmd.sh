#!/bin/bash
# Read-only status capture for the package-native v2r1 A800 allocation probe.
set -o pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r1_20260901
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
JOB_ID=217162
PROBE_SCRIPT="${PROJECT_ROOT}/hpc/tukf09_455_basin_revision_a800_exclusive_v2r1/allocation_probe.slurm"
EXPECTED_PROBE_SCRIPT_SHA=5dc332b67998b6a2fa3b5a37f3db40694ff21cea832ff61750a527f136a4597b

echo "=== FIXED IDENTITY ==="
echo "REMOTE_ROOT=${ROOT}"
echo "ALLOCATION_PROBE_JOB_ID=${JOB_ID}"
if [[ -d "${ROOT}" && ! -L "${ROOT}" ]]; then
  echo "ROOT_STATUS=REGULAR_DIRECTORY"
else
  echo "ROOT_STATUS=MISSING_OR_LINKED"
fi
if [[ -f "${PROBE_SCRIPT}" && ! -L "${PROBE_SCRIPT}" ]]; then
  actual_sha=$(sha256sum "${PROBE_SCRIPT}" | awk '{print $1}')
  echo "PROBE_SCRIPT_SHA256=${actual_sha}"
  [[ "${actual_sha}" = "${EXPECTED_PROBE_SCRIPT_SHA}" ]] && echo "PROBE_SCRIPT_SHA_STATUS=MATCH" || echo "PROBE_SCRIPT_SHA_STATUS=MISMATCH"
else
  echo "PROBE_SCRIPT_SHA_STATUS=FILE_MISSING_OR_LINKED"
fi
if [[ -f "${ROOT}/status/allocation_probe_job_id.txt" && ! -L "${ROOT}/status/allocation_probe_job_id.txt" ]]; then
  printf 'ALLOCATION_PROBE_JOB_ID_FILE='
  tr -d '\r\n' < "${ROOT}/status/allocation_probe_job_id.txt"
  printf '\n'
else
  echo "ALLOCATION_PROBE_JOB_ID_FILE=MISSING_OR_LINKED"
fi

echo "=== SLURM QUEUE ==="
squeue -j "${JOB_ID}" -o '%.18i %.30j %.10P %.10T %.24R %.10M %.20S' 2>&1 || true

echo "=== SLURM ACCOUNTING ==="
sacct -j "${JOB_ID}" -n -P --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,NodeList,Start,End 2>&1 || true

echo "=== EXACT STANDARD OUTPUT ==="
OUT_PATH="${ROOT}/logs/allocation-probe-${JOB_ID}.out"
if [[ -f "${OUT_PATH}" && ! -L "${OUT_PATH}" ]]; then
  stat -c 'STDOUT_SIZE_BYTES=%s STDOUT_LINKS=%h STDOUT_MODE=%a' "${OUT_PATH}" 2>&1 || true
  sha256sum "${OUT_PATH}" 2>&1 || true
  cat "${OUT_PATH}"
else
  echo "ALLOCATION_PROBE_STDOUT=ABSENT"
fi

echo "=== EXACT STANDARD ERROR ==="
ERR_PATH="${ROOT}/logs/allocation-probe-${JOB_ID}.err"
if [[ -f "${ERR_PATH}" && ! -L "${ERR_PATH}" ]]; then
  stat -c 'STDERR_SIZE_BYTES=%s STDERR_LINKS=%h STDERR_MODE=%a' "${ERR_PATH}" 2>&1 || true
  sha256sum "${ERR_PATH}" 2>&1 || true
  cat "${ERR_PATH}"
else
  echo "ALLOCATION_PROBE_STDERR=ABSENT"
fi

echo "TUKF09_455_A800_EXCLUSIVE_V2R1_ALLOCATION_PROBE_READONLY_STATUS_CAPTURED"
