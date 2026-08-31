#!/usr/bin/env bash
set -eo pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
JOB_ID=216549
RUN_ID="id31_DL01_s100_slurm${JOB_ID}"
MANIFEST="$ROOT/results/31_hydrologic_dynamic_tokens/_invocations/${RUN_ID}/run_manifest.json"
STDOUT="$ROOT/logs/31_hydrologic_dynamic_tokens/development-${JOB_ID}.out"
STDERR="$ROOT/logs/31_hydrologic_dynamic_tokens/development-${JOB_ID}.err"

test -d "$ROOT/.git"
cd "$ROOT"

echo "=== ID31 DL01 RETRY ${JOB_ID}: SCHEDULER ==="
squeue -j "$JOB_ID" -o '%.18i %.24j %.12P %.2t %.10M %.10l %.30R' || true
sacct -j "$JOB_ID" --format=JobID,JobName%24,Partition,State,ExitCode,Elapsed,Start,End,NodeList -n -P || true

echo "=== RUN MANIFEST ==="
if test -f "$MANIFEST"; then sha256sum "$MANIFEST"; cat "$MANIFEST"; else echo "RUN_MANIFEST_PENDING $MANIFEST"; fi

echo "=== STDOUT TAIL ==="
if test -f "$STDOUT"; then tail -n 220 "$STDOUT"; else echo "STDOUT_PENDING $STDOUT"; fi
echo "=== STDERR TAIL ==="
if test -f "$STDERR"; then tail -n 220 "$STDERR"; else echo "STDERR_PENDING $STDERR"; fi

echo "=== CURRENT SOURCE INTEGRITY ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python - <<'PY'
import json
from src.hydrologic_dynamic_tokens.scripts.run_development import capture_source_integrity

print(json.dumps(capture_source_integrity("DL01"), indent=2, sort_keys=True))
PY

echo "ID31_DL01_RETRY_STATUS_COMPLETE"
