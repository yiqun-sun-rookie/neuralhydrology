#!/usr/bin/env bash
set -o pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
JOB_ID=216549
RUN_ID="id31_DL01_s100_slurm${JOB_ID}"
RUN_ROOT="$ROOT/results/31_hydrologic_dynamic_tokens/DL01"
MANIFEST="$ROOT/results/31_hydrologic_dynamic_tokens/_invocations/${RUN_ID}/run_manifest.json"
STDERR="$ROOT/logs/31_hydrologic_dynamic_tokens/development-${JOB_ID}.err"
STAGING="$HOME/.hpc_mailbox_staging/id31-hydrologic-dynamic-tokens"

echo "=== AUX SNAPSHOT ==="
date -Is
squeue -j "$JOB_ID" -o '%.18i %.24j %.12P %.2t %.12M %.12l %.30R' || true
sacct -j "$JOB_ID" --format=JobID,JobName%24,Partition,State,ExitCode,Elapsed,Start,End,NodeList -n -P || true

echo "=== MANIFEST ==="
if test -f "$MANIFEST"; then
  python - "$MANIFEST" <<'PY'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
value = json.loads(path.read_text(encoding="utf-8"))
print(json.dumps({key: value.get(key) for key in (
    "status", "run_id", "seed", "started_at_utc", "finished_at_utc", "return_code"
)}, indent=2, sort_keys=True))
PY
  sha256sum "$MANIFEST"
else
  echo "MANIFEST_MISSING $MANIFEST"
fi

echo "=== SOURCE HASHES ==="
for path in \
  "$ROOT/neuralhydrology/training/regularization.py" \
  "$ROOT/test/test_hydrologic_dynamic_token_transformer.py" \
  "$ROOT/src/hydrologic_dynamic_tokens/configs/learned_end_to_end_s100.yml" \
  "$ROOT/src/hydrologic_dynamic_tokens/registry/experiments.csv"; do
  if test -f "$path"; then sha256sum "$path"; else echo "SOURCE_MISSING $path"; fi
done

echo "=== TRAINING PROGRESS ==="
LATEST_OUTPUT=$(find "$RUN_ROOT" -type f -name output.log -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)
if test -n "$LATEST_OUTPUT" && test -f "$LATEST_OUTPUT"; then
  echo "ACTIVE_OUTPUT $LATEST_OUTPUT"
  grep -E 'Epoch [0-9]+ average loss|Epoch [0-9]+ average validation loss|Finished training|Training ended|Stored metrics|Stored results' "$LATEST_OUTPUT" | tail -n 80 || true
else
  echo "ACTIVE_OUTPUT_MISSING"
fi

echo "=== ARTIFACTS ==="
NEW_RUN_DIR=$(find "$RUN_ROOT" -mindepth 1 -maxdepth 1 -type d -name '*2026_0831_1223_ep30' | head -n 1)
if test -n "$NEW_RUN_DIR" && test -d "$NEW_RUN_DIR"; then
  find "$NEW_RUN_DIR" -type f \( -name 'validation_metrics.csv' -o -name 'model_epoch*.pt' -o -name 'validation_results.p' \) -printf '%TY-%Tm-%TdT%TH:%TM:%TS%Tz %s %p\n' | sort
fi

echo "=== MAIN CHANNEL STAGING ==="
for seq in 39 40; do
  file="$STAGING/result_${seq}.txt"
  if test -f "$file"; then
    stat -c 'STAGING_FILE %n size=%s mtime=%y' "$file"
    tail -n 25 "$file" || true
  else
    echo "STAGING_MISSING $file"
  fi
done

echo "=== RUNNER PROCESSES ==="
pgrep -af hpc_runner_active || true
ps -eo pid,etimes,args | grep -E 'cmd_(39|40)\.sh|id31-hydrologic-dynamic-tokens|git (push|fetch|pull)' | grep -v grep || true

echo "=== STDERR ==="
if test -f "$STDERR"; then
  if test -s "$STDERR"; then tail -n 120 "$STDERR"; else echo "STDERR_EMPTY"; fi
else
  echo "STDERR_MISSING $STDERR"
fi

echo "ID31_AUX_SNAPSHOT_COMPLETE"
