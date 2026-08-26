#!/bin/bash
set -o pipefail

LANDING=/data1/home/sunyiq/id18_ties_merge_20260826
ARCHIVE=/data1/home/sunyiq/hpc_mailbox/payload/id18-weight-merge/tm01_9f859f768bd49862c8238ac087641a2d1eeda7a6c44d9ce47750c02f02d1b91f.tar.gz
ARCHIVE_SHA256=9f859f768bd49862c8238ac087641a2d1eeda7a6c44d9ce47750c02f02d1b91f
SLURM=${LANDING}/payload/code/src/lstm_fair_531/hpc/submit_tm01_sign_aware_task_vector_merge.slurm

echo "=== TM01 DEPLOYMENT PREFLIGHT ==="
date -Is
hostname
pwd
[ -f "${ARCHIVE}" ] || { echo "ARCHIVE_MISSING=${ARCHIVE}"; exit 1; }
ACTUAL_SHA256=$(sha256sum "${ARCHIVE}" | awk '{print $1}')
echo "archive_sha256=${ACTUAL_SHA256}"
[ "${ACTUAL_SHA256}" = "${ARCHIVE_SHA256}" ] || { echo "ARCHIVE_HASH_MISMATCH"; exit 2; }
[ ! -e "${LANDING}" ] || { echo "LANDING_ALREADY_EXISTS=${LANDING}"; exit 3; }

mkdir "${LANDING}" || exit 1
tar -xzf "${ARCHIVE}" -C "${LANDING}" || exit 1
find "${LANDING}/payload/code/src/lstm_fair_531" -type f \( -name '*.py' -o -name '*.slurm' \) \
    -exec sed -i 's/\r$//' {} + || exit 1

echo "=== PAYLOAD MANIFEST VERIFY ==="
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || \
source ${HOME}/miniconda3/etc/profile.d/conda.sh
conda activate nh_final || { echo "CONDA_FAILED"; exit 1; }
python - <<'PY' || exit 1
import hashlib
import json
from pathlib import Path

root = Path("/data1/home/sunyiq/id18_ties_merge_20260826/payload")
manifest_path = root / "TM01_PAYLOAD_MANIFEST.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
if manifest["unrestricted_data_included"] is not False:
    raise SystemExit("UNRESTRICTED_DATA_FLAG_FAILED")
if manifest["excluded_files"] != ["camels_attributes_v2.0/camels_hydro.txt"]:
    raise SystemExit("EXCLUSION_LIST_DRIFTED")
for record in manifest["files"]:
    path = root / record["path"]
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != record["sha256"] or path.stat().st_size != record["size_bytes"]:
        raise SystemExit(f"PAYLOAD_MEMBER_MISMATCH {record['path']}")
excluded = root / "data/camels_us_id18_20000105_20080930/camels_attributes_v2.0/camels_hydro.txt"
if excluded.exists():
    raise SystemExit("EXCLUDED_HYDROLOGICAL_SIGNATURE_FILE_PRESENT")
print("PAYLOAD_MANIFEST_OK", len(manifest["files"]))
print("CONTRACT_SHA256", manifest["contract_sha256"])
print("PINNED_CODE_COMMIT", manifest["pinned_code_commit"])
PY

echo "=== SUBMIT TM01 COMPUTE JOB ==="
[ -f "${SLURM}" ] || { echo "SLURM_MISSING=${SLURM}"; exit 1; }
SUBMIT_OUTPUT=$(sbatch "${SLURM}" 2>&1)
echo "${SUBMIT_OUTPUT}"
JOB_ID=$(echo "${SUBMIT_OUTPUT}" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "${JOB_ID}" ] || { echo "SUBMIT_FAILED"; exit 4; }
printf '%s' "${JOB_ID}" > "${LANDING}/JOB_ID.txt"
echo "JOB_ID=${JOB_ID}"
squeue -j "${JOB_ID}" -o '%.18i %.22j %.10T %.12M %.20R' || true
echo "=== TM01 SUBMITTED ==="
exit 0
