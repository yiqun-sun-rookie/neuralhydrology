#!/usr/bin/env bash
set -eo pipefail
umask 027

REMOTE_ROOT="/data1/home/sunyiq/zhenjiang_five_source_five_target_single_analysis_ukf_oracle_datong_20260904_r1"
PROTECTED_R2="/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260901_r2"
PROTECTED_RECOVERY="/data1/home/sunyiq/zhenjiang_six_source_four_target_differentiable_ukf_20260902_recovery_attempt_002"
TIDE_SOURCE="${PROTECTED_R2}/run/results/modeling/wusongkou_astronomical_tide_v1_validation/tide_model.json"
MAILBOX_ROOT="$(git rev-parse --show-toplevel)"
PAYLOAD_ROOT="${MAILBOX_ROOT}/inbox/zhenjiang-six-source-four-target-ukf/payload_20260905_stage_a_v2_attempt_002"
CODE_ARCHIVE="${PAYLOAD_ROOT}/zhenjiang_five_source_five_target_stage_a_hpc_v2.tar.gz"
BUNDLE_MANIFEST_SOURCE="${PAYLOAD_ROOT}/bundle_manifest.json"
BUNDLE_IDENTITY_SOURCE="${PAYLOAD_ROOT}/bundle_identity.json"
PREFIX_ARCHIVE="${PAYLOAD_ROOT}/zhenjiang_2017_2022_prefixes.tar.gz"
IDENTITY_MANIFEST_SOURCE="${PAYLOAD_ROOT}/identity_registration_manifest.json"
IDENTITY_LEDGER_SOURCE="${PAYLOAD_ROOT}/identity_registration_usage.sqlite3"
CODE_ARCHIVE_SHA256="f5d5c0f87c9e964e0ac906f1ec7df6b0bc52c9329017db8132064bb84c2f5caa"
CODE_ARCHIVE_BYTES="70680"
BUNDLE_MANIFEST_SHA256="087552bf4f7bdc7a464482ab6b293d8fcaa0d889f66e240b2ca50f93c3821f3f"
BUNDLE_MANIFEST_BYTES="4047"
BUNDLE_IDENTITY_SHA256="9f2569340fc0e6795b9c4131af633ea9f12ea4358e6e650a4b45a95a55546c8b"
BUNDLE_IDENTITY_BYTES="633"
PREFIX_ARCHIVE_SHA256="7d419119c623efc3fc59591acbd4490c654c6e5fe2c07da8fc331681925746fe"
PREFIX_ARCHIVE_BYTES="5778413"
IDENTITY_MANIFEST_SHA256="dbeb429521044f52558e009e5b5eeda28a48db9607140abc98a00e1501dd10ce"
IDENTITY_MANIFEST_BYTES="17124"
IDENTITY_LEDGER_SHA256="21dd23f935b922ce1bd84ae11ac72680915b2ab0a0776b65fe0ae851258a74b3"
IDENTITY_LEDGER_BYTES="16384"
DATA_AUTHORIZATION_SHA256="ab5d0c19c26026e9ab6fd4c412ba0e2573700aeca655042d23ac12b9e8b558c1"
DATA_CONTRACT_SHA256="26f1b988d0b126be172d612efa9fab0dedf8f3f48e849a3d7ddc331ffda6dc17"
EXECUTION_AUTHORIZATION_SHA256="970e1027dba389354309cd51464bed1325db9f893e29263b95459f7d07f33e36"
TIDE_MODEL_SHA256="ce8512f28e87ab6d62814b064d91ca358b98efd7ee27b4f831322ea93775516d"
TIDE_MODEL_BYTES="6197"
CONFIRMATION="CONFIRM_ZHENJIANG_FIVE_SOURCE_FIVE_TARGET_STAGE_A_PAID_HPC_20260904_R1"

fatal() {
  printf '[FATAL] %s\n' "$1" >&2
  exit 1
}

require_ordinary_file() {
  [ -f "$1" ] && [ ! -L "$1" ] || fatal "required ordinary file is absent: $1"
}

assert_file_identity() {
  local path="$1"
  local expected_bytes="$2"
  local expected_sha256="$3"
  require_ordinary_file "${path}"
  local observed_bytes
  local observed_sha256
  observed_bytes="$(stat -c '%s' -- "${path}")"
  observed_sha256="$(sha256sum -- "${path}" | awk '{print $1}')"
  [ "${observed_bytes}" = "${expected_bytes}" ] || fatal "byte count changed: ${path}"
  [ "${observed_sha256}" = "${expected_sha256}" ] || fatal "SHA-256 changed: ${path}"
}

echo '=== A. IMMUTABLE PREFLIGHT ==='
date --iso-8601=seconds
hostname
whoami
printf 'mailbox_root=%s\n' "${MAILBOX_ROOT}"
[ "$(id -un)" = 'sunyiq' ] || fatal 'unexpected remote user'
[ -d "${PROTECTED_R2}" ] && [ ! -L "${PROTECTED_R2}" ] || fatal 'protected R2 root is absent'
[ -d "${PROTECTED_RECOVERY}" ] && [ ! -L "${PROTECTED_RECOVERY}" ] || fatal 'protected recovery root is absent'
if [ -e "${REMOTE_ROOT}" ] || [ -L "${REMOTE_ROOT}" ]; then
  fatal "new remote root is not absent: ${REMOTE_ROOT}"
fi

assert_file_identity "${CODE_ARCHIVE}" "${CODE_ARCHIVE_BYTES}" "${CODE_ARCHIVE_SHA256}"
assert_file_identity "${BUNDLE_MANIFEST_SOURCE}" "${BUNDLE_MANIFEST_BYTES}" "${BUNDLE_MANIFEST_SHA256}"
assert_file_identity "${BUNDLE_IDENTITY_SOURCE}" "${BUNDLE_IDENTITY_BYTES}" "${BUNDLE_IDENTITY_SHA256}"
assert_file_identity "${PREFIX_ARCHIVE}" "${PREFIX_ARCHIVE_BYTES}" "${PREFIX_ARCHIVE_SHA256}"
assert_file_identity "${IDENTITY_MANIFEST_SOURCE}" "${IDENTITY_MANIFEST_BYTES}" "${IDENTITY_MANIFEST_SHA256}"
assert_file_identity "${IDENTITY_LEDGER_SOURCE}" "${IDENTITY_LEDGER_BYTES}" "${IDENTITY_LEDGER_SHA256}"
assert_file_identity "${TIDE_SOURCE}" "${TIDE_MODEL_BYTES}" "${TIDE_MODEL_SHA256}"

if [ -f /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh ]; then
  source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
else
  fatal 'nh_final conda activation script is absent'
fi
conda activate nh_final
export PYTHONDONTWRITEBYTECODE=1
command -v sbatch >/dev/null || fatal 'sbatch is unavailable'

python -u - "${CODE_ARCHIVE}" "${PREFIX_ARCHIVE}" "${BUNDLE_MANIFEST_SOURCE}" "${BUNDLE_IDENTITY_SOURCE}" "${IDENTITY_MANIFEST_SOURCE}" <<'PY'
import hashlib
import json
import platform
from pathlib import PurePosixPath
import sys
import tarfile

from importlib.metadata import version

code_archive, prefix_archive, manifest_path, identity_path, registration_path = sys.argv[1:]
expected_environment = {
    "python": "3.11.13",
    "torch": "2.4.0",
    "numpy": "2.3.3",
    "pandas": "2.3.2",
    "scipy": "1.16.2",
}
observed_environment = {
    "python": platform.python_version(),
    "torch": version("torch").split("+")[0],
    "numpy": version("numpy"),
    "pandas": version("pandas"),
    "scipy": version("scipy"),
}
if observed_environment != expected_environment:
    raise SystemExit("nh_final environment changed: " + repr(observed_environment))

def safe_file_members(path):
    with tarfile.open(path, "r:gz") as archive:
        members = archive.getmembers()
    files = []
    for member in members:
        normalized = member.name[2:] if member.name.startswith("./") else member.name
        candidate = PurePosixPath(normalized)
        if candidate.is_absolute() or ".." in candidate.parts:
            raise SystemExit("unsafe archive member: " + member.name)
        if member.issym() or member.islnk():
            raise SystemExit("archive link is forbidden: " + member.name)
        if member.isfile():
            files.append(normalized)
    return sorted(files)

code_members = safe_file_members(code_archive)
prefix_members = safe_file_members(prefix_archive)
if len(code_members) != 17 or "bundle_manifest.json" not in code_members:
    raise SystemExit("code archive membership changed")
for member in code_members:
    lowered = member.lower()
    if "2023" in lowered or "2024" in lowered or "stage_b" in lowered or "evaluation" in lowered:
        raise SystemExit("forbidden code archive member: " + member)
if len(prefix_members) != 12 or not all(
    member.startswith("inputs/2017_2022/") for member in prefix_members
):
    raise SystemExit("prefix archive membership changed")
if any("2023" in member or "2024" in member for member in prefix_members):
    raise SystemExit("held-out suffix appeared in prefix archive")

manifest_raw = open(manifest_path, "rb").read()
identity_raw = open(identity_path, "rb").read()
registration_raw = open(registration_path, "rb").read()
manifest = json.loads(manifest_raw.decode("utf-8"))
identity = json.loads(identity_raw.decode("utf-8"))
registration = json.loads(registration_raw.decode("utf-8"))
if manifest.get("source_file_count") != 16:
    raise SystemExit("bundle source-file count changed")
for key in ("scientific_result", "formal_data_included", "held_out_2023_or_2024_data_included"):
    if manifest.get(key) is not False:
        raise SystemExit("bundle exclusion flag changed: " + key)
expected_hashes = {
    "authorization_sha256": "ab5d0c19c26026e9ab6fd4c412ba0e2573700aeca655042d23ac12b9e8b558c1",
    "data_contract_sha256": "26f1b988d0b126be172d612efa9fab0dedf8f3f48e849a3d7ddc331ffda6dc17",
    "execution_authorization_sha256": "970e1027dba389354309cd51464bed1325db9f893e29263b95459f7d07f33e36",
}
for key, value in expected_hashes.items():
    if manifest.get(key) != value or identity.get(key) != value:
        raise SystemExit("bundle contract hash changed: " + key)
if identity.get("archive_sha256") != "f5d5c0f87c9e964e0ac906f1ec7df6b0bc52c9329017db8132064bb84c2f5caa":
    raise SystemExit("bundle identity archive hash changed")
if identity.get("manifest_sha256") != hashlib.sha256(manifest_raw).hexdigest():
    raise SystemExit("bundle identity manifest hash changed")
if len(registration.get("files", {})) != 12:
    raise SystemExit("identity-registration object count changed")
if registration.get("forbidden_2023_data_row_reads") != 0 or registration.get("forbidden_2024_data_row_reads") != 0:
    raise SystemExit("identity-registration held-out read count changed")
prefix = registration.get("materialized_prefix_bundle", {})
if prefix.get("member_count") != 12 or prefix.get("sha256") != "7d419119c623efc3fc59591acbd4490c654c6e5fe2c07da8fc331681925746fe":
    raise SystemExit("identity-registration prefix identity changed")
print("login_package_metadata_preflight=PASS runtime_imports_deferred_to_compute_node=true " + json.dumps(observed_environment, sort_keys=True))
print("archive_header_preflight=PASS code_files=17 prefix_files=12 formal_data_content_inspected=false")
PY

echo '=== B. CREATE NEW ROOT ONCE ==='
if [ -e "${REMOTE_ROOT}" ] || [ -L "${REMOTE_ROOT}" ]; then
  fatal 'new root appeared during preflight'
fi
mkdir -- "${REMOTE_ROOT}"
mkdir -p -- \
  "${REMOTE_ROOT}/logs" \
  "${REMOTE_ROOT}/runs/stage_a" \
  "${REMOTE_ROOT}/evidence/contracts" \
  "${REMOTE_ROOT}/evidence/deployment" \
  "${REMOTE_ROOT}/evidence/identity_registration" \
  "${REMOTE_ROOT}/evidence/stage_a_failures" \
  "${REMOTE_ROOT}/evidence/stage_a_attempts/seed_17" \
  "${REMOTE_ROOT}/evidence/stage_a_attempts/seed_29" \
  "${REMOTE_ROOT}/evidence/stage_a_attempts/seed_43" \
  "${REMOTE_ROOT}/evidence/stage_a_job_attempt" \
  "${REMOTE_ROOT}/evidence/submission"

tar -xzf "${CODE_ARCHIVE}" -C "${REMOTE_ROOT}" --no-same-owner --no-same-permissions
tar -xzf "${PREFIX_ARCHIVE}" -C "${REMOTE_ROOT}" --no-same-owner --no-same-permissions
install -D -m 0444 -- "${TIDE_SOURCE}" "${REMOTE_ROOT}/inputs/2017_2022/astronomical_tide/wusongkou_tide_model.json"
install -m 0444 -- "${BUNDLE_IDENTITY_SOURCE}" "${REMOTE_ROOT}/evidence/deployment/bundle_identity.json"
install -m 0444 -- "${IDENTITY_MANIFEST_SOURCE}" "${REMOTE_ROOT}/evidence/identity_registration/identity_registration_manifest.json"
install -m 0444 -- "${IDENTITY_LEDGER_SOURCE}" "${REMOTE_ROOT}/evidence/identity_registration/identity_registration_usage.sqlite3"
chmod -R a-w -- "${REMOTE_ROOT}/inputs"

assert_file_identity "${REMOTE_ROOT}/bundle_manifest.json" "${BUNDLE_MANIFEST_BYTES}" "${BUNDLE_MANIFEST_SHA256}"
assert_file_identity "${REMOTE_ROOT}/contracts/stage_a_authorization.json" "3491" "${DATA_AUTHORIZATION_SHA256}"
assert_file_identity "${REMOTE_ROOT}/contracts/stage_a_data_contract.json" "8519" "${DATA_CONTRACT_SHA256}"
assert_file_identity "${REMOTE_ROOT}/evidence/contracts/paid_hpc_execution_authorization.json" "6138" "${EXECUTION_AUTHORIZATION_SHA256}"
assert_file_identity "${REMOTE_ROOT}/inputs/2017_2022/astronomical_tide/wusongkou_tide_model.json" "${TIDE_MODEL_BYTES}" "${TIDE_MODEL_SHA256}"
assert_file_identity "${REMOTE_ROOT}/evidence/identity_registration/identity_registration_manifest.json" "${IDENTITY_MANIFEST_BYTES}" "${IDENTITY_MANIFEST_SHA256}"
assert_file_identity "${REMOTE_ROOT}/evidence/identity_registration/identity_registration_usage.sqlite3" "${IDENTITY_LEDGER_BYTES}" "${IDENTITY_LEDGER_SHA256}"

input_file_count="$(find "${REMOTE_ROOT}/inputs/2017_2022" -type f -printf '.' | wc -c)"
[ "${input_file_count}" = '13' ] || fatal "deployed input file count changed: ${input_file_count}"
if find "${REMOTE_ROOT}/inputs/2017_2022" -type f -printf '%P\n' | grep -Eiq '2023|2024'; then
  fatal 'held-out suffix appeared in deployed input names'
fi

python -u - "${REMOTE_ROOT}/evidence/deployment/deployment_receipt.json" <<'PY'
import json
from pathlib import Path
import sys

document = {
    "schema_version": 2,
    "status": "deployed_pre_submission",
    "mailbox_channel": "zhenjiang-six-source-four-target-ukf",
    "mailbox_sequence": 74,
    "remote_root": "/data1/home/sunyiq/zhenjiang_five_source_five_target_single_analysis_ukf_oracle_datong_20260904_r1",
    "code_archive_sha256": "f5d5c0f87c9e964e0ac906f1ec7df6b0bc52c9329017db8132064bb84c2f5caa",
    "bundle_manifest_sha256": "087552bf4f7bdc7a464482ab6b293d8fcaa0d889f66e240b2ca50f93c3821f3f",
    "prefix_archive_sha256": "7d419119c623efc3fc59591acbd4490c654c6e5fe2c07da8fc331681925746fe",
    "identity_registration_manifest_sha256": "dbeb429521044f52558e009e5b5eeda28a48db9607140abc98a00e1501dd10ce",
    "data_authorization_sha256": "ab5d0c19c26026e9ab6fd4c412ba0e2573700aeca655042d23ac12b9e8b558c1",
    "data_contract_sha256": "26f1b988d0b126be172d612efa9fab0dedf8f3f48e849a3d7ddc331ffda6dc17",
    "execution_authorization_sha256": "970e1027dba389354309cd51464bed1325db9f893e29263b95459f7d07f33e36",
    "protected_hpc_roots_written": False,
    "formal_training_data_content_inspected_before_ledger": False,
    "stage_b_included": False,
    "evaluation_included": False,
}
path = Path(sys.argv[1])
with path.open("x", encoding="utf-8", newline="\n") as handle:
    json.dump(document, handle, indent=2, sort_keys=True, allow_nan=False)
    handle.write("\n")
print("deployment_receipt=" + str(path))
PY

echo '=== C. ZERO-DATA-RUN PREFLIGHT ==='
VERIFIER="${REMOTE_ROOT}/run/scripts/hpc/verify_zhenjiang_five_source_five_target_stage_a_hpc_v2.py"
USAGE_LEDGER="${REMOTE_ROOT}/evidence/stage_a_formal_data_usage.sqlite3"
[ ! -e "${USAGE_LEDGER}" ] && [ ! -L "${USAGE_LEDGER}" ] || fatal 'formal training usage ledger unexpectedly exists before submission'
python -u "${VERIFIER}" \
  --remote-root "${REMOTE_ROOT}" \
  --project-root "${REMOTE_ROOT}/run" \
  --bundle-manifest "${REMOTE_ROOT}/bundle_manifest.json" \
  --trusted-bundle-manifest-sha256 "${BUNDLE_MANIFEST_SHA256}" \
  --authorization "${REMOTE_ROOT}/contracts/stage_a_authorization.json" \
  --trusted-authorization-sha256 "${DATA_AUTHORIZATION_SHA256}" \
  --usage-ledger "${USAGE_LEDGER}" \
  --data-contract "${REMOTE_ROOT}/contracts/stage_a_data_contract.json" \
  --trusted-data-contract-sha256 "${DATA_CONTRACT_SHA256}" \
  --execution-authorization "${REMOTE_ROOT}/evidence/contracts/paid_hpc_execution_authorization.json" \
  --trusted-execution-authorization-sha256 "${EXECUTION_AUTHORIZATION_SHA256}" \
  --output-root "${REMOTE_ROOT}/runs" \
  --seed 17 | tee "${REMOTE_ROOT}/evidence/deployment/preflight_seed_17.json"

for seed in 17 29 43; do
  [ ! -e "${REMOTE_ROOT}/runs/stage_a/seed_${seed}" ] || fatal "seed output exists before submission: ${seed}"
  [ ! -e "${REMOTE_ROOT}/runs/stage_a/seed_${seed}.partial" ] || fatal "partial seed output exists before submission: ${seed}"
  [ ! -e "${REMOTE_ROOT}/evidence/stage_a_attempts/seed_${seed}/attempt_001" ] || fatal "seed attempt already consumed: ${seed}"
done
[ ! -e "${REMOTE_ROOT}/evidence/stage_a_job_attempt/attempt_001" ] || fatal 'job attempt already consumed'

SUBMISSION_ATTEMPT="${REMOTE_ROOT}/evidence/submission/attempt_001"
mkdir -- "${SUBMISSION_ATTEMPT}"
python -u - "${SUBMISSION_ATTEMPT}/requested.json" <<'PY'
import json
from pathlib import Path
import sys

document = {
    "schema_version": 2,
    "status": "submission_requested",
    "stage": "stage_a",
    "attempt_number": 1,
    "sbatch_call_limit": 1,
    "execution_mode": "single_job_sequential_seed_loop",
    "seed_order": [17, 29, 43],
    "automatic_retry": False,
    "automatic_requeue": False,
    "automatic_cleanup": False,
    "stage_b_included": False,
    "evaluation_included": False,
}
with Path(sys.argv[1]).open("x", encoding="utf-8", newline="\n") as handle:
    json.dump(document, handle, indent=2, sort_keys=True, allow_nan=False)
    handle.write("\n")
PY

echo '=== D. SINGLE SBATCH CALL ==='
set +e
submission_output="$(sbatch \
  "${REMOTE_ROOT}/run/scripts/hpc/zhenjiang_five_source_five_target_stage_a_v2.slurm" \
  "${CONFIRMATION}" \
  "${DATA_AUTHORIZATION_SHA256}" \
  "${DATA_CONTRACT_SHA256}" \
  "${BUNDLE_MANIFEST_SHA256}" \
  "${EXECUTION_AUTHORIZATION_SHA256}" 2>&1)"
submission_status="$?"
set -e
printf '%s\n' "${submission_output}"
if [ "${submission_status}" -ne 0 ]; then
  python -u - "${SUBMISSION_ATTEMPT}/submission_failed.json" "${submission_status}" "${submission_output}" <<'PY'
import json
from pathlib import Path
import sys
with Path(sys.argv[1]).open("x", encoding="utf-8", newline="\n") as handle:
    json.dump({"schema_version": 2, "status": "submission_failed_no_retry", "sbatch_exit_status": int(sys.argv[2]), "sbatch_output": sys.argv[3], "retry_authorized": False}, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
  fatal 'the only authorized sbatch call failed; no retry was attempted'
fi
if [[ ! "${submission_output}" =~ ^Submitted\ batch\ job\ ([0-9]+)$ ]]; then
  python -u - "${SUBMISSION_ATTEMPT}/submission_output_rejected.json" "${submission_output}" <<'PY'
import json
from pathlib import Path
import sys
with Path(sys.argv[1]).open("x", encoding="utf-8", newline="\n") as handle:
    json.dump({"schema_version": 2, "status": "submission_output_rejected_no_retry", "sbatch_output": sys.argv[2], "retry_authorized": False}, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY
  fatal 'sbatch output was not the single accepted form; no retry was attempted'
fi
JOB_ID="${BASH_REMATCH[1]}"
python -u - "${SUBMISSION_ATTEMPT}/submission_receipt.json" "${JOB_ID}" "${submission_output}" <<'PY'
import json
from pathlib import Path
import sys

document = {
    "schema_version": 2,
    "status": "submitted",
    "stage": "stage_a",
    "attempt_number": 1,
    "job_id": sys.argv[2],
    "sbatch_output": sys.argv[3],
    "sbatch_call_count": 1,
    "execution_mode": "single_job_sequential_seed_loop",
    "seed_order": [17, 29, 43],
    "slurm_no_requeue": True,
    "automatic_retry": False,
    "automatic_requeue": False,
    "automatic_cleanup": False,
    "bundle_manifest_sha256": "087552bf4f7bdc7a464482ab6b293d8fcaa0d889f66e240b2ca50f93c3821f3f",
    "data_authorization_sha256": "ab5d0c19c26026e9ab6fd4c412ba0e2573700aeca655042d23ac12b9e8b558c1",
    "data_contract_sha256": "26f1b988d0b126be172d612efa9fab0dedf8f3f48e849a3d7ddc331ffda6dc17",
    "execution_authorization_sha256": "970e1027dba389354309cd51464bed1325db9f893e29263b95459f7d07f33e36",
}
with Path(sys.argv[1]).open("x", encoding="utf-8", newline="\n") as handle:
    json.dump(document, handle, indent=2, sort_keys=True, allow_nan=False)
    handle.write("\n")
print("submission_receipt=" + sys.argv[1])
PY

echo '=== E. SUBMISSION COMPLETE; NO FOLLOW-ON STAGE ==='
printf 'stage_a_job_id=%s\n' "${JOB_ID}"
printf 'sbatch_call_count=1\n'
printf 'stage_b_submitted=no\n'
printf 'evaluation_started=no\n'
printf 'git_fetch_used=no\n'
squeue -j "${JOB_ID}" -h -o '%i|%j|%T|%P|%M|%R|%Z' || true
