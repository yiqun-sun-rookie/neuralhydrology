#!/bin/bash
# id26-v09-strict seq=64: read-only status and artifact query for state diagnostics job 204847.
set -o pipefail
export LC_ALL=C

ROOT=/data1/home/sunyiq/v09_strict
AUDIT_PARENT=$ROOT/audit_v09
TRAIN_REPO=$ROOT/codetest/neuralhydrology
FORMAL_ROOT=$TRAIN_REPO/results/26_historical_band_experts/formal_v09
STATE_ROOT=$FORMAL_ROOT/state_diagnostics
BUILDING_ROOT=$FORMAL_ROOT/state_diagnostics.building
EXTERNAL_AUDIT=$FORMAL_ROOT/state_diagnostics_external_audit.json
JOBID_FILE=$AUDIT_PARENT/state_diagnostics_jobid.txt
JOBID=204847

echo "=== A JOB ID AND SCHEDULER ==="
if [ -f "$JOBID_FILE" ]; then
  RECORDED_JOBID=$(tr -d '[:space:]' < "$JOBID_FILE")
  echo "recorded_jobid=$RECORDED_JOBID"
else
  echo "recorded_jobid_file=missing"
fi
squeue -j "$JOBID" -o '%.12i %.18j %.12T %.12M %.24R' 2>&1 || true
sacct -X -j "$JOBID" --starttime 2026-08-18 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList -P 2>&1 || true

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
for p in "$STATE_ROOT" "$BUILDING_ROOT" "$EXTERNAL_AUDIT"; do
  if [ -e "$p" ]; then
    echo "$p|present"
  else
    echo "$p|missing"
  fi
done

if [ -d "$STATE_ROOT" ]; then
  echo "seed_dir_count=$(find "$STATE_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'E09-CONTINUOUS_s*' | wc -l)"
  echo "npy_file_count=$(find "$STATE_ROOT" -mindepth 2 -maxdepth 2 -type f -name '*.npy' | wc -l)"
  echo "child_manifest_count=$(find "$STATE_ROOT" -mindepth 2 -maxdepth 2 -type f -name 'manifest.json' | wc -l)"
  echo "child_summary_count=$(find "$STATE_ROOT" -mindepth 2 -maxdepth 2 -type f -name 'summary.json' | wc -l)"
  if [ -f "$STATE_ROOT/manifest.json" ]; then
    sha256sum "$STATE_ROOT/manifest.json" 2>&1 || true
    python - "$STATE_ROOT" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
children = manifest.get("children", [])
child_manifests = []
for child in children:
    path = root / child.get("relative_path", "") / "manifest.json"
    if path.is_file():
        child_manifests.append(json.loads(path.read_text(encoding="utf-8")))

print(json.dumps({
    "schema": manifest.get("schema"),
    "status": manifest.get("status"),
    "seed_count": manifest.get("seed_count"),
    "seeds": manifest.get("seeds"),
    "child_count": len(children),
    "child_manifest_count": len(child_manifests),
    "array_count_from_root": sum(int(child.get("array_count", 0)) for child in children),
    "array_count_from_children": sum(len(child.get("arrays", [])) for child in child_manifests),
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
  else
    echo "root_manifest=missing"
  fi
fi

if [ -d "$BUILDING_ROOT" ]; then
  echo "building_seed_dir_count=$(find "$BUILDING_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'E09-CONTINUOUS_s*' | wc -l)"
  echo "building_npy_file_count=$(find "$BUILDING_ROOT" -mindepth 2 -maxdepth 2 -type f -name '*.npy' | wc -l)"
fi

if [ -f "$EXTERNAL_AUDIT" ]; then
  sha256sum "$EXTERNAL_AUDIT" 2>&1 || true
  python - "$EXTERNAL_AUDIT" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
keys = [
    "schema", "status", "seed_count", "array_count",
    "raw_bytes_match_count", "file_sha256_match_count",
    "formal_evaluation_observation_reads", "official_score_called",
]
print(json.dumps({key: data.get(key) for key in keys}, sort_keys=True))
PY
fi

echo "=== END ==="
