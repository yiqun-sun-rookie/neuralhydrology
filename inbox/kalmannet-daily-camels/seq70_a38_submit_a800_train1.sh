#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT69="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_69.txt"
RESULT69_SHA256="017e99754d12badebb0b9ddf4b1b7566c86645e6c0ee306d0409affe41287f85"
RESULT69_SIZE="6611093"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH40_TO80_RESUME_STEP_MONOTONICITY_DIAGNOSTIC_V1_20260828_A38"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A38_A800_TRAIN1_SEQ70"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a38_a800_train1_20260828"
SOURCE_DIRECTORY="${RUN_BASE}/source_A38_a800_train1_seq70"
RUN_DIRECTORY="${RUN_BASE}/runs/${EXPERIMENT_ID}"
STATUS_DIRECTORY="${RUN_BASE}/status"
LOG_DIRECTORY="${RUN_BASE}/logs"
PAYLOAD_DIRECTORY="${MAILBOX_ROOT}/payload/kalmannet-daily-camels/a38_a800_train1_seq70_20260828"
ARCHIVE="${PAYLOAD_DIRECTORY}/${EXPERIMENT_ID}.tar.gz"
OUTER_MANIFEST="${PAYLOAD_DIRECTORY}/bundle_manifest.sha256.json"
ARCHIVE_SHA256="753dbcb1238bdbe9b9b590408fad6ba0838764ba17ff9556c694f58512a7327e"
ARCHIVE_SIZE="3084193"
OUTER_MANIFEST_SHA256="b4f000430cbb7395150211742b60c70834f5fe186f126835ee9fa5dac9884adf"
OUTER_MANIFEST_SIZE="15927"
INTERNAL_MANIFEST_SHA256="71edb4381b81d426f2e2128bf5588a52e7c3ed0e2ba3687974e8f1de669789da"
ACTIVE_CONFIG_MEMBER="configs/daily_camels_knet_epoch40_to80_resume_a38.json"
ACTIVE_CONFIG_SHA256="05bace055154c9e88124f81434fc76a4e7a0e73d1ef4b8bf2635d7507b5d7d82"
RUNNER_SHA256="412bbf69b0a5747f6fe81b7b6037757779a4fc658b20cb46ffe504c213616b59"
TRAIN_ENTRY_SHA256="58aae6396d1cd60bddf90c0436854eecd804f798a23fe11ef2d0fee608bef490"
TRAIN_ENTRY_TEST_SHA256="a1879719df1f47d7c7ddc152176ea2bbe129d6303a7ca3cb9310e6d31f0e41f8"
PREFLIGHT_SHA256="dc6b6308d79cf6796afe35fd137ca3986d38553a9c4512c167b1830ed7bc69a9"
BUILDER_SHA256="f715faab4f2bfeeb353a657e1d699004aa816fd66637eb0c934a95352efe85a9"
CHECKPOINT_SHA256="43ed17aaacabdae7e88a80de8567ac3d29d88635d93f701016c757e7f3a407f5"
SOURCE_CONFIG_SHA256="29b4bdb604f2bfbba5c1ab78576a7a21811cd0fdd75060b2dc328ff608f06f2a"
SOURCE_HISTORY_SHA256="ec64cd575dc76312ef9beaafa22c19fd0d82dec552405ac9c04923aeae2af636"
SOURCE_RESULT_SHA256="e0393fde7084575f89f17e9f64945aafe064c72e3e60f36892376a8965cbb153"
SOURCE_IDENTITY_SHA256="6015e3473a478d96908ab9eda46e582244968480db592e056ebc51d3842c1e7a"
SOURCE_COMPLETION_SHA256="2b40523a6667ee8794d0c4e705d65711ea1b3d95311b0c3f870ca20d25263c76"
SOURCE_EVIDENCE_ARCHIVE_SHA256="ff788c72a9129cddd4e04a7e6c521864b8d02ff6687e8d8e7fb71655491b103b"
EXACT_GATE="/data1/home/sunyiq/kalmannet_daily_camels_parity_20260824/status/replay_gate_DAILY_CAMELS_UKF_PARITY_KNET_FULL_STATE_EXACT_REPLAY_DTYPE_REPAIR_V3_20260825_A05.json"
EXACT_GATE_SHA256="70e73c9f014dc4a4d615e07087fb99a994ba30b8c867eb5ef49141a59a39b687"
EXACT_GATE_SIZE="2816"
CAUSAL_GATE="/data1/home/sunyiq/kalmannet_daily_camels_parity_20260824/status/replay_gate_DAILY_CAMELS_UKF_PARITY_KNET_FULL_STATE_CAUSAL_REPLAY_DTYPE_REPAIR_V3_20260825_A06.json"
CAUSAL_GATE_SHA256="0f6080a05a27244eca59c58043f265718102a4c2985684fb674781c8157d6c66"
CAUSAL_GATE_SIZE="2807"
WRAPPER_SOURCE="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels/seq70_a38_a800_train1_wrapper.slurm"
WRAPPER="${RUN_BASE}/seq70_a38_a800_train1_wrapper.slurm"
WRAPPER_SHA256="34787a955d06bcde0ede6a4c7c556e50967ce5a34d0b8ba90a77d54a967df7a0"
WRAPPER_SIZE="2491"
OFFLINE_REPORT="${STATUS_DIRECTORY}/seq70_offline_train_bundle_verification.json"
IDENTITY_FILE="${STATUS_DIRECTORY}/seq70_a800_train_submission_identity.txt"
JOB_ID_FILE="${STATUS_DIRECTORY}/seq70_a800_training_job_id.txt"
SUBMITTED_TIME_FILE="${STATUS_DIRECTORY}/seq70_a800_training_submitted_time_utc.txt"
SQUEUE_BEFORE="${STATUS_DIRECTORY}/seq70_pre_submission_squeue.txt"
SQUEUE_AFTER="${STATUS_DIRECTORY}/seq70_post_submission_squeue.txt"
SACCT_BEFORE="${STATUS_DIRECTORY}/seq70_pre_submission_sacct.txt"
SACCT_AFTER="${STATUS_DIRECTORY}/seq70_post_submission_sacct.txt"
NODE_REPORT="${STATUS_DIRECTORY}/seq70_pre_submission_ngu202_hgpu8.txt"
SUBMISSION_LOCK="${STATUS_DIRECTORY}/locks/${EXECUTION_ATTEMPT_ID}.submission.lock"
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
  [[ "$(stat -c '%s' "$path")" == "$expected_size" ]] || {
    echo "${label} size differs" >&2
    return 51
  }
  [[ "$(sha256_file "$path")" == "$expected_sha256" ]] || {
    echo "${label} SHA-256 differs" >&2
    return 52
  }
}

active_a38_job_exists() {
  awk -F'|' -v experiment="$EXPERIMENT_ID" -v execution="$EXECUTION_ATTEMPT_ID" -v root="$RUN_BASE" '
    $2 ~ /^daily-knet-a38($|-)/ || index($0, experiment) || index($0, execution) || index($0, root) {found=1}
    END {exit(found ? 0 : 1)}
  '
}

ACTUAL_USER="$(id -un)"
ACTUAL_UID="$(id -u)"
EXPECTED_UID="$(id -u "$EXPECTED_USER")"
if [[ "${USER-}" != "$EXPECTED_USER" || "$ACTUAL_USER" != "$EXPECTED_USER" || "$ACTUAL_UID" != "$EXPECTED_UID" ]]; then
  echo "fixed-user check failed" >&2
  exit 53
fi

require_regular_identity "$RESULT69" "$RESULT69_SHA256" "$RESULT69_SIZE" "sequence 69 source recovery receipt"
grep -Fq "SEQ69_A37_SOURCE_EPOCH40_ARCHIVE experiment_id=DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH10_TO40_RESUME_V1_20260826_A37 execution_attempt_id=DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_A800_TRAIN4_SEQ65 job_id=215699 terminal_state=FAILED terminal_exit_code=2:0 archive=/data1/home/sunyiq/hpc_mailbox/outbox/kalmannet-daily-camels/DAILY_CAMELS_KNET_A37_FINAL_SOURCE_EPOCH40_SEQ69.tar.gz archive_sha256=${SOURCE_EVIDENCE_ARCHIVE_SHA256} archive_size=4887226 archive_member_count=85 epoch40_member_count=1 reserved_named_member_count=0 reserved_evaluation_access_count=0" "$RESULT69" || {
  echo "sequence 69 source recovery marker differs" >&2
  exit 54
}
grep -Fq "SEQ69_A37_SOURCE_EPOCH40_COLLECTED source_manifest_sha256=f504579439c5f9b0b22b399b23bf876d60f879002fb1e06e2f23312b85b7ead7 source_config_sha256=${SOURCE_CONFIG_SHA256} source_runner_sha256=b5c7c1ec0d38d6c9721af786351bb57995b9ec66fcf022ea5e36dbae173df434 epoch40_checkpoint_sha256=${CHECKPOINT_SHA256} result_summary_sha256=${SOURCE_RESULT_SHA256} epoch_history_sha256=${SOURCE_HISTORY_SHA256} completion_marker_sha256=${SOURCE_COMPLETION_SHA256} experiment_identity_sha256=${SOURCE_IDENTITY_SHA256}" "$RESULT69" || {
  echo "sequence 69 recovered identities differ" >&2
  exit 55
}
grep -Fxq '### exit_code=0' "$RESULT69" || {
  echo "sequence 69 evidence collection did not complete successfully" >&2
  exit 56
}

require_regular_identity "$ARCHIVE" "$ARCHIVE_SHA256" "$ARCHIVE_SIZE" "A38 continuation archive"
require_regular_identity "$OUTER_MANIFEST" "$OUTER_MANIFEST_SHA256" "$OUTER_MANIFEST_SIZE" "A38 outer manifest"
require_regular_identity "$WRAPPER_SOURCE" "$WRAPPER_SHA256" "$WRAPPER_SIZE" "A38 outer Slurm wrapper"
require_regular_identity "$EXACT_GATE" "$EXACT_GATE_SHA256" "$EXACT_GATE_SIZE" "exact replay receipt"
require_regular_identity "$CAUSAL_GATE" "$CAUSAL_GATE_SHA256" "$CAUSAL_GATE_SIZE" "causal replay receipt"

python - "$OUTER_MANIFEST" "$EXPERIMENT_ID" "$ARCHIVE_SHA256" "$ARCHIVE_SIZE" \
  "$INTERNAL_MANIFEST_SHA256" "$ACTIVE_CONFIG_MEMBER" "$ACTIVE_CONFIG_SHA256" \
  "$RUNNER_SHA256" "$TRAIN_ENTRY_SHA256" "$TRAIN_ENTRY_TEST_SHA256" \
  "$PREFLIGHT_SHA256" "$BUILDER_SHA256" "$CHECKPOINT_SHA256" \
  "$SOURCE_CONFIG_SHA256" "$SOURCE_HISTORY_SHA256" "$SOURCE_RESULT_SHA256" \
  "$SOURCE_IDENTITY_SHA256" "$SOURCE_COMPLETION_SHA256" "$SOURCE_EVIDENCE_ARCHIVE_SHA256" <<'PY'
import json
from pathlib import Path
import sys

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
(
    experiment_id,
    archive_sha,
    archive_size,
    internal_sha,
    active_member,
    active_sha,
    runner_sha,
    train_sha,
    test_sha,
    preflight_sha,
    builder_sha,
    checkpoint_sha,
    source_config_sha,
    history_sha,
    result_sha,
    identity_sha,
    completion_sha,
    source_archive_sha,
) = (sys.argv[2], sys.argv[3], int(sys.argv[4]), *sys.argv[5:20])
members = manifest.get("member_sha256", {})
expected_members = {
    active_member: active_sha,
    "scripts/run_daily_camels_ukf_knet_parity.py": runner_sha,
    "hpc/daily_camels_ukf_knet_parity/submit_train_gpu.slurm": train_sha,
    "tests/test_daily_camels_ukf_knet_parity_hpc_preflight.py": test_sha,
    "hpc/daily_camels_ukf_knet_parity/preflight.py": preflight_sha,
    "scripts/build_daily_camels_ukf_knet_parity_hpc_bundle.py": builder_sha,
    "artifacts/daily_camels_knet_a37_train4_terminal_evidence/job215699/run/checkpoints/epoch_040.pt": checkpoint_sha,
    "configs/daily_camels_knet_fixed_full_training_coverage_epoch10_to40_resume_a37.json": source_config_sha,
    "artifacts/daily_camels_knet_a37_train4_terminal_evidence/job215699/run/epoch_history.json": history_sha,
    "artifacts/daily_camels_knet_a37_train4_terminal_evidence/job215699/run/result_summary.json": result_sha,
    "artifacts/daily_camels_knet_a37_train4_terminal_evidence/job215699/run/experiment_identity.json": identity_sha,
    "artifacts/daily_camels_knet_a37_train4_terminal_evidence/job215699/run/completion.marker.json": completion_sha,
}
continuation = manifest.get("continuation", {})
revision = manifest.get("gate_revision", {})
migration = revision.get("epoch_zero_reproducibility_migration", {})
if (
    manifest.get("experiment_id") != experiment_id
    or manifest.get("active_config_member") != active_member
    or manifest.get("archive_sha256") != archive_sha
    or int(manifest.get("archive_size", -1)) != archive_size
    or manifest.get("internal_manifest_sha256") != internal_sha
    or int(manifest.get("member_count", -1)) != 51
    or len(members) != 51
    or int(manifest.get("reserved_data_member_count", -1)) != 0
    or int(manifest.get("resume_checkpoint_count", -1)) != 1
    or int(manifest.get("array_members_materialized_during_build", -1)) != 0
    or any(members.get(path) != digest for path, digest in expected_members.items())
    or continuation.get("checkpoint_sha256") != checkpoint_sha
    or continuation.get("source_configuration_sha256") != source_config_sha
    or continuation.get("source_epoch_history_sha256") != history_sha
    or continuation.get("source_result_summary_sha256") != result_sha
    or continuation.get("source_identity_sha256") != identity_sha
    or continuation.get("source_evidence_archive_sha256") != source_archive_sha
    or int(continuation.get("completed_epoch", -1)) != 40
    or int(continuation.get("optimizer_steps", -1)) != 40
    or int(continuation.get("sampled_forecast_events", -1)) != 306000
    or manifest.get("cross_device_portability_receipt") is not None
    or revision.get("field") != "gate.require_same_segment_post_step_improvement"
    or revision.get("source_value") is not True
    or revision.get("target_value") is not False
    or revision.get("target_role") != "diagnostic_only"
    or revision.get("prospective_only") is not True
    or revision.get("post_hoc_source_reclassification_forbidden") is not True
    or int(revision.get("source_optimizer_steps", -1)) != 40
    or int(revision.get("source_strict_decrease_count", -1)) != 35
    or revision.get("source_not_strictly_decreased_optimizer_steps") != [12, 24, 26, 27, 30]
    or migration.get("target_device_name") != "NVIDIA A800-SXM4-80GB"
):
    raise SystemExit("A38 continuation bundle identity differs")
PY

for path in "$RUN_BASE" "$SOURCE_DIRECTORY" "$RUN_DIRECTORY" "$WRAPPER"; do
  [[ ! -e "$path" && ! -L "$path" ]] || {
    echo "A38 continuation namespace already exists: $path" >&2
    exit 57
  }
done

SQUEUE_SNAPSHOT="$(squeue -h -u "$EXPECTED_USER" -o '%A|%j|%P|%T|%u|%Z|%o')"
if active_a38_job_exists <<<"$SQUEUE_SNAPSHOT"; then
  echo "an active A38 job exists; refusing duplicate continuation" >&2
  exit 58
fi

SACCT_SNAPSHOT="$(sacct -n -X -u "$EXPECTED_USER" -S 2026-08-28 --format=JobIDRaw,JobName,State,Partition -P)"
if awk -F'|' '$2 ~ /^daily-knet-a38($|-)/ {found=1} END {exit(found ? 0 : 1)}' <<<"$SACCT_SNAPSHOT"; then
  echo "an A38 accounting record already exists; refusing duplicate first execution" >&2
  exit 59
fi

mkdir "$RUN_BASE"
mkdir -p "$SOURCE_DIRECTORY" "$STATUS_DIRECTORY/locks" "$LOG_DIRECTORY" "${RUN_BASE}/runs"
printf '%s\n' "$SQUEUE_SNAPSHOT" > "$SQUEUE_BEFORE"
printf '%s\n' "$SACCT_SNAPSHOT" > "$SACCT_BEFORE"
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
continuation = report.get("continuation", {})
revision = report.get("gate_revision", {})
portability = report.get("cross_device_portability_receipt", {})
if (
    report.get("status") != "BUNDLE_VERIFIED"
    or report.get("experiment_id") != sys.argv[2]
    or report.get("numpy_imported") is not False
    or report.get("torch_imported") is not False
    or int(report.get("array_members_materialized", -1)) != 0
    or int(report.get("member_count", -1)) != 51
    or continuation.get("checkpoint_sha256") != sys.argv[3]
    or int(continuation.get("completed_epoch", -1)) != 40
    or report.get("continuation_source_device_name") != "NVIDIA A800-SXM4-80GB"
    or portability.get("enabled") is not False
    or revision.get("field") != "gate.require_same_segment_post_step_improvement"
    or revision.get("target_role") != "diagnostic_only"
    or revision.get("prospective_only") is not True
):
    raise SystemExit("A38 continuation offline preflight differs")
PY

for path in "$RUN_DIRECTORY" \
  "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.probe.lock" \
  "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.train.lock" \
  "$SUBMISSION_LOCK" "$WRAPPER" "$IDENTITY_FILE" "$JOB_ID_FILE" "$SUBMITTED_TIME_FILE"; do
  [[ ! -e "$path" && ! -L "$path" ]] || {
    echo "A38 output, lock, or evidence path appeared before submission: $path" >&2
    exit 60
  }
done

sinfo -h -N -n ngu202 -p hgpu8 -o '%N|%P|%t|%G|%C|%m|%e' > "$NODE_REPORT"
if ! awk -F'|' '$1 == "ngu202" && $2 ~ /^hgpu8/ && $3 !~ /(down|drain|drng|fail|maint|unk)/ {healthy=1} END {exit(healthy ? 0 : 1)}' "$NODE_REPORT"; then
  echo "frozen ngu202 hgpu8 node is unavailable or unhealthy" >&2
  exit 61
fi

SQUEUE_FINAL="$(squeue -h -u "$EXPECTED_USER" -o '%A|%j|%P|%T|%u|%Z|%o')"
if active_a38_job_exists <<<"$SQUEUE_FINAL"; then
  echo "an A38 job appeared during continuation preflight" >&2
  exit 62
fi
printf '%s\n' "$SQUEUE_FINAL" > "$SQUEUE_BEFORE"

mkdir "$SUBMISSION_LOCK"
{
  printf 'experiment_id=%s\n' "$EXPERIMENT_ID"
  printf 'execution_attempt_id=%s\n' "$EXECUTION_ATTEMPT_ID"
  printf 'execution_role=%s\n' 'formal_checkpoint_continuation'
  printf 'owner_user=%s\n' "$ACTUAL_USER"
  printf 'owner_host=%s\n' "$(hostname)"
  printf 'owner_pid=%s\n' "$$"
  printf 'acquired_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$SUBMISSION_LOCK_OWNER"

cp "$WRAPPER_SOURCE" "$WRAPPER"
require_regular_identity "$WRAPPER" "$WRAPPER_SHA256" "$WRAPPER_SIZE" "materialized A38 wrapper"

IDENTITY_TEMP="$(mktemp "${STATUS_DIRECTORY}/seq70_identity.XXXXXX")"
{
  printf 'experiment_id=%s\n' "$EXPERIMENT_ID"
  printf 'execution_attempt_id=%s\n' "$EXECUTION_ATTEMPT_ID"
  printf 'source_checkpoint_sha256=%s\n' "$CHECKPOINT_SHA256"
  printf 'source_completed_epoch=40\n'
  printf 'target_total_epochs=80\n'
  printf 'source_optimizer_steps=40\n'
  printf 'target_total_optimizer_steps=80\n'
  printf 'source_sampled_forecast_events=306000\n'
  printf 'target_total_sampled_forecast_events=612000\n'
  printf 'same_segment_post_step_policy=diagnostic_only\n'
  printf 'run_base=%s\n' "$RUN_BASE"
  printf 'source_directory=%s\n' "$SOURCE_DIRECTORY"
  printf 'target_partition=hgpu8\n'
  printf 'target_node=ngu202\n'
  printf 'target_gpu=NVIDIA A800-SXM4-80GB\n'
  printf 'wrapper_sha256=%s\n' "$WRAPPER_SHA256"
  printf 'bundle_sha256=%s\n' "$ARCHIVE_SHA256"
  printf 'source_recovery_receipt_sha256=%s\n' "$RESULT69_SHA256"
  printf 'bash_version=%s\n' "$BASH_VERSION"
  printf 'control_script_sha256=%s\n' "$(sha256_file "${BASH_SOURCE[0]}")"
  printf 'control_script_size_bytes=%s\n' "$(stat -c '%s' "${BASH_SOURCE[0]}")"
  printf 'host_admission_min_bytes=2800353280\n'
  printf 'gpu_admission_min_free_mib=822\n'
} > "$IDENTITY_TEMP"
ln -- "$IDENTITY_TEMP" "$IDENTITY_FILE"
rm -- "$IDENTITY_TEMP"

SQUEUE_LAST="$(squeue -h -u "$EXPECTED_USER" -o '%A|%j|%P|%T|%u|%Z|%o')"
if active_a38_job_exists <<<"$SQUEUE_LAST"; then
  echo "an A38 job appeared immediately before continuation submission" >&2
  exit 63
fi

SUBMISSION_RAW="$(sbatch --parsable --mem=0 "$WRAPPER")"
TRAINING_JOB_ID="${SUBMISSION_RAW%%;*}"
case "$TRAINING_JOB_ID" in
  ''|*[!0-9]*) echo "invalid A38 continuation job id: $SUBMISSION_RAW" >&2; exit 64;;
esac

JOB_ID_TEMP="$(mktemp "${STATUS_DIRECTORY}/seq70_job_id.XXXXXX")"
printf '%s\n' "$TRAINING_JOB_ID" > "$JOB_ID_TEMP"
ln -- "$JOB_ID_TEMP" "$JOB_ID_FILE"
rm -- "$JOB_ID_TEMP"
TIME_TEMP="$(mktemp "${STATUS_DIRECTORY}/seq70_time.XXXXXX")"
date -u +%Y-%m-%dT%H:%M:%SZ > "$TIME_TEMP"
ln -- "$TIME_TEMP" "$SUBMITTED_TIME_FILE"
rm -- "$TIME_TEMP"

for _attempt in $(seq 1 10); do
  squeue -h -u "$EXPECTED_USER" -o '%A|%j|%P|%T|%u|%Z|%o' > "$SQUEUE_AFTER" 2>&1 || true
  sacct -j "$TRAINING_JOB_ID" --parsable2 --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,NodeList,AllocTRES,ReqTRES > "$SACCT_AFTER" 2>&1 || true
  if grep -Eq "^${TRAINING_JOB_ID}\\|daily-knet-a38\\|hgpu8\\|" "$SQUEUE_AFTER" || \
     grep -Eq "^${TRAINING_JOB_ID}\\|daily-knet-a38\\|${EXPECTED_USER}\\|hgpu8\\|" "$SACCT_AFTER"; then
    break
  fi
  sleep 1
done
if ! grep -Eq "^${TRAINING_JOB_ID}\\|daily-knet-a38\\|hgpu8\\|" "$SQUEUE_AFTER" && \
   ! grep -Eq "^${TRAINING_JOB_ID}\\|daily-knet-a38\\|${EXPECTED_USER}\\|hgpu8\\|" "$SACCT_AFTER"; then
  echo "submitted A38 continuation cannot yet be bound to hgpu8 accounting" >&2
  exit 65
fi
if awk -F'|' -v expected="$TRAINING_JOB_ID" '
    $2 ~ /^daily-knet-a38($|-)/ && $1 != expected {found=1}
    END {exit(found ? 0 : 1)}
  ' "$SQUEUE_AFTER"; then
  echo "another active A38 job appeared after continuation submission" >&2
  exit 66
fi

printf 'SEQ70_A38_A800_TRAIN_SUBMITTED experiment_id=%s execution_attempt_id=%s training_job_id=%s run_base=%s archive_sha256=%s outer_manifest_sha256=%s wrapper_sha256=%s source_checkpoint_sha256=%s source_recovery_receipt_sha256=%s target_partition=hgpu8 target_node=ngu202 target_gpu=NVIDIA_A800-SXM4-80GB\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$TRAINING_JOB_ID" "$RUN_BASE" "$ARCHIVE_SHA256" "$OUTER_MANIFEST_SHA256" "$WRAPPER_SHA256" "$CHECKPOINT_SHA256" "$RESULT69_SHA256"
