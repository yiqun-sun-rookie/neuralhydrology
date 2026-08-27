#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT53="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_53.txt"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH10_TO40_RESUME_V1_20260826_A37"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_A800_DIAG1_SEQ54"
OLD_JOB_ID="215207"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a37_a800_diag1_20260827"
SOURCE_DIRECTORY="${RUN_BASE}/source_A37_a800_diag1_seq54"
RUN_DIRECTORY="${RUN_BASE}/runs/${EXPERIMENT_ID}"
STATUS_DIRECTORY="${RUN_BASE}/status"
LOG_DIRECTORY="${RUN_BASE}/logs"
PAYLOAD_DIRECTORY="${MAILBOX_ROOT}/payload/kalmannet-daily-camels/parity-a37-a800-portability-diagnostic-v54"
ARCHIVE="${PAYLOAD_DIRECTORY}/${EXPERIMENT_ID}.tar.gz"
OUTER_MANIFEST="${PAYLOAD_DIRECTORY}/A37_bundle_manifest.sha256.json"
ARCHIVE_SHA256="1d2a5c9b6f26b8e35d8f3a73ecfc71d935930ab72f40dd7ced314e8a15adcc0f"
ARCHIVE_SIZE="1815692"
OUTER_MANIFEST_SHA256="756ddda3ba8724bedbedb5ae6ca944f883ba93a4c6e38786797d27b2751de439"
OUTER_MANIFEST_SIZE="11419"
INTERNAL_MANIFEST_SHA256="5bceec596643a9c384e08f473ad7fbd860d7aaabc054b46b8478d777eb371996"
ACTIVE_CONFIG_SHA256="70a522e9306c80d6c3010a3fbcf7fda3b4f53d850498698e1ef15f1028441984"
ENTRY_SHA256="99c9fd92603014d6fc05a0618704918243411a62f2ef88d0c18578256a288cc6"
TRAIN_ENTRY_SHA256="c502c2c35ec8091c728978ce5ab2b7631271ac9fc83bec413f908c0d64e66a82"
CHECKPOINT_SHA256="b2b93f531c7ad4922e14d5479564e82e5a6dca553835bbc8cc8af61db4a8d81e"
WRAPPER_SOURCE="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels/seq54_a37_a800_diag_wrapper.slurm"
WRAPPER="${RUN_BASE}/seq54_a37_a800_diag_wrapper.slurm"
WRAPPER_SHA256="db1942427e54d5470b986eaa793a76e52d7a5c6827b8d68c25282bed082ecf5b"
WRAPPER_SIZE="2340"
SUBMISSION_LOCK="${STATUS_DIRECTORY}/locks/${EXECUTION_ATTEMPT_ID}.submission.lock"
OFFLINE_REPORT="${STATUS_DIRECTORY}/seq54_offline_bundle_verification.json"

sha256_file() { sha256sum "$1" | awk '{print $1}'; }
require_regular_identity() {
  local path="$1" expected_sha256="$2" expected_size="$3" label="$4"
  [[ -f "$path" && ! -L "$path" ]] || { echo "$label absent or non-regular" >&2; return 50; }
  [[ "$(stat -c '%s' "$path")" = "$expected_size" ]] || { echo "$label size differs" >&2; return 51; }
  [[ "$(sha256_file "$path")" = "$expected_sha256" ]] || { echo "$label SHA-256 differs" >&2; return 52; }
}

ACTUAL_USER="$(id -un)"
[[ "${USER-}" = "$EXPECTED_USER" && "$ACTUAL_USER" = "$EXPECTED_USER" ]] || {
  echo "fixed-user check failed" >&2
  exit 53
}
[[ -f "$RESULT53" && ! -L "$RESULT53" ]] || { echo "terminal evidence result 53 absent" >&2; exit 54; }
grep -Fq "${OLD_JOB_ID}|daily-knet-a37-a800|sunyiq|hgpu8|FAILED|1:0" "$RESULT53" || {
  echo "result 53 does not prove old training terminal failure" >&2
  exit 55
}
grep -Fq "epoch-zero checkpoint objective differs from its anchor" "$RESULT53" || {
  echo "result 53 failure identity differs" >&2
  exit 56
}

OLD_STATE="$(sacct -n -X -j "$OLD_JOB_ID" --format=State -P | awk -F'|' 'NF {print $1; exit}' | sed 's/[+ ].*$//')"
OLD_EXIT="$(sacct -n -X -j "$OLD_JOB_ID" --format=ExitCode -P | awk -F'|' 'NF {print $1; exit}')"
[[ "$OLD_STATE" = "FAILED" && "$OLD_EXIT" = "1:0" ]] || {
  echo "old training terminal state changed: ${OLD_STATE:-UNKNOWN}/${OLD_EXIT:-UNKNOWN}" >&2
  exit 57
}

require_regular_identity "$ARCHIVE" "$ARCHIVE_SHA256" "$ARCHIVE_SIZE" "diagnostic archive"
require_regular_identity "$OUTER_MANIFEST" "$OUTER_MANIFEST_SHA256" "$OUTER_MANIFEST_SIZE" "diagnostic outer manifest"
require_regular_identity "$WRAPPER_SOURCE" "$WRAPPER_SHA256" "$WRAPPER_SIZE" "diagnostic wrapper"

python - "$OUTER_MANIFEST" "$EXPERIMENT_ID" "$ARCHIVE_SHA256" "$ARCHIVE_SIZE" "$INTERNAL_MANIFEST_SHA256" "$ACTIVE_CONFIG_SHA256" "$ENTRY_SHA256" "$TRAIN_ENTRY_SHA256" "$CHECKPOINT_SHA256" <<'PY'
import json
from pathlib import Path
import sys

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
experiment_id, archive_sha, archive_size = sys.argv[2], sys.argv[3], int(sys.argv[4])
internal_sha, config_sha, entry_sha, train_sha, checkpoint_sha = sys.argv[5:10]
members = manifest.get("member_sha256", {})
if (
    manifest.get("experiment_id") != experiment_id
    or manifest.get("archive_sha256") != archive_sha
    or int(manifest.get("archive_size", -1)) != archive_size
    or int(manifest.get("member_count", -1)) != 46
    or int(manifest.get("reserved_data_member_count", -1)) != 0
    or int(manifest.get("resume_checkpoint_count", -1)) != 1
    or int(manifest.get("array_members_materialized_during_build", -1)) != 0
    or manifest.get("internal_manifest_sha256") != internal_sha
    or members.get("configs/daily_camels_knet_fixed_full_training_coverage_epoch10_to40_resume_a37.json") != config_sha
    or members.get("scripts/run_daily_camels_ukf_knet_parity.py") != entry_sha
    or members.get("hpc/daily_camels_ukf_knet_parity/submit_train_gpu.slurm") != train_sha
    or manifest.get("continuation", {}).get("checkpoint_sha256") != checkpoint_sha
    or int(manifest.get("continuation", {}).get("completed_epoch", -1)) != 10
):
    raise SystemExit("diagnostic bundle identity differs")
PY

for path in "$RUN_BASE" "$SOURCE_DIRECTORY" "$RUN_DIRECTORY" "$WRAPPER"; do
  [[ ! -e "$path" && ! -L "$path" ]] || { echo "diagnostic namespace already exists: $path" >&2; exit 58; }
done

SQUEUE_BEFORE="$(squeue -h -u "$EXPECTED_USER" -o '%A|%j|%P|%T|%u|%Z|%o')"
if awk -F'|' -v experiment="$EXPERIMENT_ID" -v root="$RUN_BASE" '
    $2 ~ /^daily-knet-a37/ || index($0, experiment) || index($0, root) {found=1}
    END {exit(found ? 0 : 1)}
' <<<"$SQUEUE_BEFORE"; then
  echo "an active A37 job exists; refusing duplicate diagnostic" >&2
  exit 59
fi

mkdir "$RUN_BASE"
mkdir -p "$SOURCE_DIRECTORY" "$STATUS_DIRECTORY/locks" "$LOG_DIRECTORY" "${RUN_BASE}/runs"
tar -xzf "$ARCHIVE" -C "$SOURCE_DIRECTORY"

set +u
source "/data1/home/${USER}/miniconda3/etc/profile.d/conda.sh"
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export PYTHONPATH="${SOURCE_DIRECTORY}/src:${SOURCE_DIRECTORY}"
cd "$SOURCE_DIRECTORY"
python -u hpc/daily_camels_ukf_knet_parity/preflight.py \
  --bundle-root "$SOURCE_DIRECTORY" --phase train --offline-bundle-check --report "$OFFLINE_REPORT"
python - "$OFFLINE_REPORT" "$EXPERIMENT_ID" "$CHECKPOINT_SHA256" <<'PY'
import json
from pathlib import Path
import sys
report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
if (
    report.get("status") != "BUNDLE_VERIFIED"
    or report.get("experiment_id") != sys.argv[2]
    or report.get("numpy_imported") is not False
    or report.get("torch_imported") is not False
    or int(report.get("array_members_materialized", -1)) != 0
    or report.get("continuation", {}).get("checkpoint_sha256") != sys.argv[3]
):
    raise SystemExit("diagnostic offline preflight differs")
PY

for path in "$RUN_DIRECTORY" "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.train.lock" "$SUBMISSION_LOCK"; do
  [[ ! -e "$path" && ! -L "$path" ]] || { echo "diagnostic output or lock appeared: $path" >&2; exit 60; }
done
mkdir "$SUBMISSION_LOCK"
{
  printf 'experiment_id=%s\n' "$EXPERIMENT_ID"
  printf 'execution_attempt_id=%s\n' "$EXECUTION_ATTEMPT_ID"
  printf 'owner_user=%s\n' "$ACTUAL_USER"
  printf 'acquired_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${SUBMISSION_LOCK}/owner.txt"
cp "$WRAPPER_SOURCE" "$WRAPPER"
require_regular_identity "$WRAPPER" "$WRAPPER_SHA256" "$WRAPPER_SIZE" "materialized diagnostic wrapper"

SQUEUE_FINAL="$(squeue -h -u "$EXPECTED_USER" -o '%A|%j|%P|%T|%u|%Z|%o')"
if awk -F'|' -v experiment="$EXPERIMENT_ID" -v root="$RUN_BASE" '
    $2 ~ /^daily-knet-a37/ || index($0, experiment) || index($0, root) {found=1}
    END {exit(found ? 0 : 1)}
' <<<"$SQUEUE_FINAL"; then
  echo "an A37 job appeared during diagnostic preflight" >&2
  exit 61
fi

SUBMISSION_RAW="$(sbatch --parsable --mem=0 "$WRAPPER")"
JOB_ID="${SUBMISSION_RAW%%;*}"
case "$JOB_ID" in ''|*[!0-9]*) echo "invalid diagnostic job id: $SUBMISSION_RAW" >&2; exit 62;; esac
printf '%s\n' "$JOB_ID" > "${STATUS_DIRECTORY}/seq54_diagnostic_job_id.txt"
date -u +%Y-%m-%dT%H:%M:%SZ > "${STATUS_DIRECTORY}/seq54_diagnostic_submitted_time_utc.txt"
squeue -h -j "$JOB_ID" -o '%A|%j|%P|%T|%R|%b|%Z|%o' > "${STATUS_DIRECTORY}/seq54_post_submission_squeue.txt" 2>&1 || true
sacct -j "$JOB_ID" --parsable2 --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,NodeList,AllocTRES > "${STATUS_DIRECTORY}/seq54_post_submission_sacct.txt" 2>&1 || true

printf 'SEQ54_A37_A800_DIAGNOSTIC_SUBMITTED experiment_id=%s execution_attempt_id=%s diagnostic_job_id=%s run_base=%s archive_sha256=%s wrapper_sha256=%s source_checkpoint_sha256=%s\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$JOB_ID" "$RUN_BASE" "$ARCHIVE_SHA256" "$WRAPPER_SHA256" "$CHECKPOINT_SHA256"
