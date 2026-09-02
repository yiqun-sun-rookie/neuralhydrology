#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
cd "$ROOT"
DT08_DIR="$ROOT/results/31_hydrologic_dynamic_tokens/DT08/hydrologic_dynamic_tokens_DT08_fixed_08_s100_2026_0828_2034_ep30"
DT08_METRICS="$DT08_DIR/validation/model_epoch030/validation_metrics.csv"
echo "=== DT08 EXACT INTERNAL VALIDATION ==="
python - "$DT08_METRICS" <<'PY'
import csv, statistics, sys
p=sys.argv[1]
with open(p, newline='', encoding='utf-8') as f:
    rows=list(csv.DictReader(f))
cols=list(rows[0]) if rows else []
col='NSE' if 'NSE' in cols else 'nse'
vals=[float(r[col]) for r in rows if r.get(col) not in ('', None)]
print('DT08_METRICS_PATH', p)
print('DT08_ROW_COUNT', len(rows))
print('DT08_COLUMNS', cols)
print('DT08_MEDIAN_NSE', repr(float(statistics.median(vals))))
print('DT08_NSE_NON_NULL', len(vals))
PY
sha256sum "$DT08_METRICS" "$DT08_DIR/model_epoch030.pt"
echo "=== CURRENT DL01 ==="
JOB=216549
squeue -j "$JOB" -o '%.18i %.24j %.12P %.2t %.12M %.12l %.30R' || true
sacct -j "$JOB" --format=JobID,JobName%24,Partition,State,ExitCode,Elapsed,Start,End,NodeList -n -P || true
MANIFEST="$ROOT/results/31_hydrologic_dynamic_tokens/_invocations/id31_DL01_s100_slurm${JOB}/run_manifest.json"
if test -f "$MANIFEST"; then cat "$MANIFEST"; sha256sum "$MANIFEST"; fi
OUT=$(find "$ROOT/results/31_hydrologic_dynamic_tokens/DL01" -type f -name output.log -printf '%T@ %p\n' | sort -nr | head -n1 | cut -d' ' -f2-)
echo "DL01_OUTPUT $OUT"
grep -E 'Epoch [0-9]+ average loss|Epoch [0-9]+ average validation loss|Finished training|Training ended' "$OUT" | tail -n 18 || true
sha256sum "$OUT"
STDERR="$ROOT/logs/31_hydrologic_dynamic_tokens/development-${JOB}.err"
if test -f "$STDERR"; then if test -s "$STDERR"; then tail -n 100 "$STDERR"; else echo STDERR_EMPTY; fi; fi
sha256sum "$ROOT/neuralhydrology/training/regularization.py" "$ROOT/test/test_hydrologic_dynamic_token_transformer.py" "$ROOT/src/hydrologic_dynamic_tokens/configs/learned_end_to_end_s100.yml" "$ROOT/src/hydrologic_dynamic_tokens/registry/experiments.csv"
echo ID31_HANDOFF_AUDIT_COMPLETE