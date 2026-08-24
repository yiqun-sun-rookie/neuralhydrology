#!/usr/bin/env bash
set -eo pipefail

MAILBOX_ROOT="/data1/home/${USER}/hpc_mailbox"
BASE="/data1/home/sunyiq/kalmannet_daily_camels_20260824"
EXPERIMENT_ID="DAILY_CAMELS_NATIVE_KALMANNET_SMOKE_V1_20260824_A01"
RUN_DIRECTORY="${BASE}/${EXPERIMENT_ID}"
SOURCE_DIRECTORY="${BASE}/source"
STATUS_DIRECTORY="${BASE}/status"
LOG_DIRECTORY="${BASE}/logs"
PROBE_JOB_ID=$(tr -d '[:space:]' < "${STATUS_DIRECTORY}/probe_job_id.txt")
PROBE_REPORT="${STATUS_DIRECTORY}/probe-${PROBE_JOB_ID}.json"

echo '=== PROBE ADMISSION EVIDENCE ==='
case "$PROBE_JOB_ID" in
  ''|*[!0-9]*) echo "invalid probe job id: $PROBE_JOB_ID" >&2; exit 70 ;;
esac
test -s "$PROBE_REPORT"
python - "$PROBE_REPORT" "$RUN_DIRECTORY" <<'PY'
import json
from pathlib import Path
import sys

report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
required = {
    "status": "PREFLIGHT_PASS",
    "experiment_id": "DAILY_CAMELS_NATIVE_KALMANNET_SMOKE_V1_20260824_A01",
    "cuda_available": True,
    "cuda_device_count": 1,
    "run_root_absent": True,
    "array_members_materialized": 0,
    "reserved_data_member_count": 0,
    "input_archive_count": 2,
    "configuration_contract_validated": True,
    "runtime_interface_gap_count": 0,
}
for key, expected in required.items():
    if report.get(key) != expected:
        raise SystemExit(f"probe admission mismatch: {key}")
if report.get("run_root") != sys.argv[2]:
    raise SystemExit("probe checked a different run directory")
if int(report.get("available_host_memory_bytes", 0)) <= 0:
    raise SystemExit("probe host memory evidence is absent")
if int(report.get("cuda_free_bytes", 0)) <= 0:
    raise SystemExit("probe GPU memory evidence is absent")
print(json.dumps({
    "probe_job_id": report["slurm"]["SLURM_JOB_ID"],
    "host": report["hostname"],
    "available_host_memory_bytes": report["available_host_memory_bytes"],
    "cuda_free_bytes": report["cuda_free_bytes"],
    "cuda_total_bytes": report["cuda_total_bytes"],
    "cuda_device_name": report["cuda_device_name"],
}, sort_keys=True))
PY

export PYTHONDONTWRITEBYTECODE=1
python -u "${SOURCE_DIRECTORY}/hpc/daily_camels_native_kalmannet/preflight.py" \
  --bundle-root "$SOURCE_DIRECTORY" \
  --offline-bundle-check > "${STATUS_DIRECTORY}/offline_bundle_check_before_training.json"
test ! -e "$RUN_DIRECTORY" || {
  echo "unique training run already exists: $RUN_DIRECTORY" >&2
  exit 71
}

echo '=== SUBMIT UNIQUE DAILY TRAINING SMOKE ==='
cd "$SOURCE_DIRECTORY"
SUBMISSION_OUTPUT=$(sbatch --parsable \
  hpc/daily_camels_native_kalmannet/submit_smoke_gpu.slurm 2>&1)
printf '%s\n' "$SUBMISSION_OUTPUT" | tee "${STATUS_DIRECTORY}/smoke_submission_raw.txt"
JOB_ID=$(printf '%s' "$SUBMISSION_OUTPUT" | awk -F';' 'NR==1 {print $1}')
case "$JOB_ID" in
  ''|*[!0-9]*) echo "invalid smoke job id: $JOB_ID" >&2; exit 72 ;;
esac
printf '%s\n' "$JOB_ID" > "${STATUS_DIRECTORY}/smoke_job_id.txt"

for ATTEMPT in $(seq 1 240); do
  LIVE_STATE=$(squeue -h -j "$JOB_ID" -o '%T' 2>/dev/null | head -1 | tr -d '[:space:]')
  if [[ -z "$LIVE_STATE" ]]; then
    break
  fi
  if (( ATTEMPT % 6 == 1 )); then
    printf 'smoke_wait attempt=%s state=%s\n' "$ATTEMPT" "$LIVE_STATE"
  fi
  sleep 10
done

MAIN=""
for ATTEMPT in $(seq 1 12); do
  MAIN=$(sacct -X --noheader --parsable2 --jobs "$JOB_ID" \
    --format=JobID,State,ExitCode 2>/dev/null | \
    awk -F'|' -v id="$JOB_ID" '$1 == id {print; exit}')
  [[ -n "$MAIN" ]] && break
  sleep 5
done
STATE=$(printf '%s' "$MAIN" | awk -F'|' '{print $2}' | sed 's/+.*$//')
EXIT_CODE=$(printf '%s' "$MAIN" | awk -F'|' '{print $3}')

echo '=== SMOKE ACCOUNTING ==='
sacct -X --jobs "$JOB_ID" \
  --format=JobID,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,Start,End,MaxRSS
echo '=== SMOKE STDOUT ==='
cat "${LOG_DIRECTORY}/smoke-${JOB_ID}.out" 2>/dev/null || true
echo '=== SMOKE STDERR ==='
cat "${LOG_DIRECTORY}/smoke-${JOB_ID}.err" 2>/dev/null || true
echo '=== RUN INVENTORY ==='
if [[ -d "$RUN_DIRECTORY" ]]; then
  find "$RUN_DIRECTORY" -type f -printf '%P|%s\n' | sort
fi

SUCCESS=0
if [[ "$STATE" = "COMPLETED" && "$EXIT_CODE" = "0:0" ]]; then
  if python - "$RUN_DIRECTORY" <<'PY'
from hashlib import sha256
import json
from pathlib import Path
import sys

root = Path(sys.argv[1]).resolve()
summary_path = root / "result_summary.json"
ledger_path = root / "access_ledger.json"
manifest_path = root / "manifest.sha256.json"
completion_path = root / "completion.marker.json"
for path in (summary_path, ledger_path, manifest_path, completion_path):
    if not path.is_file() or path.is_symlink():
        raise SystemExit(f"missing sealed artifact: {path.name}")

summary = json.loads(summary_path.read_text(encoding="utf-8"))
ledger = json.loads(ledger_path.read_text(encoding="utf-8"))
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
completion = json.loads(completion_path.read_text(encoding="utf-8"))
if summary.get("status") != "COMPLETED" or summary.get("science_gate", {}).get("passed") is not True:
    raise SystemExit("science gate did not complete")
history = summary.get("history", [])
if [row.get("epoch") for row in history] != [0, 1, 2, 3, 4]:
    raise SystemExit("epoch history is not complete")
zero = float(history[0]["selection_score"])
best = float(summary["science_gate"]["best_post_zero_selection_score"])
if not best > zero + 1.0e-6:
    raise SystemExit("post-zero improvement gate is not proven")
if ledger.get("archive_materialization_sessions") != 1:
    raise SystemExit("fresh run must have one materialization session")
if ledger.get("archive_member_reads") != {
    "dates_ns": 2, "forcing": 2, "observations": 2, "parameters": 2
}:
    raise SystemExit("archive member ledger differs")
for key in (
    "raw_source_byte_reads", "evaluation_array_reads", "evaluation_predictions",
    "evaluation_metrics", "evaluation_outputs",
):
    if ledger.get(key) != 0:
        raise SystemExit(f"reserved access counter is nonzero: {key}")

def digest(path):
    return sha256(path.read_bytes()).hexdigest()

if completion.get("status") != "COMPLETED":
    raise SystemExit("completion marker status differs")
if completion.get("manifest_sha256") != digest(manifest_path):
    raise SystemExit("completion marker manifest hash differs")
if completion.get("summary_sha256") != digest(summary_path):
    raise SystemExit("completion marker summary hash differs")
files = manifest.get("files", {})
if manifest.get("file_count") != len(files):
    raise SystemExit("manifest count differs")
for relative, record in files.items():
    path = root.joinpath(*relative.split("/"))
    if not path.is_file() or digest(path) != record.get("sha256") or path.stat().st_size != record.get("size_bytes"):
        raise SystemExit(f"manifest mismatch: {relative}")
print(json.dumps({
    "epoch_zero_selection_score": zero,
    "best_post_zero_selection_score": best,
    "best_epoch": summary["science_gate"]["best_epoch"],
    "optimizer_steps": summary["science_gate"]["optimizer_steps"],
    "archive_materialization_sessions": ledger["archive_materialization_sessions"],
    "history": history,
}, sort_keys=True))
PY
  then
    SUCCESS=1
  fi
fi

echo '=== PACKAGE PRESERVED RUN EVIDENCE ==='
OUTBOX_DIRECTORY="${MAILBOX_ROOT}/outbox/kalmannet-daily-camels"
EVIDENCE_ARCHIVE="${OUTBOX_DIRECTORY}/${EXPERIMENT_ID}_evidence.tar.gz"
TEMPORARY_ARCHIVE="${OUTBOX_DIRECTORY}/.${EXPERIMENT_ID}_evidence_${JOB_ID}.tmp"
test ! -e "$EVIDENCE_ARCHIVE" || exit 73
mkdir -p "$OUTBOX_DIRECTORY"
PACKAGE_MEMBERS=(status logs)
[[ -d "$RUN_DIRECTORY" ]] && PACKAGE_MEMBERS+=("$EXPERIMENT_ID")
tar -czf "$TEMPORARY_ARCHIVE" -C "$BASE" "${PACKAGE_MEMBERS[@]}"
mv "$TEMPORARY_ARCHIVE" "$EVIDENCE_ARCHIVE"
printf 'evidence_archive=%s\n' "$EVIDENCE_ARCHIVE"
printf 'evidence_archive_sha256=%s\n' "$(sha256sum "$EVIDENCE_ARCHIVE" | awk '{print $1}')"
printf 'evidence_archive_size=%s\n' "$(stat -c '%s' "$EVIDENCE_ARCHIVE")"

if [[ "$SUCCESS" -ne 1 ]]; then
  echo "DAILY_CAMELS_KALMANNET_SMOKE_HARD_STOP state=${STATE:-UNKNOWN} exit=${EXIT_CODE:-UNKNOWN}" >&2
  exit 74
fi
echo "DAILY_CAMELS_KALMANNET_SMOKE_PASS job_id=$JOB_ID"
