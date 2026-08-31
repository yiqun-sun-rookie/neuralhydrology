#!/bin/bash
# Read-only forensic capture for failed preparation job 217149.
set -o pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2_20260831
JOB_ID=217149
PENDING="${ROOT}/runtime_v2.pending.${JOB_ID}"
EVIDENCE="${PENDING}/evidence"

echo "=== FIXED FAILED JOB ==="
echo "REMOTE_ROOT=${ROOT}"
echo "PREPARATION_JOB_ID=${JOB_ID}"
sacct -j "${JOB_ID}" -n -P --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,NodeList,Start,End 2>&1 || true

echo "=== PREPARATION LOCK AND PENDING ROOT ==="
for item in "${ROOT}/status/preparation.lock" "${ROOT}/status/initial_bundle_verification.json"; do
  if [[ -f "${item}" && ! -L "${item}" ]]; then
    stat -c 'FILE=%n SIZE_BYTES=%s LINKS=%h MODE=%a MTIME=%y' "${item}" 2>&1 || true
    sha256sum "${item}" 2>&1 || true
  elif [[ -e "${item}" || -L "${item}" ]]; then
    echo "IRREGULAR=${item}"
  else
    echo "ABSENT=${item}"
  fi
done
if [[ -d "${PENDING}" && ! -L "${PENDING}" ]]; then
  stat -c 'PENDING=%n LINKS=%h MODE=%a MTIME=%y' "${PENDING}" 2>&1 || true
  du -sb "${PENDING}" 2>&1 || true
  find "${PENDING}" -maxdepth 2 -mindepth 1 -printf '%y|%p|%s|%n|%m\n' 2>&1 | LC_ALL=C sort || true
elif [[ -e "${PENDING}" || -L "${PENDING}" ]]; then
  echo "PENDING_ROOT=IRREGULAR"
else
  echo "PENDING_ROOT=ABSENT"
fi

echo "=== EXACT PIP AND RUNTIME EVIDENCE ==="
for name in \
  pip-command.txt \
  pip-stdout.log \
  pip-stderr.log \
  runtime-import-check.txt \
  psutil-built-wheel.sha256 \
  pip-install-report.json \
  private_runtime_manifest.json; do
  item="${EVIDENCE}/${name}"
  if [[ -f "${item}" && ! -L "${item}" ]]; then
    stat -c 'EVIDENCE=%n SIZE_BYTES=%s LINKS=%h MODE=%a MTIME=%y' "${item}" 2>&1 || true
    sha256sum "${item}" 2>&1 || true
    cat "${item}"
  elif [[ -e "${item}" || -L "${item}" ]]; then
    echo "EVIDENCE_IRREGULAR=${item}"
  else
    echo "EVIDENCE_ABSENT=${item}"
  fi
done

echo "=== DOWNLOADED OR BUILT FILE INVENTORY ==="
for directory in wheelhouse sourcehouse built_wheels pysite.pending pysite; do
  item="${PENDING}/${directory}"
  if [[ -d "${item}" && ! -L "${item}" ]]; then
    echo "DIRECTORY=${item}"
    find "${item}" -maxdepth 1 -type f -printf '%f|%s|%n|%m\n' 2>&1 | LC_ALL=C sort || true
  elif [[ -e "${item}" || -L "${item}" ]]; then
    echo "DIRECTORY_IRREGULAR=${item}"
  else
    echo "DIRECTORY_ABSENT=${item}"
  fi
done

echo "=== UNPUBLISHED LATER-STAGE OUTPUTS ==="
for item in \
  "${ROOT}/runtime_v2" \
  "${ROOT}/status/staged_training_sources.json" \
  "${ROOT}/status/preparation_probe.json" \
  "${ROOT}/status/hpc_technical_admission.json"; do
  if [[ -e "${item}" || -L "${item}" ]]; then
    echo "LATER_STAGE_OUTPUT_PRESENT=${item}"
  else
    echo "LATER_STAGE_OUTPUT_ABSENT=${item}"
  fi
done
echo "TUKF09_455_A800_EXCLUSIVE_V2_FAILED_PREPARATION_FORENSICS_CAPTURED"
