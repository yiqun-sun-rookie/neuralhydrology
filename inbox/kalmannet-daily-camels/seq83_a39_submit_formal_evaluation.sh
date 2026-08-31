#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
CHANNEL="kalmannet-daily-camels"
EXPERIMENT_ID="DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_V1_20260831_A39"
EXECUTION_ID="DAILY_CAMELS_KNET_EPOCH75_SINGLE_BASIN_FORMAL_EVALUATION_A39_A800_EVAL1_SEQ83"
SUBMISSION_TOKEN="df7bb91652823a495be3a45e1afc69cf192422ea25de20def3d19cea982d0f0e"
JOB_NAME="daily-knet-a39-s83"
SUBMISSION_COMMENT="${EXECUTION_ID}"
RUN_ROOT="/data1/home/sunyiq/kalmannet_daily_camels_knet_a39_formal_evaluation1_20260831"
SOURCE_ROOT="${RUN_ROOT}/source_A39_formal_evaluation_seq83"
STATUS_ROOT="${RUN_ROOT}/status"
LOCK_ROOT="${STATUS_ROOT}/locks/${EXECUTION_ID}.submission.lock"
OWNER_JSON="${LOCK_ROOT}/owner.json"
BOUND_JSON="${LOCK_ROOT}/bound.json"
JOB_ID_FILE="${STATUS_ROOT}/submitted_job_id.txt"
PAYLOAD_ROOT="${MAILBOX_ROOT}/payload/${CHANNEL}/a39_epoch75_single_basin_formal_evaluation_seq83_20260831"
ARCHIVE="${PAYLOAD_ROOT}/${EXPERIMENT_ID}.tar.gz"
OUTER_MANIFEST="${PAYLOAD_ROOT}/bundle_manifest.sha256.json"
ARCHIVE_SHA256="7d103b0fc096dd841c42f809f0c02b23e0cfa5733dab15242ce68c6ea7a60a47"
ARCHIVE_SIZE="223131"
OUTER_MANIFEST_SHA256="7a7e272bf8a3febf9fcb6484f13ab9c8643c7a3d5f905e4e0089fae3814b11ba"
OUTER_MANIFEST_SIZE="1657"
INTERNAL_MANIFEST_SHA256="907c11e81218470bb177cf9304e41f080fa471ac20ce9b9475f5ddafc29aec5c"
SLURM_REL="hpc/daily_camels_knet_formal_evaluation/submit_evaluation_gpu.slurm"
SLURM_SHA256="a72e4a3d7b72aa04d03822aac4dab766e02f09361928c15f53b48034fcdecb53"
SLURM_SIZE="19411"
RESULT82="${MAILBOX_ROOT}/outbox/${CHANNEL}/result_82.txt"
RESULT82_SHA256="a16bfb72c526ff8ec15bb5940b80d4abe8aabe96ffda6bdd322ea604a4229e69"
RESULT82_SIZE="7403339"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

require_file() {
  [[ -f "$1" && ! -L "$1" ]] || {
    echo "$4 is absent, non-regular, or symbolic" >&2
    exit 40
  }
  [[ "$(stat -c '%s' "$1")" == "$3" ]] || {
    echo "$4 size differs" >&2
    exit 41
  }
  [[ "$(sha256_file "$1")" == "$2" ]] || {
    echo "$4 SHA-256 differs" >&2
    exit 42
  }
}

query_scheduler() {
  local prefix="$1" squeue_rc sacct_rc
  set +e
  squeue -h -u "$EXPECTED_USER" -o '%A|%j|%P|%T|%u|%k|%Z' \
    > "${prefix}.squeue" 2> "${prefix}.squeue.err"
  squeue_rc=$?
  sacct -n -X -u "$EXPECTED_USER" -S 2026-08-31 \
    --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,NodeList -P \
    > "${prefix}.sacct" 2> "${prefix}.sacct.err"
  sacct_rc=$?
  set -e
  [[ "$squeue_rc" == 0 && "$sacct_rc" == 0 ]] || {
    echo "scheduler uniqueness query failed closed" >&2
    return 70
  }
}

matching_ids() {
  python -S - "$1.squeue" "$1.sacct" "$JOB_NAME" "$EXPECTED_USER" \
    "$SUBMISSION_COMMENT" "$SOURCE_ROOT" <<'PY'
import pathlib
import sys

squeue_path, sacct_path = map(pathlib.Path, sys.argv[1:3])
job_name, expected_user, comment, source_root = sys.argv[3:]
identifiers: set[str] = set()
for line in squeue_path.read_text(encoding="utf-8").splitlines():
    fields = line.split("|")
    if (
        len(fields) >= 7
        and fields[1] == job_name
        and fields[4] == expected_user
        and fields[5] == comment
        and fields[6] == source_root
    ):
        identifiers.add(fields[0])
for line in sacct_path.read_text(encoding="utf-8").splitlines():
    fields = line.split("|")
    if (
        len(fields) >= 8
        and fields[1] == job_name
        and fields[2] == expected_user
        and fields[3] == "hgpu8"
    ):
        identifiers.add(fields[0])
for value in sorted(identifiers):
    if not value.isdigit():
        raise SystemExit("non-numeric matching Slurm identity")
    print(value)
PY
}

active_conflict_ids() {
  python -S - "$1.squeue" "$EXPECTED_USER" "$SUBMISSION_COMMENT" "$RUN_ROOT" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
expected_user, comment, run_root = sys.argv[2:]
identifiers: set[str] = set()
for line in path.read_text(encoding="utf-8").splitlines():
    fields = line.split("|")
    if len(fields) < 7 or fields[4] != expected_user:
        continue
    if fields[1].startswith("daily-knet-a39") or fields[5] == comment or fields[6].startswith(run_root):
        identifiers.add(fields[0])
for value in sorted(identifiers):
    if not value.isdigit():
        raise SystemExit("non-numeric active A39 conflict identity")
    print(value)
PY
}

record_job_id() {
  python -S - "$OWNER_JSON" "$BOUND_JSON" "$JOB_ID_FILE" \
    "$EXPERIMENT_ID" "$EXECUTION_ID" "$SUBMISSION_TOKEN" "$1" <<'PY'
import json
import os
import pathlib
import sys

owner_path, bound_path, job_path = map(pathlib.Path, sys.argv[1:4])
experiment_id, execution_id, token, job_id = sys.argv[4:]
if not owner_path.is_file() or owner_path.is_symlink():
    raise SystemExit("PREPARED owner is absent, non-regular, or symbolic")
with owner_path.open("r", encoding="utf-8") as handle:
    owner = json.load(handle)
expected_owner = {
    "experiment_id": experiment_id,
    "execution_id": execution_id,
    "submission_token": token,
    "state": "PREPARED",
    "persistent": True,
    "evaluation_only": True,
}
for key, expected in expected_owner.items():
    if owner.get(key) != expected:
        raise SystemExit(f"PREPARED owner differs at {key}")
if bound_path.exists() or bound_path.is_symlink():
    if not bound_path.is_file() or bound_path.is_symlink():
        raise SystemExit("BOUND evidence is non-regular or symbolic")
    with bound_path.open("r", encoding="utf-8") as handle:
        existing = json.load(handle)
    expected_bound = {
        "experiment_id": experiment_id,
        "execution_id": execution_id,
        "submission_token": token,
        "slurm_job_id": job_id,
        "state": "BOUND",
    }
    for key, expected in expected_bound.items():
        if existing.get(key) != expected:
            raise SystemExit(f"BOUND evidence differs at {key}")
if job_path.exists() or job_path.is_symlink():
    if not job_path.is_file() or job_path.is_symlink():
        raise SystemExit("job-id evidence is non-regular or symbolic")
    if job_path.read_text(encoding="utf-8").strip() != job_id:
        raise SystemExit("job-id evidence differs")
else:
    with job_path.open("x", encoding="utf-8") as handle:
        handle.write(job_id + "\n")
        handle.flush()
        os.fsync(handle.fileno())
PY
}

recover_only() {
  local temporary_root count bound_id
  local -a recovered_ids
  temporary_root="$(mktemp -d /tmp/a39-seq83-recover.XXXXXX)"
  query_scheduler "$temporary_root/snapshot"
  mapfile -t recovered_ids < <(matching_ids "$temporary_root/snapshot")
  count="${#recovered_ids[@]}"
  if [[ -f "$BOUND_JSON" && ! -L "$BOUND_JSON" ]]; then
    bound_id="$(python -S -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["slurm_job_id"])' "$BOUND_JSON")"
    [[ "$bound_id" =~ ^[0-9]+$ ]] || {
      echo "persisted BOUND job identity is invalid" >&2
      exit 71
    }
    [[ "$count" == 1 && "${recovered_ids[0]}" == "$bound_id" ]] || {
      echo "BOUND submission is not represented by exactly one scheduler record; no sbatch retry permitted" >&2
      exit 72
    }
    record_job_id "$bound_id"
    echo "SEQ83_A39_RECOVERED_BOUND job_id=${bound_id}"
    return 0
  fi
  [[ "$count" == 1 ]] || {
    echo "PREPARED submission has ${count} recoverable exact jobs; no sbatch retry permitted" >&2
    exit 72
  }
  record_job_id "${recovered_ids[0]}"
  echo "SEQ83_A39_RECOVERED_AFTER_AMBIGUOUS_RECEIPT job_id=${recovered_ids[0]}"
}

[[ "$(id -un)" == "$EXPECTED_USER" && "${USER-}" == "$EXPECTED_USER" ]] || {
  echo "fixed user differs" >&2
  exit 43
}
require_file "$RESULT82" "$RESULT82_SHA256" "$RESULT82_SIZE" "sequence-82 terminal receipt"
require_file "$ARCHIVE" "$ARCHIVE_SHA256" "$ARCHIVE_SIZE" "A39 sealed archive"
require_file "$OUTER_MANIFEST" "$OUTER_MANIFEST_SHA256" "$OUTER_MANIFEST_SIZE" "A39 outer manifest"

if [[ -e "$LOCK_ROOT" || -L "$LOCK_ROOT" ]]; then
  [[ -d "$LOCK_ROOT" && ! -L "$LOCK_ROOT" && -f "$OWNER_JSON" && ! -L "$OWNER_JSON" ]] || {
    echo "incomplete or unsafe persistent submission lock" >&2
    exit 73
  }
  recover_only
  exit 0
fi
[[ ! -e "$RUN_ROOT" && ! -L "$RUN_ROOT" ]] || {
  echo "new A39 root already exists without a recoverable lock" >&2
  exit 44
}

INITIAL_QUERY="$(mktemp -d /tmp/a39-seq83-pre.XXXXXX)"
query_scheduler "$INITIAL_QUERY/snapshot"
mapfile -t INITIAL_MATCHES < <(matching_ids "$INITIAL_QUERY/snapshot")
mapfile -t INITIAL_CONFLICTS < <(active_conflict_ids "$INITIAL_QUERY/snapshot")
[[ "${#INITIAL_MATCHES[@]}" == 0 && "${#INITIAL_CONFLICTS[@]}" == 0 ]] || {
  echo "matching or conflicting A39 job exists before preparation" >&2
  exit 74
}

mkdir "$RUN_ROOT"
mkdir "$SOURCE_ROOT"
mkdir -p "$STATUS_ROOT/locks" "$RUN_ROOT/logs"
cp "$INITIAL_QUERY/snapshot.squeue" "$STATUS_ROOT/initial-pre-sbatch.squeue"
cp "$INITIAL_QUERY/snapshot.sacct" "$STATUS_ROOT/initial-pre-sbatch.sacct"

python -S - "$ARCHIVE" "$SOURCE_ROOT" <<'PY'
import pathlib
import sys
import tarfile

archive_path = pathlib.Path(sys.argv[1])
target = pathlib.Path(sys.argv[2])
with tarfile.open(archive_path, "r:gz") as archive:
    members = archive.getmembers()
    # The outer manifest counts 38 registered payloads; the tar also contains its internal manifest.
    if len(members) != 39:
        raise SystemExit("archive member count differs")
    for member in members:
        path = pathlib.PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts or not member.isfile():
            raise SystemExit(f"unsafe archive member: {member.name}")
    archive.extractall(target, filter="data")
PY
require_file "$SOURCE_ROOT/bundle_manifest.json" "$INTERNAL_MANIFEST_SHA256" \
  "$(stat -c '%s' "$SOURCE_ROOT/bundle_manifest.json")" "internal manifest"
require_file "$SOURCE_ROOT/$SLURM_REL" "$SLURM_SHA256" "$SLURM_SIZE" "A39 Slurm entry"
(
  cd "$SOURCE_ROOT"
  python -B -S - <<'PY'
from pathlib import Path

from hpc.daily_camels_knet_formal_evaluation.preflight import verify_bundle_root

verify_bundle_root(Path("."))
PY
)

query_scheduler "$STATUS_ROOT/final-pre-sbatch"
mapfile -t FINAL_MATCHES < <(matching_ids "$STATUS_ROOT/final-pre-sbatch")
mapfile -t FINAL_CONFLICTS < <(active_conflict_ids "$STATUS_ROOT/final-pre-sbatch")
[[ "${#FINAL_MATCHES[@]}" == 0 && "${#FINAL_CONFLICTS[@]}" == 0 ]] || {
  echo "matching or conflicting A39 job appeared during preparation" >&2
  exit 75
}

mkdir "$LOCK_ROOT"
python -S - "$OWNER_JSON" "$EXPERIMENT_ID" "$EXECUTION_ID" "$SUBMISSION_TOKEN" \
  "$ARCHIVE_SHA256" "$SLURM_SHA256" "$(sha256_file "${BASH_SOURCE[0]}")" <<'PY'
import datetime
import json
import os
import pathlib
import socket
import sys

path = pathlib.Path(sys.argv[1])
experiment_id, execution_id, token, archive_hash, slurm_hash, controller_hash = sys.argv[2:]
payload = {
    "created_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "experiment_id": experiment_id,
    "execution_id": execution_id,
    "submission_token": token,
    "state": "PREPARED",
    "persistent": True,
    "evaluation_only": True,
    "archive_sha256": archive_hash,
    "slurm_sha256": slurm_hash,
    "controller_sha256": controller_hash,
    "owner_user": "sunyiq",
    "owner_host": socket.gethostname(),
    "owner_pid": os.getpid(),
    "mailbox_sequence": 83,
}
with path.open("x", encoding="utf-8") as handle:
    json.dump(payload, handle, sort_keys=True)
    handle.write("\n")
    handle.flush()
    os.fsync(handle.fileno())
PY

SBATCH_STDOUT="$STATUS_ROOT/sbatch.stdout"
SBATCH_STDERR="$STATUS_ROOT/sbatch.stderr"
SBATCH_RC_FILE="$STATUS_ROOT/sbatch.exit"
set +e
sbatch --parsable --chdir="$SOURCE_ROOT" --job-name="$JOB_NAME" \
  --comment="$SUBMISSION_COMMENT" \
  --export="ALL,A39_SUBMISSION_TOKEN=${SUBMISSION_TOKEN}" \
  "$SOURCE_ROOT/$SLURM_REL" >"$SBATCH_STDOUT" 2>"$SBATCH_STDERR"
SBATCH_RC=$?
set -e
printf '%s\n' "$SBATCH_RC" > "$SBATCH_RC_FILE"
RAW_RECEIPT="$(tr -d '\r' < "$SBATCH_STDOUT")"
JOB_ID="${RAW_RECEIPT%%;*}"
if [[ "$SBATCH_RC" == 0 && "$RAW_RECEIPT" =~ ^[0-9]+(\;[^[:space:]]+)?$ && "$JOB_ID" =~ ^[0-9]+$ ]]; then
  record_job_id "$JOB_ID"
  echo "SEQ83_A39_SBATCH_RECORDED job_id=${JOB_ID} bound_written_by_controller=false"
  POST_QUERY_OK="false"
  for _attempt in $(seq 1 20); do
    query_scheduler "$STATUS_ROOT/post-sbatch"
    mapfile -t POST_MATCHES < <(matching_ids "$STATUS_ROOT/post-sbatch")
    mapfile -t POST_CONFLICTS < <(active_conflict_ids "$STATUS_ROOT/post-sbatch")
    if [[ "${#POST_MATCHES[@]}" == 1 && "${POST_MATCHES[0]}" == "$JOB_ID" ]]; then
      OTHER_CONFLICT="false"
      for conflict_id in "${POST_CONFLICTS[@]}"; do
        if [[ "$conflict_id" != "$JOB_ID" ]]; then
          OTHER_CONFLICT="true"
        fi
      done
      if [[ "$OTHER_CONFLICT" == "false" ]]; then
        POST_QUERY_OK="true"
        break
      fi
    fi
    sleep 1
  done
  [[ "$POST_QUERY_OK" == "true" ]] || {
    echo "submitted job is bound, but post-submission uniqueness was not proven; no retry permitted" >&2
    exit 76
  }
  echo "SEQ83_A39_FORMAL_EVALUATION_SUBMITTED experiment_id=${EXPERIMENT_ID} execution_id=${EXECUTION_ID} job_id=${JOB_ID} archive_sha256=${ARCHIVE_SHA256} manifest_sha256=${OUTER_MANIFEST_SHA256} slurm_sha256=${SLURM_SHA256} root=${RUN_ROOT} unique_before=true unique_after=true"
  exit 0
fi

echo "sbatch receipt is ambiguous (exit=${SBATCH_RC}); entering query-only recovery" >&2
recover_only
