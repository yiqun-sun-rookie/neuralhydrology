#!/bin/bash
set -eo pipefail
umask 077

ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828_r2"
INPUT_DIR="${ROOT}/inputs/pre2024-v1"
PATHS_FILE="${ROOT}/hpc_paths.env"
SCRIPT="${ROOT}/run/scripts/hpc/zhenjiang_d32_gru_differentiable_ukf_smoke_v1.slurm"
ATTEMPT="${ROOT}/runs/smoke/ZHD32-DUKF-HPC-SMOKE-V1/attempt_001"
JOB_FILE="${ROOT}/jobs/smoke_job_id.txt"

fatal() {
  echo "[FATAL] $1"
  exit 1
}

[ -d "${ROOT}" ] || fatal "version-four deployment root is absent"
[ -f "${PATHS_FILE}" ] || fatal "hpc_paths.env is absent"
[ "$(wc -l < "${PATHS_FILE}" | tr -d '[:space:]')" = "1" ] || \
  fatal "hpc_paths.env does not contain exactly one line"
[ "$(cat "${PATHS_FILE}")" = "INPUT_DIR=${INPUT_DIR}" ] || \
  fatal "isolated input contract changed"
[ "$(readlink -f "${INPUT_DIR}")" = "${INPUT_DIR}" ] || \
  fatal "isolated input canonical path changed"
[ -d "${INPUT_DIR}" ] || fatal "isolated input directory is absent"
[ ! -L "${INPUT_DIR}" ] || fatal "isolated input directory is a symbolic link"
[ -f "${INPUT_DIR}/pre2024_input_manifest.json" ] || \
  fatal "isolated input manifest is absent"
[ -f "${SCRIPT}" ] || fatal "smoke script is absent"
[ ! -L "${SCRIPT}" ] || fatal "smoke script is a symbolic link"
[ "$(sha256sum "${SCRIPT}" | awk '{print $1}')" = \
  "d779934c45f2a810627b7a5918f1cc9ca6d1ef372f003a0826b899dbc37726d6" ] || \
  fatal "version-four smoke script identity changed"
[ ! -e "${ATTEMPT}" ] || fatal "smoke attempt already exists"
[ ! -e "${ATTEMPT}.partial" ] || fatal "partial smoke attempt already exists"
[ ! -e "${JOB_FILE}" ] || fatal "smoke job identity already exists"
[ ! -e "${JOB_FILE}.partial" ] || fatal "partial smoke job identity exists"

python - "${INPUT_DIR}/pre2024_input_manifest.json" <<'PY'
from pathlib import Path
import json
import sys

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if manifest.get("file_count") != 13 or len(manifest.get("files", [])) != 13:
    raise SystemExit("pre-2024 file count changed")
if manifest.get("maximum_target_time_beijing") != "2023-12-31T23:00:00+08:00":
    raise SystemExit("pre-2024 maximum target time changed")
counter = manifest.get("later_target_bytes_requested")
if type(counter) is not int or counter != 0:
    raise SystemExit("later-target byte counter is not integer zero")
print("PRE2024_RERUN_SUBMISSION_GATE=PASS")
PY

bash -n "${SCRIPT}"
existing="$(
  squeue -u "${USER}" -h -o '%i|%j|%T' | \
    awk -F'|' '$2 == "zhd32-dukf-smoke" {print}'
)"
[ -z "${existing}" ] || fatal "same-name smoke job already exists: ${existing}"

set +e
receipt="$(sbatch "${SCRIPT}" 2>&1)"
submit_rc=$?
set -e
printf '%s\n' "${receipt}"
submission_lines="$(
  printf '%s\n' "${receipt}" | grep -E '^Submitted batch job [0-9]+$' || true
)"
line_count="$(
  printf '%s\n' "${submission_lines}" | sed '/^$/d' | wc -l | tr -d '[:space:]'
)"
[ "${line_count}" = "1" ] || fatal "submission receipt did not contain exactly one accepted job"
job_id="${submission_lines##* }"
[[ "${job_id}" =~ ^[0-9]+$ ]] || fatal "submitted job identifier is invalid"
printf '%s\n' "${job_id}" > "${JOB_FILE}.partial"
chmod 0400 "${JOB_FILE}.partial"
mv "${JOB_FILE}.partial" "${JOB_FILE}"
[ "${submit_rc}" -eq 0 ] || fatal "job was submitted but sbatch returned nonzero"

echo "SMOKE_RERUN_SUBMISSION=ACCEPTED"
echo "SMOKE_RERUN_JOB_ID=${job_id}"
squeue -j "${job_id}" -h -o '%i|%P|%j|%T|%M|%l|%R' || true
