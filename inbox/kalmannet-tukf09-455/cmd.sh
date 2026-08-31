#!/bin/bash
# Read-only forensic capture for failed v2r1 preparation job 217163.
set -o pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_a800_exclusive_v2r1_20260901
JOB_ID=217163
PENDING="${ROOT}/runtime_v2r1.pending.${JOB_ID}"
EVIDENCE="${PENDING}/evidence"
RESULTS_ROOT="${ROOT}/bundle/kalmannet/results/tukf09_455_basin_zero_validation_target_variance_revision_v1"

echo "=== FIXED FAILED JOB ==="
echo "REMOTE_ROOT=${ROOT}"
echo "PREPARATION_JOB_ID=${JOB_ID}"
sacct -j "${JOB_ID}" -n -P --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,NodeList,Start,End 2>&1 || true

echo "=== LOCKS, JOB ID, AND INITIAL VERIFICATION ==="
for item in \
  "${ROOT}/status/preparation_submission.lock" \
  "${ROOT}/status/preparation.lock" \
  "${ROOT}/status/preparation_job_id.txt" \
  "${ROOT}/status/initial_bundle_verification.json"; do
  if [[ -f "${item}" && ! -L "${item}" ]]; then
    stat -c 'FILE=%n SIZE_BYTES=%s LINKS=%h MODE=%a MTIME=%y' "${item}" 2>&1 || true
    sha256sum "${item}" 2>&1 || true
    case "${item}" in
      *.json|*.txt) cat "${item}" ;;
    esac
  elif [[ -d "${item}" && ! -L "${item}" ]]; then
    stat -c 'DIRECTORY=%n LINKS=%h MODE=%a MTIME=%y' "${item}" 2>&1 || true
  elif [[ -e "${item}" || -L "${item}" ]]; then
    echo "IRREGULAR=${item}"
  else
    echo "ABSENT=${item}"
  fi
done

echo "=== FAILED PENDING ROOT INVENTORY ==="
if [[ -d "${PENDING}" && ! -L "${PENDING}" ]]; then
  stat -c 'PENDING=%n LINKS=%h MODE=%a MTIME=%y' "${PENDING}" 2>&1 || true
  du -sb "${PENDING}" 2>&1 || true
  find "${PENDING}" -mindepth 1 -maxdepth 3 -printf '%y|%p|%s|%n|%m\n' 2>&1 | sort || true
else
  echo "PENDING_ROOT_ABSENT_OR_IRREGULAR=${PENDING}"
fi

echo "=== EXACT RUNTIME EVIDENCE ==="
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

echo "=== DOWNLOADED, BUILT, OR INSTALLED FILE INVENTORY ==="
for directory in \
  "${PENDING}/wheelhouse" \
  "${PENDING}/sourcehouse" \
  "${PENDING}/built_wheels" \
  "${PENDING}/pysite.pending" \
  "${PENDING}/pysite"; do
  if [[ -d "${directory}" && ! -L "${directory}" ]]; then
    echo "DIRECTORY=${directory}"
    find "${directory}" -type f -printf '%p|%s|%m\n' 2>&1 | sort || true
    while IFS= read -r file; do
      sha256sum "${file}" 2>&1 || true
    done < <(find "${directory}" -type f -print 2>/dev/null | sort)
  elif [[ -e "${directory}" || -L "${directory}" ]]; then
    echo "DIRECTORY_IRREGULAR=${directory}"
  else
    echo "DIRECTORY_ABSENT=${directory}"
  fi
done

echo "=== EXACT SLURM LOGS ==="
for item in "${ROOT}/logs/prepare-${JOB_ID}.out" "${ROOT}/logs/prepare-${JOB_ID}.err"; do
  if [[ -f "${item}" && ! -L "${item}" ]]; then
    stat -c 'LOG=%n SIZE_BYTES=%s LINKS=%h MODE=%a MTIME=%y' "${item}" 2>&1 || true
    sha256sum "${item}" 2>&1 || true
    cat "${item}"
  else
    echo "LOG_ABSENT_OR_IRREGULAR=${item}"
  fi
done

echo "=== UNPUBLISHED LATER-STAGE OUTPUTS ==="
for item in \
  "${ROOT}/runtime_v2r1" \
  "${ROOT}/status/staged_training_sources.json" \
  "${ROOT}/status/preparation_probe.json" \
  "${ROOT}/status/hpc_technical_admission.json" \
  "${RESULTS_ROOT}"; do
  if [[ -e "${item}" || -L "${item}" ]]; then
    echo "LATER_STAGE_OUTPUT_PRESENT=${item}"
  else
    echo "LATER_STAGE_OUTPUT_ABSENT=${item}"
  fi
done
for name in selection evaluation formal_evaluation; do
  if [[ -e "${RESULTS_ROOT}/${name}" || -L "${RESULTS_ROOT}/${name}" ]]; then
    echo "FORBIDDEN_OUTPUT_PRESENT=${name}"
  else
    echo "FORBIDDEN_OUTPUT_ABSENT=${name}"
  fi
done
echo "TUKF09_455_A800_EXCLUSIVE_V2R1_FAILED_PREPARATION_FORENSICS_CAPTURED"
