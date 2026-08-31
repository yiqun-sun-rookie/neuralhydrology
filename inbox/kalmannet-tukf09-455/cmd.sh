#!/bin/bash
# Submit exactly one allocation-only GPU mapping probe for the isolated revision.
set -eo pipefail

ROOT=/data1/home/sunyiq/kalmannet_tukf09_455_basin_zero_validation_target_variance_revision_v1_20260831
PROJECT_ROOT="${ROOT}/bundle/kalmannet"
SUBMISSION_RECORD="${ROOT}/status/allocation_probe_submission.txt"
JOB_NAME=tukf09-455-gpu-map

test -d "${ROOT}"
test -d "${ROOT}/bundle"
test -d "${PROJECT_ROOT}"
test -d "${ROOT}/logs"
test -d "${ROOT}/status"
test ! -e "${SUBMISSION_RECORD}"
test ! -L "${SUBMISSION_RECORD}"

source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh" || \
source "${HOME}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final || { echo "CONDA_FAILED" >&2; exit 62; }
export PYTHONNOUSERSITE=1
export PYTHONDONTWRITEBYTECODE=1
PYTHON="${CONDA_PREFIX}/bin/python"

"${PYTHON}" -B "${PROJECT_ROOT}/scripts/build_tukf09_455_hpc_bundle.py" \
  --verify-extracted "${ROOT}/bundle"

existing_jobs="$(squeue -h -u "${USER}" -n "${JOB_NAME}" -o '%A' | tr -d '[:space:]')"
if [[ -n "${existing_jobs}" ]]; then
  echo "REFUSING_DUPLICATE_ALLOCATION_PROBE=${existing_jobs}" >&2
  exit 63
fi

cd "${PROJECT_ROOT}"
submission="$(sbatch hpc/tukf09_455_basin_revision/allocation_probe.slurm)"
echo "${submission}"
if [[ ! "${submission}" =~ ^Submitted\ batch\ job\ ([0-9]+)$ ]]; then
  echo "UNEXPECTED_SBATCH_RESPONSE=${submission}" >&2
  exit 64
fi
job_id="${BASH_REMATCH[1]}"

pending_record="${ROOT}/status/.allocation_probe_submission.${job_id}.$$"
printf 'job_id=%s\nslurm_response=%s\n' "${job_id}" "${submission}" > "${pending_record}"
ln "${pending_record}" "${SUBMISSION_RECORD}"
rm -f "${pending_record}"

echo "ALLOCATION_PROBE_JOB_ID=${job_id}"
squeue -h -j "${job_id}" -o 'job_id=%A state=%T partition=%P node=%R' || true
echo "TUKF09_455_GPU_ALLOCATION_MAPPING_SUBMITTED"
