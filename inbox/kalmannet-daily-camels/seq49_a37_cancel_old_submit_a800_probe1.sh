#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT35="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_35.txt"
RESULT48="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_48.txt"
PAYLOAD_DIRECTORY="${MAILBOX_ROOT}/payload/kalmannet-daily-camels/parity-a37-resume-probe2-v35"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH10_TO40_RESUME_V1_20260826_A37"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_A800_PROBE1_SEQ49"
ARCHIVE="${PAYLOAD_DIRECTORY}/${EXPERIMENT_ID}.tar.gz"
OUTER_MANIFEST="${PAYLOAD_DIRECTORY}/A37_bundle_manifest.sha256.json"
ARCHIVE_SHA256="feb7ee1f1257f021991f6d380cb49b5171af42d4de54811428f2944c1da22e81"
ARCHIVE_SIZE=1815377
OUTER_MANIFEST_SHA256="78a3a2cc642e91af2397afc542a7eff45dcf3cee17bb467fdb20ab595507859d"
OUTER_MANIFEST_SIZE=11419
INTERNAL_MANIFEST_SHA256="b0d374d72d5105735c9455271ec0f778831fa7ad2ec64c7ef4841299651cb13e"
CONFIG_SHA256="70a522e9306c80d6c3010a3fbcf7fda3b4f53d850498698e1ef15f1028441984"
PROBE_SCRIPT_SHA256="4094e0c1480481c352d4e42cf5ae4e732e18323dd772f063033e2c25e2f2ede0"
CHECKPOINT_SHA256="b2b93f531c7ad4922e14d5479564e82e5a6dca553835bbc8cc8af61db4a8d81e"
WRAPPER_SOURCE="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels/seq49_a37_a800_probe_wrapper.slurm"
WRAPPER_SHA256="949839e5007a5748f9ae9d82b0cd77d95d874ba255216b51fbd086ebf64b4d02"
WRAPPER_SIZE=2335
OLD_PROBE_JOB_ID="215178"
OLD_PROBE_JOB_NAME="daily-knet-a37-probe"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a37_a800_probe1_20260827"
SOURCE_DIRECTORY="${RUN_BASE}/source_A37_a800_probe1_seq49"
RUN_DIRECTORY="${RUN_BASE}/runs/${EXPERIMENT_ID}"
STATUS_DIRECTORY="${RUN_BASE}/status"
LOG_DIRECTORY="${RUN_BASE}/logs"
A800_WRAPPER="${RUN_BASE}/seq49_a37_a800_probe_wrapper.slurm"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

require_regular_identity() {
  local path="$1" expected_sha256="$2" expected_size="$3" label="$4"
  [[ -f "$path" && ! -L "$path" ]] || {
    echo "${label} is absent, non-regular, or symbolic: ${path}" >&2
    return 50
  }
  [[ "$(stat -c '%s' "$path")" = "$expected_size" ]] || {
    echo "${label} size differs" >&2
    return 51
  }
  [[ "$(sha256_file "$path")" = "$expected_sha256" ]] || {
    echo "${label} SHA-256 differs" >&2
    return 52
  }
}

ACTUAL_USER="$(id -un)"
ACTUAL_UID="$(id -u)"
EXPECTED_UID="$(id -u "$EXPECTED_USER")"
if [[ "${USER-}" != "$EXPECTED_USER" || "$ACTUAL_USER" != "$EXPECTED_USER" || "$ACTUAL_UID" != "$EXPECTED_UID" ]]; then
  echo "fixed-user check failed" >&2
  exit 53
fi

for receipt in "$RESULT35" "$RESULT48"; do
  [[ -f "$receipt" && ! -L "$receipt" ]] || {
    echo "required prior receipt is absent or symbolic: $receipt" >&2
    exit 54
  }
done
grep -Fq "SEQ35_A37_RESOURCE_PROBE2_SUBMITTED experiment_id=${EXPERIMENT_ID}" "$RESULT35" || {
  echo "sequence 35 does not prove the reusable A37 package identity" >&2
  exit 55
}
grep -Fq "archive_sha256=${ARCHIVE_SHA256}" "$RESULT35" || {
  echo "sequence 35 reusable archive SHA-256 differs" >&2
  exit 56
}
grep -Fq "SEQ48_A37_HGPU8_CAPACITY_AUDIT_COMPLETE old_probe_job_id=${OLD_PROBE_JOB_ID}" "$RESULT48" || {
  echo "sequence 48 capacity audit did not complete" >&2
  exit 57
}
grep -Fq "${OLD_PROBE_JOB_ID}|${OLD_PROBE_JOB_NAME}|hgpu2p|PENDING" "$RESULT48" || {
  echo "sequence 48 does not prove the old probe pending identity" >&2
  exit 58
}

require_regular_identity "$ARCHIVE" "$ARCHIVE_SHA256" "$ARCHIVE_SIZE" "reused A37 archive"
require_regular_identity "$OUTER_MANIFEST" "$OUTER_MANIFEST_SHA256" "$OUTER_MANIFEST_SIZE" "reused A37 outer manifest"
require_regular_identity "$WRAPPER_SOURCE" "$WRAPPER_SHA256" "$WRAPPER_SIZE" "A37 A800 scheduling wrapper"

python - "$ARCHIVE" "$OUTER_MANIFEST" "$EXPERIMENT_ID" "$ARCHIVE_SHA256" "$ARCHIVE_SIZE" "$INTERNAL_MANIFEST_SHA256" "$CONFIG_SHA256" "$PROBE_SCRIPT_SHA256" "$CHECKPOINT_SHA256" <<'PY'
from hashlib import sha256
import json
from pathlib import Path, PurePosixPath
import sys
import tarfile

archive = Path(sys.argv[1])
outer = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
experiment_id = sys.argv[3]
archive_sha = sys.argv[4]
archive_size = int(sys.argv[5])
internal_sha = sys.argv[6]
config_sha = sys.argv[7]
probe_sha = sys.argv[8]
checkpoint_sha = sys.argv[9]
active_config = "configs/daily_camels_knet_fixed_full_training_coverage_epoch10_to40_resume_a37.json"
probe_script = "hpc/daily_camels_ukf_knet_parity/submit_probe_gpu.slurm"
checkpoint = (
    "artifacts/daily_camels_ukf_knet_parity_seq15_failure_evidence/"
    "ff2084c4/seq15_snapshot_2831/run/checkpoints/epoch_010.pt"
)
continuation = outer.get("continuation", {})
if (
    outer.get("experiment_id") != experiment_id
    or outer.get("archive_sha256") != archive_sha
    or int(outer.get("archive_size", -1)) != archive_size
    or int(outer.get("member_count", -1)) != 46
    or int(outer.get("reserved_data_member_count", -1)) != 0
    or int(outer.get("resume_checkpoint_count", -1)) != 1
    or int(outer.get("array_members_materialized_during_build", -1)) != 0
    or outer.get("internal_manifest_sha256") != internal_sha
    or outer.get("member_sha256", {}).get(active_config) != config_sha
    or outer.get("member_sha256", {}).get(probe_script) != probe_sha
    or outer.get("member_sha256", {}).get(checkpoint) != checkpoint_sha
    or continuation.get("checkpoint_path") != checkpoint
    or continuation.get("checkpoint_sha256") != checkpoint_sha
    or int(continuation.get("completed_epoch", -1)) != 10
    or int(continuation.get("optimizer_steps", -1)) != 10
    or int(continuation.get("sampled_forecast_events", -1)) != 76500
):
    raise SystemExit("reused A37 package or continuation identity differs")
with tarfile.open(archive, "r:gz") as handle:
    members = handle.getmembers()
    if len(members) != 47:
        raise SystemExit("reused A37 raw archive member count differs")
    for member in members:
        path = PurePosixPath(member.name)
        if path.is_absolute() or ".." in path.parts or not member.isfile():
            raise SystemExit(f"unsafe or non-regular reused A37 member: {member.name}")
    stream = handle.extractfile("bundle_manifest.json")
    if stream is None:
        raise SystemExit("reused A37 internal manifest is unreadable")
    internal_bytes = stream.read()
if sha256(internal_bytes).hexdigest() != internal_sha:
    raise SystemExit("reused A37 internal manifest SHA-256 differs")
internal = json.loads(internal_bytes.decode("utf-8"))
if (
    internal.get("experiment_id") != experiment_id
    or int(internal.get("member_count", -1)) != 46
    or int(internal.get("reserved_data_member_count", -1)) != 0
    or int(internal.get("resume_checkpoint_count", -1)) != 1
    or internal.get("member_sha256") != outer.get("member_sha256")
):
    raise SystemExit("reused A37 internal and outer manifests disagree")
PY

for path in "$RUN_BASE" "$SOURCE_DIRECTORY" "$RUN_DIRECTORY" "$A800_WRAPPER"; do
  [[ ! -e "$path" && ! -L "$path" ]] || {
    echo "new A37 A800 namespace already exists: $path" >&2
    exit 59
  }
done

mkdir "$RUN_BASE"
mkdir -p "$LOG_DIRECTORY" "$STATUS_DIRECTORY/locks" "$STATUS_DIRECTORY/tmp" "${RUN_BASE}/runs"
mkdir "$SOURCE_DIRECTORY"
{
  printf 'experiment_id=%s\n' "$EXPERIMENT_ID"
  printf 'execution_attempt_id=%s\n' "$EXECUTION_ATTEMPT_ID"
  printf 'reused_archive_sha256=%s\n' "$ARCHIVE_SHA256"
  printf 'a800_wrapper_sha256=%s\n' "$WRAPPER_SHA256"
  printf 'old_probe_job_id=%s\n' "$OLD_PROBE_JOB_ID"
  printf 'target_partition=hgpu8\n'
  printf 'excluded_node=ngu201\n'
} > "${STATUS_DIRECTORY}/seq49_submission_identity.txt"
tar -xzf "$ARCHIVE" -C "$SOURCE_DIRECTORY"

set +u
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH="${SOURCE_DIRECTORY}/src:${SOURCE_DIRECTORY}"
cd "$SOURCE_DIRECTORY"
python -u hpc/daily_camels_ukf_knet_parity/preflight.py \
  --bundle-root "$SOURCE_DIRECTORY" \
  --phase train \
  --offline-bundle-check \
  --report "${STATUS_DIRECTORY}/seq49_offline_reused_A37.json"

cp "$WRAPPER_SOURCE" "$A800_WRAPPER"
require_regular_identity "$A800_WRAPPER" "$WRAPPER_SHA256" "$WRAPPER_SIZE" "materialized A37 A800 wrapper"

for path in "$RUN_DIRECTORY" \
  "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.probe.lock" \
  "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.train.lock"; do
  [[ ! -e "$path" && ! -L "$path" ]] || {
    echo "A37 A800 output or owner lock appeared before cancellation: $path" >&2
    exit 60
  }
done

sinfo -N -n ngu202,ngu203 -p hgpu8 -o '%N|%P|%t|%G|%C|%m|%e' > "${STATUS_DIRECTORY}/seq49_pre_cancel_hgpu8_candidate_nodes.txt"
if ! grep -Eq '^ngu20[23]\|hgpu8\|(idle|mix|mix\$)\|' "${STATUS_DIRECTORY}/seq49_pre_cancel_hgpu8_candidate_nodes.txt"; then
  echo "no non-drained hgpu8 candidate node is visible before cancellation" >&2
  exit 68
fi

SQUEUE_BEFORE="${STATUS_DIRECTORY}/seq49_pre_cancel_squeue.txt"
squeue -h -u "$EXPECTED_USER" -o '%A|%j|%P|%T|%u|%Z|%o' > "$SQUEUE_BEFORE"
OLD_LINE="$(awk -F'|' -v id="$OLD_PROBE_JOB_ID" '$1 == id {print; count++} END {if (count != 1) exit 1}' "$SQUEUE_BEFORE")" || {
  echo "old A37 probe is absent or duplicated before cancellation" >&2
  exit 61
}
IFS='|' read -r old_id old_name old_partition old_state old_user _rest <<< "$OLD_LINE"
if [[ "$old_id" != "$OLD_PROBE_JOB_ID" || "$old_name" != "$OLD_PROBE_JOB_NAME" || "$old_partition" != "hgpu2p" || "$old_state" != "PENDING" || "$old_user" != "$EXPECTED_USER" ]]; then
  echo "old A37 probe identity changed before cancellation: $OLD_LINE" >&2
  exit 62
fi
if awk -F'|' -v old="$OLD_PROBE_JOB_ID" -v experiment="$EXPERIMENT_ID" -v new_root="$RUN_BASE" '
    $1 != old && ($2 == "daily-knet-a37-probe" || $2 == "daily-knet-a37" ||
      $2 == "daily-knet-a37-a800-probe" || $2 == "daily-knet-a37-a800" ||
      index($0, experiment) || index($0, new_root)) {found=1}
    END {exit(found ? 0 : 1)}
' "$SQUEUE_BEFORE"; then
  echo "another A37 job exists before cancellation; refusing migration" >&2
  exit 63
fi

OLD_ACCOUNTING_STATE="$(sacct -n -X -j "$OLD_PROBE_JOB_ID" --format=State -P | awk -F'|' 'NF {print $1; exit}' | sed 's/[+ ].*$//')"
[[ "$OLD_ACCOUNTING_STATE" = "PENDING" ]] || {
  echo "old A37 probe accounting state changed before cancellation: ${OLD_ACCOUNTING_STATE:-UNKNOWN}" >&2
  exit 64
}

scancel "$OLD_PROBE_JOB_ID"
OLD_TERMINAL_STATE=""
for _attempt in $(seq 1 30); do
  OLD_TERMINAL_STATE="$(sacct -n -X -j "$OLD_PROBE_JOB_ID" --format=State -P 2>/dev/null | awk -F'|' 'NF {print $1; exit}' | sed 's/[+ ].*$//')"
  if [[ "$OLD_TERMINAL_STATE" = "CANCELLED" ]]; then
    break
  fi
  sleep 2
done
[[ "$OLD_TERMINAL_STATE" = "CANCELLED" ]] || {
  echo "old A37 probe did not reach CANCELLED after scancel: ${OLD_TERMINAL_STATE:-UNKNOWN}" >&2
  exit 65
}
if [[ -n "$(squeue -h -j "$OLD_PROBE_JOB_ID" -o '%A')" ]]; then
  echo "old A37 probe remains in squeue after terminal cancellation" >&2
  exit 66
fi
sacct -j "$OLD_PROBE_JOB_ID" --parsable2 --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,AllocTRES > "${STATUS_DIRECTORY}/seq49_old_probe_terminal_sacct.txt"

SQUEUE_AFTER="${STATUS_DIRECTORY}/seq49_post_cancel_squeue.txt"
squeue -h -u "$EXPECTED_USER" -o '%A|%j|%P|%T|%u|%Z|%o' > "$SQUEUE_AFTER"
if awk -F'|' -v experiment="$EXPERIMENT_ID" -v new_root="$RUN_BASE" '
    $2 == "daily-knet-a37-probe" || $2 == "daily-knet-a37" ||
    $2 == "daily-knet-a37-a800-probe" || $2 == "daily-knet-a37-a800" ||
    index($0, experiment) || index($0, new_root) {found=1}
    END {exit(found ? 0 : 1)}
' "$SQUEUE_AFTER"; then
  echo "an A37 job exists after old-probe cancellation; refusing duplicate submission" >&2
  exit 67
fi

SUBMISSION_RAW="$(sbatch --parsable --mem=0 "$A800_WRAPPER")"
NEW_PROBE_JOB_ID="${SUBMISSION_RAW%%;*}"
case "$NEW_PROBE_JOB_ID" in
  ''|*[!0-9]*)
    echo "invalid A37 A800 probe Slurm job identifier: ${SUBMISSION_RAW}" >&2
    exit 69
    ;;
esac
printf '%s\n' "$NEW_PROBE_JOB_ID" > "${STATUS_DIRECTORY}/seq49_a800_probe_job_id.txt"
date -u +%Y-%m-%dT%H:%M:%SZ > "${STATUS_DIRECTORY}/seq49_a800_probe_submitted_time_utc.txt"
squeue -h -j "$NEW_PROBE_JOB_ID" -o '%A|%j|%P|%T|%R|%b|%Z|%o' > "${STATUS_DIRECTORY}/seq49_post_submission_squeue.txt" 2>&1 || true
sacct -j "$NEW_PROBE_JOB_ID" --parsable2 --format=JobIDRaw,JobName,Partition,State,ExitCode,Elapsed,AllocTRES > "${STATUS_DIRECTORY}/seq49_post_submission_sacct.txt" 2>&1 || true

printf 'SEQ49_A37_A800_PROBE_SUBMITTED experiment_id=%s execution_attempt_id=%s old_job_id=%s old_terminal_state=%s new_job_id=%s run_base=%s reused_archive_sha256=%s wrapper_sha256=%s excluded_node=ngu201\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$OLD_PROBE_JOB_ID" "$OLD_TERMINAL_STATE" "$NEW_PROBE_JOB_ID" "$RUN_BASE" "$ARCHIVE_SHA256" "$WRAPPER_SHA256"
