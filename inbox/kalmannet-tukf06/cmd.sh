#!/usr/bin/env bash
set -eo pipefail

TARGET=/data1/home/sunyiq/kalmannet_tukf06_20260809/retry2
OUTPUT="$TARGET/results/tukf06_full_diagonal_search_head_to_head_v1"
JID=$(tr -d '[:space:]' < "$TARGET/results/selection_job_id.txt")
if [[ "$JID" != "202136" ]]; then
  echo "selection job identifier mismatch: $JID" >&2
  exit 71
fi

echo "=== MONITOR FORMAL SELECTION JOB $JID ==="
for i in $(seq 1 60); do
  if ! squeue -h -j "$JID" -o '%i' 2>/dev/null | grep -q .; then
    echo "selection left queue after monitor_seconds=$(((i - 1) * 30))"
    break
  fi
  if [[ $((i % 10)) -eq 0 ]]; then
    echo "monitor_seconds=$((i * 30)) timestamp=$(date -Is)"
    squeue -h -j "$JID" -o '%.18i %.24j %.10P %.8T %.10M %.20R'
    tail -30 "$TARGET/logs/selection-${JID}.out" 2>/dev/null || true
    tail -30 "$TARGET/logs/selection-${JID}.err" 2>/dev/null || true
  fi
  sleep 30
done

echo "=== ACCOUNTING SNAPSHOT ==="
sacct -j "$JID" --format=JobID%18,JobName%20,Partition%10,NodeList%12,State%18,ExitCode%8,Elapsed%10,TotalCPU%12,MaxRSS%12
echo "=== FINAL LOG TAILS ==="
tail -120 "$TARGET/logs/selection-${JID}.out" 2>/dev/null || true
tail -120 "$TARGET/logs/selection-${JID}.err" 2>/dev/null || true
echo "=== SELECTION ARTIFACT STATUS ==="
if [[ -f "$OUTPUT/selection.sealed.json" ]]; then
  python - "$OUTPUT" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1]).resolve()
summary = json.loads((root / 'selection_summary.json').read_text(encoding='utf-8'))
seal_path = root / 'selection.sealed.json'
manifest_path = root / 'selection_manifest.sha256.json'
seal = json.loads(seal_path.read_text(encoding='utf-8'))
payload = {
    'seal': seal,
    'selection_status': summary['status'],
    'basin_count': summary['basin_count'],
    'evaluation_period_read': summary['evaluation_period_read'],
    'failures': summary['failures'],
    'wall_seconds': summary['wall_seconds'],
    'environment': summary['environment'],
    'selection_manifest_sha256': hashlib.sha256(manifest_path.read_bytes()).hexdigest(),
    'selection_seal_sha256': hashlib.sha256(seal_path.read_bytes()).hexdigest(),
}
print(json.dumps(payload, indent=2, sort_keys=True))
PY
else
  echo "selection_not_yet_sealed"
  if [[ -d "$OUTPUT/selection" ]]; then
    echo "completed_basin_json_count=$(find "$OUTPUT/selection" -maxdepth 1 -name 'basin_*.json' -type f | wc -l)"
  fi
fi
