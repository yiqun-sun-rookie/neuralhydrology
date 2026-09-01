#!/bin/bash
set -eo pipefail

CHANNEL="zhenjiang-six-source-four-target-ukf"
ROOT="/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r1"
PAYLOAD_DIR="${HOME}/hpc_mailbox/inbox/${CHANNEL}/payload_20260901_r1"
ARCHIVE="${PAYLOAD_DIR}/zhenjiang_six_source_four_target_d32_gru_ukf_20260901_r1.tar.gz"
EXPECTED_ARCHIVE_SHA="57ca7c687dc846c8e6da538f5a684109442db500fa42528bb396a0625428e803"
EXPECTED_MANIFEST_SHA="bf649c5cac46019800ba4ba1e63e1d41d13b6231cf4cd77ac5d86f341b536cc9"
EXPECTED_REGISTRY_SHA="7518428f1e980bf1853296080ef93fd739678a538389cbb3716a731822d17106"
EXTRACT_ROOT=""

fatal() {
  echo "[FATAL] $1"
  exit 1
}

cleanup() {
  if [ -n "${EXTRACT_ROOT}" ] && [ -d "${EXTRACT_ROOT}" ]; then
    case "${EXTRACT_ROOT}" in
      "/data1/home/${USER}/.zsf4t_deploy_20260901_r1."*) rm -rf -- "${EXTRACT_ROOT}" ;;
      *) echo "[WARN] refusing unsafe temporary cleanup: ${EXTRACT_ROOT}" ;;
    esac
  fi
}
trap cleanup EXIT

printf '=== EXCLUSIVE_ROOT_PREFLIGHT ===\n'
for candidate in "${ROOT}" "${ROOT}.partial" "${ROOT}.staging"; do
  if [ -e "${candidate}" ] || [ -L "${candidate}" ]; then
    fatal "exclusive destination already exists: ${candidate}"
  fi
  printf 'ABSENT|%s\n' "${candidate}"
done

[ -f "${ARCHIVE}" ] && [ ! -L "${ARCHIVE}" ] || fatal "archive is absent or linked"
[ "$(stat -c '%s' "${ARCHIVE}")" = "162290" ] || fatal "archive byte count mismatch"
[ "$(sha256sum "${ARCHIVE}" | awk '{print $1}')" = "${EXPECTED_ARCHIVE_SHA}" ] || fatal "archive SHA-256 mismatch"

python - "${ARCHIVE}" <<'PY'
from __future__ import annotations
import hashlib
import json
from pathlib import PurePosixPath
import sys
import tarfile

archive = sys.argv[1]
expected_manifest_sha = "bf649c5cac46019800ba4ba1e63e1d41d13b6231cf4cd77ac5d86f341b536cc9"
expected_registry_sha = "7518428f1e980bf1853296080ef93fd739678a538389cbb3716a731822d17106"

with tarfile.open(archive, "r:gz") as handle:
    members = handle.getmembers()
    regular = [item for item in members if item.isfile()]
    if len(regular) != 40 or any(item.issym() or item.islnk() for item in members):
        raise SystemExit("archive count or link contract drift")
    for item in members:
        normalized = item.name.removeprefix("./")
        path = PurePosixPath(normalized)
        if path.is_absolute() or ".." in path.parts:
            raise SystemExit("unsafe archive member: " + item.name)
    by_name = {item.name.removeprefix("./"): item for item in regular}
    manifest_bytes = handle.extractfile(by_name["bundle_manifest.json"]).read()
    manifest = json.loads(manifest_bytes)
    if (
        hashlib.sha256(manifest_bytes).hexdigest() != expected_manifest_sha
        or manifest.get("source_file_count") != 38
        or manifest.get("registry_sha256") != expected_registry_sha
        or manifest.get("formal_jobs_submitted") is not False
        or manifest.get("heldout_2024_target_access_authorized") is not False
    ):
        raise SystemExit("inner frozen bundle identity drift")
print("bundle_identity_preflight=passed")
PY

EXTRACT_ROOT=$(mktemp -d "/data1/home/${USER}/.zsf4t_deploy_20260901_r1.XXXXXX")
case "${EXTRACT_ROOT}" in
  "/data1/home/${USER}/.zsf4t_deploy_20260901_r1."*) ;;
  *) fatal "mktemp returned an unsafe path" ;;
esac
tar -xzf "${ARCHIVE}" -C "${EXTRACT_ROOT}"
[ -f "${EXTRACT_ROOT}/deploy_exclusive_root.sh" ] || fatal "deploy script was not extracted"
bash -n "${EXTRACT_ROOT}/deploy_exclusive_root.sh"
for script in \
  zhenjiang_six_source_four_target_d32_gru_base_v1.slurm \
  zhenjiang_six_source_four_target_d32_gru_differentiable_ukf_v1.slurm \
  zhenjiang_six_source_four_target_d32_gru_ukf_development_evaluation_v1.slurm
do
  bash -n "${EXTRACT_ROOT}/run/scripts/hpc/${script}"
done
bash "${EXTRACT_ROOT}/deploy_exclusive_root.sh" "${EXTRACT_ROOT}"

printf '=== DEPLOYED_ROOT_VERIFICATION ===\n'
[ -d "${ROOT}" ] || fatal "exclusive root was not published"
[ ! -e "${ROOT}.partial" ] && [ ! -e "${ROOT}.staging" ] || fatal "partial or staging root remains"
[ "$(find "${ROOT}" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort | tr '\n' ' ')" = "evidence inputs jobs logs run runs " ] || fatal "top-level allow-list drift"
[ -z "$(find "${ROOT}" -type l -print -quit)" ] || fatal "deployed root contains a symbolic link"
[ "$(sha256sum "${ROOT}/jobs/bundle_manifest.json" | awk '{print $1}')" = "${EXPECTED_MANIFEST_SHA}" ] || fatal "retained bundle manifest changed"
[ "$(sha256sum "${ROOT}/run/docs/records/ZHENJIANG_SIX_SOURCE_FOUR_TARGET_D32_GRU_DIFFERENTIABLE_UKF_V1_REGISTRY.json" | awk '{print $1}')" = "${EXPECTED_REGISTRY_SHA}" ] || fatal "deployed registry changed"

source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
export PYTHONDONTWRITEBYTECODE=1
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export PYTHONPATH="${ROOT}/run/scripts/modeling:${ROOT}/run/scripts/analysis:${ROOT}/run/scripts/astronomical_tide:${ROOT}/run/third_party/pytides:${PYTHONPATH:-}"
cd "${ROOT}/run"
python scripts/modeling/register_zhenjiang_six_source_four_target_d32_gru_ukf_v1.py --validate-only
python scripts/analysis/zhenjiang_six_source_four_target_d32_gru_ukf_contract_v1.py --self-check
python - "${ROOT}" <<'PY'
from pathlib import Path
import json
import sys

from zhenjiang_six_source_four_target_d32_gru_differentiable_ukf_runner_v1 import (
    verify_isolated_input_manifest,
)

root = Path(sys.argv[1])
registry = json.loads(
    (
        root
        / "run/docs/records/ZHENJIANG_SIX_SOURCE_FOUR_TARGET_D32_GRU_DIFFERENTIABLE_UKF_V1_REGISTRY.json"
    ).read_text(encoding="utf-8")
)
identity = verify_isolated_input_manifest(
    root / "inputs/pre2024-four-target-v1", registry
)
if identity.get("file_count") != 11:
    raise SystemExit("isolated input verification did not return eleven files")
print("isolated_input_prefix_verification=passed")
PY

echo "ARCHIVE_SHA=${EXPECTED_ARCHIVE_SHA}"
echo "MANIFEST_SHA=${EXPECTED_MANIFEST_SHA}"
echo "REGISTRY_SHA=${EXPECTED_REGISTRY_SHA}"
echo "FORMAL_JOBS_SUBMITTED=0"
echo "HELDOUT_2024_TARGET_ACCESS_AUTHORIZED=false"
echo "[DONE] deployed create-only root=${ROOT}"
