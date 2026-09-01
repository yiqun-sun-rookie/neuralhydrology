#!/usr/bin/env bash
set -euo pipefail
umask 077

REMOTE_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_per_basin_pilots_20260901"
DEPLOYMENT_ID="DAILY_CAMELS_KNET_PER_BASIN_BUNDLE_DEPLOY3_SEQ12"
SOURCE_DIRECTORY="${REMOTE_ROOT}/deployments/${DEPLOYMENT_ID}/source"
DEPLOYMENT_RECEIPT="${REMOTE_ROOT}/deployments/${DEPLOYMENT_ID}/deployment_receipt.txt"
EXPECTED_DEPLOYMENT_RECEIPT_SHA256="7d6d5fb9aee79e1effd4ffb1a83edbc0ec756d811054f604b1cb7db878787e27"
PROBE_RECEIPT="${REMOTE_ROOT}/probes/DAILY_CAMELS_KNET_PER_BASIN_PILOT_A800_PROBE3_SEQ5/probe_receipt.json"
EXPECTED_PROBE_SHA256="be039638e7b8625aa48ed3c044fff53c4d8c63504605d48c63ff1924167d4f65"
BASIN_ID="04105700"
STATE_DIMENSION="7"
CONFIG_RELATIVE="configs/daily_camels_knet_per_basin_pilot_04105700.json"
CONFIG_PATH="${SOURCE_DIRECTORY}/${CONFIG_RELATIVE}"
EXPECTED_CONFIG_SHA256="eb6cf615a40cc6dcee9da34713621d52cbf3ef3a34b3eb02a3be3b4537f8ad55"
FAILED_EXECUTION_ID="DAILY_CAMELS_KNET_PER_BASIN_PILOT_04105700_A800_TRAIN2_SEQ10"
FAILED_JOB_ID="217410"
EXECUTION_ID="DAILY_CAMELS_KNET_PER_BASIN_PILOT_04105700_A800_TRAIN3_SEQ13"
JOB_NAME="kdpp-04105700-s13"
STATUS_DIRECTORY="${REMOTE_ROOT}/status"
RUN_DIRECTORY="${REMOTE_ROOT}/runs/${EXECUTION_ID}"
AUDIT_REPORT="${STATUS_DIRECTORY}/${EXECUTION_ID}.audit.json"
SUBMISSION_RECEIPT="${STATUS_DIRECTORY}/${EXECUTION_ID}.submission_receipt.txt"
STDOUT_PATTERN="${STATUS_DIRECTORY}/${EXECUTION_ID}.slurm-%j.out"
STDERR_PATTERN="${STATUS_DIRECTORY}/${EXECUTION_ID}.slurm-%j.err"
WRAPPER="${SOURCE_DIRECTORY}/hpc/daily_camels_knet_per_basin/submit_train_gpu.slurm"

echo '=== FRAMEWORK-FREE FIRST PILOT SUBMISSION IDENTITY ==='
date --iso-8601=seconds
hostname
echo 'channel=kalmannet-daily-perbasin sequence=13 purpose=submit-once-04105700-after-framework-free-runtime-gate-repair'
echo "basin_id=${BASIN_ID} state_dimension=${STATE_DIMENSION}"

if [[ ! -f "${DEPLOYMENT_RECEIPT}" ]] || \
   [[ "$(sha256sum "${DEPLOYMENT_RECEIPT}" | awk '{print $1}')" != "${EXPECTED_DEPLOYMENT_RECEIPT_SHA256}" ]]; then
  echo 'framework-free deployment receipt is absent or changed' >&2
  exit 100
fi
if [[ ! -f "${PROBE_RECEIPT}" ]] || \
   [[ "$(sha256sum "${PROBE_RECEIPT}" | awk '{print $1}')" != "${EXPECTED_PROBE_SHA256}" ]]; then
  echo 'passing A800 probe receipt is absent or changed' >&2
  exit 101
fi
if [[ ! -f "${CONFIG_PATH}" ]] || \
   [[ "$(sha256sum "${CONFIG_PATH}" | awk '{print $1}')" != "${EXPECTED_CONFIG_SHA256}" ]]; then
  echo '04105700 frozen configuration is absent or changed' >&2
  exit 102
fi
if [[ ! -f "${WRAPPER}" ]] || grep -F -q 'pytest' "${WRAPPER}" || \
   ! grep -F -q 'scripts/check_daily_camels_knet_per_basin_runtime.py' "${WRAPPER}"; then
  echo 'framework-free training wrapper is absent or changed' >&2
  exit 103
fi
if [[ -e "${REMOTE_ROOT}/runs/${FAILED_EXECUTION_ID}" ]] || \
   ! sacct -j "${FAILED_JOB_ID}" -X --format=JobIDRaw,State,ExitCode -n -P | \
     grep -F -x -q "${FAILED_JOB_ID}|FAILED|1:0"; then
  echo 'previous pre-training failure evidence changed' >&2
  exit 104
fi

mkdir -p "${STATUS_DIRECTORY}" "${REMOTE_ROOT}/runs"
for target in \
  "${RUN_DIRECTORY}" \
  "${AUDIT_REPORT}" \
  "${SUBMISSION_RECEIPT}" \
  "${STATUS_DIRECTORY}/${EXECUTION_ID}.gpu.csv" \
  "${STATUS_DIRECTORY}/${EXECUTION_ID}.cgroup.txt" \
  "${STATUS_DIRECTORY}/${EXECUTION_ID}.entry.json" \
  "${STATUS_DIRECTORY}/locks/${EXECUTION_ID}.lock"
do
  if [[ -e "${target}" ]]; then
    echo "refusing pre-existing execution target: ${target}" >&2
    exit 105
  fi
done
if find "${STATUS_DIRECTORY}" -maxdepth 1 -type f \
  \( -name "${EXECUTION_ID}.slurm-*.out" -o -name "${EXECUTION_ID}.slurm-*.err" \) \
  -print -quit | grep -q .; then
  echo 'refusing pre-existing Slurm output for this execution identity' >&2
  exit 106
fi

set +u
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH="${SOURCE_DIRECTORY}/src:${SOURCE_DIRECTORY}"
python -u "${SOURCE_DIRECTORY}/scripts/build_daily_camels_knet_per_basin_hpc_bundle.py" \
  --inspect-root "${SOURCE_DIRECTORY}"
python - "${CONFIG_PATH}" "${REMOTE_ROOT}/runs" "${EXECUTION_ID}" "${SOURCE_DIRECTORY}" <<'PY'
from pathlib import Path
import sys

from scripts.run_daily_camels_knet_per_basin_pilot import standard_preflight

preflight = standard_preflight(
    Path(sys.argv[1]),
    output_parent=Path(sys.argv[2]),
    execution_id=sys.argv[3],
    repository_root=Path(sys.argv[4]),
)
print(
    "preflight_status=PASS "
    f"basin_id={preflight.basin_specification.basin_id} "
    f"state_dimension={preflight.basin_specification.state_dimension} "
    f"configuration_sha256={preflight.configuration_sha256} "
    f"run_directory={preflight.run_directory}"
)
PY

echo '=== LIVE GPU RESOURCE STATE BEFORE SUBMISSION ==='
sinfo -N -n ngu201,ngu202,ngu203 -o '%N|%P|%T|%G|%C|%m'
squeue -u sunyiq -p hgpu8,hgpu4,hgpu2 -o '%i|%j|%P|%T|%R|%M|%S|%N'
ACTIVE_EXACT_BEFORE="$(squeue -h -u sunyiq -o '%i|%j|%T|%N' | awk -F'|' -v name="${JOB_NAME}" '$2 == name {count++} END {print count+0}')"
HISTORICAL_EXACT_BEFORE="$(sacct -u sunyiq -S 2026-09-01T00:00:00 -X --format=JobIDRaw,JobName,State -n -P | awk -F'|' -v name="${JOB_NAME}" '$2 == name {count++} END {print count+0}')"
ACTIVE_PILOT_TRAINING_BEFORE="$(squeue -h -u sunyiq -o '%i|%j|%T|%N' | awk -F'|' '$2 ~ /^kdpp-(04105700|08070200|09035800)-s/ {count++} END {print count+0}')"
echo "active_exact_before=${ACTIVE_EXACT_BEFORE}"
echo "historical_exact_before=${HISTORICAL_EXACT_BEFORE}"
echo "active_three_pilot_training_before=${ACTIVE_PILOT_TRAINING_BEFORE}"
if [[ "${ACTIVE_EXACT_BEFORE}" != "0" || "${HISTORICAL_EXACT_BEFORE}" != "0" || \
      "${ACTIVE_PILOT_TRAINING_BEFORE}" != "0" ]]; then
  echo 'duplicate or concurrent pilot training detected before submission' >&2
  exit 107
fi

cd "${SOURCE_DIRECTORY}"
JOB_ID="$(sbatch \
  --parsable \
  --job-name="${JOB_NAME}" \
  --output="${STDOUT_PATTERN}" \
  --error="${STDERR_PATTERN}" \
  --export="ALL,PILOT_REMOTE_ROOT=${REMOTE_ROOT},PILOT_CONFIG_RELATIVE=${CONFIG_RELATIVE},PILOT_EXECUTION_ID=${EXECUTION_ID},PILOT_AUDIT_REPORT=${AUDIT_REPORT}" \
  "${WRAPPER}")"
case "${JOB_ID}" in
  ''|*[!0-9]*) echo "invalid Slurm job identifier: ${JOB_ID}" >&2; exit 108 ;;
esac

ACTIVE_JOB_AFTER="$(squeue -h -j "${JOB_ID}" -o '%i|%j|%T|%N' | wc -l | tr -d ' ')"
ACTIVE_EXACT_AFTER="$(squeue -h -u sunyiq -o '%i|%j|%T|%N' | awk -F'|' -v name="${JOB_NAME}" '$2 == name {count++} END {print count+0}')"
if [[ "${ACTIVE_JOB_AFTER}" != "1" || "${ACTIVE_EXACT_AFTER}" != "1" ]]; then
  echo 'post-submission uniqueness proof failed' >&2
  exit 109
fi

if [[ -e "${SUBMISSION_RECEIPT}" ]]; then
  echo 'refusing to replace pilot submission receipt' >&2
  exit 110
fi
{
  printf 'channel=kalmannet-daily-perbasin\n'
  printf 'sequence=13\n'
  printf 'basin_id=%s\n' "${BASIN_ID}"
  printf 'state_dimension=%s\n' "${STATE_DIMENSION}"
  printf 'execution_id=%s\n' "${EXECUTION_ID}"
  printf 'job_name=%s\n' "${JOB_NAME}"
  printf 'job_id=%s\n' "${JOB_ID}"
  printf 'configuration_sha256=%s\n' "${EXPECTED_CONFIG_SHA256}"
  printf 'deployment_receipt_sha256=%s\n' "${EXPECTED_DEPLOYMENT_RECEIPT_SHA256}"
  printf 'probe_receipt_sha256=%s\n' "${EXPECTED_PROBE_SHA256}"
  printf 'active_exact_before=%s\n' "${ACTIVE_EXACT_BEFORE}"
  printf 'historical_exact_before=%s\n' "${HISTORICAL_EXACT_BEFORE}"
  printf 'active_three_pilot_training_before=%s\n' "${ACTIVE_PILOT_TRAINING_BEFORE}"
  printf 'active_job_after=%s\n' "${ACTIVE_JOB_AFTER}"
  printf 'active_exact_after=%s\n' "${ACTIVE_EXACT_AFTER}"
  printf 'submission_count=1\n'
  printf 'signals_sent=0\n'
  printf 'formal_evaluation_access_count=0\n'
} > "${SUBMISSION_RECEIPT}"

echo '=== SUBMISSION RECEIPT ==='
sha256sum "${SUBMISSION_RECEIPT}"
cat "${SUBMISSION_RECEIPT}"
echo '=== CURRENT PILOT JOB ==='
squeue -j "${JOB_ID}" -o '%i|%j|%P|%T|%R|%M|%S|%N'
echo '=== SUBMISSION COMPLETE: EXACTLY ONE 04105700 TRAINING JOB, NO SIGNAL ==='
