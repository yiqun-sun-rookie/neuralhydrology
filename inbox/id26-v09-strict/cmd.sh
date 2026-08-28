#!/bin/bash
# id26-v09-strict seq=69: read-only status and evidence query for independent state replay audit job 215874.
set -o pipefail
export LC_ALL=C

ROOT=/data1/home/sunyiq/v09_strict
AUDIT_PARENT=$ROOT/audit_v09
TRAIN_REPO=$ROOT/codetest/neuralhydrology
FORMAL_ROOT=$TRAIN_REPO/results/26_historical_band_experts/formal_v09
REPORT=$FORMAL_ROOT/state_diagnostics_external_audit.json
JOBID_FILE=$AUDIT_PARENT/state_diagnostics_audit_attempt_01_jobid.txt
JOBID=215874

echo "=== A JOB ID AND SCHEDULER ==="
if [ -f "$JOBID_FILE" ]; then
  echo "recorded_jobid=$(tr -d '[:space:]' < "$JOBID_FILE")"
else
  echo "recorded_jobid_file=missing"
fi
squeue -j "$JOBID" -o '%.12i %.18j %.12T %.12M %.24R' 2>&1 || true
sacct -X -j "$JOBID" --starttime 2026-08-28 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList -P 2>&1 || true

echo "=== B LOG FILES ==="
for f in "$ROOT/logs/state_diagnostics_audit_${JOBID}.out" "$ROOT/logs/state_diagnostics_audit_${JOBID}.err"; do
  if [ -f "$f" ]; then
    stat -c '%n|bytes=%s|mtime=%y' "$f" 2>&1 || true
    echo "--- tail $f ---"
    tail -n 100 "$f" 2>&1 || true
  else
    echo "$f|missing"
  fi
done

echo "=== C EXTERNAL AUDIT REPORT ==="
if [ -f "$REPORT" ]; then
  stat -c '%n|bytes=%s|mtime=%y' "$REPORT" 2>&1 || true
  sha256sum "$REPORT" 2>&1 || true
  python - "$REPORT" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
report = json.loads(path.read_text(encoding="utf-8"))
seeds = report.get("seeds", [])
print(json.dumps({
    "schema": report.get("schema"),
    "status": report.get("status"),
    "seed_count": report.get("seed_count"),
    "array_count": report.get("array_count"),
    "raw_array_sha256_matches": report.get("raw_array_sha256_matches"),
    "npy_file_sha256_matches": report.get("npy_file_sha256_matches"),
    "seed_records": len(seeds) if isinstance(seeds, list) else None,
    "seed_array_count_sum": sum(int(seed.get("array_count", 0)) for seed in seeds) if isinstance(seeds, list) else None,
    "seed_raw_match_sum": sum(int(seed.get("raw_array_sha256_matches", 0)) for seed in seeds) if isinstance(seeds, list) else None,
    "seed_npy_match_sum": sum(int(seed.get("npy_file_sha256_matches", 0)) for seed in seeds) if isinstance(seeds, list) else None,
    "training_target_reads": report.get("training_target_reads"),
    "formal_evaluation_observation_reads": report.get("formal_evaluation_observation_reads"),
    "recent_path_executed": report.get("recent_path_executed"),
    "flow_head_executed": report.get("flow_head_executed"),
    "formal_period_predictions_generated": report.get("formal_period_predictions_generated"),
    "official_score_called": report.get("official_score_called"),
    "diagnostic_root_manifest_sha256": report.get("diagnostic_root_manifest_sha256"),
    "training_external_audit_sha256": report.get("training_external_audit_sha256"),
    "run_order_canonical_sha256": report.get("run_order_canonical_sha256"),
    "state_diagnostics_preregistration_sha256": report.get("state_diagnostics_preregistration_sha256"),
    "environment_sha256": report.get("environment_sha256"),
    "diagnostic_source_tree_sha256": report.get("diagnostic_source_tree_sha256"),
    "diagnostic_source_sha256": report.get("diagnostic_source_sha256"),
    "environment": report.get("environment"),
}, sort_keys=True))
PY
else
  echo "$REPORT|missing"
fi
echo "=== END ==="
