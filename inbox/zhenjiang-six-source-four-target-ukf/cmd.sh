#!/bin/bash
set -eo pipefail

ROOT="/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r2"
FAILED_R1_ROOT="/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r1"
PROJECT_ROOT="${ROOT}/run"
REGISTRY="${PROJECT_ROOT}/docs/records/ZHENJIANG_SIX_SOURCE_FOUR_TARGET_D32_GRU_DIFFERENTIABLE_UKF_V1_REGISTRY.json"
UPSTREAM_SCRIPT="${PROJECT_ROOT}/scripts/hpc/zhenjiang_six_source_four_target_d32_gru_base_v1.slurm"
FILTER_SCRIPT="${PROJECT_ROOT}/scripts/hpc/zhenjiang_six_source_four_target_d32_gru_differentiable_ukf_v1.slurm"
DEVELOPMENT_SCRIPT="${PROJECT_ROOT}/scripts/hpc/zhenjiang_six_source_four_target_d32_gru_ukf_development_evaluation_v1.slurm"
CONFIRMATION="CONFIRM_ZHENJIANG_SIX_SOURCE_FOUR_TARGET_UKF_HPC_20260901"
EXPECTED_MANIFEST_SHA="f458886b60b123386be7e906eed8e4e80f8aa248998f1f8c3d15db17b3dd2688"
EXPECTED_REGISTRY_SHA="704366cb22eef1d3acb58f4f0524a6e50d49ffa442afcf0fca498fbd21154cb8"
EVENTS="${ROOT}/jobs/submission_chain_20260901_r2_events.jsonl"
CHAIN="${ROOT}/jobs/submission_chain_20260901_r2.json"
LAST_JOB_ID=""

fatal() {
  echo "[FATAL] $1"
  exit 1
}

printf '=== SUBMISSION_PREFLIGHT ===\n'
[ -d "${ROOT}" ] && [ ! -L "${ROOT}" ] || fatal "deployed r2 root is absent or linked"
[ ! -e "${ROOT}.partial" ] && [ ! -e "${ROOT}.staging" ] || fatal "r2 partial or staging root exists"
[ -d "${FAILED_R1_ROOT}.staging" ] && [ ! -L "${FAILED_R1_ROOT}.staging" ] || fatal "failed r1 staging evidence is absent"
[ ! -e "${FAILED_R1_ROOT}" ] && [ ! -e "${FAILED_R1_ROOT}.partial" ] || fatal "failed r1 formal or partial root unexpectedly exists"
stat -c 'PRESERVED_R1_STAGING|%F|%s|%n' "${FAILED_R1_ROOT}.staging"
[ "$(find "${ROOT}" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | tr '\n' ' ')" = "evidence inputs jobs logs run runs " ] || fatal "r2 top-level allow-list drift"
[ -z "$(find "${ROOT}" -type l -print -quit)" ] || fatal "r2 contains a symbolic link"
for file in "${REGISTRY}" "${UPSTREAM_SCRIPT}" "${FILTER_SCRIPT}" "${DEVELOPMENT_SCRIPT}"; do
  [ -f "${file}" ] && [ ! -L "${file}" ] || fatal "required registered file is absent or linked: ${file}"
done
[ "$(sha256sum "${ROOT}/jobs/bundle_manifest.json" | awk '{print $1}')" = "${EXPECTED_MANIFEST_SHA}" ] || fatal "retained manifest identity drift"
[ "$(sha256sum "${REGISTRY}" | awk '{print $1}')" = "${EXPECTED_REGISTRY_SHA}" ] || fatal "registry identity drift"
[ ! -e "${EVENTS}" ] && [ ! -e "${CHAIN}" ] || fatal "submission record already exists"

for seed in 17 29 43; do
  for relative in \
    "runs/base_smoke/s${seed}/attempt_001" \
    "runs/base/s${seed}/attempt_001" \
    "runs/observation_head_smoke/s${seed}/attempt_001" \
    "runs/observation_head/s${seed}/attempt_001" \
    "runs/filter_real_batch_smoke/s${seed}/attempt_001" \
    "runs/filter/s${seed}/attempt_001"
  do
    for candidate in "${ROOT}/${relative}" "${ROOT}/${relative}.partial"; do
      [ ! -e "${candidate}" ] && [ ! -L "${candidate}" ] || fatal "registered attempt collision: ${candidate}"
    done
  done
done
for relative in \
  "runs/development_evaluation_smoke/attempt_001" \
  "evidence/development_2023/evaluation/attempt_001" \
  "evidence/development_2023/independent_audit/attempt_001"
do
  for candidate in "${ROOT}/${relative}" "${ROOT}/${relative}.partial"; do
    [ ! -e "${candidate}" ] && [ ! -L "${candidate}" ] || fatal "registered post-training collision: ${candidate}"
  done
done

source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
export PYTHONDONTWRITEBYTECODE=1
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export PYTHONPATH="${PROJECT_ROOT}/scripts/modeling:${PROJECT_ROOT}/scripts/analysis:${PROJECT_ROOT}/scripts/astronomical_tide:${PROJECT_ROOT}/third_party/pytides:${PYTHONPATH:-}"
cd "${PROJECT_ROOT}"
bash -n "${UPSTREAM_SCRIPT}"
bash -n "${FILTER_SCRIPT}"
bash -n "${DEVELOPMENT_SCRIPT}"
python scripts/modeling/register_zhenjiang_six_source_four_target_d32_gru_ukf_v1.py --validate-only

set -C
: > "${EVENTS}"
set +C

submit_job() {
  local label="$1"
  shift
  local output rc job_id
  set +e
  output=$(sbatch "$@" 2>&1)
  rc=$?
  set -e
  printf '%s\n' "${output}"
  [ ${rc} -eq 0 ] || fatal "sbatch failed for ${label} with exit ${rc}"
  job_id=$(printf '%s\n' "${output}" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
  [ -n "${job_id}" ] && [ "$(printf '%s\n' "${job_id}" | wc -l)" -eq 1 ] || fatal "cannot parse one job id for ${label}"
  printf '{"stage":"%s","job_id":"%s"}\n' "${label}" "${job_id}" >> "${EVENTS}"
  LAST_JOB_ID="${job_id}"
}

printf '=== SUBMIT_DEPENDENCY_CHAIN ===\n'
submit_job base_preflight "${UPSTREAM_SCRIPT}" preflight "" base
BASE_PREFLIGHT="${LAST_JOB_ID}"

submit_job development_preflight "${DEVELOPMENT_SCRIPT}" preflight
DEVELOPMENT_PREFLIGHT="${LAST_JOB_ID}"

submit_job base_formal --dependency="afterok:${BASE_PREFLIGHT}" \
  "${UPSTREAM_SCRIPT}" formal "${CONFIRMATION}" base
BASE_FORMAL="${LAST_JOB_ID}"

submit_job observation_head_preflight --dependency="afterok:${BASE_FORMAL}" \
  "${UPSTREAM_SCRIPT}" preflight "" observation_head
OBSERVATION_HEAD_PREFLIGHT="${LAST_JOB_ID}"

submit_job observation_head_formal --dependency="afterok:${OBSERVATION_HEAD_PREFLIGHT}" \
  "${UPSTREAM_SCRIPT}" formal "${CONFIRMATION}" observation_head
OBSERVATION_HEAD_FORMAL="${LAST_JOB_ID}"

submit_job filter_real_batch_preflight --dependency="afterok:${OBSERVATION_HEAD_FORMAL}" \
  "${FILTER_SCRIPT}" preflight "${CONFIRMATION}"
FILTER_PREFLIGHT="${LAST_JOB_ID}"

submit_job filter_formal --dependency="afterok:${FILTER_PREFLIGHT}" \
  "${FILTER_SCRIPT}" formal "${CONFIRMATION}"
FILTER_FORMAL="${LAST_JOB_ID}"

submit_job development_2023_formal \
  --dependency="afterok:${FILTER_FORMAL}:${DEVELOPMENT_PREFLIGHT}" \
  "${DEVELOPMENT_SCRIPT}" formal "${CONFIRMATION}"
DEVELOPMENT_FORMAL="${LAST_JOB_ID}"

python - "${EVENTS}" "${CHAIN}" \
  "${BASE_PREFLIGHT}" "${DEVELOPMENT_PREFLIGHT}" "${BASE_FORMAL}" \
  "${OBSERVATION_HEAD_PREFLIGHT}" "${OBSERVATION_HEAD_FORMAL}" \
  "${FILTER_PREFLIGHT}" "${FILTER_FORMAL}" "${DEVELOPMENT_FORMAL}" <<'PY'
from __future__ import annotations
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sys

events_path = Path(sys.argv[1])
chain_path = Path(sys.argv[2])
ids = sys.argv[3:]
labels = [
    "base_preflight",
    "development_preflight",
    "base_formal",
    "observation_head_preflight",
    "observation_head_formal",
    "filter_real_batch_preflight",
    "filter_formal",
    "development_2023_formal",
]
rows = [json.loads(line) for line in events_path.read_text(encoding="utf-8").splitlines()]
if (
    len(ids) != 8
    or any(not value.isdigit() for value in ids)
    or len(set(ids)) != 8
    or rows != [
        {"stage": label, "job_id": job_id}
        for label, job_id in zip(labels, ids)
    ]
):
    raise SystemExit("submission event identities drift")
jobs = {
    label: {
        "job_id": job_id,
        "job_shape": "array_0_2" if label not in {
            "development_preflight", "development_2023_formal"
        } else "single",
        "depends_on": [],
    }
    for label, job_id in zip(labels, ids)
}
jobs["base_formal"]["depends_on"] = [ids[0]]
jobs["observation_head_preflight"]["depends_on"] = [ids[2]]
jobs["observation_head_formal"]["depends_on"] = [ids[3]]
jobs["filter_real_batch_preflight"]["depends_on"] = [ids[4]]
jobs["filter_formal"]["depends_on"] = [ids[5]]
jobs["development_2023_formal"]["depends_on"] = [ids[6], ids[1]]
document = {
    "schema_version": 1,
    "status": "submitted_dependency_chain",
    "submitted_at_utc": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    "remote_root": "/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r2",
    "failed_r1_staging_preserved": True,
    "archive_sha256": "56935861d76557f2c6047b3b580030d6dad4d042b3549796fc1f2079f72b8776",
    "manifest_sha256": "f458886b60b123386be7e906eed8e4e80f8aa248998f1f8c3d15db17b3dd2688",
    "registry_sha256": "704366cb22eef1d3acb58f4f0524a6e50d49ffa442afcf0fca498fbd21154cb8",
    "heldout_2024_target_access_authorized": False,
    "scientific_result_created": False,
    "jobs": jobs,
}
with chain_path.open("x", encoding="utf-8", newline="\n") as handle:
    json.dump(document, handle, indent=2, sort_keys=True)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
print(json.dumps(document, indent=2, sort_keys=True))
PY
chmod 0444 "${EVENTS}" "${CHAIN}"

ALL_IDS="${BASE_PREFLIGHT},${DEVELOPMENT_PREFLIGHT},${BASE_FORMAL},${OBSERVATION_HEAD_PREFLIGHT},${OBSERVATION_HEAD_FORMAL},${FILTER_PREFLIGHT},${FILTER_FORMAL},${DEVELOPMENT_FORMAL}"
printf '=== QUEUE_AFTER_SUBMISSION ===\n'
squeue -j "${ALL_IDS}" -o '%i|%j|%T|%P|%N|%M|%l|%R' || true
echo "SUBMISSION_RECORD=${CHAIN}"
echo "HELDOUT_2024_TARGET_ACCESS_AUTHORIZED=false"
echo "[DONE] submitted exactly eight dependency jobs without altering existing jobs"
