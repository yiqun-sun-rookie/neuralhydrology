#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT56="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_56.txt"
OLD_JOB_ID="215268"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH10_TO40_RESUME_V1_20260826_A37"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_A800_PORTABILITY_PROBE2_SEQ57"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a37_a800_portability_probe2_20260827"
SOURCE_DIRECTORY="${RUN_BASE}/source_A37_a800_portability_probe2_seq57"
RUN_DIRECTORY="${RUN_BASE}/runs/${EXPERIMENT_ID}"
STATUS_DIRECTORY="${RUN_BASE}/status"
LOG_DIRECTORY="${RUN_BASE}/logs"
PAYLOAD_DIRECTORY="${MAILBOX_ROOT}/payload/kalmannet-daily-camels/parity-a37-a800-portability-probe2-v57"
ARCHIVE="${PAYLOAD_DIRECTORY}/${EXPERIMENT_ID}.tar.gz"
OUTER_MANIFEST="${PAYLOAD_DIRECTORY}/A37_bundle_manifest.sha256.json"
ARCHIVE_SHA256="c9c7a08cefd4e5ea335ea946a5035f6321b1ce0c28f80a0b25ed5338751df51d"
ARCHIVE_SIZE="2009071"
OUTER_MANIFEST_SHA256="68ff515d54f5ef8557181338d0df0795b7140d69e4e10ce08adee3bbdf60eaa8"
OUTER_MANIFEST_SIZE="12886"
INTERNAL_MANIFEST_SHA256="742f49bee2c8a29e2c1b465b54387533d8837ac662307f98cc51fb31f60ed877"
ACTIVE_CONFIG_SHA256="70a522e9306c80d6c3010a3fbcf7fda3b4f53d850498698e1ef15f1028441984"
ENTRY_SHA256="5a83f4e665d1d28b89da4c114da41b4f41c89cea200af5f8c66484fcee29b4f1"
TRAIN_ENTRY_SHA256="3cdbe0c6cc25507c51785b052be7cb08de7296e72281ba5f427686080369d9ef"
PREFLIGHT_SHA256="5222e45d23d38023ef99147a59c6a1033c61dca9492a0a5dbe869054b55b14d6"
BUILDER_SHA256="1db655d532b6ab2ebfa03929f0e1060ea2ec54f89cd99810cad7e106a47da14e"
CHECKPOINT_SHA256="b2b93f531c7ad4922e14d5479564e82e5a6dca553835bbc8cc8af61db4a8d81e"
SOURCE_HISTORY_SHA256="7d418f55eed64e0f4e30335d38b4e56998bd8b1c89be44c94fe8b718a8a605c2"
EPOCH_ZERO_PREDICTION_SHA256="17a6f0dbbe145b0262e0b2c1f426c49f1687a29927e8f8348f6ea293e246d91f"
EPOCH_TEN_PREDICTION_SHA256="0517d0e6d4fb290e0cfe1f70ca1ed22e87b1c2c63618edf2b67d725445d7b440"
SOURCE_DEVICE_SHA256="d9c7a88af68821725083e384601eac70c45f6363d7c13a0fa4e588d5b0f55897"
WRAPPER_SOURCE="${MAILBOX_ROOT}/inbox/kalmannet-daily-camels/seq57_a37_a800_portability_probe2_wrapper.slurm"
WRAPPER="${RUN_BASE}/seq57_a37_a800_portability_probe2_wrapper.slurm"
WRAPPER_SHA256="1a9fd96e3161a7449babc35443e6d067acdfb2af84f45c8431179bd89511da28"
WRAPPER_SIZE="2579"
SUBMISSION_LOCK="${STATUS_DIRECTORY}/locks/${EXECUTION_ATTEMPT_ID}.submission.lock"
OFFLINE_REPORT="${STATUS_DIRECTORY}/seq57_offline_portability_probe_bundle_verification.json"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}
require_regular_identity() {
  local path="$1" expected_sha256="$2" expected_size="$3" label="$4"
  [[ -f "$path" && ! -L "$path" ]] || { echo "$label absent or non-regular" >&2; return 50; }
  [[ "$(stat -c '%s' "$path")" == "$expected_size" ]] || { echo "$label size differs" >&2; return 51; }
  [[ "$(sha256_file "$path")" == "$expected_sha256" ]] || { echo "$label SHA-256 differs" >&2; return 52; }
}

ACTUAL_USER="$(id -un)"
[[ "${USER-}" == "$EXPECTED_USER" && "$ACTUAL_USER" == "$EXPECTED_USER" ]] || {
  echo "fixed-user check failed" >&2
  exit 53
}
[[ -f "$RESULT56" && ! -L "$RESULT56" ]] || { echo "terminal evidence result 56 absent" >&2; exit 54; }
grep -Fq "SEQ56_A37_A800_DIAGNOSTIC_TERMINAL_COLLECTED experiment_id=${EXPERIMENT_ID} execution_attempt_id=DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A37_A800_DIAG1_SEQ54 job_id=${OLD_JOB_ID} terminal_state=FAILED terminal_exit_code=1:0 reserved_named_path_count=0" "$RESULT56" || {
  echo "result 56 terminal identity differs" >&2
  exit 55
}
grep -Fq '"absolute_objective_delta":2.2920620956767834e-10' "$RESULT56" || {
  echo "result 56 does not preserve the measured cross-device objective delta" >&2
  exit 56
}
grep -Fq '"actual_parameter_sha256":"b4a375c3195cae48c984e9a18cd470746950fda5a5aceec60b6e594f1a352645"' "$RESULT56" || {
  echo "result 56 does not prove unchanged epoch-zero parameters" >&2
  exit 57
}
grep -Fq '"mismatched_fields":["objective","prediction_sha256"]' "$RESULT56" || {
  echo "result 56 failure classification differs" >&2
  exit 58
}

OLD_STATE="$(sacct -n -X -j "$OLD_JOB_ID" --format=State -P | awk -F'|' 'NF {print $1; exit}' | sed 's/[+ ].*$//')"
OLD_EXIT="$(sacct -n -X -j "$OLD_JOB_ID" --format=ExitCode -P | awk -F'|' 'NF {print $1; exit}')"
[[ "$OLD_STATE" == "FAILED" && "$OLD_EXIT" == "1:0" ]] || {
  echo "old diagnostic terminal state changed: ${OLD_STATE:-UNKNOWN}/${OLD_EXIT:-UNKNOWN}" >&2
  exit 59
}

require_regular_identity "$ARCHIVE" "$ARCHIVE_SHA256" "$ARCHIVE_SIZE" "portability-probe archive"
require_regular_identity "$OUTER_MANIFEST" "$OUTER_MANIFEST_SHA256" "$OUTER_MANIFEST_SIZE" "portability-probe outer manifest"
require_regular_identity "$WRAPPER_SOURCE" "$WRAPPER_SHA256" "$WRAPPER_SIZE" "portability-probe wrapper"

python - "$OUTER_MANIFEST" "$EXPERIMENT_ID" "$ARCHIVE_SHA256" "$ARCHIVE_SIZE" \
  "$INTERNAL_MANIFEST_SHA256" "$ACTIVE_CONFIG_SHA256" "$ENTRY_SHA256" \
  "$TRAIN_ENTRY_SHA256" "$PREFLIGHT_SHA256" "$BUILDER_SHA256" "$CHECKPOINT_SHA256" \
  "$SOURCE_HISTORY_SHA256" "$EPOCH_ZERO_PREDICTION_SHA256" \
  "$EPOCH_TEN_PREDICTION_SHA256" "$SOURCE_DEVICE_SHA256" <<'PY'
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
    entry_sha,
    train_sha,
    preflight_sha,
    builder_sha,
    checkpoint_sha,
    history_sha,
    epoch_zero_sha,
    epoch_ten_sha,
    source_device_sha,
) = (*sys.argv[2:4], int(sys.argv[4]), *sys.argv[5:16])
members = manifest.get("member_sha256", {})
expected_members = {
    "configs/daily_camels_knet_fixed_full_training_coverage_epoch10_to40_resume_a37.json": config_sha,
    "scripts/run_daily_camels_ukf_knet_parity.py": entry_sha,
    "hpc/daily_camels_ukf_knet_parity/submit_train_gpu.slurm": train_sha,
    "hpc/daily_camels_ukf_knet_parity/preflight.py": preflight_sha,
    "scripts/build_daily_camels_ukf_knet_parity_hpc_bundle.py": builder_sha,
    "artifacts/daily_camels_ukf_knet_parity_seq15_failure_evidence/ff2084c4/seq15_snapshot_2831/run/checkpoints/epoch_010.pt": checkpoint_sha,
    "artifacts/daily_camels_ukf_knet_parity_seq15_failure_evidence/ff2084c4/seq15_snapshot_2831/run/epoch_history.json": history_sha,
    "artifacts/daily_camels_ukf_knet_parity_seq15_failure_evidence/ff2084c4/seq15_snapshot_2831/run/predictions/epoch_000.npz": epoch_zero_sha,
    "artifacts/daily_camels_ukf_knet_parity_seq15_failure_evidence/ff2084c4/seq15_snapshot_2831/run/predictions/epoch_010.npz": epoch_ten_sha,
    "artifacts/daily_camels_ukf_knet_parity_seq15_failure_evidence/ff2084c4/seq15_snapshot_2831/status/train-preflight-DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_TEN_EPOCH_V1_20260825_A16-211291.json": source_device_sha,
}
continuation = manifest.get("continuation", {})
if (
    manifest.get("experiment_id") != experiment_id
    or manifest.get("archive_sha256") != archive_sha
    or int(manifest.get("archive_size", -1)) != archive_size
    or int(manifest.get("member_count", -1)) != 50
    or len(members) != 50
    or int(manifest.get("reserved_data_member_count", -1)) != 0
    or int(manifest.get("resume_checkpoint_count", -1)) != 1
    or int(manifest.get("array_members_materialized_during_build", -1)) != 0
    or manifest.get("internal_manifest_sha256") != internal_sha
    or any(members.get(path) != digest for path, digest in expected_members.items())
    or continuation.get("checkpoint_sha256") != checkpoint_sha
    or int(continuation.get("completed_epoch", -1)) != 10
    or int(continuation.get("optimizer_steps", -1)) != 10
    or int(continuation.get("sampled_forecast_events", -1)) != 76500
):
    raise SystemExit("portability-probe bundle identity differs")
PY

for path in "$RUN_BASE" "$SOURCE_DIRECTORY" "$RUN_DIRECTORY" "$WRAPPER"; do
  [[ ! -e "$path" && ! -L "$path" ]] || { echo "portability-probe namespace already exists: $path" >&2; exit 60; }
done

SQUEUE_BEFORE="$(squeue -h -u "$EXPECTED_USER" -o '%A|%j|%P|%T|%u|%Z|%o')"
if awk -F'|' -v experiment="$EXPERIMENT_ID" -v root="$RUN_BASE" '
    $2 ~ /^daily-knet-a37/ || index($0, experiment) || index($0, root) {found=1}
    END {exit(found ? 0 : 1)}
' <<<"$SQUEUE_BEFORE"; then
  echo "an active A37 job exists; refusing duplicate portability probe" >&2
  exit 61
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
    or int(report.get("member_count", -1)) != 50
    or report.get("continuation", {}).get("checkpoint_sha256") != sys.argv[3]
    or int(report.get("continuation", {}).get("completed_epoch", -1)) != 10
):
    raise SystemExit("portability-probe offline preflight differs")
PY

for path in "$RUN_DIRECTORY" "${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.train.lock" "$SUBMISSION_LOCK"; do
  [[ ! -e "$path" && ! -L "$path" ]] || { echo "portability-probe output or lock appeared: $path" >&2; exit 62; }
done
mkdir "$SUBMISSION_LOCK"
{
  printf 'experiment_id=%s\n' "$EXPERIMENT_ID"
  printf 'execution_attempt_id=%s\n' "$EXECUTION_ATTEMPT_ID"
  printf 'execution_role=%s\n' 'cross_device_zero_update_portability_diagnostic'
  printf 'owner_user=%s\n' "$ACTUAL_USER"
  printf 'acquired_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "${SUBMISSION_LOCK}/owner.txt"
cp "$WRAPPER_SOURCE" "$WRAPPER"
require_regular_identity "$WRAPPER" "$WRAPPER_SHA256" "$WRAPPER_SIZE" "materialized portability-probe wrapper"

SQUEUE_FINAL="$(squeue -h -u "$EXPECTED_USER" -o '%A|%j|%P|%T|%u|%Z|%o')"
if awk -F'|' -v experiment="$EXPERIMENT_ID" -v root="$RUN_BASE" '
    $2 ~ /^daily-knet-a37/ || index($0, experiment) || index($0, root) {found=1}
    END {exit(found ? 0 : 1)}
' <<<"$SQUEUE_FINAL"; then
  echo "an A37 job appeared during portability-probe preflight" >&2
  exit 63
fi

SUBMISSION_RAW="$(sbatch --parsable --mem=0 "$WRAPPER")"
JOB_ID="${SUBMISSION_RAW%%;*}"
case "$JOB_ID" in ''|*[!0-9]*) echo "invalid portability-probe job id: $SUBMISSION_RAW" >&2; exit 64;; esac
printf '%s\n' "$JOB_ID" > "${STATUS_DIRECTORY}/seq57_portability_probe_job_id.txt"
date -u +%Y-%m-%dT%H:%M:%SZ > "${STATUS_DIRECTORY}/seq57_portability_probe_submitted_time_utc.txt"
squeue -h -j "$JOB_ID" -o '%A|%j|%P|%T|%R|%b|%Z|%o' > "${STATUS_DIRECTORY}/seq57_post_submission_squeue.txt" 2>&1 || true
sacct -j "$JOB_ID" --parsable2 --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,NodeList,AllocTRES > "${STATUS_DIRECTORY}/seq57_post_submission_sacct.txt" 2>&1 || true

printf 'SEQ57_A37_A800_PORTABILITY_PROBE_SUBMITTED experiment_id=%s execution_attempt_id=%s portability_probe_job_id=%s run_base=%s archive_sha256=%s wrapper_sha256=%s source_checkpoint_sha256=%s portability_diagnostic_only=1\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$JOB_ID" "$RUN_BASE" "$ARCHIVE_SHA256" "$WRAPPER_SHA256" "$CHECKPOINT_SHA256"
