#!/bin/bash
# id26-v09-strict seq=67: read-only terminal status and artifact query for state diagnostics attempt 02 job 211643.
set -o pipefail
export LC_ALL=C

ROOT=/data1/home/sunyiq/v09_strict
AUDIT_PARENT=$ROOT/audit_v09
TRAIN_REPO=$ROOT/codetest/neuralhydrology
FORMAL_ROOT=$TRAIN_REPO/results/26_historical_band_experts/formal_v09
STATE_ROOT=$FORMAL_ROOT/state_diagnostics
BUILDING_ROOT=$FORMAL_ROOT/state_diagnostics.building
FAILED_ROOT=$FORMAL_ROOT/state_diagnostics.attempt_01.job_204847.failed
JOBID_FILE=$AUDIT_PARENT/state_diagnostics_attempt_02_jobid.txt
JOBID=211643

echo "=== A JOB ID AND SCHEDULER ==="
if [ -f "$JOBID_FILE" ]; then
  echo "recorded_jobid=$(tr -d '[:space:]' < "$JOBID_FILE")"
else
  echo "recorded_jobid_file=missing"
fi
squeue -j "$JOBID" -o '%.12i %.18j %.12T %.12M %.24R' 2>&1 || true
sacct -X -j "$JOBID" --starttime 2026-08-25 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList -P 2>&1 || true

echo "=== B LOG FILES ==="
for f in "$ROOT/logs/state_diagnostics_${JOBID}.out" "$ROOT/logs/state_diagnostics_${JOBID}.err"; do
  if [ -f "$f" ]; then
    stat -c '%n|bytes=%s|mtime=%y' "$f" 2>&1 || true
    echo "--- tail $f ---"
    tail -n 80 "$f" 2>&1 || true
  else
    echo "$f|missing"
  fi
done

echo "=== C OUTPUT INVENTORY ==="
for p in "$STATE_ROOT" "$BUILDING_ROOT" "$FAILED_ROOT"; do
  if [ -e "$p" ]; then
    echo "$p|present"
  else
    echo "$p|missing"
  fi
done

for p in "$STATE_ROOT" "$BUILDING_ROOT"; do
  if [ -d "$p" ]; then
    echo "$p|seed_dirs=$(find "$p" -mindepth 1 -maxdepth 1 -type d -name 'E09-CONTINUOUS_s*' | wc -l)|npy_files=$(find "$p" -mindepth 2 -maxdepth 2 -type f -name '*.npy' | wc -l)|manifests=$(find "$p" -mindepth 2 -maxdepth 2 -type f -name 'manifest.json' | wc -l)|summaries=$(find "$p" -mindepth 2 -maxdepth 2 -type f -name 'summary.json' | wc -l)"
    if [ -f "$p/manifest.json" ]; then
      sha256sum "$p/manifest.json" 2>&1 || true
      python - "$p" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
children = manifest.get("children", [])
child_manifests = []
child_summaries = []
for child in children:
    child_root = root / child.get("relative_path", "")
    manifest_path = child_root / "manifest.json"
    summary_path = child_root / "summary.json"
    if manifest_path.is_file():
        child_manifests.append(json.loads(manifest_path.read_text(encoding="utf-8")))
    if summary_path.is_file():
        child_summaries.append(json.loads(summary_path.read_text(encoding="utf-8")))

nonfinite_positions = 0
for summary in child_summaries:
    for checkpoint in summary.get("checkpoints", {}).values():
        for key in ("panel", "all_training_keys"):
            block = checkpoint.get(key)
            if isinstance(block, dict):
                nonfinite_positions += len(block.get("nonfinite_positions", []))

print(json.dumps({
    "schema": manifest.get("schema"),
    "status": manifest.get("status"),
    "seed_count": manifest.get("seed_count"),
    "seeds": manifest.get("seeds"),
    "child_count": len(children),
    "child_manifest_count": len(child_manifests),
    "array_count_from_root": sum(int(child.get("array_count", 0)) for child in children),
    "array_count_from_children": sum(len(child.get("arrays", {})) for child in child_manifests),
    "nonfinite_positions": nonfinite_positions,
    "training_target_reads": manifest.get("training_target_reads"),
    "formal_evaluation_observation_reads": manifest.get("formal_evaluation_observation_reads"),
    "recent_path_executed": manifest.get("recent_path_executed"),
    "flow_head_executed": manifest.get("flow_head_executed"),
    "formal_period_predictions_generated": manifest.get("formal_period_predictions_generated"),
    "official_score_called": manifest.get("official_score_called"),
    "training_external_audit_sha256": manifest.get("training_external_audit_sha256"),
    "environment_sha256": manifest.get("environment_sha256"),
    "diagnostic_source_sha256": manifest.get("diagnostic_source_sha256"),
}, sort_keys=True))
PY
    fi
  fi
done

echo "=== END ==="
