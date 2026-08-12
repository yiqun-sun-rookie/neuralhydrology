#!/bin/bash
# id26-v09-strict seq=62 : query training audit attempt 03 once; do not submit anything.
set -euo pipefail
export LC_ALL=C
ROOT=/data1/home/sunyiq/v09_strict
AUDIT_PARENT=$ROOT/audit_v09
TRAIN_REPO=$ROOT/codetest/neuralhydrology
FORMAL_ROOT=$TRAIN_REPO/results/26_historical_band_experts/formal_v09
JOBID_FILE=$AUDIT_PARENT/training_audit_attempt_03_jobid.txt
REPORT=$FORMAL_ROOT/training_external_audit.json
JID=$(tr -d '[:space:]' < "$JOBID_FILE")
test "$JID" = 202777
OUT=$ROOT/logs/training_audit_${JID}.out
ERR=$ROOT/logs/training_audit_${JID}.err

echo "=== A JOB ==="
echo "TRAINING_AUDIT_ATTEMPT_03_JOBID=$JID"
squeue -j "$JID" -o '%.12i %.18j %.10T %.12M %.24R' || true
sacct -X -j "$JID" --starttime 2026-08-12 --format=JobIDRaw,JobName%20,State,ExitCode,Elapsed,Start,End,NodeList -P

echo "=== B LOG FILES ==="
find "$ROOT/logs" -maxdepth 1 -type f \( -name "training_audit_${JID}.out" -o -name "training_audit_${JID}.err" \) -printf '%p %s bytes\n' | sort
echo "--- stdout tail ---"
if [ -f "$OUT" ]; then tail -n 160 "$OUT"; else echo "MISSING $OUT"; fi
echo "--- stderr tail ---"
if [ -f "$ERR" ]; then tail -n 160 "$ERR"; else echo "MISSING $ERR"; fi

echo "=== C REPORT SUMMARY ==="
python - "$REPORT" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
print(f"report_present={str(path.is_file()).lower()}")
if path.is_file():
    data = json.loads(path.read_text(encoding="utf-8"))
    runs = data.get("runs", [])
    checkpoint_count = sum(len(run.get("checkpoints", [])) for run in runs)
    nonfinite_count = sum(run.get("nonfinite_tensor_count", 0) for run in runs)
    summary = {
        "schema": data.get("schema"),
        "status": data.get("status"),
        "coverage": data.get("coverage"),
        "training_progress": data.get("training_progress"),
        "run_count": len(runs),
        "expected_run_count": 24,
        "checkpoint_count": checkpoint_count,
        "expected_checkpoint_count": 72,
        "nonfinite_tensor_count": nonfinite_count,
        "all_checkpoint_tensors_finite": data.get("all_checkpoint_tensors_finite"),
        "formal_evaluation_observation_reads": data.get("formal_evaluation_observation_reads"),
        "formal_period_predictions_generated": data.get("formal_period_predictions_generated"),
        "official_score_called": data.get("official_score_called"),
        "validation_metrics_computed": data.get("validation_metrics_computed"),
        "training_git_commit": data.get("source_context", {}).get("training_git_commit"),
        "audit_git_commit": data.get("audit_source_context", {}).get("git_commit"),
        "audit_source_clean": data.get("audit_source_context", {}).get("tracked_source_clean"),
        "pre_seal_evidence": data.get("pre_seal_evidence"),
    }
    print(json.dumps(summary, sort_keys=True, separators=(",", ":")))
PY
if [ -f "$REPORT" ]; then sha256sum "$REPORT"; fi

echo "=== D DOWNSTREAM ABSENCE ==="
find "$FORMAL_ROOT" -maxdepth 2 -type f \( -name 'training_seal.json' -o -name 'state_diagnostics_root_manifest.json' -o -name 'state_diagnostics_external_audit.json' \) -print
echo "=== END ==="
