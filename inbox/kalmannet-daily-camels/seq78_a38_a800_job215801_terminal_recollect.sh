#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT70="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_70.txt"
RESULT74="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_74.txt"
RESULT75="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_75.txt"
RESULT76="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_76.txt"
RESULT77="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_77.txt"
RESULT70_SHA256="7b72da67bc1c9fa6e36c35e1d2f49656e4e27037fe52eee5d6e556594e276077"
RESULT70_SIZE="12788"
RESULT74_SHA256="ce0b8960820372a70fe29d8eaef4a43491a8c626b39ba62cb61da1feda5a26b6"
RESULT74_SIZE="1351"
RESULT75_SHA256="a3a8725e3191ae64256df62983621c485d947dbbdb020158fdda07a177234809"
RESULT75_SIZE="354"
RESULT76_SHA256="8de1626a8ca208a9f3d5eb60585d5e18b48f5d84d966f3f941a331c0a5642052"
RESULT76_SIZE="7397367"
RESULT77_SHA256="bebbb0619be3e044f5c5f120efc46ff21efbf7122699197a60f108b1d5ca3425"
RESULT77_SIZE="1495"
JOB_ID="215801"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH40_TO80_RESUME_STEP_MONOTONICITY_DIAGNOSTIC_V1_20260828_A38"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A38_A800_TRAIN1_SEQ70"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a38_a800_train1_20260828"
SOURCE_DIRECTORY="${RUN_BASE}/source_A38_a800_train1_seq70"
RUN_DIRECTORY="${RUN_BASE}/runs/${EXPERIMENT_ID}"
COMPLETION_MARKER="${RUN_DIRECTORY}/completion.marker.json"
STATUS_DIRECTORY="${RUN_BASE}/status"
LOG_DIRECTORY="${RUN_BASE}/logs"
LOG_OUT="${LOG_DIRECTORY}/train1-${JOB_ID}.out"
LOG_ERR="${LOG_DIRECTORY}/train1-${JOB_ID}.err"
PREFLIGHT_REPORT="${STATUS_DIRECTORY}/train-preflight-${EXPERIMENT_ID}-${JOB_ID}.json"
GPU_RESOURCE_LOG="${STATUS_DIRECTORY}/train-gpu-resources-${EXPERIMENT_ID}-${JOB_ID}.csv"
CGROUP_RESOURCE_LOG="${STATUS_DIRECTORY}/train-cgroup-resources-${EXPERIMENT_ID}-${JOB_ID}.txt"
TRAIN_LOCK="${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.train.lock"
RUN_OWNER_LOCK="${RUN_DIRECTORY}/.owner.lock"
SUBMISSION_LOCK="${STATUS_DIRECTORY}/locks/${EXECUTION_ATTEMPT_ID}.submission.lock"
SUBMISSION_OWNER="${SUBMISSION_LOCK}/owner.txt"
SOURCE_CHECKPOINT_SHA256="43ed17aaacabdae7e88a80de8567ac3d29d88635d93f701016c757e7f3a407f5"
SOURCE_EPOCH_HISTORY_SHA256="ec64cd575dc76312ef9beaafa22c19fd0d82dec552405ac9c04923aeae2af636"
SOURCE_EPOCH40_PARAMETER_SHA256="448a7c8d21c5eaecb21c375f60d873d6c804ad71376a8e3c95a16e71c3bbc72c"
SOURCE_CONFIGURATION_SHA256="29b4bdb604f2bfbba5c1ab78576a7a21811cd0fdd75060b2dc328ff608f06f2a"
SOURCE_IDENTITY_SHA256="6015e3473a478d96908ab9eda46e582244968480db592e056ebc51d3842c1e7a"
SOURCE_RESULT_SUMMARY_SHA256="e0393fde7084575f89f17e9f64945aafe064c72e3e60f36892376a8965cbb153"
SOURCE_EVIDENCE_ARCHIVE_SHA256="ff788c72a9129cddd4e04a7e6c521864b8d02ff6687e8d8e7fb71655491b103b"
SOURCE_RESULT_SUMMARY="${SOURCE_DIRECTORY}/artifacts/daily_camels_knet_a37_train4_terminal_evidence/job215699/run/result_summary.json"
NORMALIZED_A38_REPLAY_SHA256="8c5ce9fbf5de85435fb8b9d18592753bf139fe66a5b3148bcd0235e87c283884"
ACTIVE_CONFIG_SHA256="05bace055154c9e88124f81434fc76a4e7a0e73d1ef4b8bf2635d7507b5d7d82"
FAILED_ARCHIVE75="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/DAILY_CAMELS_KNET_A38_JOB215801_TERMINAL_EVIDENCE_SEQ75.tar.gz"
FAILED_ARCHIVE76="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/DAILY_CAMELS_KNET_A38_JOB215801_TERMINAL_EVIDENCE_SEQ76.tar.gz"
ARCHIVE="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/DAILY_CAMELS_KNET_A38_JOB215801_TERMINAL_EVIDENCE_SEQ78.tar.gz"

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

reserved_named_path() {
  shopt -s nocasematch
  if [[ "$1" =~ held.?out|reserved.?evaluation|formal.?evaluation ]]; then
    shopt -u nocasematch
    return 0
  fi
  shopt -u nocasematch
  return 1
}

safe_regular_under_run_base() {
  local relative="$1" current="$RUN_BASE" component
  [[ "$relative" != /* && "$relative" != *".."* ]] || return 1
  reserved_named_path "$relative" && return 1
  IFS='/' read -r -a components <<<"$relative"
  for component in "${components[@]}"; do
    [[ -n "$component" ]] || return 1
    current="${current}/${component}"
    [[ ! -L "$current" ]] || return 1
  done
  [[ -f "$current" ]]
}

[[ "${USER-}" == "$EXPECTED_USER" && "$(id -un)" == "$EXPECTED_USER" ]] || {
  echo "fixed-user check failed" >&2
  exit 53
}

require_regular_identity "$RESULT70" "$RESULT70_SHA256" "$RESULT70_SIZE" "sequence 70 submission receipt"
require_regular_identity "$RESULT74" "$RESULT74_SHA256" "$RESULT74_SIZE" "sequence 74 terminal receipt"
require_regular_identity "$RESULT75" "$RESULT75_SHA256" "$RESULT75_SIZE" "sequence 75 failed collection receipt"
require_regular_identity "$RESULT76" "$RESULT76_SHA256" "$RESULT76_SIZE" "sequence 76 failed collection receipt"
require_regular_identity "$RESULT77" "$RESULT77_SHA256" "$RESULT77_SIZE" "sequence 77 GPU coverage diagnostic receipt"
grep -Fxq "SEQ70_A38_A800_TRAIN_SUBMITTED experiment_id=${EXPERIMENT_ID} execution_attempt_id=${EXECUTION_ATTEMPT_ID} training_job_id=${JOB_ID} run_base=${RUN_BASE} archive_sha256=753dbcb1238bdbe9b9b590408fad6ba0838764ba17ff9556c694f58512a7327e outer_manifest_sha256=b4f000430cbb7395150211742b60c70834f5fe186f126835ee9fa5dac9884adf wrapper_sha256=34787a955d06bcde0ede6a4c7c556e50967ce5a34d0b8ba90a77d54a967df7a0 source_checkpoint_sha256=${SOURCE_CHECKPOINT_SHA256} source_recovery_receipt_sha256=017e99754d12badebb0b9ddf4b1b7566c86645e6c0ee306d0409affe41287f85 target_partition=hgpu8 target_node=ngu202 target_gpu=NVIDIA_A800-SXM4-80GB" "$RESULT70" || {
  echo "sequence 70 unique-submission marker differs" >&2
  exit 54
}
grep -Fxq '### exit_code=0' "$RESULT70" || {
  echo "sequence 70 mailbox command did not complete successfully" >&2
  exit 55
}
grep -Fq "${JOB_ID}|daily-knet-a38|sunyiq|hgpu8|COMPLETED|0:0|01:19:11|2026-08-28T13:56:10|2026-08-28T15:15:21|ngu202|" "$RESULT74" || {
  echo "sequence 74 does not prove the expected completed A38 job" >&2
  exit 56
}
grep -Fxq '### exit_code=0' "$RESULT74" || {
  echo "sequence 74 status query did not complete successfully" >&2
  exit 57
}
grep -Fxq 'A37 source replay evidence is absent or symbolic' "$RESULT75" || {
  echo "sequence 75 recoverable collection failure differs" >&2
  exit 57
}
grep -Fxq '### exit_code=63' "$RESULT75" || {
  echo "sequence 75 mailbox exit code differs" >&2
  exit 57
}
grep -Fxq 'GPU resource log does not cover the completed training step' "$RESULT76" || {
  echo "sequence 76 recoverable GPU coverage failure differs" >&2
  exit 57
}
grep -Fxq '### exit_code=66' "$RESULT76" || {
  echo "sequence 76 mailbox exit code differs" >&2
  exit 57
}
grep -Fq '"coverage_seconds":4747.581' "$RESULT77" || {
  echo "sequence 77 GPU duration evidence differs" >&2
  exit 57
}
grep -Fq '"first_minus_step_start_seconds":-26.215' "$RESULT77" || {
  echo "sequence 77 GPU start clock-offset evidence differs" >&2
  exit 57
}
grep -Fq '"step_end_minus_last_seconds":26.634' "$RESULT77" || {
  echo "sequence 77 GPU end clock-offset evidence differs" >&2
  exit 57
}
grep -Fq '"maximum_sample_gap_seconds":1.04' "$RESULT77" || {
  echo "sequence 77 GPU continuity evidence differs" >&2
  exit 57
}
grep -Fxq "SEQ77_A38_GPU_COVERAGE_DIAGNOSTIC_COMPLETE experiment_id=${EXPERIMENT_ID} job_id=${JOB_ID} training_lock_present=0 run_owner_lock_present=0 submission_lock_present=1 failed_archive75_present=0 failed_archive76_present=0" "$RESULT77" || {
  echo "sequence 77 completion marker differs" >&2
  exit 57
}
grep -Fxq '### exit_code=0' "$RESULT77" || {
  echo "sequence 77 mailbox exit code differs" >&2
  exit 57
}
[[ ! -e "$FAILED_ARCHIVE75" && ! -L "$FAILED_ARCHIVE75" ]] || {
  echo "failed sequence 75 archive unexpectedly exists" >&2
  exit 57
}
[[ ! -e "$FAILED_ARCHIVE76" && ! -L "$FAILED_ARCHIVE76" ]] || {
  echo "failed sequence 76 archive unexpectedly exists" >&2
  exit 57
}
[[ ! -e "$ARCHIVE" && ! -L "$ARCHIVE" ]] || {
  echo "sequence 78 terminal evidence archive already exists" >&2
  exit 57
}

ACCOUNTING_LINE="$(
  sacct -n -X -j "$JOB_ID" --parsable2 --format=State,ExitCode,JobName,User,Partition,NodeList |
    awk 'NF {print; exit}'
)"
[[ -n "$ACCOUNTING_LINE" ]] || { echo "A38 accounting is empty" >&2; exit 58; }
IFS='|' read -r STATE EXIT_CODE JOB_NAME ACCOUNTING_USER PARTITION NODELIST _ <<<"$ACCOUNTING_LINE"
STATE="$(printf '%s' "$STATE" | sed 's/[+ ].*$//')"
[[ "$STATE" == "COMPLETED" && "$EXIT_CODE" == "0:0" ]] || {
  echo "A38 terminal state changed: ${STATE:-UNKNOWN}/${EXIT_CODE:-UNKNOWN}" >&2
  exit 58
}
[[ "$JOB_NAME" == "daily-knet-a38" && "$ACCOUNTING_USER" == "$EXPECTED_USER" && "$PARTITION" == "hgpu8" && "$NODELIST" == "ngu202" ]] || {
  echo "A38 Slurm identity differs" >&2
  exit 59
}
STEP_ACCOUNTING="$(sacct -n -j "$JOB_ID" --parsable2 --format=JobIDRaw,State,ExitCode,Start,End,ElapsedRaw)"
BATCH_STEP_LINE="$(awk -F'|' -v id="${JOB_ID}.batch" '$1 == id {print; exit}' <<<"$STEP_ACCOUNTING")"
PREFLIGHT_STEP_LINE="$(awk -F'|' -v id="${JOB_ID}.0" '$1 == id {print; exit}' <<<"$STEP_ACCOUNTING")"
TRAINING_STEP_LINE="$(awk -F'|' -v id="${JOB_ID}.1" '$1 == id {print; exit}' <<<"$STEP_ACCOUNTING")"
[[ -n "$BATCH_STEP_LINE" && -n "$PREFLIGHT_STEP_LINE" && -n "$TRAINING_STEP_LINE" ]] || {
  echo "A38 batch, preflight, or training step accounting is absent" >&2
  exit 59
}
IFS='|' read -r _ BATCH_STEP_STATE BATCH_STEP_EXIT _ <<<"$BATCH_STEP_LINE"
IFS='|' read -r _ PREFLIGHT_STEP_STATE PREFLIGHT_STEP_EXIT _ <<<"$PREFLIGHT_STEP_LINE"
IFS='|' read -r _ TRAINING_STEP_STATE TRAINING_STEP_EXIT TRAINING_STEP_START TRAINING_STEP_END TRAINING_STEP_ELAPSED_SECONDS _ <<<"$TRAINING_STEP_LINE"
BATCH_STEP_STATE="$(printf '%s' "$BATCH_STEP_STATE" | sed 's/[+ ].*$//')"
PREFLIGHT_STEP_STATE="$(printf '%s' "$PREFLIGHT_STEP_STATE" | sed 's/[+ ].*$//')"
TRAINING_STEP_STATE="$(printf '%s' "$TRAINING_STEP_STATE" | sed 's/[+ ].*$//')"
[[ "$BATCH_STEP_STATE" == "COMPLETED" && "$BATCH_STEP_EXIT" == "0:0" ]] || {
  echo "A38 batch step did not complete successfully" >&2
  exit 59
}
[[ "$PREFLIGHT_STEP_STATE" == "COMPLETED" && "$PREFLIGHT_STEP_EXIT" == "0:0" ]] || {
  echo "A38 preflight step did not complete successfully" >&2
  exit 59
}
[[ "$TRAINING_STEP_STATE" == "COMPLETED" && "$TRAINING_STEP_EXIT" == "0:0" ]] || {
  echo "A38 training step did not complete successfully" >&2
  exit 59
}
[[ "$TRAINING_STEP_START" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$ \
  && "$TRAINING_STEP_END" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$ \
  && "$TRAINING_STEP_ELAPSED_SECONDS" =~ ^[0-9]+$ \
  && "$TRAINING_STEP_ELAPSED_SECONDS" -gt 0 ]] || {
  echo "A38 training-step timing evidence differs" >&2
  exit 59
}
set +e
SQUEUE_SNAPSHOT="$(squeue -h -j "$JOB_ID" -o '%A|%j|%P|%T|%R|%b|%Z|%o' 2>&1)"
SQUEUE_EXIT_CODE="$?"
set -e
printf '%s\n' 'SEQ78_A38_SQUEUE_BEGIN' "$SQUEUE_SNAPSHOT" 'SEQ78_A38_SQUEUE_END'
if [[ "$SQUEUE_EXIT_CODE" == "0" && -n "$SQUEUE_SNAPSHOT" ]]; then
  echo "completed A38 job unexpectedly remains active" >&2
  exit 60
fi
if [[ "$SQUEUE_EXIT_CODE" != "0" && "$SQUEUE_SNAPSHOT" != *"Invalid job id specified"* ]]; then
  echo "target-only squeue query failed unexpectedly" >&2
  exit 60
fi

for directory in "$RUN_BASE" "$SOURCE_DIRECTORY" "$STATUS_DIRECTORY" "$LOG_DIRECTORY" "$RUN_DIRECTORY"; do
  [[ -d "$directory" && ! -L "$directory" ]] || {
    echo "required A38 directory is absent or symbolic: $directory" >&2
    exit 61
  }
done
[[ ! -e "$TRAIN_LOCK" && ! -L "$TRAIN_LOCK" ]] || { echo "A38 active training lock remains" >&2; exit 62; }
[[ ! -e "$RUN_OWNER_LOCK" && ! -L "$RUN_OWNER_LOCK" ]] || { echo "A38 run owner lock remains" >&2; exit 62; }
[[ -d "$SUBMISSION_LOCK" && ! -L "$SUBMISSION_LOCK" ]] || { echo "A38 persistent submission lock is absent or symbolic" >&2; exit 63; }
[[ -f "$SUBMISSION_OWNER" && ! -L "$SUBMISSION_OWNER" ]] || { echo "A38 submission owner evidence is absent or symbolic" >&2; exit 63; }
[[ -f "$SOURCE_RESULT_SUMMARY" && ! -L "$SOURCE_RESULT_SUMMARY" ]] || { echo "A37 source result summary is absent or symbolic" >&2; exit 63; }
[[ "$(sha256_file "$SOURCE_RESULT_SUMMARY")" == "$SOURCE_RESULT_SUMMARY_SHA256" ]] || { echo "A37 source result summary SHA-256 differs" >&2; exit 63; }

printf '%s\n' 'SEQ78_A38_SACCT_BEGIN'
sacct -j "$JOB_ID" --units=K --parsable2 \
  --format=JobIDRaw,JobName,User,Partition,State,ExitCode,Elapsed,Start,End,NodeList,AllocCPUS,ReqMem,AllocTRES,ReqTRES,MaxRSS,MaxVMSize,AveRSS
printf '%s\n' 'SEQ78_A38_SACCT_END'

RESERVED_PATH_COUNT=0
SAFE_FILE_COUNT=0
inventory_directory() {
  local directory="$1" path file_size file_sha256
  [[ -d "$directory" && ! -L "$directory" && -r "$directory" && -x "$directory" ]] || {
    echo "inventory directory is absent, symbolic, or unreadable: $directory" >&2
    return 64
  }
  shopt -s nullglob dotglob
  for path in "$directory"/*; do
    if [[ "$path" == "${STATUS_DIRECTORY}/cache" || "$path" == "${STATUS_DIRECTORY}/tmp" ]]; then
      printf '%s|RUNTIME_CACHE_DIRECTORY_SKIPPED\n' "$path"
    elif reserved_named_path "$path"; then
      RESERVED_PATH_COUNT=$((RESERVED_PATH_COUNT + 1))
      printf '%s|RESERVED_NAMED_PATH_SKIPPED\n' "$path"
    elif [[ -L "$path" ]]; then
      printf '%s|SYMBOLIC_LINK_SKIPPED\n' "$path"
    elif [[ -d "$path" ]]; then
      inventory_directory "$path"
    elif [[ -f "$path" ]]; then
      file_size="$(stat -c '%s' "$path")"
      file_sha256="$(sha256_file "$path")"
      SAFE_FILE_COUNT=$((SAFE_FILE_COUNT + 1))
      printf '%s|size=%s|sha256=%s\n' "$path" "$file_size" "$file_sha256"
    else
      printf '%s|NON_REGULAR_PATH_SKIPPED\n' "$path"
    fi
  done
}

printf '%s\n' 'SEQ78_A38_FILE_INVENTORY_BEGIN'
inventory_directory "$LOG_DIRECTORY"
inventory_directory "$STATUS_DIRECTORY"
inventory_directory "$RUN_DIRECTORY"
printf '%s\n' 'SEQ78_A38_FILE_INVENTORY_END'
[[ "$RESERVED_PATH_COUNT" == "0" ]] || { echo "reserved-named runtime path was present" >&2; exit 65; }

for path in "$LOG_OUT" "$LOG_ERR" "$PREFLIGHT_REPORT" "$CGROUP_RESOURCE_LOG" \
  "${STATUS_DIRECTORY}/seq70_offline_train_bundle_verification.json" \
  "${STATUS_DIRECTORY}/seq70_a800_train_submission_identity.txt" \
  "${STATUS_DIRECTORY}/seq70_a800_training_job_id.txt" \
  "${STATUS_DIRECTORY}/seq70_a800_training_submitted_time_utc.txt" \
  "$SUBMISSION_OWNER" "${RUN_DIRECTORY}/completion.marker.json" \
  "${RUN_DIRECTORY}/experiment_identity.json" "${RUN_DIRECTORY}/owner_evidence.json" \
  "${RUN_DIRECTORY}/preflight.json"; do
  if [[ -f "$path" && ! -L "$path" ]] && ! reserved_named_path "$path"; then
    printf 'SEQ78_A38_CONTENT_BEGIN path=%s size=%s sha256=%s\n' "$path" "$(stat -c '%s' "$path")" "$(sha256_file "$path")"
    sed -n '1,30000p' "$path"
    printf 'SEQ78_A38_CONTENT_END path=%s\n' "$path"
  else
    printf 'SEQ78_A38_CONTENT_ABSENT_OR_UNSAFE path=%s\n' "$path"
  fi
done

[[ -f "$GPU_RESOURCE_LOG" && ! -L "$GPU_RESOURCE_LOG" ]] || { echo "A38 GPU resource log is absent or symbolic" >&2; exit 66; }
[[ -f "$COMPLETION_MARKER" && ! -L "$COMPLETION_MARKER" ]] || { echo "A38 completion marker is absent or symbolic" >&2; exit 66; }
printf '%s\n' 'SEQ78_A38_GPU_RESOURCE_SUMMARY_BEGIN'
GPU_RESOURCE_SUMMARY="$(python - "$GPU_RESOURCE_LOG" "$COMPLETION_MARKER" "$TRAINING_STEP_START" "$TRAINING_STEP_END" "$TRAINING_STEP_ELAPSED_SECONDS" "$EXPERIMENT_ID" <<'GPU_PY'
import csv
import datetime as dt
import json
import math
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
completion_path = Path(sys.argv[2])
step_start = dt.datetime.strptime(sys.argv[3], "%Y-%m-%dT%H:%M:%S")
step_end = dt.datetime.strptime(sys.argv[4], "%Y-%m-%dT%H:%M:%S")
elapsed_seconds = int(sys.argv[5])
experiment_id = sys.argv[6]
rows = []
with path.open("r", encoding="utf-8", newline="") as stream:
    for line_number, row in enumerate(csv.reader(stream), start=1):
        if len(row) != 7:
            raise SystemExit(f"GPU row {line_number} does not have seven fields")
        timestamp_text, uuid, name, total_text, used_text, free_text, utilization_text = (
            value.strip() for value in row
        )
        try:
            timestamp = dt.datetime.strptime(timestamp_text, "%Y/%m/%d %H:%M:%S.%f")
            total = float(total_text)
            used = float(used_text)
            free = float(free_text)
            utilization = float(utilization_text)
        except (TypeError, ValueError) as error:
            raise SystemExit(f"GPU row {line_number} is malformed: {error}") from error
        if (
            not re.fullmatch(r"GPU-[0-9a-fA-F-]+", uuid)
            or name != "NVIDIA A800-SXM4-80GB"
            or not all(math.isfinite(value) for value in (total, used, free, utilization))
            or total <= 0.0
            or used < 0.0
            or free < 0.0
            or used > total
            or free > total
            or not 0.0 <= utilization <= 100.0
        ):
            raise SystemExit(f"GPU row {line_number} has invalid identity or resources")
        rows.append((timestamp, uuid, name, total, used, free, utilization))
minimum_rows = max(60, elapsed_seconds // 10)
if len(rows) < minimum_rows:
    raise SystemExit("GPU resource log is too sparse for the completed training step")
if any(current[0] <= previous[0] for previous, current in zip(rows, rows[1:])):
    raise SystemExit("GPU resource timestamps are not strictly increasing")
sample_gaps_seconds = [
    (current[0] - previous[0]).total_seconds()
    for previous, current in zip(rows, rows[1:])
]
if not sample_gaps_seconds or max(sample_gaps_seconds) > 10.0:
    raise SystemExit("GPU resource log contains an uncovered interval longer than ten seconds")
if len({row[1] for row in rows}) != 1 or len({row[2] for row in rows}) != 1 or len({row[3] for row in rows}) != 1:
    raise SystemExit("GPU identity or total memory changed during training")
coverage_seconds = (rows[-1][0] - rows[0][0]).total_seconds()
start_clock_offset_seconds = (rows[0][0] - step_start).total_seconds()
end_clock_offset_seconds = (rows[-1][0] - step_end).total_seconds()
clock_offset_drift_seconds = abs(end_clock_offset_seconds - start_clock_offset_seconds)
elapsed_coverage_difference_seconds = abs(coverage_seconds - elapsed_seconds)
completion = json.loads(completion_path.read_text(encoding="utf-8"))
if completion.get("experiment_id") != experiment_id or completion.get("status") != "TRAINING_COMPLETE_GATE_PASS":
    raise SystemExit("GPU coverage completion marker binding differs")
completed_at = dt.datetime.fromisoformat(completion["completed_at_utc"].replace("Z", "+00:00"))
completed_at_cluster = completed_at.astimezone(dt.timezone(dt.timedelta(hours=8))).replace(tzinfo=None)
last_minus_completion_marker_seconds = (rows[-1][0] - completed_at_cluster).total_seconds()
if (
    elapsed_coverage_difference_seconds > 2.0
    or clock_offset_drift_seconds > 2.0
    or last_minus_completion_marker_seconds < 0.0
):
    raise SystemExit("GPU resource log duration or stable-clock-offset coverage differs")
print(
    "rows={}|first_timestamp={}|last_timestamp={}|coverage_seconds={:.3f}|max_sample_gap_seconds={:.3f}|"
    "elapsed_coverage_difference_seconds={:.3f}|start_clock_offset_seconds={:.3f}|"
    "end_clock_offset_seconds={:.3f}|clock_offset_drift_seconds={:.3f}|"
    "last_minus_completion_marker_seconds={:.3f}|completion_marker_cluster_time={}|"
    "gpu_uuid={}|gpu_name={}|total_mib={:.0f}|max_used_mib={:.0f}|"
    "min_free_mib={:.0f}|max_utilization_percent={:.0f}".format(
        len(rows),
        rows[0][0].isoformat(),
        rows[-1][0].isoformat(),
        coverage_seconds,
        max(sample_gaps_seconds),
        elapsed_coverage_difference_seconds,
        start_clock_offset_seconds,
        end_clock_offset_seconds,
        clock_offset_drift_seconds,
        last_minus_completion_marker_seconds,
        completed_at_cluster.isoformat(),
        rows[0][1],
        rows[0][2],
        rows[0][3],
        max(row[4] for row in rows),
        min(row[5] for row in rows),
        max(row[6] for row in rows),
    )
)
GPU_PY
)" || { echo "A38 GPU resource evidence differs" >&2; exit 66; }
printf '%s\n' "$GPU_RESOURCE_SUMMARY"
printf '%s\n' 'SEQ78_A38_GPU_RESOURCE_SUMMARY_END'

[[ -f "$CGROUP_RESOURCE_LOG" && ! -L "$CGROUP_RESOURCE_LOG" ]] || { echo "A38 cgroup resource log is absent or symbolic" >&2; exit 66; }
grep -Fxq "slurm_job_id=${JOB_ID}" "$CGROUP_RESOURCE_LOG" || { echo "A38 cgroup job identity differs" >&2; exit 66; }
CGROUP_MEMORY_PEAK_BYTES="$(awk -F= '$1 == "current_memory_peak" && $2 ~ /^[0-9]+$/ {print $2; exit}' "$CGROUP_RESOURCE_LOG")"
if [[ -z "$CGROUP_MEMORY_PEAK_BYTES" ]]; then
  CGROUP_MEMORY_PEAK_BYTES="$(awk -F= '$1 == "parent_memory_peak" && $2 ~ /^[0-9]+$/ {print $2; exit}' "$CGROUP_RESOURCE_LOG")"
fi
[[ -n "$CGROUP_MEMORY_PEAK_BYTES" && "$CGROUP_MEMORY_PEAK_BYTES" -gt 0 ]] || { echo "A38 numeric cgroup memory peak is absent" >&2; exit 66; }
printf 'SEQ78_A38_CGROUP_RESOURCE_SUMMARY slurm_job_id=%s memory_peak_bytes=%s\n' "$JOB_ID" "$CGROUP_MEMORY_PEAK_BYTES"

python - "$RUN_DIRECTORY" "$PREFLIGHT_REPORT" "$SOURCE_RESULT_SUMMARY" "$EXPERIMENT_ID" "$SOURCE_CHECKPOINT_SHA256" "$SOURCE_EPOCH_HISTORY_SHA256" "$SOURCE_EPOCH40_PARAMETER_SHA256" "$SOURCE_CONFIGURATION_SHA256" "$SOURCE_IDENTITY_SHA256" "$SOURCE_RESULT_SUMMARY_SHA256" "$SOURCE_EVIDENCE_ARCHIVE_SHA256" "$ACTIVE_CONFIG_SHA256" "$JOB_ID" "$NORMALIZED_A38_REPLAY_SHA256" <<'PY'
import copy
import hashlib
import json
import math
import os
from pathlib import Path, PurePosixPath
import re
import sys

root = Path(sys.argv[1])
preflight_path = Path(sys.argv[2])
source_summary_path = Path(sys.argv[3])
experiment_id = sys.argv[4]
source_checkpoint_sha = sys.argv[5]
source_history_sha = sys.argv[6]
source_parameter_sha = sys.argv[7]
source_configuration_sha = sys.argv[8]
source_identity_sha = sys.argv[9]
source_summary_sha = sys.argv[10]
source_archive_sha = sys.argv[11]
active_config_sha = sys.argv[12]
job_id = sys.argv[13]
expected_normalized_replay_sha = sys.argv[14]

def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

def canonical_json_bytes(value):
    return (
        json.dumps(
            value,
            ensure_ascii=False,
            sort_keys=True,
            separators=(",", ":"),
            allow_nan=False,
        ).encode("utf-8")
        + b"\n"
    )

def finite_float(value, label, *, nonnegative=False):
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise SystemExit(f"{label} is not numeric")
    result = float(value)
    if not math.isfinite(result) or (nonnegative and result < 0.0):
        raise SystemExit(f"{label} is not finite and valid")
    return result

def exact_int(value, label, *, minimum=None):
    if type(value) is not int:
        raise SystemExit(f"{label} is not an exact JSON integer")
    if minimum is not None and value < minimum:
        raise SystemExit(f"{label} is below its minimum")
    return value

def load(name):
    path = root / name
    if not path.is_file() or path.is_symlink():
        raise SystemExit(f"required safe run file differs: {name}")
    return json.loads(path.read_text(encoding="utf-8"))

completion = load("completion.marker.json")
summary = load("result_summary.json")
history = load("epoch_history.json")
identity = load("experiment_identity.json")
manifest = load("manifest.sha256.json")
replay_evidence = load("replay_evidence.json")
preflight = json.loads(preflight_path.read_text(encoding="utf-8"))
if not source_summary_path.is_file() or source_summary_path.is_symlink() or sha(source_summary_path) != source_summary_sha:
    raise SystemExit("registered A37 source result summary differs")
source_summary = json.loads(source_summary_path.read_text(encoding="utf-8"))
files = manifest.get("files")
if not isinstance(files, dict) or not files:
    raise SystemExit("run manifest file map is absent")
reserved = re.compile(r"held.?out|reserved.?evaluation|formal.?evaluation", re.I)
root_resolved = root.resolve()
for relative, expected in sorted(files.items()):
    pure = PurePosixPath(relative)
    if pure.is_absolute() or ".." in pure.parts or reserved.search(relative):
        raise SystemExit(f"unsafe manifest member: {relative}")
    path = root / Path(*pure.parts)
    resolved = path.resolve()
    if not path.is_file() or path.is_symlink() or not str(resolved).startswith(str(root_resolved) + os.sep):
        raise SystemExit(f"manifest member is absent or unsafe: {relative}")
    if sha(path) != expected:
        raise SystemExit(f"manifest member hash differs: {relative}")

actual_identity_sha = sha(root / "experiment_identity.json")
if (
    completion.get("experiment_id") != experiment_id
    or completion.get("status") != "TRAINING_COMPLETE_GATE_PASS"
    or completion.get("phase") != "train"
    or completion.get("summary_sha256") != sha(root / "result_summary.json")
    or completion.get("identity_sha256") != sha(root / "experiment_identity.json")
    or completion.get("manifest_sha256") != sha(root / "manifest.sha256.json")
    or manifest.get("experiment_id") != experiment_id
    or manifest.get("identity_sha256") != completion.get("identity_sha256")
    or summary.get("identity_sha256") != actual_identity_sha
    or completion.get("identity_sha256") != actual_identity_sha
    or identity.get("experiment_id") != experiment_id
    or identity.get("configuration_sha256") != active_config_sha
    or identity.get("phase") != "train"
):
    raise SystemExit("completion, identity, or manifest binding differs")

normalized_replay = copy.deepcopy(replay_evidence)
if normalized_replay.get("identity_sha256") != actual_identity_sha:
    raise SystemExit("replay evidence identity binding differs before normalization")
normalized_replay["identity_sha256"] = "<NORMALIZED_ACTUAL_IDENTITY_SHA256>"
actual_normalized_replay_sha = hashlib.sha256(canonical_json_bytes(normalized_replay)).hexdigest()
if actual_normalized_replay_sha != expected_normalized_replay_sha:
    raise SystemExit("complete normalized A38 UKF and zero-gain replay evidence differs")

replay_windows = replay_evidence.get("windows", {})
if (
    summary.get("schema_version") != "daily_camels_ukf_knet_parity_result_v1"
    or replay_evidence.get("schema_version") != "daily_camels_ukf_knet_parity_replay_v1"
    or summary.get("artifacts", {}).get("replay_evidence") != "replay_evidence.json"
    or replay_evidence.get("experiment_id") != experiment_id
    or replay_evidence.get("identity_sha256") != summary.get("identity_sha256")
    or replay_evidence.get("diagnostic_limitation") != summary.get("diagnostic_limitation")
    or replay_evidence.get("scientific_claim_allowed") != summary.get("scientific_claim_allowed")
    or set(replay_windows) != {"diagnostic", "recovery"}
):
    raise SystemExit("UKF and zero-gain replay evidence binding differs")
for window_name, window in replay_windows.items():
    ukf = window.get("ukf", {})
    zero_gain = window.get("zero_gain_knet", {})
    if (
        window.get("identical_ukf_knet_geometry") is not True
        or ukf.get("geometry") != zero_gain.get("geometry")
        or zero_gain.get("maximum_open_loop_difference") != 0.0
    ):
        raise SystemExit(f"{window_name} UKF and zero-gain replay geometry differs")
recovery_window = replay_windows["recovery"]
expected_recovery_nse = {
    "1": 0.9742508181649119,
    "2": 0.9557071265978458,
    "3": 0.9373297632941142,
}
if (
    summary.get("ukf_recovery_checkpoint_objective_728")
    != recovery_window["ukf"].get("checkpoint_objective_without_warmup")
    or summary.get("ukf_recovery_nse_by_lead_712")
    != recovery_window["ukf"].get("nse_by_lead_after_warmup")
    or summary.get("zero_gain_maximum_open_loop_difference")
    != recovery_window["zero_gain_knet"].get("maximum_open_loop_difference")
    or summary.get("zero_gain_maximum_open_loop_difference") != 0.0
    or abs(finite_float(recovery_window["ukf"].get("checkpoint_objective_without_warmup"), "UKF recovery checkpoint objective", nonnegative=True) - 0.05968865108183612) > 1.0e-12
    or any(
        abs(finite_float(recovery_window["ukf"].get("nse_by_lead_after_warmup", {}).get(key), f"UKF recovery lead-{key} NSE") - expected) > 1.0e-12
        for key, expected in expected_recovery_nse.items()
    )
    or recovery_window["ukf"].get("target_count_by_lead_after_warmup") != {str(lead): 712 for lead in (1, 2, 3)}
    or recovery_window["ukf"].get("target_count_by_lead_without_warmup") != {str(lead): 728 for lead in (1, 2, 3)}
    or replay_windows["diagnostic"]["ukf"].get("target_count_by_lead_after_warmup") != {str(lead): 109 for lead in (1, 2, 3)}
    or replay_windows["diagnostic"]["ukf"].get("target_count_by_lead_without_warmup") != {str(lead): 125 for lead in (1, 2, 3)}
):
    raise SystemExit("reported UKF recovery or zero-gain replay metrics differ")

continuation_identity = identity.get("continuation", {})
if (
    continuation_identity.get("checkpoint_sha256") != source_checkpoint_sha
    or continuation_identity.get("source_epoch_history_sha256") != source_history_sha
    or continuation_identity.get("parameter_sha256") != source_parameter_sha
    or continuation_identity.get("source_configuration_sha256") != source_configuration_sha
    or continuation_identity.get("source_identity_sha256") != source_identity_sha
    or continuation_identity.get("source_result_summary_sha256") != source_summary_sha
    or continuation_identity.get("source_evidence_archive_sha256") != source_archive_sha
    or continuation_identity.get("completed_epoch") != 40
    or continuation_identity.get("optimizer_steps") != 40
    or continuation_identity.get("sampled_forecast_events") != 306000
    or files.get("checkpoints/epoch_040.pt") != source_checkpoint_sha
):
    raise SystemExit("source epoch-40 continuation identity differs")

training = summary.get("training", {})
continuation = training.get("continuation", {})
access = summary.get("access_ledger", {})
if (
    summary.get("experiment_id") != experiment_id
    or summary.get("status") != "TRAINING_COMPLETE_GATE_PASS"
    or summary.get("execution_role") != "train"
    or summary.get("phase") != "train"
    or summary.get("device") != "cuda"
    or summary.get("portability_diagnostic_only") is not False
    or summary.get("scientific_claim_allowed") is not True
    or training.get("status") != "TRAINING_COMPLETE_GATE_PASS"
    or training.get("gate_passed") is not True
    or training.get("failed_gates") != []
    or exact_int(training.get("optimizer_steps"), "training optimizer steps", minimum=0) != 80
    or exact_int(training.get("sampled_forecast_events"), "training forecast events", minimum=0) != 612000
    or exact_int(training.get("epoch_checkpoint_count"), "epoch checkpoint count", minimum=0) != 41
    or exact_int(training.get("fixed_window_prediction_artifact_count"), "prediction artifact count", minimum=0) != 40
    or exact_int(training.get("cumulative_history_epoch_count"), "history epoch count", minimum=0) != 81
    or continuation.get("enabled") is not True
    or continuation.get("checkpoint_sha256") != source_checkpoint_sha
    or continuation.get("source_epoch_history_sha256") != source_history_sha
    or continuation.get("parameter_sha256") != source_parameter_sha
    or continuation.get("source_configuration_sha256") != source_configuration_sha
    or continuation.get("source_identity_sha256") != source_identity_sha
    or continuation.get("source_result_summary_sha256") != source_summary_sha
    or continuation.get("source_evidence_archive_sha256") != source_archive_sha
    or exact_int(continuation.get("completed_epoch"), "source completed epoch", minimum=0) != 40
    or exact_int(continuation.get("optimizer_steps"), "source optimizer steps", minimum=0) != 40
    or exact_int(continuation.get("sampled_forecast_events"), "source forecast events", minimum=0) != 306000
    or exact_int(continuation.get("source_history_epoch_count"), "source history epoch count", minimum=0) != 41
    or exact_int(continuation.get("imported_epoch_checkpoint_count"), "imported checkpoint count", minimum=0) != 1
    or exact_int(continuation.get("new_epoch_count"), "new epoch count", minimum=0) != 40
    or exact_int(continuation.get("new_optimizer_steps"), "new optimizer steps", minimum=0) != 40
    or exact_int(continuation.get("new_sampled_forecast_events"), "new forecast events", minimum=0) != 306000
    or continuation.get("post_resume_improvement_gate_passed") is not True
    or not 41 <= int(continuation.get("post_resume_best_epoch", -1)) <= 80
):
    raise SystemExit("training completion counts or post-resume science gate differ")

if len(history) != 81 or any(type(row.get("epoch")) is not int for row in history) or [row.get("epoch") for row in history] != list(range(81)):
    raise SystemExit("epoch history is not exactly epoch 0 through 80")
if any(type(row.get("optimizer_steps")) is not int for row in history) or [row.get("optimizer_steps") for row in history] != list(range(81)):
    raise SystemExit("optimizer-step history is not exactly 0 through 80")
if any(type(row.get("sampled_forecast_events")) is not int for row in history) or [row.get("sampled_forecast_events") for row in history] != [7650 * value for value in range(81)]:
    raise SystemExit("forecast-event history does not total 612000")

actual_source_history_sha = hashlib.sha256(canonical_json_bytes(history[:41])).hexdigest()
if (
    actual_source_history_sha != source_history_sha
    or history[40].get("parameter_sha256") != source_parameter_sha
    or continuation_identity.get("source_epoch_history_sha256") != actual_source_history_sha
    or continuation.get("source_epoch_history_sha256") != actual_source_history_sha
):
    raise SystemExit("epoch-0-through-40 source history or epoch-40 parameter binding differs")

events_path = root / "events.jsonl"
if not events_path.is_file() or events_path.is_symlink():
    raise SystemExit("event ledger is absent or unsafe")
events = [json.loads(line) for line in events_path.read_text(encoding="utf-8").splitlines() if line.strip()]
resume_events = [event for event in events if event.get("event_type") == "resume_checkpoint_loaded"]
if len(resume_events) != 1:
    raise SystemExit("resume checkpoint event count differs")
resume_event = resume_events[0]
if (
    resume_event.get("source_experiment_id") != continuation_identity.get("source_experiment_id")
    or resume_event.get("source_identity_sha256") != source_identity_sha
    or resume_event.get("source_checkpoint_sha256") != source_checkpoint_sha
    or resume_event.get("source_epoch_history_sha256") != source_history_sha
    or resume_event.get("completed_epoch") != 40
    or resume_event.get("optimizer_steps") != 40
    or resume_event.get("sampled_forecast_events") != 306000
    or resume_event.get("parameter_sha256") != source_parameter_sha
    or resume_event.get("reserved_evaluation_operations") != 0
):
    raise SystemExit("resume checkpoint event binding differs")

objective_key = "checkpoint_selection_objective_728_origins_without_warmup"
history_objectives = [
    finite_float(row.get(objective_key), f"epoch-{epoch} checkpoint objective", nonnegative=True)
    for epoch, row in enumerate(history)
]
source_objective = history_objectives[40]
post_best_epoch = min(range(41, 81), key=lambda epoch: history_objectives[epoch])
post_best_objective = history_objectives[post_best_epoch]
post_improvement = source_objective - post_best_objective
if (
    finite_float(continuation.get("source_checkpoint_objective"), "declared source checkpoint objective", nonnegative=True) != source_objective
    or continuation.get("post_resume_best_epoch") != post_best_epoch
    or finite_float(continuation.get("post_resume_best_checkpoint_objective"), "declared post-resume best objective", nonnegative=True) != post_best_objective
    or finite_float(continuation.get("post_resume_checkpoint_objective_improvement"), "declared post-resume improvement") != post_improvement
    or post_improvement < 1.0e-6
):
    raise SystemExit("independently recomputed post-resume science gate differs")

global_best_epoch = min(range(81), key=lambda epoch: history_objectives[epoch])
global_best_objective = history_objectives[global_best_epoch]

best_epoch = exact_int(training.get("best_epoch"), "best epoch", minimum=0)
if not 41 <= best_epoch <= 80 or best_epoch != global_best_epoch:
    raise SystemExit("best epoch is not after the continuation boundary")
best_row = history[best_epoch]
best_objective = finite_float(training.get("best_checkpoint_objective"), "declared best checkpoint objective", nonnegative=True)
if best_objective != global_best_objective or best_objective != post_best_objective:
    raise SystemExit("best checkpoint objective differs from history")
if training.get("best_nse_by_lead") != best_row.get("nse_by_lead_after_warmup"):
    raise SystemExit("best future 1-3 day NSE differs from history")
if training.get("best_target_count_by_lead_after_warmup") != {"1": 712, "2": 712, "3": 712}:
    raise SystemExit("best development target counts after warmup differ")
if training.get("best_target_count_by_lead_without_warmup") != {"1": 728, "2": 728, "3": 728}:
    raise SystemExit("best development target counts without warmup differ")
best_nse = {
    str(lead): finite_float(training["best_nse_by_lead"].get(str(lead)), f"best lead-{lead} NSE")
    for lead in (1, 2, 3)
}
best_mse = {
    str(lead): finite_float(best_row["mse_by_lead_after_warmup"].get(str(lead)), f"best lead-{lead} MSE", nonnegative=True)
    for lead in (1, 2, 3)
}
if any(value <= 0.6 for value in best_nse.values()):
    raise SystemExit("best future 1-3 day NSE gate differs")
overall_improvement = history_objectives[0] - global_best_objective
if (
    overall_improvement <= 1.0e-6
    or finite_float(training.get("objective_improvement"), "overall checkpoint objective improvement") != overall_improvement
    or training.get("parameter_hash_changed") is not True
    or training.get("best_parameter_sha256") != best_row.get("parameter_sha256")
    or training.get("last_parameter_sha256") != history[-1].get("parameter_sha256")
    or training.get("best_parameter_sha256") == training.get("epoch_zero_parameter_sha256")
    or training.get("best_better_than_strict_zero_gain_each_lead") is not True
):
    raise SystemExit("independently recomputed global training gate differs")
zero_comparison = training.get("best_vs_strict_zero_gain", {})
by_lead_zero = zero_comparison.get("by_lead_712", {})
strict_zero_recovery = replay_windows["recovery"]["zero_gain_knet"]
strict_zero_checkpoint_objective = finite_float(
    strict_zero_recovery.get("checkpoint_objective_without_warmup"),
    "strict-zero checkpoint objective",
    nonnegative=True,
)
if (
    zero_comparison.get("candidate_better_than_strict_zero_gain_each_lead") is not True
    or finite_float(zero_comparison.get("strict_zero_gain_checkpoint_objective_728"), "declared strict-zero checkpoint objective", nonnegative=True) != strict_zero_checkpoint_objective
    or finite_float(zero_comparison.get("candidate_checkpoint_objective_728"), "declared candidate checkpoint objective", nonnegative=True) != best_objective
    or finite_float(zero_comparison.get("checkpoint_objective_improvement_zero_minus_candidate"), "declared checkpoint objective improvement") != strict_zero_checkpoint_objective - best_objective
    or strict_zero_checkpoint_objective - best_objective <= 0.0
):
    raise SystemExit("best checkpoint is not better than strict zero gain on every lead")
for lead in (1, 2, 3):
    key = str(lead)
    comparison = by_lead_zero.get(key, {})
    strict_zero_mse = finite_float(
        strict_zero_recovery.get("mse_by_lead_after_warmup", {}).get(key),
        f"lead-{lead} strict-zero MSE",
        nonnegative=True,
    )
    strict_zero_nse = finite_float(
        strict_zero_recovery.get("nse_by_lead_after_warmup", {}).get(key),
        f"lead-{lead} strict-zero NSE",
    )
    mse_improvement = strict_zero_mse - best_mse[key]
    nse_improvement = best_nse[key] - strict_zero_nse
    if (
        comparison.get("candidate_better") is not (mse_improvement > 0.0 and nse_improvement > 0.0)
        or comparison.get("candidate_better") is not True
        or finite_float(comparison.get("strict_zero_gain_mse"), f"lead-{lead} declared strict-zero MSE", nonnegative=True) != strict_zero_mse
        or finite_float(comparison.get("strict_zero_gain_nse"), f"lead-{lead} declared strict-zero NSE") != strict_zero_nse
        or finite_float(comparison.get("candidate_mse"), f"lead-{lead} candidate MSE", nonnegative=True) != best_mse[key]
        or finite_float(comparison.get("candidate_nse"), f"lead-{lead} candidate NSE") != best_nse[key]
        or finite_float(comparison.get("mse_improvement_zero_minus_candidate"), f"lead-{lead} MSE improvement") != mse_improvement
        or finite_float(comparison.get("nse_delta_candidate_minus_zero"), f"lead-{lead} NSE improvement") != nse_improvement
        or mse_improvement <= 0.0
        or nse_improvement <= 0.0
    ):
        raise SystemExit("best checkpoint strict-zero-gain comparison differs")
if files.get("checkpoints/best.pt") != training.get("best_checkpoint_sha256"):
    raise SystemExit("best checkpoint hash differs")
if files.get("checkpoints/last.pt") != training.get("last_checkpoint_sha256"):
    raise SystemExit("last checkpoint hash differs")
if files.get("checkpoints/epoch_080.pt") != training.get("last_checkpoint_sha256"):
    raise SystemExit("epoch-80 checkpoint hash differs")

ledgers = {
    "summary": access,
    "training": training.get("access_ledger", {}),
    "replay": replay_evidence.get("access_ledger", {}),
}
if ledgers["summary"] != ledgers["training"] or ledgers["summary"] != ledgers["replay"]:
    raise SystemExit("access ledgers differ across terminal artifacts")
required_zero_access = {
    "evaluation_array_reads": 0,
    "evaluation_prediction_count": 0,
    "evaluation_metric_count": 0,
    "evaluation_output_count": 0,
}
for ledger_name, ledger in ledgers.items():
    if not isinstance(ledger, dict):
        raise SystemExit(f"{ledger_name} access ledger is not an object")
    if any(type(ledger.get(key)) is not int or ledger.get(key) != value for key, value in required_zero_access.items()):
        raise SystemExit(f"{ledger_name} access ledger lacks explicit zero evaluation counts")
    for key, value in ledger.items():
        if "evaluation" in key and (type(value) is not int or value != 0):
            raise SystemExit(f"reserved evaluation access is nonzero in {ledger_name}: {key}")
replays = training.get("same_segment_step_replays")
if not isinstance(replays, list) or len(replays) != 80:
    raise SystemExit("same-batch diagnostic replay count differs")
source_replays_expected = source_summary.get("training", {}).get("same_segment_step_replays")
if (
    not isinstance(source_replays_expected, list)
    or len(source_replays_expected) != 40
    or replays[:40] != source_replays_expected
):
    raise SystemExit("imported A37 same-batch replay evidence changed")
plan = training.get("training_segment_plan", {})
plan_starts = plan.get("fixed_training_segment_start_indices")
expected_plan_starts = [
    0, 100, 201, 301, 401, 501, 602, 702, 802, 903,
    1003, 1103, 1204, 1304, 1404, 1504, 1605, 1705,
    1805, 1906, 2006, 2106, 2206, 2307, 2407,
]
if (
    exact_int(plan.get("training_epochs"), "plan training epochs", minimum=0) != 80
    or exact_int(plan.get("steps_per_epoch"), "plan steps per epoch", minimum=0) != 1
    or exact_int(plan.get("expected_optimizer_step_count"), "plan optimizer steps", minimum=0) != 80
    or exact_int(plan.get("total_candidate_forecast_target_event_count_all_epochs"), "plan forecast events", minimum=0) != 612000
    or exact_int(plan.get("candidate_forecast_target_event_count_all_leads"), "plan step forecast events", minimum=0) != 7650
    or exact_int(plan.get("segments_per_optimizer_step"), "plan segments per step", minimum=0) != 25
    or exact_int(plan.get("scored_issue_count_per_segment"), "plan scored issues per segment", minimum=0) != 102
    or exact_int(plan.get("segment_days"), "plan segment days", minimum=0) != 150
    or exact_int(plan.get("filter_warmup_days"), "plan warmup days", minimum=0) != 45
    or exact_int(plan.get("maximum_lead_days"), "plan maximum lead", minimum=0) != 3
    or plan.get("complete_eligible_issue_coverage") is not True
    or plan.get("uncovered_issue_count") != 0
    or not isinstance(plan_starts, list)
    or any(type(value) is not int for value in plan_starts)
    or plan_starts != expected_plan_starts
    or plan.get("fixed_training_segment_start_indices_sha256")
    != "e4e47bf9dd10ce5b1c287f4a0ddfc14bfb00cc93b71013037b09985e2902bbe6"
    or plan.get("fixed_training_segment_start_indices_sha256")
    != hashlib.sha256(canonical_json_bytes(expected_plan_starts)).hexdigest()
    or training.get("same_segment_post_step_replay_count") != 80
    or training.get("same_segment_every_optimizer_step_strictly_decreased") is not False
    or "same_segment_post_step_improvement" in training.get("failed_gates", [])
):
    raise SystemExit("frozen full-training-coverage plan differs")
source_segment_rows = source_replays_expected[0].get("training_segment_replays")
if not isinstance(source_segment_rows, list) or len(source_segment_rows) != 25:
    raise SystemExit("registered source segment date evidence differs")
frozen_segment_dates_by_start = {
    row.get("segment_start_index_global_inclusive"): (
        row.get("segment_first_date"),
        row.get("segment_last_date"),
        row.get("scored_issue_first_date"),
        row.get("scored_issue_last_date"),
    )
    for row in source_segment_rows
}
if set(frozen_segment_dates_by_start) != set(expected_plan_starts) or any(
    not all(isinstance(value, str) and value for value in dates)
    for dates in frozen_segment_dates_by_start.values()
):
    raise SystemExit("registered source segment dates are absent or incomplete")
flattened_history_replays = []
for epoch, row in enumerate(history):
    row_replays = row.get("same_segment_step_replays")
    expected_count = 0 if epoch == 0 else 1
    if not isinstance(row_replays, list) or len(row_replays) != expected_count:
        raise SystemExit("per-epoch same-batch replay count differs")
    flattened_history_replays.extend(row_replays)
if flattened_history_replays != replays:
    raise SystemExit("summary same-batch replays differ from epoch history")
strict_count = 0
not_strict = []
max_increase = 0.0
reference_segment_starts = None
reference_geometry_sha = None
expected_mask_sha = hashlib.sha256(bytes([1]) * 102).hexdigest()
for expected_step, replay in enumerate(replays, start=1):
    if (
        type(replay.get("optimizer_step")) is not int
        or replay.get("optimizer_step") != expected_step
        or replay.get("reserved_evaluation_values_used") != 0
        or replay.get("identical_target_geometry_before_after") is not True
        or replay.get("after_step_was_recomputed") is not True
        or replay.get("after_step_recomputed_under_no_grad") is not True
        or type(replay.get("training_segment_count")) is not int
        or replay.get("training_segment_count") != 25
    ):
        raise SystemExit("same-batch diagnostic identity or isolation differs")
    starts = replay.get("training_segment_start_indices")
    segments = replay.get("training_segment_replays")
    geometry = replay.get("target_geometry_by_training_segment")
    if (
        not isinstance(starts, list)
        or len(starts) != 25
        or any(type(value) is not int for value in starts)
        or starts != sorted(set(starts))
        or not isinstance(segments, list)
        or len(segments) != 25
        or not isinstance(geometry, list)
        or len(geometry) != 25
        or replay.get("training_segment_start_indices_sha256")
        != hashlib.sha256(canonical_json_bytes(starts)).hexdigest()
        or replay.get("target_geometry_by_training_segment_sha256")
        != hashlib.sha256(canonical_json_bytes(geometry)).hexdigest()
    ):
        raise SystemExit("same-batch segment inventory or geometry hash differs")
    if starts != plan_starts:
        raise SystemExit("same-batch segment starts differ from the frozen plan")
    if reference_segment_starts is None:
        reference_segment_starts = starts
        reference_geometry_sha = replay["target_geometry_by_training_segment_sha256"]
    elif starts != reference_segment_starts or replay["target_geometry_by_training_segment_sha256"] != reference_geometry_sha:
        raise SystemExit("fixed training target geometry changed across optimizer steps")
    if replay["target_geometry_by_training_segment_sha256"] != "ed04952e7468ffaa69376af8be4495a0f684b06ccd7a3127ce924231b3ec5114":
        raise SystemExit("fixed training target geometry differs from the registered source")

    before = finite_float(replay.get("before_step_objective_physical_unit_multilead_mse"), "same-batch before objective", nonnegative=True)
    after = finite_float(replay.get("after_step_objective_physical_unit_multilead_mse"), "same-batch after objective", nonnegative=True)
    improvement = finite_float(replay.get("objective_improvement_before_minus_after"), "same-batch objective improvement")
    if improvement != before - after:
        raise SystemExit("same-batch diagnostic arithmetic differs")
    expected_relative = improvement / before if before > 0.0 else None
    if replay.get("relative_objective_improvement") != expected_relative:
        raise SystemExit("same-batch relative objective improvement differs")
    strict = after < before
    if replay.get("strict_objective_decrease") is not strict:
        raise SystemExit("same-batch strict-decrease flag differs")

    before_by_lead = replay.get("mse_by_lead_before_step")
    after_by_lead = replay.get("mse_by_lead_after_step")
    lead_improvements = replay.get("mse_improvement_by_lead_before_minus_after")
    before_counts = replay.get("target_count_by_lead_before_step")
    after_counts = replay.get("target_count_by_lead_after_step")
    expected_counts = {str(lead): 2550 for lead in (1, 2, 3)}
    if (
        not isinstance(before_counts, dict)
        or not isinstance(after_counts, dict)
        or any(type(value) is not int for value in before_counts.values())
        or any(type(value) is not int for value in after_counts.values())
        or before_counts != expected_counts
        or after_counts != expected_counts
    ):
        raise SystemExit("same-batch target counts differ from 25 segments by 102 targets")
    for mapping, label in (
        (before_by_lead, "same-batch before MSE"),
        (after_by_lead, "same-batch after MSE"),
        (lead_improvements, "same-batch lead improvement"),
    ):
        if not isinstance(mapping, dict) or set(mapping) != {"1", "2", "3"}:
            raise SystemExit(f"{label} lead inventory differs")
    normalized_before = {
        key: finite_float(value, f"same-batch lead-{key} before MSE", nonnegative=True)
        for key, value in before_by_lead.items()
    }
    normalized_after = {
        key: finite_float(value, f"same-batch lead-{key} after MSE", nonnegative=True)
        for key, value in after_by_lead.items()
    }
    if not math.isclose(before, math.fsum(normalized_before.values()) / 3.0, rel_tol=1.0e-6, abs_tol=1.0e-8):
        raise SystemExit("same-batch before objective does not reconstruct")
    if not math.isclose(after, math.fsum(normalized_after.values()) / 3.0, rel_tol=1.0e-6, abs_tol=1.0e-8):
        raise SystemExit("same-batch after objective does not reconstruct")
    if any(
        finite_float(lead_improvements[key], f"same-batch lead-{key} improvement")
        != normalized_before[key] - normalized_after[key]
        for key in ("1", "2", "3")
    ):
        raise SystemExit("same-batch per-lead improvement arithmetic differs")

    strict_segment_count = 0
    constituent_before_objectives = []
    constituent_after_objectives = []
    constituent_before_by_lead = {str(lead): [] for lead in (1, 2, 3)}
    constituent_after_by_lead = {str(lead): [] for lead in (1, 2, 3)}
    for segment, start, expected_geometry in zip(segments, starts, geometry):
        if (
            not isinstance(segment, dict)
            or type(segment.get("optimizer_step")) is not int
            or segment.get("optimizer_step") != expected_step
            or type(segment.get("segment_start_index_global_inclusive")) is not int
            or segment.get("segment_start_index_global_inclusive") != start
            or type(segment.get("segment_end_index_global_exclusive")) is not int
            or segment.get("segment_end_index_global_exclusive") != start + 150
            or type(segment.get("segment_days")) is not int
            or segment.get("segment_days") != 150
            or type(segment.get("filter_warmup_days")) is not int
            or segment.get("filter_warmup_days") != 45
            or segment.get("identical_target_geometry_before_after") is not True
            or segment.get("after_step_was_recomputed") is not True
            or segment.get("after_step_recomputed_under_no_grad") is not True
            or segment.get("reserved_evaluation_values_used") != 0
            or segment.get("target_geometry_by_lead") != expected_geometry
            or any(type(value) is not int for value in segment.get("target_count_by_lead_before_step", {}).values())
            or any(type(value) is not int for value in segment.get("target_count_by_lead_after_step", {}).values())
            or segment.get("target_count_by_lead_before_step") != {str(lead): 102 for lead in (1, 2, 3)}
            or segment.get("target_count_by_lead_after_step") != {str(lead): 102 for lead in (1, 2, 3)}
            or (
                segment.get("segment_first_date"),
                segment.get("segment_last_date"),
                segment.get("scored_issue_first_date"),
                segment.get("scored_issue_last_date"),
            )
            != frozen_segment_dates_by_start[start]
        ):
            raise SystemExit("same-batch constituent target identity or isolation differs")
        issue_start = start + 45
        issue_end = start + 147
        if not isinstance(expected_geometry, dict) or set(expected_geometry) != {"1", "2", "3"}:
            raise SystemExit("same-batch constituent lead geometry differs")
        for lead in (1, 2, 3):
            declared = expected_geometry[str(lead)]
            target_indices = list(range(issue_start + lead, issue_end + lead))
            if (
                declared.get("issue_start_index_global_inclusive") != issue_start
                or declared.get("issue_end_index_global_exclusive") != issue_end
                or declared.get("target_start_index_global_inclusive") != target_indices[0]
                or declared.get("target_end_index_global_inclusive") != target_indices[-1]
                or declared.get("target_index_sha256") != hashlib.sha256(canonical_json_bytes(target_indices)).hexdigest()
                or declared.get("finite_target_mask_sha256") != expected_mask_sha
                or declared.get("finite_target_count") != 102
            ):
                raise SystemExit("same-batch constituent index, mask, or count geometry differs")
        segment_before = finite_float(segment.get("before_step_objective_physical_unit_multilead_mse"), "segment before objective", nonnegative=True)
        segment_after = finite_float(segment.get("after_step_objective_physical_unit_multilead_mse"), "segment after objective", nonnegative=True)
        segment_improvement = finite_float(segment.get("objective_improvement_before_minus_after"), "segment improvement")
        segment_before_by_lead = segment.get("mse_by_lead_before_step")
        segment_after_by_lead = segment.get("mse_by_lead_after_step")
        segment_lead_improvements = segment.get("mse_improvement_by_lead_before_minus_after")
        if (
            not isinstance(segment_before_by_lead, dict)
            or not isinstance(segment_after_by_lead, dict)
            or not isinstance(segment_lead_improvements, dict)
            or set(segment_before_by_lead) != {"1", "2", "3"}
            or set(segment_after_by_lead) != {"1", "2", "3"}
            or set(segment_lead_improvements) != {"1", "2", "3"}
        ):
            raise SystemExit("same-batch constituent lead MSE inventory differs")
        normalized_segment_before = {
            key: finite_float(value, f"segment lead-{key} before MSE", nonnegative=True)
            for key, value in segment_before_by_lead.items()
        }
        normalized_segment_after = {
            key: finite_float(value, f"segment lead-{key} after MSE", nonnegative=True)
            for key, value in segment_after_by_lead.items()
        }
        if (
            segment_improvement != segment_before - segment_after
            or segment.get("relative_objective_improvement")
            != (segment_improvement / segment_before if segment_before > 0.0 else None)
            or segment.get("strict_objective_decrease") is not (segment_after < segment_before)
            or not math.isclose(segment_before, math.fsum(normalized_segment_before.values()) / 3.0, rel_tol=1.0e-6, abs_tol=1.0e-8)
            or not math.isclose(segment_after, math.fsum(normalized_segment_after.values()) / 3.0, rel_tol=1.0e-6, abs_tol=1.0e-8)
            or any(
                finite_float(segment_lead_improvements[key], f"segment lead-{key} improvement")
                != normalized_segment_before[key] - normalized_segment_after[key]
                for key in ("1", "2", "3")
            )
        ):
            raise SystemExit("same-batch constituent objective arithmetic differs")
        for key in ("1", "2", "3"):
            constituent_before_by_lead[key].append(normalized_segment_before[key])
            constituent_after_by_lead[key].append(normalized_segment_after[key])
        constituent_before_objectives.append(segment_before)
        constituent_after_objectives.append(segment_after)
        strict_segment_count += int(segment_after < segment_before)
    if (
        replay.get("training_segment_strict_objective_decrease_count") != strict_segment_count
        or replay.get("training_segment_strict_objective_decrease_fraction") != strict_segment_count / 25
        or replay.get("every_training_segment_strictly_decreased") is not (strict_segment_count == 25)
        or before != math.fsum(constituent_before_objectives) / 25
        or after != math.fsum(constituent_after_objectives) / 25
        or any(
            normalized_before[key] != math.fsum(constituent_before_by_lead[key]) / 25
            or normalized_after[key] != math.fsum(constituent_after_by_lead[key]) / 25
            for key in ("1", "2", "3")
        )
    ):
        raise SystemExit("same-batch constituent strict-decrease summary differs")

    strict_count += int(strict)
    if not strict:
        not_strict.append(expected_step)
    max_increase = max(max_increase, after - before, 0.0)
diagnostic = training.get("same_segment_post_step_diagnostic", {})
cumulative = diagnostic.get("cumulative", {})
imported_source = diagnostic.get("imported_source", {})
new_continuation = diagnostic.get("new_continuation", {})
source_replays = replays[:40]
new_replays = replays[40:]
source_not_strict = [row["optimizer_step"] for row in source_replays if not row["strict_objective_decrease"]]
new_not_strict = [row["optimizer_step"] for row in new_replays if not row["strict_objective_decrease"]]
source_strict_count = 40 - len(source_not_strict)
new_strict_count = 40 - len(new_not_strict)
source_max_increase = max((max(row["after_step_objective_physical_unit_multilead_mse"] - row["before_step_objective_physical_unit_multilead_mse"], 0.0) for row in source_replays), default=0.0)
new_max_increase = max((max(row["after_step_objective_physical_unit_multilead_mse"] - row["before_step_objective_physical_unit_multilead_mse"], 0.0) for row in new_replays), default=0.0)
if (
    diagnostic.get("schema_version") != "daily_camels_knet_same_segment_post_step_diagnostic_v1"
    or diagnostic.get("policy") != "diagnostic_only"
    or diagnostic.get("required_for_scientific_gate") is not False
    or exact_int(diagnostic.get("source_optimizer_step_boundary"), "diagnostic source step boundary", minimum=0) != 40
    or exact_int(cumulative.get("replay_count"), "cumulative replay count", minimum=0) != 80
    or exact_int(cumulative.get("strict_decrease_count"), "cumulative strict-decrease count", minimum=0) != strict_count
    or cumulative.get("strict_decrease_fraction") != strict_count / 80
    or exact_int(cumulative.get("not_strictly_decreased_count"), "cumulative non-decrease count", minimum=0) != len(not_strict)
    or cumulative.get("not_strictly_decreased_optimizer_steps") != not_strict
    or cumulative.get("every_optimizer_step_strictly_decreased") is not (strict_count == 80)
    or finite_float(cumulative.get("maximum_objective_increase"), "cumulative maximum objective increase", nonnegative=True) != max_increase
    or exact_int(imported_source.get("replay_count"), "source replay count", minimum=0) != 40
    or source_strict_count != 35
    or source_not_strict != [12, 24, 26, 27, 30]
    or source_max_increase != 0.02514404172971965
    or exact_int(imported_source.get("strict_decrease_count"), "source strict-decrease count", minimum=0) != source_strict_count
    or imported_source.get("strict_decrease_fraction") != source_strict_count / 40
    or exact_int(imported_source.get("not_strictly_decreased_count"), "source non-decrease count", minimum=0) != len(source_not_strict)
    or imported_source.get("not_strictly_decreased_optimizer_steps") != source_not_strict
    or imported_source.get("every_optimizer_step_strictly_decreased") is not (source_strict_count == 40)
    or finite_float(imported_source.get("maximum_objective_increase"), "source maximum objective increase", nonnegative=True) != source_max_increase
    or imported_source.get("historical_policy") != "required_hard_gate"
    or imported_source.get("historical_gate_passed") is not (source_strict_count == 40)
    or exact_int(new_continuation.get("replay_count"), "new replay count", minimum=0) != 40
    or new_continuation.get("policy") != "diagnostic_only"
    or exact_int(new_continuation.get("strict_decrease_count"), "new strict-decrease count", minimum=0) != new_strict_count
    or new_continuation.get("strict_decrease_fraction") != new_strict_count / 40
    or exact_int(new_continuation.get("not_strictly_decreased_count"), "new non-decrease count", minimum=0) != len(new_not_strict)
    or new_continuation.get("not_strictly_decreased_optimizer_steps") != new_not_strict
    or new_continuation.get("every_optimizer_step_strictly_decreased") is not (new_strict_count == 40)
    or finite_float(new_continuation.get("maximum_objective_increase"), "new maximum objective increase", nonnegative=True) != new_max_increase
):
    raise SystemExit("same-batch diagnostic summary differs")

admission = preflight.get("resource_admission", {})
cuda_probe = preflight.get("cuda_probe_without_torch_import", {})
if (
    preflight.get("status") != "PREFLIGHT_PASS"
    or preflight.get("experiment_id") != experiment_id
    or preflight.get("phase") != "train"
    or str(preflight.get("slurm_job_id")) != job_id
    or preflight.get("hostname") != "ngu202"
    or preflight.get("run_directory_absent") is not True
    or exact_int(preflight.get("reserved_data_member_count"), "preflight reserved data member count", minimum=0) != 0
    or exact_int(preflight.get("array_members_materialized"), "preflight materialized array count", minimum=0) != 0
    or preflight.get("numpy_imported") is not False
    or preflight.get("torch_imported") is not False
    or admission.get("status") != "PASS"
    or exact_int(admission.get("host_admission_min_bytes"), "host memory admission minimum", minimum=0) != 2800353280
    or exact_int(admission.get("available_host_memory_bytes"), "available host memory", minimum=0) < 2800353280
    or exact_int(admission.get("gpu_admission_min_free_mib"), "GPU memory admission minimum", minimum=0) != 822
    or exact_int(admission.get("gpu_memory_free_mib"), "free GPU memory", minimum=0) < 822
    or cuda_probe.get("device_name") != "NVIDIA A800-SXM4-80GB"
    or exact_int(cuda_probe.get("visible_device_count"), "visible GPU count", minimum=0) != 1
):
    raise SystemExit("allocated-node preflight or resource admission differs")

resources = summary.get("resource_peaks", {})
if (
    exact_int(resources.get("host_peak_rss_bytes"), "host peak resident memory", minimum=0) <= 0
    or exact_int(resources.get("graphics_peak_allocated_bytes"), "GPU peak allocated memory", minimum=0) <= 0
    or exact_int(resources.get("graphics_peak_reserved_bytes"), "GPU peak reserved memory", minimum=0) <= 0
):
    raise SystemExit("measured resource peaks are absent")

audit = {
    "validation_exit_code": 0,
    "technical_status": "PASS",
    "scientific_status": "PASS",
    "convergence_status": "UNKNOWN",
    "best_epoch": best_epoch,
    "source_checkpoint_objective": continuation["source_checkpoint_objective"],
    "post_resume_best_checkpoint_objective": continuation["post_resume_best_checkpoint_objective"],
    "post_resume_checkpoint_objective_improvement": continuation["post_resume_checkpoint_objective_improvement"],
    "best_nse_by_lead_712_origins": training["best_nse_by_lead"],
    "best_mse_by_lead_712_origins": best_mse,
    "optimizer_steps": training["optimizer_steps"],
    "sampled_forecast_events": training["sampled_forecast_events"],
    "new_optimizer_steps": continuation["new_optimizer_steps"],
    "new_sampled_forecast_events": continuation["new_sampled_forecast_events"],
    "same_batch_strict_decrease_count_cumulative": strict_count,
    "same_batch_not_strictly_decreased_steps_cumulative": not_strict,
    "same_batch_new_continuation": new_continuation,
    "same_batch_strict_decrease_count_new_continuation": new_strict_count,
    "same_batch_not_strictly_decreased_steps_new_continuation": new_not_strict,
    "same_batch_maximum_objective_increase_new_continuation": new_max_increase,
    "same_batch_maximum_objective_increase_cumulative": max_increase,
    "access_ledger": access,
    "resource_admission": admission,
    "resource_peaks": resources,
    "source_epoch40_checkpoint_sha256": source_checkpoint_sha,
    "source_epoch0_through_40_history_sha256": actual_source_history_sha,
    "source_epoch40_parameter_sha256": source_parameter_sha,
    "normalized_a38_replay_evidence_sha256": actual_normalized_replay_sha,
    "replay_evidence_sha256": sha(root / "replay_evidence.json"),
    "epoch80_checkpoint_sha256": files["checkpoints/epoch_080.pt"],
    "best_checkpoint_sha256": files["checkpoints/best.pt"],
    "result_summary_sha256": sha(root / "result_summary.json"),
    "epoch_history_sha256": sha(root / "epoch_history.json"),
    "completion_marker_sha256": sha(root / "completion.marker.json"),
    "manifest_member_count": len(files),
}
print("SEQ78_A38_INDEPENDENT_VALIDATION " + json.dumps(audit, sort_keys=True, separators=(",", ":")))
PY
INDEPENDENT_VALIDATION_EXIT_CODE="$?"
[[ "$INDEPENDENT_VALIDATION_EXIT_CODE" == "0" ]] || {
  echo "A38 independent standard-library validation failed" >&2
  exit 67
}

BEST_EPOCH="$(python -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["training"]["best_epoch"])' "${RUN_DIRECTORY}/result_summary.json")"
case "$BEST_EPOCH" in
  ''|*[!0-9]*) echo "A38 best epoch is malformed" >&2; exit 68;;
esac
printf -v BEST_EPOCH_PADDED '%03d' "$BEST_EPOCH"

[[ ! -e "$ARCHIVE" && ! -L "$ARCHIVE" ]] || { echo "A38 terminal evidence archive already exists" >&2; exit 69; }
declare -a ARCHIVE_FILES=()
declare -A ARCHIVE_SEEN=()
add_archive_file() {
  local relative="$1" required="$2"
  if safe_regular_under_run_base "$relative"; then
    if [[ -z "${ARCHIVE_SEEN[$relative]-}" ]]; then
      ARCHIVE_FILES+=("$relative")
      ARCHIVE_SEEN["$relative"]="1"
    fi
  elif [[ "$required" == "1" ]]; then
    echo "required A38 archive member is absent or unsafe: $relative" >&2
    return 70
  fi
}

for relative in \
  "logs/train1-${JOB_ID}.out" \
  "logs/train1-${JOB_ID}.err" \
  "status/train-preflight-${EXPERIMENT_ID}-${JOB_ID}.json" \
  "status/train-gpu-resources-${EXPERIMENT_ID}-${JOB_ID}.csv" \
  "status/train-cgroup-resources-${EXPERIMENT_ID}-${JOB_ID}.txt" \
  "status/seq70_offline_train_bundle_verification.json" \
  "status/seq70_a800_train_submission_identity.txt" \
  "status/seq70_a800_training_job_id.txt" \
  "status/seq70_a800_training_submitted_time_utc.txt" \
  "status/seq70_pre_submission_squeue.txt" \
  "status/seq70_post_submission_squeue.txt" \
  "status/seq70_pre_submission_sacct.txt" \
  "status/seq70_post_submission_sacct.txt" \
  "status/seq70_pre_submission_ngu202_hgpu8.txt" \
  "status/locks/${EXECUTION_ATTEMPT_ID}.submission.lock/owner.txt" \
  "runs/${EXPERIMENT_ID}/completion.marker.json" \
  "runs/${EXPERIMENT_ID}/epoch_history.json" \
  "runs/${EXPERIMENT_ID}/events.jsonl" \
  "runs/${EXPERIMENT_ID}/experiment_identity.json" \
  "runs/${EXPERIMENT_ID}/feature_diagnostics.json" \
  "runs/${EXPERIMENT_ID}/manifest.sha256.json" \
  "runs/${EXPERIMENT_ID}/owner_evidence.json" \
  "runs/${EXPERIMENT_ID}/preflight.json" \
  "runs/${EXPERIMENT_ID}/replay_evidence.json" \
  "runs/${EXPERIMENT_ID}/result_summary.json" \
  "runs/${EXPERIMENT_ID}/checkpoints/epoch_040.pt" \
  "runs/${EXPERIMENT_ID}/checkpoints/epoch_080.pt" \
  "runs/${EXPERIMENT_ID}/checkpoints/best.pt" \
  "runs/${EXPERIMENT_ID}/checkpoints/last.pt" \
  "runs/${EXPERIMENT_ID}/checkpoints/epoch_${BEST_EPOCH_PADDED}.pt" \
  "runs/${EXPERIMENT_ID}/predictions/epoch_080.npz" \
  "runs/${EXPERIMENT_ID}/predictions/epoch_${BEST_EPOCH_PADDED}.npz"; do
  add_archive_file "$relative" "1"
done
add_archive_file "runs/${EXPERIMENT_ID}/replay_predictions.npz" "0"

ARCHIVE_TEMP="$(mktemp "${ARCHIVE}.tmp.XXXXXX")"
ARCHIVE_PUBLISHED=0
cleanup_archive_temp() {
  if [[ "$ARCHIVE_PUBLISHED" == "1" && -e "$ARCHIVE" && "$ARCHIVE" -ef "$ARCHIVE_TEMP" ]]; then
    rm -f -- "$ARCHIVE"
  fi
  rm -f -- "$ARCHIVE_TEMP"
}
trap cleanup_archive_temp EXIT
tar -czf "$ARCHIVE_TEMP" -C "$RUN_BASE" -- "${ARCHIVE_FILES[@]}"
gzip -t "$ARCHIVE_TEMP"
ARCHIVE_MEMBER_COUNT="$(tar -tzf "$ARCHIVE_TEMP" | sed '/^$/d' | wc -l | tr -d ' ')"
ARCHIVE_RESERVED_MEMBER_COUNT="$(tar -tzf "$ARCHIVE_TEMP" | awk 'BEGIN{IGNORECASE=1} /held.?out|reserved.?evaluation|formal.?evaluation/{count++} END{print count+0}')"
[[ "$ARCHIVE_RESERVED_MEMBER_COUNT" == "0" ]] || { echo "A38 terminal archive contains a reserved-named member" >&2; exit 71; }
ARCHIVE_SHA256="$(sha256_file "$ARCHIVE_TEMP")"
ARCHIVE_SIZE="$(stat -c '%s' "$ARCHIVE_TEMP")"

[[ ! -e "$TRAIN_LOCK" && ! -L "$TRAIN_LOCK" ]] || { echo "A38 training lock reappeared before archive publication" >&2; exit 72; }
[[ ! -e "$RUN_OWNER_LOCK" && ! -L "$RUN_OWNER_LOCK" ]] || { echo "A38 run owner lock reappeared before archive publication" >&2; exit 72; }
ln -- "$ARCHIVE_TEMP" "$ARCHIVE"
ARCHIVE_PUBLISHED=1
[[ "$ARCHIVE" -ef "$ARCHIVE_TEMP" && "$(sha256_file "$ARCHIVE")" == "$ARCHIVE_SHA256" && "$(stat -c '%s' "$ARCHIVE")" == "$ARCHIVE_SIZE" ]] || {
  echo "A38 published archive identity differs" >&2
  exit 72
}

[[ ! -e "$TRAIN_LOCK" && ! -L "$TRAIN_LOCK" ]] || { echo "A38 training lock reappeared after archive publication" >&2; exit 72; }
[[ ! -e "$RUN_OWNER_LOCK" && ! -L "$RUN_OWNER_LOCK" ]] || { echo "A38 run owner lock reappeared after archive publication" >&2; exit 72; }

printf 'SEQ78_A38_TERMINAL_COLLECTED experiment_id=%s execution_attempt_id=%s job_id=%s terminal_state=%s terminal_exit_code=%s batch_step_exit_code=%s preflight_step_exit_code=%s training_step_exit_code=%s independent_validation_exit_code=%s partition=%s node=%s gpu=NVIDIA_A800-SXM4-80GB reserved_named_path_count=%s safe_file_count=%s training_lock_present=0 run_owner_lock_present=0 submission_lock_present=1 archive=%s archive_sha256=%s archive_size=%s archive_member_count=%s archive_reserved_member_count=%s\n' \
  "$EXPERIMENT_ID" "$EXECUTION_ATTEMPT_ID" "$JOB_ID" "$STATE" "$EXIT_CODE" "$BATCH_STEP_EXIT" "$PREFLIGHT_STEP_EXIT" "$TRAINING_STEP_EXIT" "$INDEPENDENT_VALIDATION_EXIT_CODE" "$PARTITION" "$NODELIST" "$RESERVED_PATH_COUNT" "$SAFE_FILE_COUNT" "$ARCHIVE" "$ARCHIVE_SHA256" "$ARCHIVE_SIZE" "$ARCHIVE_MEMBER_COUNT" "$ARCHIVE_RESERVED_MEMBER_COUNT"
rm -- "$ARCHIVE_TEMP"
ARCHIVE_PUBLISHED=0
trap - EXIT
