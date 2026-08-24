#!/usr/bin/env bash
set -eo pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf20_20260824
STATUS_ROOT="$TARGET/artifacts/tukf20_hpc_deployment_v1/status"
EXPECTED_ARCHIVE_SHA=721fa666319cc448e901515d066bb217560c87ec8edd19e5cbb2300269074f76
EXPECTED_CONFIG_SHA=56ea39cad0debfd996f86d221d0de3671c8ecdfbac99e9b9bb96a913c7ec614f
DEPLOYMENT_ID=TUKF20_HBV_ROLLING_ORIGIN_JOINT_LEARNING_HPC_DEPLOYMENT_V1
SCIENTIFIC_ID=TUKF20_HBV_ROLLING_ORIGIN_JOINT_LEARNING_V1
CLAIM="$STATUS_ROOT/.formal_submission_claim"
RAW="$STATUS_ROOT/formal_submission_raw.txt"
RECEIPT="$STATUS_ROOT/formal_submission_receipt.json"
JOBID_FILE="$STATUS_ROOT/formal_job_id.txt"
SQUEUE="$STATUS_ROOT/formal_squeue_snapshot.txt"
SACCT="$STATUS_ROOT/formal_sacct_snapshot.txt"
SLURM="$TARGET/hpc/tukf20_hbv_rolling_origin_joint_learning/submit_formal_cpu.slurm"

source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
PYTHON=$(command -v python)
test -n "$PYTHON"
test -d "$TARGET" -a -d "$STATUS_ROOT/.smoke_submission_claim"

echo '=== TUKF20 FULL SMOKE GATE REVALIDATION ==='
cd "$TARGET"
"$PYTHON" -B - <<'PY'
from pathlib import Path
from scripts import run_tukf20_hpc_formal_pipeline as pipeline

context = pipeline._gate_context(
    Path("configs/tukf20_hpc_deployment_v1.json"),
    Path("_transport/bundle_manifest.sha256.json"),
)
assert context["smoke"]["status"] == "HPC_SMOKE_PASS"
assert context["smoke_completion"]["status"] == "HPC_SMOKE_SLURM_COMPLETED"
assert int(context["smoke_completion"]["smoke_job_id"]) == 210745
print(f"TUKF20_FULL_SMOKE_GATE_VERIFIED checks={len(context['smoke']['checks'])}")
PY

test ! -e "$STATUS_ROOT/formal_pipeline_started.json"
test ! -e "$STATUS_ROOT/formal_pipeline_complete.json"
if compgen -G "$STATUS_ROOT/formal_pipeline_failure_*.json" > /dev/null; then
  echo TUKF20_FORMAL_PIPELINE_PRIOR_FAILURE_EXISTS
  exit 70
fi

echo '=== TUKF20 UNIQUE FORMAL SUBMISSION ==='
for path in "$RAW" "$RECEIPT" "$JOBID_FILE" "$SQUEUE" "$SACCT"; do
  test ! -e "$path" || { echo "TUKF20_FORMAL_EVIDENCE_ALREADY_EXISTS=$path"; exit 71; }
done
EXISTING_QUEUE=$(squeue -u "$USER" -h -o '%i|%j' 2>/dev/null | awk -F'|' '$2 == "tukf20-formal" {print $1}')
EXISTING_ACCOUNTING=$(sacct -u "$USER" -S 2026-08-24 -X -n -P --format=JobIDRaw,JobName 2>/dev/null | awk -F'|' '$2 == "tukf20-formal" {print $1}')
test -z "$EXISTING_QUEUE" -a -z "$EXISTING_ACCOUNTING" || {
  echo "TUKF20_FORMAL_PRIOR_SCHEDULER_RECORD queue=$EXISTING_QUEUE accounting=$EXISTING_ACCOUNTING"
  exit 72
}
mkdir "$CLAIM" 2>/dev/null || { echo TUKF20_FORMAL_STAGE_ALREADY_CLAIMED; exit 73; }
printf 'stage=formal\nclaimed_at_utc=%s\nhost=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(hostname)" > "$CLAIM/owner.txt"

set +e
(
  set -o noclobber
  sbatch "$SLURM" > "$RAW" 2>&1
)
SUBMIT_RC=$?
set -e
cat "$RAW"
test "$SUBMIT_RC" -eq 0
MATCH_COUNT=$(grep -cE '^Submitted batch job [0-9]+$' "$RAW" || true)
test "$MATCH_COUNT" -eq 1 || { echo TUKF20_FORMAL_SUBMIT_LITERAL_RECORD_INVALID; exit 74; }
JID=$(awk '/^Submitted batch job [0-9]+$/ {print $4}' "$RAW")
test -n "$JID" -a "$JID" != "210745"
(
  set -o noclobber
  printf '%s\n' "$JID" > "$JOBID_FILE"
)

SQUEUE_TMP="$SQUEUE.tmp.$$"
QUEUE_ROW=""
for attempt in $(seq 1 10); do
  QUEUE_ROW=$(squeue --noheader --jobs "$JID" --format='%i|%j|%T|%P|%C' 2>/dev/null || true)
  if printf '%s\n' "$QUEUE_ROW" | awk -F'|' -v id="$JID" '$1 == id {found=1} END {exit !found}'; then
    break
  fi
  QUEUE_ROW=""
  sleep 1
done
test -n "$QUEUE_ROW" || { echo TUKF20_FORMAL_SQUEUE_CONFIRMATION_MISSING; exit 75; }
printf '%s\n' "$QUEUE_ROW" > "$SQUEUE_TMP"
mv "$SQUEUE_TMP" "$SQUEUE"

"$PYTHON" -B - "$RECEIPT" "$RAW" "$SQUEUE" "$JID" "$EXPECTED_ARCHIVE_SHA" "$EXPECTED_CONFIG_SHA" "$DEPLOYMENT_ID" "$SCIENTIFIC_ID" <<'PY'
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

destination, raw_path, queue_path = map(Path, sys.argv[1:4])
payload = {
    "schema_version": "tukf20_hpc_submission_receipt_v1",
    "deployment_id": sys.argv[7],
    "scientific_experiment_id": sys.argv[8],
    "stage": "formal",
    "job_id": int(sys.argv[4]),
    "raw_output_sha256": hashlib.sha256(raw_path.read_bytes()).hexdigest(),
    "squeue_snapshot_sha256": hashlib.sha256(queue_path.read_bytes()).hexdigest(),
    "bundle_sha256": sys.argv[5],
    "deployment_config_sha256": sys.argv[6],
    "submitted_at_utc": datetime.now(timezone.utc).isoformat(),
}
with destination.open("x", encoding="utf-8", newline="\n") as handle:
    json.dump(payload, handle, indent=2, sort_keys=True)
    handle.write("\n")
PY

echo "TUKF20_FORMAL_JOB_ID=$JID"
cat "$SQUEUE"
sacct -X --jobs "$JID" --format=JobID,JobName,Partition,AllocCPUS,State,ExitCode,Elapsed,Start,End 2>&1 || true
echo TUKF20_FORMAL_SUBMISSION_RECORDED
exit 0
