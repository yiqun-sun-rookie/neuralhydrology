#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT49="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_49.txt"
RESULT50="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_50.txt"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH10_TO40_RESUME_V1_20260826_A37"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_A800_TRAIN1_SEQ51"
PROBE_EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_A800_PROBE1_SEQ49"
PROBE_JOB_ID="215199"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a37_a800_probe1_20260827"
SOURCE_DIRECTORY="${RUN_BASE}/source_A37_a800_probe1_seq49"
RUN_DIRECTORY="${RUN_BASE}/runs/${EXPERIMENT_ID}"
STATUS_DIRECTORY="${RUN_BASE}/status"
LOG_DIRECTORY="${RUN_BASE}/logs"
WRAPPER_SOURCE="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels/seq51_a37_a800_train_wrapper.slurm"
TRAIN_WRAPPER="${RUN_BASE}/seq51_a37_a800_train_wrapper.slurm"
WRAPPER_SHA256="7506bb514f3cfbb8328c2d1f58d4c52f7bdb04012e2592be6ffa0f714b8b8b0f"
WRAPPER_SIZE="2868"
BUNDLE_MANIFEST="${SOURCE_DIRECTORY}/bundle_manifest.json"
BUNDLE_MANIFEST_SHA256="b0d374d72d5105735c9455271ec0f778831fa7ad2ec64c7ef4841299651cb13e"
ACTIVE_CONFIG="${SOURCE_DIRECTORY}/configs/daily_camels_knet_fixed_full_training_coverage_epoch10_to40_resume_a37.json"
ACTIVE_CONFIG_SHA256="70a522e9306c80d6c3010a3fbcf7fda3b4f53d850498698e1ef15f1028441984"
ACTIVE_CONFIG_SIZE="9704"
TRAIN_SCRIPT="${SOURCE_DIRECTORY}/hpc/daily_camels_ukf_knet_parity/submit_train_gpu.slurm"
TRAIN_SCRIPT_SHA256="c502c2c35ec8091c728978ce5ab2b7631271ac9fc83bec413f908c0d64e66a82"
TRAIN_SCRIPT_SIZE="8909"
CHECKPOINT_RELATIVE="artifacts/daily_camels_ukf_knet_parity_seq15_failure_evidence/ff2084c4/seq15_snapshot_2831/run/checkpoints/epoch_010.pt"
CHECKPOINT="${SOURCE_DIRECTORY}/${CHECKPOINT_RELATIVE}"
CHECKPOINT_SHA256="b2b93f531c7ad4922e14d5479564e82e5a6dca553835bbc8cc8af61db4a8d81e"
CHECKPOINT_SIZE="2244424"
EXACT_GATE="/data1/home/sunyiq/kalmannet_daily_camels_parity_20260824/status/replay_gate_DAILY_CAMELS_UKF_PARITY_KNET_FULL_STATE_EXACT_REPLAY_DTYPE_REPAIR_V3_20260825_A05.json"
EXACT_GATE_SHA256="70e73c9f014dc4a4d615e07087fb99a994ba30b8c867eb5ef49141a59a39b687"
EXACT_GATE_SIZE="2816"
CAUSAL_GATE="/data1/home/sunyiq/kalmannet_daily_camels_parity_20260824/status/replay_gate_DAILY_CAMELS_UKF_PARITY_KNET_FULL_STATE_CAUSAL_REPLAY_DTYPE_REPAIR_V3_20260825_A06.json"
CAUSAL_GATE_SHA256="0f6080a05a27244eca59c58043f265718102a4c2985684fb674781c8157d6c66"
CAUSAL_GATE_SIZE="2807"
OFFLINE_REPORT="${STATUS_DIRECTORY}/seq51_offline_train_bundle_verification.json"
IDENTITY_FILE="${STATUS_DIRECTORY}/seq51_a800_train_submission_identity.txt"
JOB_ID_FILE="${STATUS_DIRECTORY}/seq51_a800_training_job_id.txt"
SUBMITTED_TIME_FILE="${STATUS_DIRECTORY}/seq51_a800_training_submitted_time_utc.txt"
SQUEUE_BEFORE="${STATUS_DIRECTORY}/seq51_pre_submission_squeue.txt"
SQUEUE_AFTER="${STATUS_DIRECTORY}/seq51_post_submission_squeue.txt"
SACCT_AFTER="${STATUS_DIRECTORY}/seq51_post_submission_sacct.txt"
NODE_REPORT="${STATUS_DIRECTORY}/seq51_pre_submission_hgpu8_candidate_nodes.txt"
SUBMISSION_LOCK="${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.submission.lock"
SUBMISSION_LOCK_OWNER="${SUBMISSION_LOCK}/owner.txt"

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

for receipt in "$RESULT49" "$RESULT50"; do
  [[ -f "$receipt" && ! -L "$receipt" ]] || {
    echo "required prior receipt is absent or symbolic: $receipt" >&2
    exit 54
  }
done
grep -Fq "SEQ49_A37_A800_PROBE_SUBMITTED experiment_id=${EXPERIMENT_ID} execution_attempt_id=${PROBE_EXECUTION_ATTEMPT_ID}" "$RESULT49" || {
  echo "sequence 49 does not bind the completed A800 probe identity" >&2
  exit 55
}
grep -Fq "new_job_id=${PROBE_JOB_ID}" "$RESULT49" || {
  echo "sequence 49 A800 probe job identifier differs" >&2
  exit 56
}
grep -Fq "${PROBE_JOB_ID}|daily-knet-a37-a800-probe|sunyiq|hgpu8|COMPLETED|0:0" "$RESULT50" || {
  echo "sequence 50 does not prove a successful terminal A800 probe" >&2
  exit 57
}
grep -Fq "hostname=ngu202 partition=hgpu8" "$RESULT50" || {
  echo "sequence 50 does not prove an approved A800 host" >&2
  exit 58
}
grep -Fq "gpu_name= NVIDIA A800-SXM4-80GB" "$RESULT50" || {
  echo "sequence 50 does not prove the actual A800 device model" >&2
  exit 59
}
grep -Fq '"run_directory_absent": true' "$RESULT50" || {
  echo "sequence 50 does not prove the A37 run directory was absent" >&2
  exit 60
}

[[ -d "$SOURCE_DIRECTORY" && ! -L "$SOURCE_DIRECTORY" ]] || {
  echo "fixed A37 source directory is absent or symbolic" >&2
  exit 61
}
[[ -d "$STATUS_DIRECTORY" && ! -L "$STATUS_DIRECTORY" ]] || {
  echo "fixed A37 status directory is absent or symbolic" >&2
  exit 62
}
[[ -d "$LOG_DIRECTORY" && ! -L "$LOG_DIRECTORY" ]] || {
  echo "fixed A37 log directory is absent or symbolic" >&2
  exit 63
}

require_regular_identity "$BUNDLE_MANIFEST" "$BUNDLE_MANIFEST_SHA256" "14669" "A37 internal bundle manifest"
require_regular_identity "$ACTIVE_CONFIG" "$ACTIVE_CONFIG_SHA256" "$ACTIVE_CONFIG_SIZE" "A37 active configuration"
require_regular_identity "$TRAIN_SCRIPT" "$TRAIN_SCRIPT_SHA256" "$TRAIN_SCRIPT_SIZE" "A37 frozen training entry"
require_regular_identity "$CHECKPOINT" "$CHECKPOINT_SHA256" "$CHECKPOINT_SIZE" "A16 epoch-10 continuation checkpoint"
require_regular_identity "$EXACT_GATE" "$EXACT_GATE_SHA256" "$EXACT_GATE_SIZE" "exact replay receipt"
require_regular_identity "$CAUSAL_GATE" "$CAUSAL_GATE_SHA256" "$CAUSAL_GATE_SIZE" "causal replay receipt"
require_regular_identity "$WRAPPER_SOURCE" "$WRAPPER_SHA256" "$WRAPPER_SIZE" "A37 A800 training wrapper"

python - "$BUNDLE_MANIFEST" "$ACTIVE_CONFIG" "$EXPERIMENT_ID" "$CHECKPOINT_RELATIVE" "$CHECKPOINT_SHA256" "$TRAIN_SCRIPT_SHA256" "$EXACT_GATE_SHA256" "$CAUSAL_GATE_SHA256" <<'PY'
import json
from pathlib import Path
import sys

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
configuration = json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))
experiment_id = sys.argv[3]
checkpoint_relative = sys.argv[4]
checkpoint_sha256 = sys.argv[5]
train_script_sha256 = sys.argv[6]
exact_gate_sha256 = sys.argv[7]
causal_gate_sha256 = sys.argv[8]
continuation = configuration.get("continuation", {})
optimization = configuration.get("optimization", {})
requirements = configuration.get("replay_gate_requirements", {})
if (
    manifest.get("experiment_id") != experiment_id
    or int(manifest.get("member_count", -1)) != 46
    or int(manifest.get("reserved_data_member_count", -1)) != 0
    or int(manifest.get("resume_checkpoint_count", -1)) != 1
    or manifest.get("member_sha256", {}).get(
        "hpc/daily_camels_ukf_knet_parity/submit_train_gpu.slurm"
    ) != train_script_sha256
    or configuration.get("experiment_id") != experiment_id
    or continuation.get("checkpoint_path") != checkpoint_relative
    or continuation.get("checkpoint_sha256") != checkpoint_sha256
    or int(continuation.get("completed_epoch", -1)) != 10
    or int(continuation.get("optimizer_steps", -1)) != 10
    or int(continuation.get("sampled_forecast_events", -1)) != 76500
    or int(optimization.get("training_epochs", -1)) != 40
    or requirements.get("exact", {}).get("receipt_sha256") != exact_gate_sha256
    or requirements.get("causal", {}).get("receipt_sha256") != causal_gate_sha256
    or configuration.get("execution_policy", {}).get("allow_training") is not True
):
    raise SystemExit("A37 frozen continuation contract differs")
PY

if [[ -e "$RUN_DIRECTORY" || -L "$RUN_DIRECTORY" ]]; then
  echo "A37 run directory already exists; refusing a duplicate or overwrite" >&2
  exit 64
fi
for path in \
  "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.probe.lock" \
  "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.train.lock" \
  "$SUBMISSION_LOCK" \
  "$TRAIN_WRAPPER" "$OFFLINE_REPORT" "$IDENTITY_FILE" "$JOB_ID_FILE" "$SUBMITTED_TIME_FILE" \
  "$SQUEUE_BEFORE" "$SQUEUE_AFTER" "$SACCT_AFTER" "$NODE_REPORT"; do
  [[ ! -e "$path" && ! -L "$path" ]] || {
    echo "A37 training evidence path or lock already exists: $path" >&2
    exit 65
  }
done

PROBE_TERMINAL_STATE="$(sacct -n -X -j "$PROBE_JOB_ID" --format=State -P | awk -F'|' 'NF {print $1; exit}' | sed 's/[+ ].*$//')"
PROBE_EXIT_CODE="$(sacct -n -X -j "$PROBE_JOB_ID" --format=ExitCode -P | awk -F'|' 'NF {print $1; exit}')"
if [[ "$PROBE_TERMINAL_STATE" != "COMPLETED" || "$PROBE_EXIT_CODE" != "0:0" ]]; then
  echo "A800 probe terminal identity changed: state=${PROBE_TERMINAL_STATE:-UNKNOWN} exit=${PROBE_EXIT_CODE:-UNKNOWN}" >&2
  exit 66
fi

sinfo -h -N -n ngu202,ngu203 -p hgpu8 -o '%N|%P|%t|%G|%C|%m|%e' > "$NODE_REPORT"
if ! awk -F'|' '$1 ~ /^ngu20[23]$/ && $2 ~ /^hgpu8/ && $3 !~ /(down|drain|fail|maint|unk)/ {healthy=1} END {exit(healthy ? 0 : 1)}' "$NODE_REPORT"; then
  echo "no non-drained approved hgpu8 A800 candidate is visible" >&2
  exit 67
fi

squeue -h -u "$EXPECTED_USER" -o '%A|%j|%P|%T|%u|%Z|%o' > "$SQUEUE_BEFORE"
if awk -F'|' -v experiment="$EXPERIMENT_ID" -v root="$RUN_BASE" '
    $2 == "daily-knet-a37" || $2 == "daily-knet-a37-a800" ||
    $2 == "daily-knet-a37-probe" || $2 == "daily-knet-a37-a800-probe" ||
    index($0, experiment) || index($0, root) {found=1}
    END {exit(found ? 0 : 1)}
' "$SQUEUE_BEFORE"; then
  echo "an active A37 probe or training job already exists; refusing duplicate submission" >&2
  exit 68
fi

if ! mkdir "$SUBMISSION_LOCK"; then
  echo "A37 submission owner lock already exists; refusing duplicate submission" >&2
  exit 76
fi
{
  printf 'experiment_id=%s\n' "$EXPERIMENT_ID"
  printf 'execution_attempt_id=%s\n' "$EXECUTION_ATTEMPT_ID"
  printf 'owner_user=%s\n' "$ACTUAL_USER"
  printf 'owner_host=%s\n' "$(hostname)"
  printf 'owner_pid=%s\n' "$$"
  printf 'acquired_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$SUBMISSION_LOCK_OWNER"

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
  --report "$OFFLINE_REPORT"

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
    or int(report.get("member_count", -1)) != 46
    or report.get("continuation", {}).get("checkpoint_sha256") != sys.argv[3]
    or int(report.get("continuation", {}).get("completed_epoch", -1)) != 10
):
    raise SystemExit("A37 offline training bundle verification differs")
PY

for path in "$RUN_DIRECTORY" \
  "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.probe.lock" \
  "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.train.lock"; do
  [[ ! -e "$path" && ! -L "$path" ]] || {
    echo "A37 output or lock appeared after offline verification: $path" >&2
    exit 69
  }
done
[[ -d "$SUBMISSION_LOCK" && ! -L "$SUBMISSION_LOCK" && -f "$SUBMISSION_LOCK_OWNER" && ! -L "$SUBMISSION_LOCK_OWNER" ]] || {
  echo "A37 submission owner lock changed before submission" >&2
  exit 75
}
grep -Fxq "experiment_id=${EXPERIMENT_ID}" "$SUBMISSION_LOCK_OWNER" || {
  echo "A37 submission lock experiment identity differs" >&2
  exit 74
}
grep -Fxq "execution_attempt_id=${EXECUTION_ATTEMPT_ID}" "$SUBMISSION_LOCK_OWNER" || {
  echo "A37 submission lock execution identity differs" >&2
  exit 73
}
squeue -h -u "$EXPECTED_USER" -o '%A|%j|%P|%T|%u|%Z|%o' > "${SQUEUE_BEFORE}.final"
if awk -F'|' -v experiment="$EXPERIMENT_ID" -v root="$RUN_BASE" '
    $2 == "daily-knet-a37" || $2 == "daily-knet-a37-a800" ||
    $2 == "daily-knet-a37-probe" || $2 == "daily-knet-a37-a800-probe" ||
    index($0, experiment) || index($0, root) {found=1}
    END {exit(found ? 0 : 1)}
' "${SQUEUE_BEFORE}.final"; then
  echo "an A37 job appeared during preflight; refusing duplicate submission" >&2
  exit 77
fi
mv "${SQUEUE_BEFORE}.final" "$SQUEUE_BEFORE"

cp "$WRAPPER_SOURCE" "$TRAIN_WRAPPER"
require_regular_identity "$TRAIN_WRAPPER" "$WRAPPER_SHA256" "$WRAPPER_SIZE" "materialized A37 A800 training wrapper"

IDENTITY_TEMP="$(mktemp "${STATUS_DIRECTORY}/seq51_identity.XXXXXX")"
{
  printf 'experiment_id=%s\n' "$EXPERIMENT_ID"
  printf 'execution_attempt_id=%s\n' "$EXECUTION_ATTEMPT_ID"
  printf 'source_checkpoint_sha256=%s\n' "$CHECKPOINT_SHA256"
  printf 'source_completed_epoch=10\n'
  printf 'target_total_epochs=40\n'
  printf 'source_optimizer_steps=10\n'
  printf 'target_total_optimizer_steps=40\n'
  printf 'source_sampled_forecast_events=76500\n'
  printf 'target_total_sampled_forecast_events=306000\n'
  printf 'run_base=%s\n' "$RUN_BASE"
  printf 'source_directory=%s\n' "$SOURCE_DIRECTORY"
  printf 'target_partition=hgpu8\n'
  printf 'approved_nodes=ngu202,ngu203\n'
  printf 'excluded_node=ngu201\n'
  printf 'wrapper_sha256=%s\n' "$WRAPPER_SHA256"
  printf 'control_script_sha256=%s\n' "$(sha256_file "${BASH_SOURCE[0]}")"
  printf 'control_script_size_bytes=%s\n' "$(stat -c '%s' "${BASH_SOURCE[0]}")"
  printf 'host_admission_min_bytes=2800353280\n'
  printf 'gpu_admission_min_free_mib=822\n'
} > "$IDENTITY_TEMP"
ln -- "$IDENTITY_TEMP" "$IDENTITY_FILE"
rm -- "$IDENTITY_TEMP"

SUBMISSION_RAW="$(sbatch --parsable --mem=0 "$TRAIN_WRAPPER")"
TRAINING_JOB_ID="${SUBMISSION_RAW%%;*}"
case "$TRAINING_JOB_ID" in
  ''|*[!0-9]*)
    echo "invalid A37 A800 training Slurm job identifier: ${SUBMISSION_RAW}" >&2
    exit 78
    ;;
esac

JOB_ID_TEMP="$(mktemp "${STATUS_DIRECTORY}/seq51_job_id.XXXXXX")"
printf '%s\n' "$TRAINING_JOB_ID" > "$JOB_ID_TEMP"
ln -- "$JOB_ID_TEMP" "$JOB_ID_FILE"
rm -- "$JOB_ID_TEMP"
TIME_TEMP="$(mktemp "${STATUS_DIRECTORY}/seq51_time.XXXXXX")"
date -u +%Y-%m-%dT%H:%M:%SZ > "$TIME_TEMP"
ln -- "$TIME_TEMP" "$SUBMITTED_TIME_FILE"
rm -- "$TIME_TEMP"

for _attempt in $(seq 1 10); do
  squeue -h -u "$EXPECTED_USER" -o '%A|%j|%P|%T|%u|%Z|%o' > "$SQUEUE_AFTER" 2>&1 || true
  sacct -j "$TRAINING_JOB_ID" --parsable2 --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,NodeList,AllocTRES,ReqTRES > "$SACCT_AFTER" 2>&1 || true
  if grep -Eq "^${TRAINING_JOB_ID}\|daily-knet-a37-a800\|hgpu8\|" "$SQUEUE_AFTER" || \
     grep -Eq "^${TRAINING_JOB_ID}\|daily-knet-a37-a800\|${EXPECTED_USER}\|hgpu8\|" "$SACCT_AFTER"; then
    break
  fi
  sleep 1
done

if ! grep -Eq "^${TRAINING_JOB_ID}\|daily-knet-a37-a800\|hgpu8\|" "$SQUEUE_AFTER" && \
   ! grep -Eq "^${TRAINING_JOB_ID}\|daily-knet-a37-a800\|${EXPECTED_USER}\|hgpu8\|" "$SACCT_AFTER"; then
  echo "submitted A37 A800 training job cannot yet be bound to hgpu8 accounting" >&2
  exit 79
fi
if awk -F'|' -v expected="$TRAINING_JOB_ID" '
    ($2 == "daily-knet-a37" || $2 == "daily-knet-a37-a800" ||
     $2 == "daily-knet-a37-probe" || $2 == "daily-knet-a37-a800-probe") && $1 != expected {found=1}
    END {exit(found ? 0 : 1)}
' "$SQUEUE_AFTER"; then
  echo "another active A37 job appeared after submission" >&2
  exit 80
fi

printf 'SEQ51_A37_A800_TRAIN_SUBMITTED experiment_id=%s execution_attempt_id=%s training_job_id=%s run_base=%s source_checkpoint_sha256=%s wrapper_sha256=%s target_partition=hgpu8 excluded_node=ngu201\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$TRAINING_JOB_ID" "$RUN_BASE" "$CHECKPOINT_SHA256" "$WRAPPER_SHA256"
