#!/bin/bash
set -eo pipefail
umask 077

ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828"
ROOT_PARTIAL="${ROOT}.partial"
SOURCE_INPUT="/data1/home/sunyiq/zhenjiang_oyv_v1/repo/data/processed/water_level_model_input_v7_beijing_realtime_verified"
PAYLOAD="/data1/home/sunyiq/hpc_mailbox/payload/zhenjiang-d32-diff-ukf/v3"
ARCHIVE="${PAYLOAD}/zhenjiang_d32_gru_differentiable_ukf_hpc_v3.tar.gz"
INPUT_DIR="${ROOT}/inputs/pre2024-v1"

fatal() {
  echo "[FATAL] $1"
  exit 1
}

verify_file() {
  local path="$1"
  local expected_bytes="$2"
  local expected_sha="$3"
  [ -f "${path}" ] || fatal "missing payload: ${path}"
  [ ! -L "${path}" ] || fatal "payload is a symbolic link: ${path}"
  [ "$(stat -c '%s' "${path}")" = "${expected_bytes}" ] || \
    fatal "payload byte count mismatch: ${path}"
  [ "$(sha256sum "${path}" | awk '{print $1}')" = "${expected_sha}" ] || \
    fatal "payload SHA-256 mismatch: ${path}"
}

[ ! -e "${ROOT}" ] || fatal "remote root already exists"
[ ! -e "${ROOT_PARTIAL}" ] || fatal "remote partial root already exists"
[ -d "${SOURCE_INPUT}" ] || fatal "source input directory is absent"
[ ! -L "${SOURCE_INPUT}" ] || fatal "source input directory is a symbolic link"

verify_file "${ARCHIVE}" 330893 \
  7ce75f030a2d567443eadddd29f73abd12675055bcbdce0ffc9fa6b03e052ad0

export PYTHONDONTWRITEBYTECODE=1
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final

python - "${ARCHIVE}" <<'PY'
from pathlib import Path, PurePosixPath
import hashlib
import json
import sys
import tarfile

archive_path = Path(sys.argv[1])

def normalized(name):
    while name.startswith("./"):
        name = name[2:]
    return name

with tarfile.open(archive_path, "r:gz") as archive:
    members = archive.getmembers()
    regular = []
    names = set()
    for member in members:
        path = PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts:
            raise SystemExit(f"unsafe archive path: {member.name}")
        if not (member.isfile() or member.isdir()):
            raise SystemExit(f"unsafe archive member type: {member.name}")
        if member.isfile():
            name = normalized(member.name)
            if not name or name in names:
                raise SystemExit(f"empty or duplicate archive file: {member.name}")
            names.add(name)
            regular.append((name, member))
    if len(regular) != 35:
        raise SystemExit("archive regular-file count changed")
    by_name = dict(regular)
    manifest_bytes = archive.extractfile(by_name["bundle_manifest.json"]).read()
    manifest = json.loads(manifest_bytes)
    rows = manifest.get("source_files")
    if not isinstance(rows, list) or manifest.get("source_file_count") != 34:
        raise SystemExit("internal bundle manifest source count changed")
    expected_names = {"bundle_manifest.json"}
    expected_names.update(row.get("relative_path") for row in rows)
    if names != expected_names:
        raise SystemExit("archive file set differs from internal manifest")
    for row in rows:
        relative = row["relative_path"]
        payload = archive.extractfile(by_name[relative]).read()
        if len(payload) != row.get("byte_count"):
            raise SystemExit(f"archive byte count mismatch: {relative}")
        if hashlib.sha256(payload).hexdigest() != row.get("sha256"):
            raise SystemExit(f"archive SHA-256 mismatch: {relative}")
    registry_rows = [
        row for row in rows
        if row.get("relative_path") == "docs/records/ZHENJIANG_D32_GRU_DIFFERENTIABLE_UKF_V1_TRAINING_REGISTRY.json"
    ]
    if len(registry_rows) != 1 or registry_rows[0].get("sha256") != "ba06d9649b86bd8b3e533174d09ad438a85451411e36bb3a53cad56c63ac8fb8":
        raise SystemExit("training registry identity changed")

print("ARCHIVE_SAFETY_AND_IDENTITY=PASS")
PY

mkdir "${ROOT}"
mkdir -p \
  "${ROOT}/bundles" \
  "${ROOT}/run.partial" \
  "${ROOT}/inputs" \
  "${ROOT}/logs" \
  "${ROOT}/runs" \
  "${ROOT}/results" \
  "${ROOT}/jobs"

install -m 0400 "${ARCHIVE}" "${ROOT}/bundles/"
tar -xzf "${ROOT}/bundles/$(basename "${ARCHIVE}")" -C "${ROOT}/run.partial"

python - "${ROOT}/run.partial" <<'PY'
from pathlib import Path
import hashlib
import json
import sys

root = Path(sys.argv[1]).resolve()
manifest = json.loads((root / "bundle_manifest.json").read_text(encoding="utf-8"))
rows = manifest.get("source_files")
if not isinstance(rows, list) or manifest.get("source_file_count") != len(rows) or len(rows) != 34:
    raise SystemExit("extracted bundle source count changed")
expected = {"bundle_manifest.json"}
seen = set()
for row in rows:
    relative = row.get("relative_path")
    if not isinstance(relative, str) or relative in seen:
        raise SystemExit(f"invalid extracted path: {relative!r}")
    seen.add(relative)
    expected.add(relative)
    path = (root / relative).resolve()
    if root not in path.parents or not path.is_file() or path.is_symlink():
        raise SystemExit(f"unsafe or missing extracted file: {relative}")
    if path.stat().st_size != row.get("byte_count"):
        raise SystemExit(f"extracted byte count mismatch: {relative}")
    if hashlib.sha256(path.read_bytes()).hexdigest() != row.get("sha256"):
        raise SystemExit(f"extracted SHA-256 mismatch: {relative}")
actual = {
    path.relative_to(root).as_posix()
    for path in root.rglob("*")
    if path.is_file()
}
if actual != expected:
    raise SystemExit("extracted file set differs from manifest")
for relative in (
    "scripts/hpc/zhenjiang_d32_gru_differentiable_ukf_smoke_v1.slurm",
    "scripts/hpc/zhenjiang_d32_gru_differentiable_ukf_formal_v1.slurm",
):
    if b"\r\n" in (root / relative).read_bytes():
        raise SystemExit(f"CRLF detected: {relative}")
print("EXTRACTED_BUNDLE_IDENTITY=PASS")
PY

bash -n "${ROOT}/run.partial/scripts/hpc/zhenjiang_d32_gru_differentiable_ukf_smoke_v1.slurm"
bash -n "${ROOT}/run.partial/scripts/hpc/zhenjiang_d32_gru_differentiable_ukf_formal_v1.slurm"
mv "${ROOT}/run.partial" "${ROOT}/run"

python -u "${ROOT}/run/scripts/hpc/materialize_zhenjiang_pre2024_input_v1.py" \
  --source-input-dir "${SOURCE_INPUT}" \
  --destination-input-dir "${INPUT_DIR}"
python -u "${ROOT}/run/scripts/hpc/materialize_zhenjiang_pre2024_input_v1.py" \
  --verify-output "${INPUT_DIR}"

[ "$(readlink -f "${INPUT_DIR}")" = "${INPUT_DIR}" ] || \
  fatal "isolated input canonical path changed"
[ ! -L "${INPUT_DIR}" ] || fatal "isolated input directory is a symbolic link"
if [ -n "$(find "${INPUT_DIR}" -type l -print -quit)" ]; then
  fatal "isolated input contains a symbolic link"
fi

python - "${INPUT_DIR}" <<'PY'
from pathlib import Path
import hashlib
import json
import sys

root = Path(sys.argv[1]).resolve()
manifest_path = root / "pre2024_input_manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
if manifest.get("file_count") != 13 or len(manifest.get("files", [])) != 13:
    raise SystemExit("isolated input file count is not 13")
if manifest.get("maximum_target_time_beijing") != "2023-12-31T23:00:00+08:00":
    raise SystemExit("isolated maximum target time changed")
if type(manifest.get("later_target_bytes_requested")) is not int or manifest["later_target_bytes_requested"] != 0:
    raise SystemExit("later target byte counter is not integer zero")
expected = {"pre2024_input_manifest.json"}
for row in manifest["files"]:
    relative = row["path"]
    expected.add(relative)
    path = (root / relative).resolve()
    if root not in path.parents or not path.is_file() or path.is_symlink():
        raise SystemExit(f"unsafe isolated file: {relative}")
    if path.stat().st_size != row["byte_count"]:
        raise SystemExit(f"isolated byte count mismatch: {relative}")
    if hashlib.sha256(path.read_bytes()).hexdigest() != row["sha256"]:
        raise SystemExit(f"isolated SHA-256 mismatch: {relative}")
actual = {
    path.relative_to(root).as_posix()
    for path in root.rglob("*")
    if path.is_file()
}
if actual != expected:
    raise SystemExit("isolated directory contains an unregistered file")
print("PRE2024_MANIFEST_SHA256=" + hashlib.sha256(manifest_path.read_bytes()).hexdigest())
PY

PATHS_PARTIAL="${ROOT}/hpc_paths.env.partial"
[ ! -e "${ROOT}/hpc_paths.env" ] || fatal "hpc_paths.env already exists"
[ ! -e "${PATHS_PARTIAL}" ] || fatal "partial hpc_paths.env already exists"
printf 'INPUT_DIR=%s\n' "${INPUT_DIR}" > "${PATHS_PARTIAL}"
chmod 0400 "${PATHS_PARTIAL}"
mv "${PATHS_PARTIAL}" "${ROOT}/hpc_paths.env"

echo "DEPLOYMENT_STATUS=PASS"
echo "REMOTE_ROOT=${ROOT}"
echo "INPUT_DIR=${INPUT_DIR}"
echo "RUN_ROOT=${ROOT}/runs"
sha256sum \
  "${ROOT}/bundles/zhenjiang_d32_gru_differentiable_ukf_hpc_v3.tar.gz"
