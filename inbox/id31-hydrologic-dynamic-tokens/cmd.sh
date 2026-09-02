#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
cd "$ROOT"
DT08_DIR="$ROOT/results/31_hydrologic_dynamic_tokens/DT08/hydrologic_dynamic_tokens_DT08_fixed_08_s100_2026_0828_2034_ep30"
DT08_METRICS="$DT08_DIR/validation/model_epoch030/validation_metrics.csv"
echo "=== DT08 EXACT INTERNAL VALIDATION ==="
python - "$DT08_METRICS" <<'PY'
import sys
import pandas as pd
p=sys.argv[1]
df=pd.read_csv(p, dtype={"basin": str})
col="NSE" if "NSE" in df.columns else "nse"
print("DT08_METRICS_PATH", p)
print("DT08_ROW_COUNT", len(df))
print("DT08_COLUMNS", list(df.columns))
print("DT08_MEDIAN_NSE", repr(float(df[col].median())))
print("DT08_NSE_NON_NULL", int(df[col].notna().sum()))
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