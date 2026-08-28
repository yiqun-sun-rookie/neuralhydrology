#!/bin/bash
set -eo pipefail
umask 077

ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828_r2"
SOURCE_INPUT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828/inputs/pre2024-v1"
PAYLOAD="/data1/home/sunyiq/hpc_mailbox/payload/zhenjiang-d32-diff-ukf/v4"
ARCHIVE="${PAYLOAD}/zhenjiang_d32_gru_differentiable_ukf_hpc_v4.tar.gz"
INPUT_DIR="${ROOT}/inputs/pre2024-v1"

fatal() {
  echo "[FATAL] $1"
  exit 1
}

[ ! -e "${ROOT}" ] || fatal "second deployment root already exists"
[ ! -e "${ROOT}.partial" ] || fatal "second partial deployment root exists"
[ -d "${SOURCE_INPUT}" ] || fatal "preserved pre-2024 source is absent"
[ ! -L "${SOURCE_INPUT}" ] || fatal "preserved pre-2024 source is a symbolic link"
[ "$(readlink -f "${SOURCE_INPUT}")" = "${SOURCE_INPUT}" ] || \
  fatal "preserved pre-2024 source canonical path changed"
[ -f "${SOURCE_INPUT}/pre2024_input_manifest.json" ] || \
  fatal "preserved pre-2024 manifest is absent"
[ -f "${ARCHIVE}" ] || fatal "version-four archive is absent"
[ ! -L "${ARCHIVE}" ] || fatal "version-four archive is a symbolic link"
[ "$(stat -c '%s' "${ARCHIVE}")" = "330877" ] || \
  fatal "version-four archive byte count changed"
[ "$(sha256sum "${ARCHIVE}" | awk '{print $1}')" = \
  "62ade1f8d092c02e4cd9d3516b271103ca21171f9fdba6ef2aa329fe2d37b7e3" ] || \
  fatal "version-four archive identity changed"

python - "${SOURCE_INPUT}/pre2024_input_manifest.json" <<'PY'
from pathlib import Path
import json
import sys

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if manifest.get("file_count") != 13 or len(manifest.get("files", [])) != 13:
    raise SystemExit("preserved pre-2024 file count changed")
if manifest.get("maximum_target_time_beijing") != "2023-12-31T23:00:00+08:00":
    raise SystemExit("preserved pre-2024 maximum target time changed")
counter = manifest.get("later_target_bytes_requested")
if type(counter) is not int or counter != 0:
    raise SystemExit("preserved later-target byte counter changed")
print("PRESERVED_PRE2024_GATE=PASS")
PY

export PYTHONDONTWRITEBYTECODE=1
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final

python - "${ARCHIVE}" <<'PY'
from pathlib import PurePosixPath
import hashlib
import json
import sys
import tarfile

with tarfile.open(sys.argv[1], "r:gz") as archive:
    members = archive.getmembers()
    regular = {}
    for member in members:
        path = PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts:
            raise SystemExit(f"unsafe archive path: {member.name}")
        if not (member.isfile() or member.isdir()):
            raise SystemExit(f"unsafe archive member type: {member.name}")
        if member.isfile():
            name = member.name
            while name.startswith("./"):
                name = name[2:]
            if not name or name in regular:
                raise SystemExit(f"empty or duplicate archive file: {member.name}")
            regular[name] = member
    if len(regular) != 35:
        raise SystemExit("archive regular-file count changed")
    manifest = json.loads(archive.extractfile(regular["bundle_manifest.json"]).read())
    rows = manifest.get("source_files")
    if not isinstance(rows, list) or manifest.get("source_file_count") != 34:
        raise SystemExit("bundle source count changed")
    expected = {"bundle_manifest.json"}
    expected.update(row.get("relative_path") for row in rows)
    if set(regular) != expected:
        raise SystemExit("archive file set differs from bundle manifest")
    for row in rows:
        relative = row["relative_path"]
        payload = archive.extractfile(regular[relative]).read()
        if len(payload) != row.get("byte_count"):
            raise SystemExit(f"archive byte count mismatch: {relative}")
        if hashlib.sha256(payload).hexdigest() != row.get("sha256"):
            raise SystemExit(f"archive SHA-256 mismatch: {relative}")
    registry = [
        row for row in rows
        if row.get("relative_path") == "docs/records/ZHENJIANG_D32_GRU_DIFFERENTIABLE_UKF_V1_TRAINING_REGISTRY.json"
    ]
    if len(registry) != 1 or registry[0].get("sha256") != "50be91777ed0ab04f025ee3e10d307e8c4960cac932e1c047caa93e1d0189557":
        raise SystemExit("version-four registry identity changed")
print("V4_ARCHIVE_SAFETY_AND_IDENTITY=PASS")
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
    raise SystemExit("extracted source count changed")
expected = {"bundle_manifest.json"}
for row in rows:
    relative = row["relative_path"]
    expected.add(relative)
    path = (root / relative).resolve()
    if root not in path.parents or not path.is_file() or path.is_symlink():
        raise SystemExit(f"unsafe or missing extracted file: {relative}")
    if path.stat().st_size != row["byte_count"]:
        raise SystemExit(f"extracted byte count mismatch: {relative}")
    if hashlib.sha256(path.read_bytes()).hexdigest() != row["sha256"]:
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
print("V4_EXTRACTED_BUNDLE_IDENTITY=PASS")
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
  fatal "second isolated input canonical path changed"
[ ! -L "${INPUT_DIR}" ] || fatal "second isolated input is a symbolic link"
[ -z "$(find "${INPUT_DIR}" -type l -print -quit)" ] || \
  fatal "second isolated input contains a symbolic link"

python - "${INPUT_DIR}/pre2024_input_manifest.json" <<'PY'
from pathlib import Path
import hashlib
import json
import sys

path = Path(sys.argv[1])
manifest = json.loads(path.read_text(encoding="utf-8"))
if manifest.get("file_count") != 13 or len(manifest.get("files", [])) != 13:
    raise SystemExit("second isolated input file count changed")
if manifest.get("maximum_target_time_beijing") != "2023-12-31T23:00:00+08:00":
    raise SystemExit("second isolated maximum target time changed")
counter = manifest.get("later_target_bytes_requested")
if type(counter) is not int or counter != 0:
    raise SystemExit("second isolated later-target byte counter changed")
print("PRE2024_MANIFEST_SHA256=" + hashlib.sha256(path.read_bytes()).hexdigest())
PY

PATHS_PARTIAL="${ROOT}/hpc_paths.env.partial"
[ ! -e "${ROOT}/hpc_paths.env" ] || fatal "second hpc_paths.env already exists"
[ ! -e "${PATHS_PARTIAL}" ] || fatal "second partial hpc_paths.env exists"
printf 'INPUT_DIR=%s\n' "${INPUT_DIR}" > "${PATHS_PARTIAL}"
chmod 0400 "${PATHS_PARTIAL}"
mv "${PATHS_PARTIAL}" "${ROOT}/hpc_paths.env"

echo "V4_DEPLOYMENT_STATUS=PASS"
echo "PRESERVED_FAILED_JOB_ID=215811"
echo "PRESERVED_ROOT=/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828"
echo "REMOTE_ROOT=${ROOT}"
echo "INPUT_DIR=${INPUT_DIR}"
sha256sum "${ROOT}/bundles/zhenjiang_d32_gru_differentiable_ukf_hpc_v4.tar.gz"
