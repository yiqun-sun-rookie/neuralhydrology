#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

EXPECTED_USER="sunyiq"
MAILBOX_ROOT="/data1/home/sunyiq/hpc_mailbox"
RESULT76="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/result_76.txt"
RESULT76_SHA256="8de1626a8ca208a9f3d5eb60585d5e18b48f5d84d966f3f941a331c0a5642052"
RESULT76_SIZE="7397367"
JOB_ID="215801"
EXPERIMENT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_EPOCH40_TO80_RESUME_STEP_MONOTONICITY_DIAGNOSTIC_V1_20260828_A38"
EXECUTION_ATTEMPT_ID="DAILY_CAMELS_KNET_FIXED_FULL_TRAINING_COVERAGE_A38_A800_TRAIN1_SEQ70"
RUN_BASE="/data1/home/sunyiq/kalmannet_daily_camels_knet_a38_a800_train1_20260828"
RUN_DIRECTORY="${RUN_BASE}/runs/${EXPERIMENT_ID}"
STATUS_DIRECTORY="${RUN_BASE}/status"
GPU_RESOURCE_LOG="${STATUS_DIRECTORY}/train-gpu-resources-${EXPERIMENT_ID}-${JOB_ID}.csv"
COMPLETION_MARKER="${RUN_DIRECTORY}/completion.marker.json"
TRAIN_LOCK="${STATUS_DIRECTORY}/locks/${EXPERIMENT_ID}.train.lock"
RUN_OWNER_LOCK="${RUN_DIRECTORY}/.owner.lock"
SUBMISSION_LOCK="${STATUS_DIRECTORY}/locks/${EXECUTION_ATTEMPT_ID}.submission.lock"
FAILED_ARCHIVE75="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/DAILY_CAMELS_KNET_A38_JOB215801_TERMINAL_EVIDENCE_SEQ75.tar.gz"
FAILED_ARCHIVE76="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels/DAILY_CAMELS_KNET_A38_JOB215801_TERMINAL_EVIDENCE_SEQ76.tar.gz"

sha256_file() {
  sha256sum "$1" | awk '{print $1}'
}

[[ "${USER-}" == "$EXPECTED_USER" && "$(id -un)" == "$EXPECTED_USER" ]] || {
  echo "fixed-user check failed" >&2
  exit 50
}
[[ -f "$RESULT76" && ! -L "$RESULT76" ]] || { echo "sequence 76 receipt is absent or symbolic" >&2; exit 51; }
[[ "$(stat -c '%s' "$RESULT76")" == "$RESULT76_SIZE" ]] || { echo "sequence 76 receipt size differs" >&2; exit 51; }
[[ "$(sha256_file "$RESULT76")" == "$RESULT76_SHA256" ]] || { echo "sequence 76 receipt SHA-256 differs" >&2; exit 51; }
grep -Fxq 'GPU resource log does not cover the completed training step' "$RESULT76" || { echo "sequence 76 coverage failure differs" >&2; exit 52; }
grep -Fxq '### exit_code=66' "$RESULT76" || { echo "sequence 76 exit code differs" >&2; exit 52; }
[[ ! -e "$FAILED_ARCHIVE75" && ! -L "$FAILED_ARCHIVE75" ]] || { echo "sequence 75 failed archive exists" >&2; exit 53; }
[[ ! -e "$FAILED_ARCHIVE76" && ! -L "$FAILED_ARCHIVE76" ]] || { echo "sequence 76 failed archive exists" >&2; exit 53; }
[[ ! -e "$TRAIN_LOCK" && ! -L "$TRAIN_LOCK" ]] || { echo "active training lock remains" >&2; exit 54; }
[[ ! -e "$RUN_OWNER_LOCK" && ! -L "$RUN_OWNER_LOCK" ]] || { echo "run owner lock remains" >&2; exit 54; }
[[ -d "$SUBMISSION_LOCK" && ! -L "$SUBMISSION_LOCK" ]] || { echo "persistent submission lock is absent or symbolic" >&2; exit 54; }
[[ -f "$GPU_RESOURCE_LOG" && ! -L "$GPU_RESOURCE_LOG" ]] || { echo "GPU resource log is absent or symbolic" >&2; exit 55; }
[[ -f "$COMPLETION_MARKER" && ! -L "$COMPLETION_MARKER" ]] || { echo "completion marker is absent or symbolic" >&2; exit 55; }

STEP_ACCOUNTING="$(sacct -n -j "$JOB_ID" --parsable2 --format=JobIDRaw,State,ExitCode,Start,End,ElapsedRaw)"
TRAINING_STEP_LINE="$(awk -F'|' -v id="${JOB_ID}.1" '$1 == id {print; exit}' <<<"$STEP_ACCOUNTING")"
[[ -n "$TRAINING_STEP_LINE" ]] || { echo "training step accounting is absent" >&2; exit 56; }
IFS='|' read -r _ TRAINING_STEP_STATE TRAINING_STEP_EXIT TRAINING_STEP_START TRAINING_STEP_END TRAINING_STEP_ELAPSED_SECONDS _ <<<"$TRAINING_STEP_LINE"
TRAINING_STEP_STATE="$(printf '%s' "$TRAINING_STEP_STATE" | sed 's/[+ ].*$//')"
[[ "$TRAINING_STEP_STATE" == "COMPLETED" && "$TRAINING_STEP_EXIT" == "0:0" ]] || { echo "training step terminal identity differs" >&2; exit 56; }

python - "$GPU_RESOURCE_LOG" "$COMPLETION_MARKER" "$TRAINING_STEP_START" "$TRAINING_STEP_END" "$TRAINING_STEP_ELAPSED_SECONDS" "$EXPERIMENT_ID" "$JOB_ID" <<'PY'
import csv
import datetime as dt
import hashlib
import json
import math
from pathlib import Path
import re
import sys

log_path = Path(sys.argv[1])
completion_path = Path(sys.argv[2])
step_start = dt.datetime.strptime(sys.argv[3], "%Y-%m-%dT%H:%M:%S")
step_end = dt.datetime.strptime(sys.argv[4], "%Y-%m-%dT%H:%M:%S")
elapsed_seconds = int(sys.argv[5])
experiment_id = sys.argv[6]
job_id = sys.argv[7]

rows = []
with log_path.open("r", encoding="utf-8", newline="") as stream:
    for line_number, row in enumerate(csv.reader(stream), start=1):
        if len(row) != 7:
            raise SystemExit(f"GPU row {line_number} does not have seven fields")
        timestamp_text, uuid, name, total_text, used_text, free_text, utilization_text = (
            value.strip() for value in row
        )
        try:
            timestamp = dt.datetime.strptime(timestamp_text, "%Y/%m/%d %H:%M:%S.%f")
            total, used, free, utilization = map(
                float, (total_text, used_text, free_text, utilization_text)
            )
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
if len(rows) < 2:
    raise SystemExit("GPU resource log has fewer than two rows")
if any(current[0] <= previous[0] for previous, current in zip(rows, rows[1:])):
    raise SystemExit("GPU resource timestamps are not strictly increasing")
gaps = [(current[0] - previous[0]).total_seconds() for previous, current in zip(rows, rows[1:])]
if len({row[1] for row in rows}) != 1 or len({row[2] for row in rows}) != 1 or len({row[3] for row in rows}) != 1:
    raise SystemExit("GPU identity or total memory changed")
completion = json.loads(completion_path.read_text(encoding="utf-8"))
if completion.get("experiment_id") != experiment_id or completion.get("status") != "TRAINING_COMPLETE_GATE_PASS":
    raise SystemExit("completion marker identity differs")
completed_at = dt.datetime.fromisoformat(completion["completed_at_utc"].replace("Z", "+00:00"))
completed_at_cluster = completed_at.astimezone(dt.timezone(dt.timedelta(hours=8))).replace(tzinfo=None)
digest = hashlib.sha256(log_path.read_bytes()).hexdigest()
evidence = {
    "experiment_id": experiment_id,
    "job_id": job_id,
    "training_step_start": step_start.isoformat(),
    "training_step_end": step_end.isoformat(),
    "training_step_elapsed_seconds": elapsed_seconds,
    "completion_marker_cluster_time": completed_at_cluster.isoformat(),
    "gpu_log_sha256": digest,
    "gpu_log_size": log_path.stat().st_size,
    "row_count": len(rows),
    "first_timestamp": rows[0][0].isoformat(),
    "last_timestamp": rows[-1][0].isoformat(),
    "coverage_seconds": (rows[-1][0] - rows[0][0]).total_seconds(),
    "first_minus_step_start_seconds": (rows[0][0] - step_start).total_seconds(),
    "step_end_minus_last_seconds": (step_end - rows[-1][0]).total_seconds(),
    "last_minus_completion_marker_seconds": (rows[-1][0] - completed_at_cluster).total_seconds(),
    "maximum_sample_gap_seconds": max(gaps),
    "gpu_uuid": rows[0][1],
    "gpu_name": rows[0][2],
    "total_mib": rows[0][3],
    "maximum_used_mib": max(row[4] for row in rows),
    "minimum_free_mib": min(row[5] for row in rows),
    "maximum_utilization_percent": max(row[6] for row in rows),
}
print("SEQ77_A38_GPU_COVERAGE_DIAGNOSTIC " + json.dumps(evidence, sort_keys=True, separators=(",", ":")))
PY

printf 'SEQ77_A38_GPU_COVERAGE_DIAGNOSTIC_COMPLETE experiment_id=%s job_id=%s training_lock_present=0 run_owner_lock_present=0 submission_lock_present=1 failed_archive75_present=0 failed_archive76_present=0\n' "$EXPERIMENT_ID" "$JOB_ID"
