#!/bin/bash
set -eo pipefail
umask 077

EVALUATION_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_dev_eval_20260831"
TRAINING_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828_r2"
INPUT_ROOT="${TRAINING_ROOT}/inputs/pre2024-v1"
PAYLOAD_ROOT="/data1/home/sunyiq/hpc_mailbox/payload/zhenjiang-d32-diff-ukf/dev-eval-20260831-v1"
ARCHIVE_NAME="zhenjiang_d32_gru_differentiable_ukf_dev_eval_20260831_v1.tar.gz"
ARCHIVE="${PAYLOAD_ROOT}/${ARCHIVE_NAME}"
EXPECTED_ARCHIVE_BYTES=101034
EXPECTED_ARCHIVE_SHA="e43bbd68a2893c4b7e9707c68820d2cb87e77e9c34018c392ea0a2f31ac40f69"
EXPECTED_REGISTRY_SHA="094894c6a0c83e5e384c17227f0add9760b9f994afe2d3b6e4d1f91f7877f71d"

fatal() {
  echo "[FATAL] $1" >&2
  exit 1
}

verify_file() {
  local path="$1"
  local expected_bytes="$2"
  local expected_sha="$3"
  [ -f "${path}" ] || fatal "missing file: ${path}"
  [ ! -L "${path}" ] || fatal "symbolic file is forbidden: ${path}"
  [ "$(stat -c '%s' "${path}")" = "${expected_bytes}" ] || \
    fatal "byte count mismatch: ${path}"
  [ "$(sha256sum "${path}" | awk '{print $1}')" = "${expected_sha}" ] || \
    fatal "SHA-256 mismatch: ${path}"
}

[ ! -e "${EVALUATION_ROOT}" ] || fatal "evaluation root already exists"
[ -d "${TRAINING_ROOT}" ] || fatal "training root is absent"
[ ! -L "${TRAINING_ROOT}" ] || fatal "training root is symbolic"
[ -d "${INPUT_ROOT}" ] || fatal "isolated input root is absent"
[ ! -L "${INPUT_ROOT}" ] || fatal "isolated input root is symbolic"
verify_file "${ARCHIVE}" "${EXPECTED_ARCHIVE_BYTES}" "${EXPECTED_ARCHIVE_SHA}"

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
    regular = []
    names = set()
    for member in archive.getmembers():
        path = PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts:
            raise SystemExit("unsafe archive path: %s" % member.name)
        if not (member.isfile() or member.isdir()):
            raise SystemExit("unsafe archive member type: %s" % member.name)
        if member.isfile():
            name = normalized(member.name)
            if not name or name in names:
                raise SystemExit("empty or duplicate archive file: %s" % member.name)
            names.add(name)
            regular.append((name, member))
    if len(regular) != 28:
        raise SystemExit("archive regular-file count changed")
    by_name = dict(regular)
    manifest = json.loads(
        archive.extractfile(by_name["bundle_manifest.json"]).read()
    )
    rows = manifest.get("source_files")
    if not isinstance(rows, list) or manifest.get("source_file_count") != 27:
        raise SystemExit("bundle source-file count changed")
    expected_names = {"bundle_manifest.json"}
    expected_names.update(row.get("path") for row in rows)
    if names != expected_names:
        raise SystemExit("archive file set differs from bundle manifest")
    for row in rows:
        relative = row["path"]
        payload = archive.extractfile(by_name[relative]).read()
        if len(payload) != row.get("byte_count"):
            raise SystemExit("archive byte count mismatch: %s" % relative)
        if hashlib.sha256(payload).hexdigest() != row.get("sha256"):
            raise SystemExit("archive SHA-256 mismatch: %s" % relative)
    if any(
        name.lower().endswith(".pt") or name.startswith("data/")
        for name in names
    ):
        raise SystemExit("archive contains data or a training checkpoint")
print("ARCHIVE_SAFETY_AND_IDENTITY=PASS")
PY

mkdir "${EVALUATION_ROOT}"
mkdir -p \
  "${EVALUATION_ROOT}/bundles" \
  "${EVALUATION_ROOT}/run.partial" \
  "${EVALUATION_ROOT}/logs" \
  "${EVALUATION_ROOT}/smoke" \
  "${EVALUATION_ROOT}/workers" \
  "${EVALUATION_ROOT}/summary" \
  "${EVALUATION_ROOT}/jobs"
install -m 0400 "${ARCHIVE}" "${EVALUATION_ROOT}/bundles/${ARCHIVE_NAME}"
tar -xzf "${EVALUATION_ROOT}/bundles/${ARCHIVE_NAME}" \
  -C "${EVALUATION_ROOT}/run.partial"

python - \
  "${EVALUATION_ROOT}/run.partial" \
  "${TRAINING_ROOT}" \
  "${INPUT_ROOT}" \
  "${EXPECTED_REGISTRY_SHA}" <<'PY'
from pathlib import Path
import hashlib
import json
import sys


run_root = Path(sys.argv[1]).resolve()
training_root = Path(sys.argv[2]).resolve()
input_root = Path(sys.argv[3]).resolve()
expected_registry_sha = sys.argv[4]


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


manifest = json.loads((run_root / "bundle_manifest.json").read_text())
rows = manifest.get("source_files")
if not isinstance(rows, list) or len(rows) != 27:
    raise SystemExit("extracted bundle source count changed")
expected = {"bundle_manifest.json"}
seen = set()
for row in rows:
    relative = row.get("path")
    if not isinstance(relative, str) or relative in seen:
        raise SystemExit("invalid extracted path: %r" % relative)
    seen.add(relative)
    expected.add(relative)
    path = (run_root / relative).resolve()
    if run_root not in path.parents or not path.is_file() or path.is_symlink():
        raise SystemExit("unsafe or missing extracted file: %s" % relative)
    if path.stat().st_size != row.get("byte_count"):
        raise SystemExit("extracted byte count mismatch: %s" % relative)
    if sha256(path) != row.get("sha256"):
        raise SystemExit("extracted SHA-256 mismatch: %s" % relative)
actual = {
    path.relative_to(run_root).as_posix()
    for path in run_root.rglob("*")
    if path.is_file()
}
if actual != expected:
    raise SystemExit("extracted file set differs from the exact manifest")

registry_path = (
    run_root
    / "docs/records/ZHENJIANG_D32_GRU_DIFFERENTIABLE_UKF_V1_DEVELOPMENT_EVALUATION_REGISTRY.json"
)
if sha256(registry_path) != expected_registry_sha:
    raise SystemExit("development evaluation registry identity changed")
identities_path = (
    run_root
    / "docs/records/ZHENJIANG_D32_GRU_DIFFERENTIABLE_UKF_V1_TRAINING_OUTPUT_IDENTITIES_2026-08-31.json"
)
identities = json.loads(identities_path.read_text())
if Path(identities.get("training_root", "")).resolve() != training_root:
    raise SystemExit("training root identity changed")
input_identity = identities.get("input_identity", {})
input_manifest = input_root / "pre2024_input_manifest.json"
if sha256(input_manifest) != input_identity.get("manifest_sha256"):
    raise SystemExit("isolated input manifest identity changed")
if input_identity.get("test_target_counters") != {
    "test_target_rows_read": 0,
    "test_target_values_loaded": 0,
    "test_target_values_parsed": 0,
}:
    raise SystemExit("input identity reports target-period access")
for seed in (17, 29, 43):
    experiment = "ZHD32-DUKF-S%d-V1" % seed
    row = identities["experiments"][experiment]
    attempt = Path(row["attempt_directory"]).resolve()
    expected_attempt = (
        training_root / "runs" / "formal" / experiment / "attempt_001"
    )
    if attempt != expected_attempt:
        raise SystemExit("training attempt path changed: %s" % experiment)
    for name in ("completion_manifest.json", "best_checkpoint.pt"):
        identity = row["required_file_identities"][name]
        path = attempt / name
        if not path.is_file() or path.is_symlink():
            raise SystemExit("training evidence is missing: %s" % path)
        if path.stat().st_size != identity["byte_count"]:
            raise SystemExit("training evidence byte count changed: %s" % path)
        if sha256(path) != identity["sha256"]:
            raise SystemExit("training evidence SHA-256 changed: %s" % path)
print("EXTRACTED_BUNDLE_AND_TRAINING_IDENTITIES=PASS")
PY

for SCRIPT in \
  "${EVALUATION_ROOT}/run.partial/scripts/hpc/zhenjiang_d32_gru_differentiable_ukf_development_evaluation_smoke_v1.slurm" \
  "${EVALUATION_ROOT}/run.partial/scripts/hpc/zhenjiang_d32_gru_differentiable_ukf_development_evaluation_formal_v1.slurm"
do
  if grep -q $'\r' "${SCRIPT}"; then
    fatal "carriage return detected in job script: ${SCRIPT}"
  fi
  bash -n "${SCRIPT}"
done

mv "${EVALUATION_ROOT}/run.partial" "${EVALUATION_ROOT}/run"
PATHS_PARTIAL="${EVALUATION_ROOT}/hpc_paths.env.partial"
[ ! -e "${EVALUATION_ROOT}/hpc_paths.env" ] || fatal "path contract exists"
printf 'EVALUATION_ROOT=%s\n' "${EVALUATION_ROOT}" > "${PATHS_PARTIAL}"
printf 'TRAINING_ROOT=%s\n' "${TRAINING_ROOT}" >> "${PATHS_PARTIAL}"
printf 'INPUT_DIR=%s\n' "${INPUT_ROOT}" >> "${PATHS_PARTIAL}"
chmod 0400 "${PATHS_PARTIAL}"
mv "${PATHS_PARTIAL}" "${EVALUATION_ROOT}/hpc_paths.env"

echo "DEPLOYMENT_STATUS=PASS"
echo "EVALUATION_ROOT=${EVALUATION_ROOT}"
echo "TRAINING_ROOT=${TRAINING_ROOT}"
echo "INPUT_ROOT=${INPUT_ROOT}"
sha256sum \
  "${EVALUATION_ROOT}/bundles/${ARCHIVE_NAME}" \
  "${EVALUATION_ROOT}/run/docs/records/ZHENJIANG_D32_GRU_DIFFERENTIABLE_UKF_V1_DEVELOPMENT_EVALUATION_REGISTRY.json"
echo "=== USER_QUEUE_UNCHANGED_BY_DEPLOYMENT ==="
squeue -u "${USER}" -o '%i|%j|%T|%P|%N|%M|%l' || true
