#!/usr/bin/env bash
set -eo pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
JOB_ID=216549
RUN_ID="id31_DL01_s100_slurm${JOB_ID}"
RUN_ROOT="$ROOT/results/31_hydrologic_dynamic_tokens/DL01"
MANIFEST="$ROOT/results/31_hydrologic_dynamic_tokens/_invocations/${RUN_ID}/run_manifest.json"
STDERR="$ROOT/logs/31_hydrologic_dynamic_tokens/development-${JOB_ID}.err"

test -d "$ROOT/.git"
cd "$ROOT"

echo "=== SCHEDULER ==="
date -Is
squeue -j "$JOB_ID" -o '%.18i %.24j %.12P %.2t %.12M %.12l %.30R' || true
sacct -j "$JOB_ID" --format=JobID,JobName%24,Partition,State,ExitCode,Elapsed,Start,End,NodeList -n -P || true

echo "=== MANIFEST STATUS ==="
python - "$MANIFEST" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.is_file():
    print("MANIFEST_MISSING", path)
else:
    value = json.loads(path.read_text(encoding="utf-8"))
    print(json.dumps({
        "path": str(path),
        "sha256_note": "reported separately below",
        "status": value.get("status"),
        "run_id": value.get("run_id"),
        "seed": value.get("seed"),
        "started_at_utc": value.get("started_at_utc"),
        "finished_at_utc": value.get("finished_at_utc"),
        "return_code": value.get("return_code"),
    }, indent=2, sort_keys=True))
PY
if test -f "$MANIFEST"; then sha256sum "$MANIFEST"; fi

echo "=== BOUND SOURCE HASHES ==="
for path in \
  "$ROOT/neuralhydrology/training/regularization.py" \
  "$ROOT/test/test_hydrologic_dynamic_token_transformer.py" \
  "$ROOT/src/31_hydrologic_dynamic_tokens/configs/maurer/dl01_learned_end_to_end.yml" \
  "$ROOT/src/31_hydrologic_dynamic_tokens/registry/experiment_registry.yml"; do
  if test -f "$path"; then sha256sum "$path"; else echo "SOURCE_MISSING $path"; fi
done

LATEST_OUTPUT=$(find "$RUN_ROOT" -type f -name output.log -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)
echo "=== COMPACT TRAINING PROGRESS ==="
if test -n "$LATEST_OUTPUT" && test -f "$LATEST_OUTPUT"; then
  echo "ACTIVE_OUTPUT $LATEST_OUTPUT"
  grep -E 'Epoch [0-9]+ average loss|Finished training|Training ended|median.*NSE|NSE.*median|Validation.*finished' \
    "$LATEST_OUTPUT" | tail -n 80 || true
  echo "LAST_TIMESTAMPED_LINES"
  grep -E '^20[0-9]{2}-[0-9]{2}-[0-9]{2} ' "$LATEST_OUTPUT" | tail -n 30 || true
else
  echo "ACTIVE_OUTPUT_MISSING"
fi

echo "=== NEW-RUN METRICS AND CHECKPOINTS ==="
NEW_RUN_DIR=$(find "$RUN_ROOT" -mindepth 1 -maxdepth 1 -type d -name '*2026_0831_1223_ep30' | head -n 1)
if test -n "$NEW_RUN_DIR" && test -d "$NEW_RUN_DIR"; then
  echo "NEW_RUN_DIR $NEW_RUN_DIR"
  find "$NEW_RUN_DIR" -type f \
    \( -name 'epoch*_metrics.json' -o -name 'validation_metrics.csv' -o -name 'model_epoch*.pt' \
       -o -name 'validation_results.p' \) \
    -printf '%TY-%Tm-%TdT%TH:%TM:%TS%Tz %s %p\n' | sort
  python - "$NEW_RUN_DIR" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
for path in sorted(root.rglob("epoch*_metrics.json")):
    value = json.loads(path.read_text(encoding="utf-8"))
    selected = {}
    for key, item in value.items():
        lowered = str(key).lower()
        if any(token in lowered for token in ("epoch", "median", "nse", "basin", "status")):
            if isinstance(item, (str, int, float, bool)) or item is None:
                selected[key] = item
    print("COMPACT_METRICS", path)
    print(json.dumps(selected, indent=2, sort_keys=True))
PY
else
  echo "NEW_RUN_DIR_MISSING"
fi

echo "=== STDERR ==="
if test -f "$STDERR"; then
  if test -s "$STDERR"; then tail -n 120 "$STDERR"; else echo "STDERR_EMPTY"; fi
else
  echo "STDERR_MISSING $STDERR"
fi

echo "ID31_DL01_COMPACT_PROGRESS_COMPLETE"
