#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
OLD_JOB=215880
cd "$ROOT"
echo "=== OLD SCHEDULER ==="
sacct -j "$OLD_JOB" --format=JobID,JobName%24,Partition,State,ExitCode,Elapsed,Start,End,NodeList -n -P || true
echo "=== OLD MANIFEST ==="
MANIFEST="$ROOT/results/31_hydrologic_dynamic_tokens/_invocations/id31_DL01_s100_slurm${OLD_JOB}/run_manifest.json"
if test -f "$MANIFEST"; then cat "$MANIFEST"; sha256sum "$MANIFEST"; else echo "OLD_MANIFEST_MISSING $MANIFEST"; fi
echo "=== OLD STDERR ==="
STDERR="$ROOT/logs/31_hydrologic_dynamic_tokens/development-${OLD_JOB}.err"
if test -f "$STDERR"; then wc -c "$STDERR"; tail -n 240 "$STDERR"; else echo "OLD_STDERR_MISSING $STDERR"; fi
echo "=== MATCHING OLD OUTPUT ==="
find "$ROOT/results/31_hydrologic_dynamic_tokens/DL01" -type f -name output.log -print0 2>/dev/null | while IFS= read -r -d '' f; do if grep -qE 'RuntimeError|broadcast shape|Traceback' "$f"; then echo "OLD_OUTPUT $f"; tail -n 240 "$f"; fi; done
echo "=== FIXED SOURCE ==="
sha256sum "$ROOT/neuralhydrology/training/regularization.py" "$ROOT/test/test_hydrologic_dynamic_token_transformer.py" "$ROOT/src/hydrologic_dynamic_tokens/configs/learned_end_to_end_s100.yml"
sed -n '70,88p' "$ROOT/neuralhydrology/training/regularization.py"
echo ID31_OLD_FAILURE_AUDIT_COMPLETE