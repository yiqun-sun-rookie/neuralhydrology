#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT61="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_61.txt"
RESULT61_SHA256="b13499659b67a6414395d68eadabfbdb6f54fcb1853e8ce40ee3200c9eaaab35"
RESULT64="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_64.txt"
RESULT64_SHA256="c2963dc0f4bb023d2e68886ba3a543f8c4e5459e39397c5112880f2683123a34"
PROBE_JOB_ID="215366"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH10_TO40_RESUME_V1_20260826_A37"
FAILED_JOB_ID="215649"
FAILED_EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_A800_TRAIN3_SEQ61"
FAILED_RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a37_a800_train3_20260827"
FAILED_RUN_DIRECTORY="${FAILED_RUN_BASE}/runs/${EXPERIMENT_ID}"
FAILED_STATUS_DIRECTORY="${FAILED_RUN_BASE}/status"
FAILED_JOB_ID_FILE="${FAILED_STATUS_DIRECTORY}/seq61_a800_training_job_id.txt"
FAILED_IDENTITY_FILE="${FAILED_STATUS_DIRECTORY}/seq61_a800_train_submission_identity.txt"
FAILED_WRAPPER="${FAILED_RUN_BASE}/seq61_a37_a800_train3_wrapper.slurm"
FAILED_SUBMISSION_LOCK_OWNER="${FAILED_RUN_BASE}/status/locks/${FAILED_EXECUTION_ATTEMPT_ID}.submission.lock/owner.txt"
FAILED_TRAIN_LOCK="${FAILED_STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.train.lock"
FAILED_RUN_OWNER_LOCK="${FAILED_RUN_DIRECTORY}/.owner.lock"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_A800_TRAIN4_SEQ65"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a37_a800_train4_20260827"
SOURCE_DIRECTORY="${RUN_BASE}/source_A37_a800_train4_seq65"
RUN_DIRECTORY="${RUN_BASE}/runs/${EXPERIMENT_ID}"
STATUS_DIRECTORY="${RUN_BASE}/status"
LOG_DIRECTORY="${RUN_BASE}/logs"
PAYLOAD_DIRECTORY="${MAILBOX_ROOT}/payload/kalmannet-daily-camels/a37_a800_train4_seq65_20260827"
ARCHIVE="${PAYLOAD_DIRECTORY}/${EXPERIMENT_ID}.tar.gz"
OUTER_MANIFEST="${PAYLOAD_DIRECTORY}/bundle_manifest.sha256.json"
ARCHIVE_SHA256="758c43ac6823b7e306b04871fa77a5bbd6e66981ee02cc6b8ec0b83d8ac08044"
ARCHIVE_SIZE="2020535"
OUTER_MANIFEST_SHA256="704b2275a20219a084d505baf8f603ef983534e4e0aa327bfce8d54fb94ccd5f"
OUTER_MANIFEST_SIZE="13686"
INTERNAL_MANIFEST_SHA256="f504579439c5f9b0b22b399b23bf876d60f879002fb1e06e2f23312b85b7ead7"
ACTIVE_CONFIG_SHA256="29b4bdb604f2bfbba5c1ab78576a7a21811cd0fdd75060b2dc328ff608f06f2a"
RUNNER_SHA256="b5c7c1ec0d38d6c9721af786351bb57995b9ec66fcf022ea5e36dbae173df434"
TRAIN_ENTRY_SHA256="58aae6396d1cd60bddf90c0436854eecd804f798a23fe11ef2d0fee608bef490"
TRAIN_ENTRY_TEST_SHA256="6d40af0f7e0de49a8bae58e70d248cdb3047843751acf77d17087dd76bfa286c"
PREFLIGHT_SHA256="1cd507aed08fa3f201b92c632860df272b2415329ec3134836e292a4f6112c5d"
BUILDER_SHA256="a90de22a635fadda3fbbec631453925a8fe06d8fa5f2c905f23d545a8a39952b"
CHECKPOINT_SHA256="b2b93f531c7ad4922e14d5479564e82e5a6dca553835bbc8cc8af61db4a8d81e"
SOURCE_HISTORY_SHA256="7d418f55eed64e0f4e30335d38b4e56998bd8b1c89be44c94fe8b718a8a605c2"
EPOCH_ZERO_PREDICTION_SHA256="17a6f0dbbe145b0262e0b2c1f426c49f1687a29927e8f8348f6ea293e246d91f"
EPOCH_TEN_PREDICTION_SHA256="0517d0e6d4fb290e0cfe1f70ca1ed22e87b1c2c63618edf2b67d725445d7b440"
SOURCE_DEVICE_SHA256="d9c7a88af68821725083e384601eac70c45f6363d7c13a0fa4e588d5b0f55897"
PORTABILITY_RECEIPT_SHA256="747c304f1ec12d551d4b8b6f6a525fe28c9d757313c9fd009a741f8a3dcfacae"
EXACT_GATE="/data1/home/sunyiq/kalmannet_daily_camels_parity_20260824/status/replay_gate_DAILY_CAMELS_UKF_PARITY_KNET_FULL_STATE_EXACT_REPLAY_DTYPE_REPAIR_V3_20260825_A05.json"
EXACT_GATE_SHA256="70e73c9f014dc4a4d615e07087fb99a994ba30b8c867eb5ef49141a59a39b687"
EXACT_GATE_SIZE="2816"
CAUSAL_GATE="/data1/home/sunyiq/kalmannet_daily_camels_parity_20260824/status/replay_gate_DAILY_CAMELS_UKF_PARITY_KNET_FULL_STATE_CAUSAL_REPLAY_DTYPE_REPAIR_V3_20260825_A06.json"
CAUSAL_GATE_SHA256="0f6080a05a27244eca59c58043f265718102a4c2985684fb674781c8157d6c66"
CAUSAL_GATE_SIZE="2807"
WRAPPER_SOURCE="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels/seq65_a37_a800_train4_wrapper.slurm"
WRAPPER="${RUN_BASE}/seq65_a37_a800_train4_wrapper.slurm"
WRAPPER_SHA256="6c6b7281a37216787e5c9ff56b935213dd3297d6c457141daf6e419e555086a5"
WRAPPER_SIZE="2490"
OFFLINE_REPORT="${STATUS_DIRECTORY}/seq65_offline_train_bundle_verification.json"
IDENTITY_FILE="${STATUS_DIRECTORY}/seq65_a800_train_submission_identity.txt"
JOB_ID_FILE="${STATUS_DIRECTORY}/seq65_a800_training_job_id.txt"
SUBMITTED_TIME_FILE="${STATUS_DIRECTORY}/seq65_a800_training_submitted_time_utc.txt"
SQUEUE_BEFORE="${STATUS_DIRECTORY}/seq65_pre_submission_squeue.txt"
SQUEUE_AFTER="${STATUS_DIRECTORY}/seq65_post_submission_squeue.txt"
SACCT_AFTER="${STATUS_DIRECTORY}/seq65_post_submission_sacct.txt"
NODE_REPORT="${STATUS_DIRECTORY}/seq65_pre_submission_hgpu8_candidate_nodes.txt"
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

active_a37_job_exists() {
  awk -F'|' -v experiment="$EXPERIMENT_ID" -v root="$RUN_BASE" '
    $2 ~ /^daily-knet-a37($|-)/ || index($0, experiment) || index($0, root) {found=1}
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

require_regular_identity "$RESULT61" "$RESULT61_SHA256" "11899" "sequence 61 unique-submission evidence"
grep -Fxq "SEQ61_A37_A800_TRAIN_SUBMITTED experiment_id=${EXPERIMENT_ID} execution_attempt_id=${FAILED_EXECUTION_ATTEMPT_ID} training_job_id=${FAILED_JOB_ID} run_base=${FAILED_RUN_BASE} archive_sha256=651cc732bc435233a79aca9bfa17c672166e22a2bd0ba0266193f763b0075d1b wrapper_sha256=4b617343afeea05c3b94f7c415874f6ce2ff2f3c5e6f7ded72de3cdbd289f88e source_checkpoint_sha256=${CHECKPOINT_SHA256} portability_receipt_sha256=${PORTABILITY_RECEIPT_SHA256} target_partition=hgpu8 excluded_node=ngu201" "$RESULT61" || {
  echo "sequence 61 unique-submission marker differs" >&2
  exit 54
}
grep -Fxq '### exit_code=0' "$RESULT61" || {
  echo "sequence 61 mailbox command did not complete successfully" >&2
  exit 54
}

require_regular_identity "$RESULT64" "$RESULT64_SHA256" "63429" "sequence 64 terminal evidence"
grep -Fq 'submit_train_gpu.slurm: line 208: PORTABILITY_ARGUMENTS[@]: unbound variable' "$RESULT64" || {
  echo "sequence 64 does not prove the recoverable old-Bash empty-array failure" >&2
  exit 54
}
grep -Fq '"status": "PREFLIGHT_PASS"' "$RESULT64" || {
  echo "sequence 64 does not prove that the formal preflight passed" >&2
  exit 55
}
grep -Fq '"run_directory_absent": true' "$RESULT64" || {
  echo "sequence 64 does not prove that the failed attempt created no run directory" >&2
  exit 66
}
grep -Fq "SEQ64_A37_A800_TERMINAL_COLLECTED experiment_id=${EXPERIMENT_ID} execution_attempt_id=${FAILED_EXECUTION_ATTEMPT_ID} job_id=${FAILED_JOB_ID} terminal_state=FAILED terminal_exit_code=1:0 partition=hgpu8 node=ngu202 reserved_named_path_count=0 training_lock_present=0 run_owner_lock_present=0" "$RESULT64" || {
  echo "sequence 64 terminal identity or zero-access/lock evidence differs" >&2
  exit 66
}
grep -Fxq '### exit_code=0' "$RESULT64" || {
  echo "sequence 64 evidence collection did not complete successfully" >&2
  exit 66
}
require_regular_identity "$FAILED_IDENTITY_FILE" "9fb931b128cb9f0cbea7859eb66da24b1e9fca0b33182f75adce1e811d4b3846" "1108" "sequence 61 submission identity"
require_regular_identity "$FAILED_SUBMISSION_LOCK_OWNER" "bad29637253d4a26d923016975e64c5e0a95ef013692c6e38ea48af86984ed67" "322" "sequence 61 persistent submission lock owner"
require_regular_identity "$FAILED_WRAPPER" "4b617343afeea05c3b94f7c415874f6ce2ff2f3c5e6f7ded72de3cdbd289f88e" "2490" "sequence 61 materialized wrapper"
for prior_evidence in "$FAILED_IDENTITY_FILE" "$FAILED_SUBMISSION_LOCK_OWNER"; do
  [[ -f "$prior_evidence" && ! -L "$prior_evidence" ]] || {
    echo "sequence 61 prior-attempt identity evidence is absent or symbolic: $prior_evidence" >&2
    exit 68
  }
  grep -Fxq "experiment_id=${EXPERIMENT_ID}" "$prior_evidence" || {
    echo "sequence 61 prior-attempt experiment identity differs" >&2
    exit 69
  }
  grep -Fxq "execution_attempt_id=${FAILED_EXECUTION_ATTEMPT_ID}" "$prior_evidence" || {
    echo "sequence 61 prior-attempt execution identity differs" >&2
    exit 70
  }
done
grep -Fxq 'wrapper_sha256=4b617343afeea05c3b94f7c415874f6ce2ff2f3c5e6f7ded72de3cdbd289f88e' "$FAILED_IDENTITY_FILE" || {
  echo "sequence 61 prior-attempt wrapper identity differs" >&2
  exit 71
}
require_regular_identity "$FAILED_JOB_ID_FILE" "7ad84bef761838ef30a0c7f47751a02af1ecf972b3ac74c5ed525d2bab3a626b" "7" "sequence 61 job identifier"
grep -Fxq "$FAILED_JOB_ID" "$FAILED_JOB_ID_FILE" || {
  echo "sequence 61 job identifier differs" >&2
  exit 72
}
FAILED_STATE="$(sacct -n -X -j "$FAILED_JOB_ID" --format=State -P | awk -F'|' 'NF {print $1; exit}' | sed 's/[+ ].*$//')"
FAILED_EXIT="$(sacct -n -X -j "$FAILED_JOB_ID" --format=ExitCode -P | awk -F'|' 'NF {print $1; exit}')"
if [[ "$FAILED_STATE" != "FAILED" || "$FAILED_EXIT" != "1:0" ]]; then
  echo "sequence 61 failed job terminal state changed: ${FAILED_STATE:-UNKNOWN}/${FAILED_EXIT:-UNKNOWN}" >&2
  exit 73
fi
if squeue -h -j "$FAILED_JOB_ID" 2>/dev/null | grep -q .; then
  echo "sequence 61 failed job is unexpectedly still active" >&2
  exit 74
fi
if [[ -e "$FAILED_RUN_DIRECTORY" || -L "$FAILED_RUN_DIRECTORY" || \
      -e "$FAILED_TRAIN_LOCK" || -L "$FAILED_TRAIN_LOCK" || \
      -e "$FAILED_RUN_OWNER_LOCK" || -L "$FAILED_RUN_OWNER_LOCK" ]]; then
  echo "sequence 61 created a run directory or retained an active lock; refusing retry" >&2
  exit 67
fi

PROBE_STATE="$(sacct -n -X -j "$PROBE_JOB_ID" --format=State -P | awk -F'|' 'NF {print $1; exit}' | sed 's/[+ ].*$//')"
PROBE_EXIT="$(sacct -n -X -j "$PROBE_JOB_ID" --format=ExitCode -P | awk -F'|' 'NF {print $1; exit}')"
if [[ "$PROBE_STATE" != "COMPLETED" || "$PROBE_EXIT" != "0:0" ]]; then
  echo "portability probe terminal state changed: ${PROBE_STATE:-UNKNOWN}/${PROBE_EXIT:-UNKNOWN}" >&2
  exit 56
fi

require_regular_identity "$ARCHIVE" "$ARCHIVE_SHA256" "$ARCHIVE_SIZE" "formal A800 continuation archive"
require_regular_identity "$OUTER_MANIFEST" "$OUTER_MANIFEST_SHA256" "$OUTER_MANIFEST_SIZE" "formal A800 continuation outer manifest"
require_regular_identity "$WRAPPER_SOURCE" "$WRAPPER_SHA256" "$WRAPPER_SIZE" "formal A800 continuation wrapper"
require_regular_identity "$EXACT_GATE" "$EXACT_GATE_SHA256" "$EXACT_GATE_SIZE" "exact replay receipt"
require_regular_identity "$CAUSAL_GATE" "$CAUSAL_GATE_SHA256" "$CAUSAL_GATE_SIZE" "causal replay receipt"

python - "$OUTER_MANIFEST" "$EXPERIMENT_ID" "$ARCHIVE_SHA256" "$ARCHIVE_SIZE" \
  "$INTERNAL_MANIFEST_SHA256" "$ACTIVE_CONFIG_SHA256" "$RUNNER_SHA256" \
  "$TRAIN_ENTRY_SHA256" "$TRAIN_ENTRY_TEST_SHA256" "$PREFLIGHT_SHA256" "$BUILDER_SHA256" "$CHECKPOINT_SHA256" \
  "$SOURCE_HISTORY_SHA256" "$EPOCH_ZERO_PREDICTION_SHA256" \
  "$EPOCH_TEN_PREDICTION_SHA256" "$SOURCE_DEVICE_SHA256" "$PORTABILITY_RECEIPT_SHA256" <<'PY'
import json
from pathlib import Path
import sys

manifest = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
(
    experiment_id,
    archive_sha,
    archive_size,
    internal_sha,
    config_sha,
    runner_sha,
    train_sha,
    train_test_sha,
    preflight_sha,
    builder_sha,
    checkpoint_sha,
    history_sha,
    epoch_zero_sha,
    epoch_ten_sha,
    source_device_sha,
    portability_sha,
) = (sys.argv[2], sys.argv[3], int(sys.argv[4]), *sys.argv[5:18])
members = manifest.get("member_sha256", {})
expected_members = {
    "configs/daily_camels_knet_fixed_full_training_coverage_epoch10_to40_resume_a37.json": config_sha,
    "scripts/run_daily_camels_ukf_knet_parity.py": runner_sha,
    "hpc/daily_camels_ukf_knet_parity/submit_train_gpu.slurm": train_sha,
    "tests/test_daily_camels_ukf_knet_parity_hpc_preflight.py": train_test_sha,
    "hpc/daily_camels_ukf_knet_parity/preflight.py": preflight_sha,
    "scripts/build_daily_camels_ukf_knet_parity_hpc_bundle.py": builder_sha,
    "artifacts/daily_camels_ukf_knet_parity_seq15_failure_evidence/ff2084c4/seq15_snapshot_2831/run/checkpoints/epoch_010.pt": checkpoint_sha,
    "artifacts/daily_camels_ukf_knet_parity_seq15_failure_evidence/ff2084c4/seq15_snapshot_2831/run/epoch_history.json": history_sha,
    "artifacts/daily_camels_ukf_knet_parity_seq15_failure_evidence/ff2084c4/seq15_snapshot_2831/run/predictions/epoch_000.npz": epoch_zero_sha,
    "artifacts/daily_camels_ukf_knet_parity_seq15_failure_evidence/ff2084c4/seq15_snapshot_2831/run/predictions/epoch_010.npz": epoch_ten_sha,
    "artifacts/daily_camels_ukf_knet_parity_seq15_failure_evidence/ff2084c4/seq15_snapshot_2831/status/train-preflight-DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_TEN_EPOCH_V1_20260825_A16-211291.json": source_device_sha,
    "artifacts/daily_camels_knet_a37_portability_contract/A37_A800_PORTABILITY_PROBE2_SEQ57_RECEIPT.json": portability_sha,
}
continuation = manifest.get("continuation", {})
portability = manifest.get("cross_device_portability_receipt", {})
if (
    manifest.get("experiment_id") != experiment_id
    or manifest.get("archive_sha256") != archive_sha
    or int(manifest.get("archive_size", -1)) != archive_size
    or int(manifest.get("member_count", -1)) != 51
    or len(members) != 51
    or int(manifest.get("reserved_data_member_count", -1)) != 0
    or int(manifest.get("resume_checkpoint_count", -1)) != 1
    or int(manifest.get("array_members_materialized_during_build", -1)) != 0
    or manifest.get("internal_manifest_sha256") != internal_sha
    or any(members.get(path) != digest for path, digest in expected_members.items())
    or continuation.get("checkpoint_sha256") != checkpoint_sha
    or int(continuation.get("completed_epoch", -1)) != 10
    or int(continuation.get("optimizer_steps", -1)) != 10
    or int(continuation.get("sampled_forecast_events", -1)) != 76500
    or portability.get("sha256") != portability_sha
    or portability.get("source_device_name") != "NVIDIA GeForce RTX 3090"
    or portability.get("target_device_name") != "NVIDIA A800-SXM4-80GB"
    or float(portability.get("prediction_maximum_absolute_error_limit", -1)) != 3e-7
    or float(portability.get("prediction_maximum_relative_error_limit", -1)) != 3e-7
    or float(portability.get("objective_and_metric_absolute_error_limit", -1)) != 3e-9
):
    raise SystemExit("formal A800 continuation bundle identity differs")
PY

for path in "$RUN_BASE" "$SOURCE_DIRECTORY" "$RUN_DIRECTORY" "$WRAPPER"; do
  [[ ! -e "$path" && ! -L "$path" ]] || {
    echo "formal A800 continuation namespace already exists: $path" >&2
    exit 57
  }
done

SQUEUE_SNAPSHOT="$(squeue -h -u "$EXPECTED_USER" -o '%A|%j|%P|%T|%u|%Z|%o')"
if active_a37_job_exists <<<"$SQUEUE_SNAPSHOT"; then
  echo "an active A37 job exists; refusing duplicate formal continuation" >&2
  exit 58
fi

mkdir "$RUN_BASE"
mkdir -p "$SOURCE_DIRECTORY" "$STATUS_DIRECTORY/locks" "$LOG_DIRECTORY" "${RUN_BASE}/runs"
printf '%s\n' "$SQUEUE_SNAPSHOT" > "$SQUEUE_BEFORE"
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
python - "$OFFLINE_REPORT" "$EXPERIMENT_ID" "$CHECKPOINT_SHA256" "$PORTABILITY_RECEIPT_SHA256" <<'PY'
import json
from pathlib import Path
import sys

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
continuation = report.get("continuation", {})
portability = report.get("cross_device_portability_receipt", {})
if (
    report.get("status") != "BUNDLE_VERIFIED"
    or report.get("experiment_id") != sys.argv[2]
    or report.get("numpy_imported") is not False
    or report.get("torch_imported") is not False
    or int(report.get("array_members_materialized", -1)) != 0
    or int(report.get("member_count", -1)) != 51
    or continuation.get("checkpoint_sha256") != sys.argv[3]
    or int(continuation.get("completed_epoch", -1)) != 10
    or portability.get("enabled") is not True
    or portability.get("sha256") != sys.argv[4]
    or float(portability.get("prediction_maximum_absolute_error_limit", -1)) != 3e-7
    or float(portability.get("prediction_maximum_relative_error_limit", -1)) != 3e-7
    or float(portability.get("objective_and_metric_absolute_error_limit", -1)) != 3e-9
):
    raise SystemExit("formal A800 continuation offline preflight differs")
PY

for path in "$RUN_DIRECTORY" \
  "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.probe.lock" \
  "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.train.lock" \
  "$SUBMISSION_LOCK" "$WRAPPER" "$IDENTITY_FILE" "$JOB_ID_FILE" "$SUBMITTED_TIME_FILE"; do
  [[ ! -e "$path" && ! -L "$path" ]] || {
    echo "formal A800 continuation output, lock, or evidence path appeared: $path" >&2
    exit 59
  }
done

sinfo -h -N -n ngu202,ngu203 -p hgpu8 -o '%N|%P|%t|%G|%C|%m|%e' > "$NODE_REPORT"
if ! awk -F'|' '$1 ~ /^ngu20[23]$/ && $2 ~ /^hgpu8/ && $3 !~ /(down|drain|drng|fail|maint|unk)/ {healthy=1} END {exit(healthy ? 0 : 1)}' "$NODE_REPORT"; then
  echo "no non-drained approved hgpu8 A800 candidate is visible" >&2
  exit 60
fi

SQUEUE_FINAL="$(squeue -h -u "$EXPECTED_USER" -o '%A|%j|%P|%T|%u|%Z|%o')"
if active_a37_job_exists <<<"$SQUEUE_FINAL"; then
  echo "an A37 job appeared during formal continuation preflight" >&2
  exit 61
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
require_regular_identity "$WRAPPER" "$WRAPPER_SHA256" "$WRAPPER_SIZE" "materialized formal A800 continuation wrapper"

IDENTITY_TEMP="$(mktemp "${STATUS_DIRECTORY}/seq65_identity.XXXXXX")"
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
  printf 'cross_device_portability_receipt_sha256=%s\n' "$PORTABILITY_RECEIPT_SHA256"
  printf 'run_base=%s\n' "$RUN_BASE"
  printf 'source_directory=%s\n' "$SOURCE_DIRECTORY"
  printf 'target_partition=hgpu8\n'
  printf 'approved_nodes=ngu202,ngu203\n'
  printf 'excluded_node=ngu201\n'
  printf 'wrapper_sha256=%s\n' "$WRAPPER_SHA256"
  printf 'recovered_submission_receipt_sha256=%s\n' "$RESULT61_SHA256"
  printf 'recovered_failure_receipt_sha256=%s\n' "$RESULT64_SHA256"
  printf 'recovered_failure_job_id=%s\n' "$FAILED_JOB_ID"
  printf 'bash_version=%s\n' "$BASH_VERSION"
  printf 'control_script_sha256=%s\n' "$(sha256_file "${BASH_SOURCE[0]}")"
  printf 'control_script_size_bytes=%s\n' "$(stat -c '%s' "${BASH_SOURCE[0]}")"
  printf 'host_admission_min_bytes=2800353280\n'
  printf 'gpu_admission_min_free_mib=822\n'
} > "$IDENTITY_TEMP"
ln -- "$IDENTITY_TEMP" "$IDENTITY_FILE"
rm -- "$IDENTITY_TEMP"

SQUEUE_LAST="$(squeue -h -u "$EXPECTED_USER" -o '%A|%j|%P|%T|%u|%Z|%o')"
if active_a37_job_exists <<<"$SQUEUE_LAST"; then
  echo "an A37 job appeared immediately before formal continuation submission" >&2
  exit 62
fi

SUBMISSION_RAW="$(sbatch --parsable --mem=0 "$WRAPPER")"
TRAINING_JOB_ID="${SUBMISSION_RAW%%;*}"
case "$TRAINING_JOB_ID" in
  ''|*[!0-9]*) echo "invalid formal A800 continuation job id: $SUBMISSION_RAW" >&2; exit 63;;
esac

JOB_ID_TEMP="$(mktemp "${STATUS_DIRECTORY}/seq65_job_id.XXXXXX")"
printf '%s\n' "$TRAINING_JOB_ID" > "$JOB_ID_TEMP"
ln -- "$JOB_ID_TEMP" "$JOB_ID_FILE"
rm -- "$JOB_ID_TEMP"
TIME_TEMP="$(mktemp "${STATUS_DIRECTORY}/seq65_time.XXXXXX")"
date -u +%Y-%m-%dT%H:%M:%SZ > "$TIME_TEMP"
ln -- "$TIME_TEMP" "$SUBMITTED_TIME_FILE"
rm -- "$TIME_TEMP"

for _attempt in $(seq 1 10); do
  squeue -h -u "$EXPECTED_USER" -o '%A|%j|%P|%T|%u|%Z|%o' > "$SQUEUE_AFTER" 2>&1 || true
  sacct -j "$TRAINING_JOB_ID" --parsable2 --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,NodeList,AllocTRES,ReqTRES > "$SACCT_AFTER" 2>&1 || true
  if grep -Eq "^${TRAINING_JOB_ID}\\|daily-knet-a37\\|hgpu8\\|" "$SQUEUE_AFTER" || \
     grep -Eq "^${TRAINING_JOB_ID}\\|daily-knet-a37\\|${EXPECTED_USER}\\|hgpu8\\|" "$SACCT_AFTER"; then
    break
  fi
  sleep 1
done
if ! grep -Eq "^${TRAINING_JOB_ID}\\|daily-knet-a37\\|hgpu8\\|" "$SQUEUE_AFTER" && \
   ! grep -Eq "^${TRAINING_JOB_ID}\\|daily-knet-a37\\|${EXPECTED_USER}\\|hgpu8\\|" "$SACCT_AFTER"; then
  echo "submitted formal A800 continuation cannot yet be bound to hgpu8 accounting" >&2
  exit 64
fi
if awk -F'|' -v expected="$TRAINING_JOB_ID" '
    $2 ~ /^daily-knet-a37($|-)/ && $1 != expected {found=1}
    END {exit(found ? 0 : 1)}
  ' "$SQUEUE_AFTER"; then
  echo "another active A37 job appeared after formal continuation submission" >&2
  exit 65
fi

printf 'SEQ65_A37_A800_TRAIN_SUBMITTED experiment_id=%s execution_attempt_id=%s training_job_id=%s run_base=%s archive_sha256=%s wrapper_sha256=%s source_checkpoint_sha256=%s portability_receipt_sha256=%s recovered_submission_receipt_sha256=%s recovered_failure_receipt_sha256=%s target_partition=hgpu8 excluded_node=ngu201\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$TRAINING_JOB_ID" "$RUN_BASE" "$ARCHIVE_SHA256" "$WRAPPER_SHA256" "$CHECKPOINT_SHA256" "$PORTABILITY_RECEIPT_SHA256" "$RESULT61_SHA256" "$RESULT64_SHA256"
