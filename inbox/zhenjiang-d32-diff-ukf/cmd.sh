#!/bin/bash
set -eo pipefail
umask 077

EVALUATION_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_dev_eval_20260831_r3"
STAGING_ROOT="${EVALUATION_ROOT}.deploy_seq28_partial"
TRAINING_ROOT="/data1/home/sunyiq/zhenjiang_d32_differentiable_ukf_20260828_r2"
INPUT_ROOT="${TRAINING_ROOT}/inputs/pre2024-v1"
PAYLOAD_ROOT="/data1/home/sunyiq/hpc_mailbox/payload/zhenjiang-d32-diff-ukf/dev-eval-20260831-r3"
ARCHIVE_NAME="zhenjiang_d32_gru_differentiable_ukf_dev_eval_20260831_r3.tar.gz"
ARCHIVE="${PAYLOAD_ROOT}/${ARCHIVE_NAME}"
EXPECTED_ARCHIVE_BYTES=111275
EXPECTED_ARCHIVE_SHA="9258a4160bb435cb6bd79c60d6f7e43465a1ced6d67f4718eb367acb0596f2a1"
EXPECTED_MANIFEST_SHA="44431d5caf008201e40501b176e7121b13e16a97419f4d37b04e72672155059a"
EXPECTED_REGISTRY_SHA="7ce4e50faac807bbf3557eb0befc6e05769bba263390b3a1be0a55b0097d5b04"
PREVIOUS_REGISTRY_SHA="446db662812f1b7bf83c095dc5f279566a7b4ddfd3e7549acdabd76ceb9cbed3"

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

[ ! -e "${EVALUATION_ROOT}" ] || fatal "revision-three evaluation root already exists"
[ ! -e "${STAGING_ROOT}" ] || fatal "revision-three deployment staging root already exists"
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

python - \
  "${ARCHIVE}" \
  "${EXPECTED_MANIFEST_SHA}" \
  "${EXPECTED_REGISTRY_SHA}" \
  "${EVALUATION_ROOT}" \
  "${TRAINING_ROOT}" <<'PY'
from pathlib import PurePosixPath
import hashlib
import json
import sys
import tarfile


archive_path = sys.argv[1]
expected_manifest_sha = sys.argv[2]
expected_registry_sha = sys.argv[3]
expected_evaluation_root = sys.argv[4]
expected_training_root = sys.argv[5]


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
    if len(regular) != 33:
        raise SystemExit("archive regular-file count changed")
    by_name = dict(regular)
    embedded_manifest_bytes = archive.extractfile(
        by_name["bundle_manifest.json"]
    ).read()
    if hashlib.sha256(embedded_manifest_bytes).hexdigest() != expected_manifest_sha:
        raise SystemExit("embedded bundle manifest identity changed")
    embedded_manifest = json.loads(embedded_manifest_bytes)
    if (
        embedded_manifest.get("migration_id")
        != "zhenjiang_d32_gru_differentiable_ukf_dev_eval_20260831_r3"
        or embedded_manifest.get("registry_sha256") != expected_registry_sha
        or embedded_manifest.get("evaluation_root") != expected_evaluation_root
        or embedded_manifest.get("training_root") != expected_training_root
        or embedded_manifest.get("training") is not False
        or embedded_manifest.get("held_out_target_scoring") is not False
    ):
        raise SystemExit("embedded bundle contract changed")
    rows = embedded_manifest.get("source_files")
    if not isinstance(rows, list) or embedded_manifest.get("source_file_count") != 32:
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
        name.lower().endswith(
            (
                ".pt",
                ".csv",
                ".tsv",
                ".parquet",
                ".feather",
                ".npy",
                ".npz",
                ".h5",
                ".hdf5",
            )
        )
        or any(
            part in {"data", "archive", ".git"}
            for part in name.lower().split("/")
        )
        or "retired_paper_routes" in name.lower()
        for name in names
    ):
        raise SystemExit("archive contains forbidden data, checkpoint, or retired content")
print("REVISION_THREE_ARCHIVE_SAFETY_AND_IDENTITY=PASS")
PY

mkdir "${STAGING_ROOT}"
mkdir -p \
  "${STAGING_ROOT}/bundles" \
  "${STAGING_ROOT}/run.partial" \
  "${STAGING_ROOT}/logs" \
  "${STAGING_ROOT}/smoke" \
  "${STAGING_ROOT}/workers" \
  "${STAGING_ROOT}/summary" \
  "${STAGING_ROOT}/jobs"
install -m 0400 "${ARCHIVE}" "${STAGING_ROOT}/bundles/${ARCHIVE_NAME}"
tar -xzf "${STAGING_ROOT}/bundles/${ARCHIVE_NAME}" -C "${STAGING_ROOT}/run.partial"

python - \
  "${STAGING_ROOT}/run.partial" \
  "${TRAINING_ROOT}" \
  "${INPUT_ROOT}" \
  "${EXPECTED_REGISTRY_SHA}" \
  "${PREVIOUS_REGISTRY_SHA}" <<'PY'
from pathlib import Path
import hashlib
import json
import struct
import sys


run_root = Path(sys.argv[1]).resolve()
training_root = Path(sys.argv[2]).resolve()
input_root = Path(sys.argv[3]).resolve()
expected_registry_sha = sys.argv[4]
previous_registry_sha = sys.argv[5]


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


manifest_path = run_root / "bundle_manifest.json"
manifest = json.loads(manifest_path.read_text())
rows = manifest.get("source_files")
if not isinstance(rows, list) or len(rows) != 32:
    raise SystemExit("extracted bundle source count changed")
expected = {"bundle_manifest.json"}
seen = set()
for row in rows:
    relative = row.get("path")
    if not isinstance(relative, str) or relative in seen:
        raise SystemExit("invalid extracted path: %r" % relative)
    seen.add(relative)
    expected.add(relative)
    candidate = run_root / relative
    if candidate.is_symlink() or not candidate.is_file():
        raise SystemExit("unsafe or missing extracted file: %s" % relative)
    path = candidate.resolve()
    path.relative_to(run_root)
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
    / "docs/records/ZHENJIANG_D32_GRU_DIFFERENTIABLE_UKF_V1_DEVELOPMENT_EVALUATION_REGISTRY_R3.json"
)
if sha256(registry_path) != expected_registry_sha:
    raise SystemExit("revision-three development registry identity changed")
registry = json.loads(registry_path.read_text())
compute = registry.get("compute_contract", {})
normalization = registry.get("normalization_identity_contract", {})
if (
    registry.get("technical_revision") != "normalization_identity_contract_r3"
    or registry.get("supersedes_registry_sha256") != previous_registry_sha
    or registry.get("scientific_contract_changed") is not False
    or registry.get("numerical_logic_changed") is not False
    or registry.get("failed_job_id") != "216818"
    or registry.get("remote_paths", {}).get("training_root") != str(training_root)
    or registry.get("remote_paths", {}).get("input_root") != str(input_root)
    or compute.get("maximum_concurrency") != 1
    or compute.get("excluded_node") != "ngu002"
    or compute.get("formal_array") != "0-2%1"
    or registry.get("authorization", {}).get("training") is not False
    or registry.get("authorization", {}).get("held_out_target_access") is not False
):
    raise SystemExit("revision-three technical or scientific contract changed")
expected_mean_bits = [
    1091151381,
    1084854959,
    1083302174,
    1079155211,
    1076876457,
    1074733478,
]
expected_scale_bits = [
    1077169630,
    1070336360,
    1067417841,
    1063208851,
    1063488626,
    1063505265,
]
expected_run_hashes = {
    "17": "ee28f4edade42deb612a3c6a32ec703cb9521f7565f0ef68f3e68b5014c7c312",
    "29": "ffc2eac67bc32f3df43cda6e598f9c24e8dac8edc95b9c9b0ddcb4f6fb6873e1",
    "43": "9acae724e1cb3e7071b1f6f33c3e317df16ff9f318144b834f43fd91ea8f3ee3",
}
expected_data_hash = (
    "d8491b3e9a61a6c6102f14a15401e1e4d2e8078d3c553c46fb008c6f929eb74f"
)
if (
    normalization.get("legacy_training_data_identity_sha256")
    != expected_data_hash
    or normalization.get("legacy_training_target_mean_key_present") is not False
    or normalization.get("verification_method")
    != "hash_verified_input_replay_under_matching_python_numpy"
    or normalization.get("numpy") != "2.3.3"
    or normalization.get("training_base_sample_count") != 46182
    or normalization.get("validation_base_sample_count") != 8046
    or normalization.get("target_mean_float32_bits") != expected_mean_bits
    or normalization.get("target_standard_deviation_float32_bits")
    != expected_scale_bits
    or normalization.get("training_run_identity_sha256_by_seed")
    != expected_run_hashes
):
    raise SystemExit("revision-three normalization identity contract changed")

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
    expected_attempt = training_root / "runs" / "formal" / experiment / "attempt_001"
    if attempt != expected_attempt:
        raise SystemExit("training attempt path changed: %s" % experiment)
    for name in (
        "completion_manifest.json",
        "best_checkpoint.pt",
        "data_identity.json",
        "run_identity.json",
    ):
        identity = row["required_file_identities"][name]
        path = attempt / name
        if not path.is_file() or path.is_symlink():
            raise SystemExit("training evidence is missing: %s" % path)
        if path.stat().st_size != identity["byte_count"]:
            raise SystemExit("training evidence byte count changed: %s" % path)
        if sha256(path) != identity["sha256"]:
            raise SystemExit("training evidence SHA-256 changed: %s" % path)
    if row["required_file_identities"]["data_identity.json"]["sha256"] != expected_data_hash:
        raise SystemExit("training data identity hash changed: %s" % experiment)
    if row["required_file_identities"]["run_identity.json"]["sha256"] != expected_run_hashes[str(seed)]:
        raise SystemExit("training run identity hash changed: %s" % experiment)
    data_identity = json.loads((attempt / "data_identity.json").read_text())
    run_identity = json.loads((attempt / "run_identity.json").read_text())
    scale_bits = [
        struct.unpack("<I", struct.pack("<f", value))[0]
        for value in data_identity.get("target_standard_deviation_m", [])
    ]
    if (
        data_identity.get("schema_version") != "1.0"
        or "target_mean_m" in data_identity
        or scale_bits != expected_scale_bits
        or run_identity.get("environment", {}).get("python")
        != normalization.get("python")
        or run_identity.get("environment", {}).get("numpy")
        != normalization.get("numpy")
    ):
        raise SystemExit("legacy normalization source changed: %s" % experiment)
print("REVISION_THREE_EXTRACTED_BUNDLE_AND_TRAINING_IDENTITIES=PASS")
PY

for SCRIPT in \
  "${STAGING_ROOT}/run.partial/scripts/hpc/zhenjiang_d32_gru_differentiable_ukf_development_evaluation_smoke_v1.slurm" \
  "${STAGING_ROOT}/run.partial/scripts/hpc/zhenjiang_d32_gru_differentiable_ukf_development_evaluation_formal_v1.slurm"
do
  if grep -q $'\r' "${SCRIPT}"; then
    fatal "carriage return detected in job script: ${SCRIPT}"
  fi
  bash -n "${SCRIPT}"
done

mv "${STAGING_ROOT}/run.partial" "${STAGING_ROOT}/run"
PATHS_PARTIAL="${STAGING_ROOT}/hpc_paths.env.partial"
printf 'EVALUATION_ROOT=%s\n' "${EVALUATION_ROOT}" > "${PATHS_PARTIAL}"
printf 'TRAINING_ROOT=%s\n' "${TRAINING_ROOT}" >> "${PATHS_PARTIAL}"
printf 'INPUT_DIR=%s\n' "${INPUT_ROOT}" >> "${PATHS_PARTIAL}"
printf 'REGISTRY_SHA256=%s\n' "${EXPECTED_REGISTRY_SHA}" >> "${PATHS_PARTIAL}"
chmod 0400 "${PATHS_PARTIAL}"
mv "${PATHS_PARTIAL}" "${STAGING_ROOT}/hpc_paths.env"
mv "${STAGING_ROOT}" "${EVALUATION_ROOT}"

echo "REVISION_THREE_DEPLOYMENT_STATUS=PASS"
echo "EVALUATION_ROOT=${EVALUATION_ROOT}"
echo "TRAINING_ROOT=${TRAINING_ROOT}"
echo "INPUT_ROOT=${INPUT_ROOT}"
sha256sum \
  "${EVALUATION_ROOT}/bundles/${ARCHIVE_NAME}" \
  "${EVALUATION_ROOT}/run/docs/records/ZHENJIANG_D32_GRU_DIFFERENTIABLE_UKF_V1_DEVELOPMENT_EVALUATION_REGISTRY_R3.json"
echo "=== USER_QUEUE_UNCHANGED_BY_DEPLOYMENT ==="
squeue -u "${USER}" -o '%i|%j|%T|%P|%N|%M|%l' || true
