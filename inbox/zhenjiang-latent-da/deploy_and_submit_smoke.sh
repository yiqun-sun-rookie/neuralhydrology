#!/bin/bash
set -eo pipefail
umask 077

MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
PAYLOAD_DIRECTORY="${MAILBOX_ROOT}/payload/zhenjiang-latent-da/smoke-v1"
ARCHIVE="${PAYLOAD_DIRECTORY}/zhenjiang_latent_gru_kalmannet_hpc_smoke_v1.tar.gz"
EXPECTED_ARCHIVE_SHA256="b54000f2fdc1c9c24008f94d3c34d24db592246f6e74719164a66ee11d418437"
EXPECTED_ARCHIVE_BYTES="68225"
REMOTE_ROOT="/data1/home/sunyiq/zhenjiang_latent_da_20260827"
RUN_DIRECTORY="${REMOTE_ROOT}/run"
LOG_DIRECTORY="${REMOTE_ROOT}/logs"
EXTERNAL_DIRECTORY="${REMOTE_ROOT}/external"
INPUT_DIR="/data1/home/sunyiq/zhenjiang_oyv_v1/repo/data/processed/water_level_model_input_v7_beijing_realtime_verified"
KALMANNET_ORIGIN="/data1/home/sunyiq/kalmannet_daily_camels_official_core_a35_20260825/source_seq27/third_party/KalmanNet_TSP_828a2cf/KNet/KalmanNet_nn.py"
KALMANNET_SOURCE="${EXTERNAL_DIRECTORY}/KalmanNet_nn.py"
EXPECTED_KALMANNET_SHA256="0cad52635723eaf8c4bbfc331a2d0614520363c71953f650794b4794d7aab33d"
SLURM_SCRIPT="${RUN_DIRECTORY}/scripts/hpc/zhenjiang_latent_gru_kalmannet_smoke_v1.slurm"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

echo "DEPLOY_START $(date -Is)"
if [ "$(id -un)" != "sunyiq" ]; then
  echo "[FATAL] unexpected user: $(id -un)"
  exit 1
fi
if [ -e "${REMOTE_ROOT}" ] || [ -L "${REMOTE_ROOT}" ]; then
  echo "[FATAL] refusing to overwrite remote root: ${REMOTE_ROOT}"
  exit 1
fi
for required in "${ARCHIVE}" "${INPUT_DIR}" "${KALMANNET_ORIGIN}"
do
  if [ ! -e "${required}" ]; then
    echo "[FATAL] missing deployment input: ${required}"
    exit 1
  fi
done
if [ "$(stat -c '%s' "${ARCHIVE}")" != "${EXPECTED_ARCHIVE_BYTES}" ]; then
  echo "[FATAL] payload byte count mismatch"
  exit 1
fi
if [ "$(sha256_file "${ARCHIVE}")" != "${EXPECTED_ARCHIVE_SHA256}" ]; then
  echo "[FATAL] payload SHA-256 mismatch"
  exit 1
fi
if [ "$(sha256_file "${KALMANNET_ORIGIN}")" != "${EXPECTED_KALMANNET_SHA256}" ]; then
  echo "[FATAL] origin KalmanNet SHA-256 mismatch"
  exit 1
fi
if tar -tzf "${ARCHIVE}" | grep -E '(^/|(^|/)\.\.(/|$))' >/dev/null; then
  echo "[FATAL] payload contains an unsafe member path"
  exit 1
fi

mkdir -p "${RUN_DIRECTORY}" "${LOG_DIRECTORY}" "${EXTERNAL_DIRECTORY}" "${REMOTE_ROOT}/bundle"
cp --archive "${ARCHIVE}" "${REMOTE_ROOT}/bundle/"
tar -xzf "${ARCHIVE}" -C "${RUN_DIRECTORY}"
cp --archive "${KALMANNET_ORIGIN}" "${KALMANNET_SOURCE}"
if find "${RUN_DIRECTORY}" -type l -print -quit | grep -q .; then
  echo "[FATAL] extracted run contains a symbolic link"
  exit 1
fi
if [ "$(sha256_file "${KALMANNET_SOURCE}")" != "${EXPECTED_KALMANNET_SHA256}" ]; then
  echo "[FATAL] isolated KalmanNet copy SHA-256 mismatch"
  exit 1
fi

source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
export DEPLOY_PROJECT_ROOT="${RUN_DIRECTORY}"
python - <<'PY'
import hashlib
import json
import os
from pathlib import Path

root = Path(os.environ["DEPLOY_PROJECT_ROOT"]).resolve()
manifest = json.loads((root / "bundle_manifest.json").read_text(encoding="utf-8"))
rows = manifest.get("source_files")
if manifest.get("experiment_id") != "ZLDA-SMOKE-01" or not isinstance(rows, list):
    raise SystemExit("invalid internal bundle manifest")
if len(rows) != manifest.get("source_file_count"):
    raise SystemExit("internal bundle source count mismatch")
for row in rows:
    path = (root / row["relative_path"]).resolve()
    if root not in path.parents or not path.is_file():
        raise SystemExit("unsafe or missing internal source: " + row["relative_path"])
    content = path.read_bytes()
    if len(content) != row["byte_count"]:
        raise SystemExit("internal source byte mismatch: " + row["relative_path"])
    if hashlib.sha256(content).hexdigest() != row["sha256"]:
        raise SystemExit("internal source SHA-256 mismatch: " + row["relative_path"])
print("internal_bundle_verification=passed")
print("internal_source_file_count=" + str(len(rows)))
PY

sed -i 's/\r$//' "${SLURM_SCRIPT}"
bash -n "${SLURM_SCRIPT}"
printf 'INPUT_DIR=%q\nKALMANNET_SOURCE=%q\n' \
  "${INPUT_DIR}" "${KALMANNET_SOURCE}" > "${REMOTE_ROOT}/hpc_paths.env"
python - <<PY
import json
from pathlib import Path
payload = {
    "schema_version": 1,
    "experiment_id": "ZLDA-SMOKE-01",
    "archive_sha256": "${EXPECTED_ARCHIVE_SHA256}",
    "archive_byte_count": int("${EXPECTED_ARCHIVE_BYTES}"),
    "input_dir": "${INPUT_DIR}",
    "kalmannet_origin": "${KALMANNET_ORIGIN}",
    "isolated_kalmannet_source": "${KALMANNET_SOURCE}",
    "kalmannet_sha256": "${EXPECTED_KALMANNET_SHA256}",
    "submitted_job_id": None,
}
Path("${REMOTE_ROOT}/deployment_manifest.json").write_text(
    json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
)
PY

SUBMISSION="$(sbatch "${SLURM_SCRIPT}")"
echo "${SUBMISSION}"
if ! echo "${SUBMISSION}" | grep -E '^Submitted batch job [0-9]+$' >/dev/null; then
  echo "[FATAL] Slurm did not return a submission receipt"
  exit 1
fi
JOB_ID="${SUBMISSION##* }"
printf '%s\n' "${JOB_ID}" > "${REMOTE_ROOT}/submitted_job_id.txt"
python - <<PY
import json
from pathlib import Path
path = Path("${REMOTE_ROOT}/deployment_manifest.json")
payload = json.loads(path.read_text(encoding="utf-8"))
payload["submitted_job_id"] = int("${JOB_ID}")
path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
PY
squeue -j "${JOB_ID}" -h -o '%i|%j|%T|%P|%M|%R' || true
echo "DEPLOY_END $(date -Is) JOB_ID=${JOB_ID}"
