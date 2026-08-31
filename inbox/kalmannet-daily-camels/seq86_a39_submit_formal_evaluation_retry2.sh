#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL="kalmannet-daily-camels"
EXPERIMENT_ID="DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_V1_20260831_A39"
EXECUTION_ID="DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_A39_A800_EVAL2_SEQ86"
SUBMISSION_TOKEN="89baa27b6d8c5012d8719e56e6967b6e71e38e9c1b2346d5c5a8561a1ce57e93"
JOB_NAME="daily-knet-a39-s86"
SUBMISSION_COMMENT="${EXECUTION_ID}"
RUN_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation2_20260831"
SOURCE_ROOT="${RUN_ROOT}/source_A39_formal_evaluation_seq86"
STATUS_ROOT="${RUN_ROOT}/status"
LOCK_ROOT="${STATUS_ROOT}/locks/${EXECUTION_ID}.submission.lock"
OWNER_JSON="${LOCK_ROOT}/owner.json"
BOUND_JSON="${LOCK_ROOT}/bound.json"
JOB_ID_FILE="${STATUS_ROOT}/submitted_job_id.txt"
PAYLOAD_ROOT="${MAILBOX_ROOT}/payload/${CHANNEL}/a39_epoch75_single_basin_formal_evaluation_retry2_seq86_20260831"
ARCHIVE="${PAYLOAD_ROOT}/${EXPERIMENT_ID}.tar.gz"
OUTER_MANIFEST="${PAYLOAD_ROOT}/bundle_manifest.sha256.json"
ARCHIVE_SHA256="ad8de48d58e087f6d7c6e39c96c411ee9c2edcf4a9b6f263ca0c230f3dbc94f2"
ARCHIVE_SIZE="224203"
OUTER_MANIFEST_SHA256="caf3b03bf6324e8c5c8ed8c1a141a3ade60babb9583436313d797e4b796d1131"
OUTER_MANIFEST_SIZE="1657"
INTERNAL_MANIFEST_SHA256="7b51b42b6eda845c7ad0003e252c80ac4452ca712d4998f47923fa87e27ae15b"
INTERNAL_MANIFEST_SIZE="9682"
ARCHIVE_MEMBER_COUNT="39"
REGISTERED_MEMBER_COUNT="38"
SLURM_REL="hpc/daily_camels_knet_formal_evaluation/submit_evaluation_gpu.slurm"
SLURM_SHA256="0b4a2bbbdae45d78e811861c5ed8a64b96c974fcc7a56db3d78b19bc8f43d1b3"
SLURM_SIZE="19640"
PREFLIGHT_REL="hpc/daily_camels_knet_formal_evaluation/preflight.py"
PREFLIGHT_SHA256="1f3a3d251a9184954cfbe16b5016cd1b702db04d15bfbbf2388601b4159898d1"
PREFLIGHT_SIZE="33418"
RESULT85="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_85.txt"
RESULT85_SHA256="a3ef9061e9b9634c10792700407c077d4e34529f58dc6052a68eea5594e10a2a"
RESULT85_SIZE="3789"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

require_file() {
  local path="$1" expected_sha="$2" expected_size="$3" label="$4"
  [[ -f "${path}" && ! -L "${path}" ]] || {
    echo "${label} absent, non-regular, or symbolic" >&2
    exit 40
  }
  [[ "$(stat -c '%s' "${path}")" == "${expected_size}" ]] || {
    echo "${label} size differs" >&2
    exit 41
  }
  [[ "$(sha256_file "${path}")" == "${expected_sha}" ]] || {
    echo "${label} SHA-256 differs" >&2
    exit 42
  }
}

verify_outer_manifest() {
  python -B -S - \
    "${OUTER_MANIFEST}" \
    "${EXPERIMENT_ID}" \
    "$(basename "${ARCHIVE}")" \
    "${ARCHIVE_SHA256}" \
    "${ARCHIVE_SIZE}" \
    "${REGISTERED_MEMBER_COUNT}" \
    "${INTERNAL_MANIFEST_SHA256}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
experiment_id, archive_name, archive_sha, archive_size, registered_count, internal_sha = sys.argv[2:]
payload = json.loads(path.read_text(encoding="utf-8"))
expected = {
    "schema_version": "daily_camels_knet_formal_evaluation_hpc_archive_v1",
    "experiment_id": experiment_id,
    "archive_name": archive_name,
    "archive_sha256": archive_sha,
    "archive_size": int(archive_size),
    "member_count": int(registered_count),
    "internal_manifest_sha256": internal_sha,
    "checkpoint_member_count": 0,
    "historical_evaluation_array_member_count": 0,
}
for key, expected_value in expected.items():
    if payload.get(key) != expected_value:
        raise SystemExit(f"outer manifest differs at {key}")
PY
}

query_scheduler() {
  local prefix="$1" squeue_rc sacct_rc
  set +e
  squeue -h -u "${EXPECTED_USER}" -o '%A|%j|%P|%T|%u|%k|%Z' \
    > "${prefix}.squeue" 2> "${prefix}.squeue.err"
  squeue_rc=$?
  sacct -n -X -u "${EXPECTED_USER}" -S 2026-08-31 \
    --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,NodeList -P \
    > "${prefix}.sacct" 2> "${prefix}.sacct.err"
  sacct_rc=$?
  set -e
  [[ "${squeue_rc}" == 0 && "${sacct_rc}" == 0 ]] || {
    echo "scheduler uniqueness query failed closed" >&2
    return 70
  }
}

matching_ids() {
  python -B -S - \
    "$1.squeue" \
    "$1.sacct" \
    "${JOB_NAME}" \
    "${EXPECTED_USER}" \
    "${SUBMISSION_COMMENT}" \
    "${SOURCE_ROOT}" <<'PY'
import pathlib
import sys

squeue_path = pathlib.Path(sys.argv[1])
sacct_path = pathlib.Path(sys.argv[2])
job_name, expected_user, comment, source_root = sys.argv[3:]
job_ids = set()
for line in squeue_path.read_text(encoding="utf-8").splitlines():
    parts = line.split("|")
    if (
        len(parts) >= 7
        and parts[1] == job_name
        and parts[4] == expected_user
        and parts[5] == comment
        and parts[6] == source_root
    ):
        job_ids.add(parts[0])
for line in sacct_path.read_text(encoding="utf-8").splitlines():
    parts = line.split("|")
    if (
        len(parts) >= 8
        and parts[1] == job_name
        and parts[2] == expected_user
        and parts[3] == "hgpu8"
    ):
        job_ids.add(parts[0])
for value in sorted(job_ids):
    if not value.isdigit():
        raise SystemExit("non-numeric matching Slurm identity")
    print(value)
PY
}

validate_prepared_owner() {
  python -B -S - \
    "${OWNER_JSON}" \
    "${EXPERIMENT_ID}" \
    "${EXECUTION_ID}" \
    "${SUBMISSION_TOKEN}" \
    "${ARCHIVE_SHA256}" \
    "${SLURM_SHA256}" \
    "${RESULT85_SHA256}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
if not path.is_file() or path.is_symlink():
    raise SystemExit("PREPARED owner is absent, non-regular, or symbolic")
payload = json.loads(path.read_text(encoding="utf-8"))
experiment_id, execution_id, token, archive_sha, slurm_sha, result85_sha = sys.argv[2:]
expected = {
    "experiment_id": experiment_id,
    "execution_id": execution_id,
    "submission_token": token,
    "state": "PREPARED",
    "persistent": True,
    "evaluation_only": True,
    "archive_sha256": archive_sha,
    "slurm_sha256": slurm_sha,
    "prior_failure_result85_sha256": result85_sha,
    "mailbox_sequence": 86,
}
for key, expected_value in expected.items():
    if payload.get(key) != expected_value:
        raise SystemExit(f"PREPARED owner differs at {key}")
PY
}

validate_bound_if_present() {
  local expected_job_id="$1"
  if [[ ! -e "${BOUND_JSON}" && ! -L "${BOUND_JSON}" ]]; then
    return 0
  fi
  python -B -S - \
    "${BOUND_JSON}" \
    "${EXPERIMENT_ID}" \
    "${EXECUTION_ID}" \
    "${SUBMISSION_TOKEN}" \
    "${expected_job_id}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
if not path.is_file() or path.is_symlink():
    raise SystemExit("Slurm-written BOUND evidence is non-regular or symbolic")
payload = json.loads(path.read_text(encoding="utf-8"))
experiment_id, execution_id, token, job_id = sys.argv[2:]
expected = {
    "experiment_id": experiment_id,
    "execution_id": execution_id,
    "submission_token": token,
    "slurm_job_id": job_id,
    "state": "BOUND",
    "persistent": True,
    "evaluation_only": True,
}
for key, expected_value in expected.items():
    if payload.get(key) != expected_value:
        raise SystemExit(f"Slurm-written BOUND evidence differs at {key}")
PY
}

record_job_id() {
  local job_id="$1"
  [[ "${job_id}" =~ ^[0-9]+$ ]] || {
    echo "refusing non-numeric Slurm job identity" >&2
    exit 71
  }
  python -B -S - "${JOB_ID_FILE}" "${job_id}" <<'PY'
import os
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
job_id = sys.argv[2]
if path.exists() or path.is_symlink():
    if not path.is_file() or path.is_symlink():
        raise SystemExit("job-id evidence is non-regular or symbolic")
    if path.read_text(encoding="utf-8").strip() != job_id:
        raise SystemExit("job-id evidence differs")
else:
    with path.open("x", encoding="utf-8") as handle:
        handle.write(job_id + "\n")
        handle.flush()
        os.fsync(handle.fileno())
PY
}

recover_only() {
  local temporary_directory count bound_job_id existing_job_id
  local -a recovered_ids
  temporary_directory="$(mktemp -d /tmp/a39-seq86-recover.XXXXXX)"
  query_scheduler "${temporary_directory}/snapshot"
  mapfile -t recovered_ids < <(matching_ids "${temporary_directory}/snapshot")
  count="${#recovered_ids[@]}"

  if [[ -f "${JOB_ID_FILE}" && ! -L "${JOB_ID_FILE}" ]]; then
    existing_job_id="$(tr -d '\r\n' < "${JOB_ID_FILE}")"
    [[ "${existing_job_id}" =~ ^[0-9]+$ ]] || {
      echo "recorded Slurm job identity is invalid" >&2
      exit 71
    }
    [[ "${count}" == 1 && "${recovered_ids[0]}" == "${existing_job_id}" ]] || {
      echo "recorded job does not have exactly one scheduler identity; no sbatch retry permitted" >&2
      exit 72
    }
    record_job_id "${existing_job_id}"
    validate_bound_if_present "${existing_job_id}"
    echo "SEQ86_A39_RECOVERED_RECORDED job_id=${existing_job_id}"
    return 0
  fi

  if [[ -f "${BOUND_JSON}" && ! -L "${BOUND_JSON}" ]]; then
    bound_job_id="$(python -B -S -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["slurm_job_id"])' "${BOUND_JSON}")"
    [[ "${bound_job_id}" =~ ^[0-9]+$ ]] || {
      echo "Slurm-written BOUND job identity is invalid" >&2
      exit 71
    }
    [[ "${count}" == 1 && "${recovered_ids[0]}" == "${bound_job_id}" ]] || {
      echo "BOUND job does not have exactly one scheduler identity; no sbatch retry permitted" >&2
      exit 72
    }
    validate_bound_if_present "${bound_job_id}"
    record_job_id "${bound_job_id}"
    echo "SEQ86_A39_RECOVERED_BOUND job_id=${bound_job_id}"
    return 0
  fi

  [[ "${count}" == 1 ]] || {
    echo "PREPARED submission has ${count} recoverable exact jobs; no sbatch retry permitted" >&2
    exit 72
  }
  record_job_id "${recovered_ids[0]}"
  echo "SEQ86_A39_RECOVERED_AFTER_AMBIGUOUS_RECEIPT job_id=${recovered_ids[0]}"
}

[[ "$(id -un)" == "${EXPECTED_USER}" && "${USER-}" == "${EXPECTED_USER}" ]] || {
  echo "fixed user differs" >&2
  exit 43
}
require_file "${RESULT85}" "${RESULT85_SHA256}" "${RESULT85_SIZE}" "sequence-85 terminal diagnostic receipt"
require_file "${ARCHIVE}" "${ARCHIVE_SHA256}" "${ARCHIVE_SIZE}" "A39 retry sealed archive"
require_file "${OUTER_MANIFEST}" "${OUTER_MANIFEST_SHA256}" "${OUTER_MANIFEST_SIZE}" "A39 retry outer manifest"
verify_outer_manifest

if [[ -e "${LOCK_ROOT}" || -L "${LOCK_ROOT}" ]]; then
  [[ -d "${LOCK_ROOT}" && ! -L "${LOCK_ROOT}" ]] || {
    echo "persistent submission lock is incomplete or unsafe" >&2
    exit 73
  }
  validate_prepared_owner
  recover_only
  exit 0
fi
[[ ! -e "${RUN_ROOT}" && ! -L "${RUN_ROOT}" ]] || {
  echo "new A39 retry root already exists without a recoverable lock" >&2
  exit 44
}

PRE_QUERY="$(mktemp -d /tmp/a39-seq86-pre.XXXXXX)"
query_scheduler "${PRE_QUERY}/pre"
mapfile -t PRE_IDS < <(matching_ids "${PRE_QUERY}/pre")
[[ "${#PRE_IDS[@]}" == 0 ]] || {
  echo "matching A39 retry job exists before preparation" >&2
  exit 74
}

mkdir "${RUN_ROOT}"
mkdir -p "${SOURCE_ROOT}" "${STATUS_ROOT}/locks" "${RUN_ROOT}/logs"
cp "${PRE_QUERY}/pre.squeue" "${STATUS_ROOT}/prepared-pre-sbatch.squeue"
cp "${PRE_QUERY}/pre.sacct" "${STATUS_ROOT}/prepared-pre-sbatch.sacct"

python -B -S - "${ARCHIVE}" "${SOURCE_ROOT}" "${ARCHIVE_MEMBER_COUNT}" <<'PY'
import pathlib
import sys
import tarfile

archive = pathlib.Path(sys.argv[1])
target = pathlib.Path(sys.argv[2])
expected_count = int(sys.argv[3])
with tarfile.open(archive, "r:gz") as handle:
    members = handle.getmembers()
    if len(members) != expected_count:
        raise SystemExit("archive member count differs")
    names = set()
    for member in members:
        path = pathlib.PurePosixPath(member.name)
        if (
            path.is_absolute()
            or ".." in path.parts
            or path == pathlib.PurePosixPath(".")
            or not member.isfile()
            or member.name in names
        ):
            raise SystemExit(f"unsafe archive member: {member.name}")
        names.add(member.name)
    handle.extractall(target, filter="data")
PY
require_file "${SOURCE_ROOT}/bundle_manifest.json" "${INTERNAL_MANIFEST_SHA256}" "${INTERNAL_MANIFEST_SIZE}" "A39 internal manifest"
require_file "${SOURCE_ROOT}/${SLURM_REL}" "${SLURM_SHA256}" "${SLURM_SIZE}" "A39 Slurm entry"
require_file "${SOURCE_ROOT}/${PREFLIGHT_REL}" "${PREFLIGHT_SHA256}" "${PREFLIGHT_SIZE}" "A39 preflight entry"
(
  cd "${SOURCE_ROOT}"
  python -B -S - <<'PY'
from pathlib import Path

from hpc.daily_camels_knet_formal_evaluation.preflight import verify_bundle_root

verify_bundle_root(Path("."))
PY
)

query_scheduler "${STATUS_ROOT}/final-pre-sbatch"
mapfile -t FINAL_IDS < <(matching_ids "${STATUS_ROOT}/final-pre-sbatch")
[[ "${#FINAL_IDS[@]}" == 0 ]] || {
  echo "matching A39 retry job appeared during preparation" >&2
  exit 75
}

mkdir "${LOCK_ROOT}"
OWNER_TEMPORARY="$(mktemp "${STATUS_ROOT}/owner.XXXXXX")"
python -B -S - \
  "${OWNER_TEMPORARY}" \
  "${EXPERIMENT_ID}" \
  "${EXECUTION_ID}" \
  "${SUBMISSION_TOKEN}" \
  "${ARCHIVE_SHA256}" \
  "${SLURM_SHA256}" \
  "$(sha256_file "${BASH_SOURCE[0]}")" \
  "${RESULT85_SHA256}" <<'PY'
import datetime
import json
import os
import pathlib
import socket
import sys

path = pathlib.Path(sys.argv[1])
experiment_id, execution_id, token, archive_sha, slurm_sha, controller_sha, result85_sha = sys.argv[2:]
payload = {
    "created_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "experiment_id": experiment_id,
    "execution_id": execution_id,
    "submission_token": token,
    "state": "PREPARED",
    "persistent": True,
    "evaluation_only": True,
    "archive_sha256": archive_sha,
    "slurm_sha256": slurm_sha,
    "controller_sha256": controller_sha,
    "prior_failure_result85_sha256": result85_sha,
    "prior_failure_reason": "SLURM_SUBMIT_DIR remained the mailbox root despite sbatch --chdir",
    "owner_user": "sunyiq",
    "owner_host": socket.gethostname(),
    "owner_pid": os.getpid(),
    "mailbox_sequence": 86,
}
with path.open("w", encoding="utf-8") as handle:
    json.dump(payload, handle, sort_keys=True)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
PY
ln "${OWNER_TEMPORARY}" "${OWNER_JSON}"
rm "${OWNER_TEMPORARY}"
validate_prepared_owner

SBATCH_STDOUT="${STATUS_ROOT}/sbatch.stdout"
SBATCH_STDERR="${STATUS_ROOT}/sbatch.stderr"
SBATCH_EXIT_FILE="${STATUS_ROOT}/sbatch.exit"
set +e
(
  cd "${SOURCE_ROOT}" || exit 97
  sbatch --parsable \
    --chdir="${SOURCE_ROOT}" \
    --job-name="${JOB_NAME}" \
    --comment="${SUBMISSION_COMMENT}" \
    --export="ALL,A39_SUBMISSION_TOKEN=${SUBMISSION_TOKEN},A39_BUNDLE_ROOT=${SOURCE_ROOT}" \
    "${SOURCE_ROOT}/${SLURM_REL}"
) > "${SBATCH_STDOUT}" 2> "${SBATCH_STDERR}"
SBATCH_EXIT=$?
set -e
printf '%s\n' "${SBATCH_EXIT}" > "${SBATCH_EXIT_FILE}"
RAW_RECEIPT="$(tr -d '\r\n' < "${SBATCH_STDOUT}")"
JOB_ID="${RAW_RECEIPT%%;*}"
if [[ "${SBATCH_EXIT}" == 0 && "${RAW_RECEIPT}" =~ ^[0-9]+(\;[^[:space:]]+)?$ && "${JOB_ID}" =~ ^[0-9]+$ ]]; then
  record_job_id "${JOB_ID}"
  query_scheduler "${STATUS_ROOT}/post-sbatch"
  mapfile -t POST_IDS < <(matching_ids "${STATUS_ROOT}/post-sbatch")
  if [[ "${#POST_IDS[@]}" != 1 || "${POST_IDS[0]}" != "${JOB_ID}" ]]; then
    echo "job ${JOB_ID} was submitted and recorded, but post-submit uniqueness proof differs; do not resubmit" >&2
    exit 76
  fi
  echo "SEQ86_A39_FORMAL_EVALUATION_SUBMITTED experiment_id=${EXPERIMENT_ID} execution_id=${EXECUTION_ID} job_id=${JOB_ID} archive_sha256=${ARCHIVE_SHA256} manifest_sha256=${OUTER_MANIFEST_SHA256} slurm_sha256=${SLURM_SHA256} preflight_sha256=${PREFLIGHT_SHA256} prior_result85_sha256=${RESULT85_SHA256} root=${RUN_ROOT} source_root=${SOURCE_ROOT}"
  exit 0
fi
echo "sbatch receipt is ambiguous (exit=${SBATCH_EXIT}); entering query-only recovery with no sbatch retry" >&2
recover_only
