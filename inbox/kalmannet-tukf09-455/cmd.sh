#!/bin/bash
# Read-only status capture for the already-submitted A800 allocation probe.
set -o pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_a800_exclusive_semantics_probe_v1_20260831_01a055e6
JOB_ID=217122
EXPECTED_PROBE_SHA=fd34fa08da8d74781ef952f21907ba62018475702b299611db414cd4a3ddaed6

echo "=== FIXED IDENTITY ==="
echo "PROBE_ROOT=${ROOT}"
echo "JOB_ID=${JOB_ID}"
if [[ -d "${ROOT}" && ! -L "${ROOT}" ]]; then
  echo "ROOT_STATUS=REGULAR_DIRECTORY"
else
  echo "ROOT_STATUS=MISSING_OR_LINKED"
fi
if [[ -f "${ROOT}/probe.slurm" && ! -L "${ROOT}/probe.slurm" ]]; then
  actual_probe_sha=$(sha256sum "${ROOT}/probe.slurm" | awk '{print $1}')
  echo "PROBE_SHA256=${actual_probe_sha}"
  [[ "${actual_probe_sha}" = "${EXPECTED_PROBE_SHA}" ]] && echo "PROBE_SHA_STATUS=MATCH" || echo "PROBE_SHA_STATUS=MISMATCH"
else
  echo "PROBE_SHA_STATUS=FILE_MISSING_OR_LINKED"
fi
if [[ -f "${ROOT}/status/submitted_job_id.txt" && ! -L "${ROOT}/status/submitted_job_id.txt" ]]; then
  printf 'SUBMITTED_JOB_ID_FILE='
  tr -d '\r\n' < "${ROOT}/status/submitted_job_id.txt"
  printf '\n'
else
  echo "SUBMITTED_JOB_ID_FILE=MISSING_OR_LINKED"
fi

echo "=== SLURM QUEUE ==="
squeue -j "${JOB_ID}" -o '%.18i %.20j %.10P %.10T %.24R %.10M %.20S' 2>&1 || true

echo "=== SLURM ACCOUNTING ==="
sacct -j "${JOB_ID}" -n -P --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,NodeList,Start,End 2>&1 || true

echo "=== ALLOCATION PROBE JSON ==="
JSON_PATH="${ROOT}/status/allocation_probe.json"
if [[ -f "${JSON_PATH}" && ! -L "${JSON_PATH}" ]]; then
  stat -c 'JSON_SIZE_BYTES=%s JSON_LINKS=%h JSON_MODE=%a' "${JSON_PATH}" 2>&1 || true
  sha256sum "${JSON_PATH}" 2>&1 || true
  cat "${JSON_PATH}"
else
  echo "ALLOCATION_PROBE_JSON=ABSENT"
fi

echo "=== EXACT STANDARD OUTPUT ==="
OUT_PATH="${ROOT}/logs/probe-${JOB_ID}.out"
if [[ -f "${OUT_PATH}" && ! -L "${OUT_PATH}" ]]; then
  stat -c 'STDOUT_SIZE_BYTES=%s STDOUT_LINKS=%h STDOUT_MODE=%a' "${OUT_PATH}" 2>&1 || true
  sha256sum "${OUT_PATH}" 2>&1 || true
  cat "${OUT_PATH}"
else
  echo "PROBE_STDOUT=ABSENT"
fi

echo "=== EXACT STANDARD ERROR ==="
ERR_PATH="${ROOT}/logs/probe-${JOB_ID}.err"
if [[ -f "${ERR_PATH}" && ! -L "${ERR_PATH}" ]]; then
  stat -c 'STDERR_SIZE_BYTES=%s STDERR_LINKS=%h STDERR_MODE=%a' "${ERR_PATH}" 2>&1 || true
  sha256sum "${ERR_PATH}" 2>&1 || true
  cat "${ERR_PATH}"
else
  echo "PROBE_STDERR=ABSENT"
fi

echo "TUKF09_455_A800_EXCLUSIVE_SEMANTICS_PROBE_READONLY_STATUS_CAPTURED"
