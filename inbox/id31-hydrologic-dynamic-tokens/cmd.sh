#!/usr/bin/env bash
# ID31 seq=68 : DL01 job 216549 epoch-30 technical-completeness audit,
# DT08 control re-verification, and raw paired validation tables.
# Diagnostic only. No -e (an unmatched grep must not kill the script).
set -o pipefail

ROOT=/data1/home/sunyiq/id31_hydrologic_dynamic_tokens_20260828/repo
JOB_ID=216549
RUN_ID="id31_DL01_s100_slurm${JOB_ID}"
INV="$ROOT/results/31_hydrologic_dynamic_tokens/_invocations/${RUN_ID}"
MANIFEST="$INV/run_manifest.json"
STDERR="$ROOT/logs/31_hydrologic_dynamic_tokens/development-${JOB_ID}.err"
DL01="$ROOT/results/31_hydrologic_dynamic_tokens/DL01/hydrologic_dynamic_tokens_DL01_learned_end_to_end_s100_2026_0831_1223_ep30"
DT08="$ROOT/results/31_hydrologic_dynamic_tokens/DT08/hydrologic_dynamic_tokens_DT08_fixed_08_s100_2026_0828_2034_ep30"

echo "=== A. TIMESTAMP ==="
date -Is

echo "=== B. SLURM FINAL STATE ==="
squeue -j "$JOB_ID" -o '%.18i %.24j %.12P %.2t %.12M %.30R' 2>&1 || true
sacct -j "$JOB_ID" --format=JobID,JobName%24,Partition,State,ExitCode,Elapsed,Start,End,NodeList -n -P 2>&1 || true

echo "=== C. RUN MANIFEST FINAL ==="
python - "$MANIFEST" <<'PY' 2>&1 || true
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
if not p.is_file():
    print("MANIFEST_MISSING", p)
else:
    v = json.loads(p.read_text(encoding="utf-8"))
    print(json.dumps({k: v.get(k) for k in
        ("run_id","seed","status","started_at_utc","finished_at_utc",
         "return_code","formal_evaluation_authorized")},
        indent=2, sort_keys=True))
PY
test -f "$MANIFEST" && sha256sum "$MANIFEST" 2>&1 || true

echo "=== D. SOURCE INTEGRITY AFTER TRAINING ==="
for p in \
  "$ROOT/neuralhydrology/training/regularization.py" \
  "$ROOT/test/test_hydrologic_dynamic_token_transformer.py" \
  "$ROOT/src/hydrologic_dynamic_tokens/configs/learned_end_to_end_s100.yml" \
  "$ROOT/src/hydrologic_dynamic_tokens/configs/fixed_08_s100.yml" \
  "$ROOT/src/hydrologic_dynamic_tokens/registry/experiments.csv" \
  "$ROOT/neuralhydrology/modelzoo/hydrologic_dynamic_token_transformer.py" \
  "$ROOT/neuralhydrology/modelzoo/hydrologic_dynamic_tokenizer.py" \
  "$ROOT/neuralhydrology/modelzoo/modern_causal_transformer.py" ; do
  if test -f "$p"; then sha256sum "$p" 2>&1; else echo "SOURCE_MISSING $p"; fi
done

echo "=== E. DL01 EPOCH-30 ARTIFACTS ==="
for p in "$DL01/model_epoch030.pt" "$DL01/validation/model_epoch030/validation_metrics.csv"; do
  if test -f "$p"; then ls -la "$p" 2>&1; sha256sum "$p" 2>&1; else echo "ARTIFACT_MISSING $p"; fi
done

echo "=== F. DL01 TRAINING LOG TAIL ==="
if test -f "$DL01/output.log"; then
  grep -E 'Epoch (29|30) average|Epoch 30 average validation|Finished training|Training ended' "$DL01/output.log" 2>&1 | tail -n 12 || true
  echo "-- last 12 timestamped lines --"
  grep -E '^20[0-9]{2}-[0-9]{2}-[0-9]{2} ' "$DL01/output.log" 2>&1 | tail -n 12 || true
  echo "-- error scan --"
  grep -n -E 'Traceback|RuntimeError|CUDA error|nan|NaN' "$DL01/output.log" 2>&1 | tail -n 15 || echo "NO_ERROR_TOKENS"
else
  echo "OUTPUT_LOG_MISSING $DL01/output.log"
fi

echo "=== G. STDERR ==="
if test -f "$STDERR"; then
  echo "bytes=$(stat -c %s "$STDERR" 2>/dev/null)"
  tail -c 3000 "$STDERR" 2>&1 || true
  echo "STDERR_SHOWN"
else
  echo "STDERR_FILE_ABSENT $STDERR"
fi

echo "=== H. DATA ACCESS AUDIT ==="
if test -f "$INV/data_access.jsonl"; then
  echo "lines=$(wc -l < "$INV/data_access.jsonl" 2>/dev/null)"
  echo "-- forbidden token count (expect 0) --"
  grep -c -E 'usgs_streamflow|camels_hydro|_obs_eval\.parquet' "$INV/data_access.jsonl" 2>/dev/null || echo 0
  echo "-- sealed-window token count (expect 0) --"
  grep -c -E '19(89|9[0-8])-' "$INV/data_access.jsonl" 2>/dev/null || echo 0
  echo "-- first 3 records --"
  head -n 3 "$INV/data_access.jsonl" 2>&1 || true
  echo "-- last 2 records --"
  tail -n 2 "$INV/data_access.jsonl" 2>&1 || true
else
  echo "DATA_ACCESS_LOG_ABSENT $INV/data_access.jsonl"
fi

echo "=== I. VALIDATION TABLE SHAPE CHECK ==="
python - "$DL01/validation/model_epoch030/validation_metrics.csv" \
         "$DT08/validation/model_epoch030/validation_metrics.csv" <<'PY' 2>&1 || true
import csv, math, sys
from pathlib import Path
for tag, arg in zip(("DL01_ep030","DT08_ep030"), sys.argv[1:]):
    p = Path(arg)
    if not p.is_file():
        print(tag, "MISSING", p); continue
    rows = list(csv.DictReader(p.open(encoding="utf-8")))
    col = "NSE" if rows and "NSE" in rows[0] else (list(rows[0].keys())[-1] if rows else None)
    vals = []
    bad = 0
    for r in rows:
        s = (r.get(col) or "").strip()
        try:
            v = float(s)
        except ValueError:
            bad += 1; continue
        if math.isfinite(v): vals.append(v)
        else: bad += 1
    vals_sorted = sorted(vals)
    n = len(vals_sorted)
    med = None if n == 0 else (vals_sorted[n//2] if n % 2 else 0.5*(vals_sorted[n//2-1]+vals_sorted[n//2]))
    print(tag, "rows=%d" % len(rows), "column=%s" % col,
          "finite=%d" % n, "nonfinite_or_blank=%d" % bad, "median=%r" % med)
PY

echo "=== J. DL01 EPOCH-30 VALIDATION TABLE (full) ==="
cat "$DL01/validation/model_epoch030/validation_metrics.csv" 2>&1 || true
echo "DL01_TABLE_END"

echo "=== K. DT08 EPOCH-30 VALIDATION TABLE (full) ==="
cat "$DT08/validation/model_epoch030/validation_metrics.csv" 2>&1 || true
echo "DT08_TABLE_END"

echo "=== L. DT08 CONTROL RE-VERIFICATION ==="
sacct -j 215879 --format=JobID,JobName%24,State,ExitCode,Elapsed,End -n -P 2>&1 || true
for p in "$DT08/model_epoch030.pt" "$DT08/validation/model_epoch030/validation_metrics.csv"; do
  if test -f "$p"; then sha256sum "$p" 2>&1; else echo "DT08_ARTIFACT_MISSING $p"; fi
done

echo "=== M. PRESERVED FAILED RUN 215880 ==="
sacct -j 215880 --format=JobID,State,ExitCode,Elapsed,End -n -P 2>&1 || true
FAILMAN="$ROOT/results/31_hydrologic_dynamic_tokens/_invocations/id31_DL01_s100_slurm215880/run_manifest.json"
if test -f "$FAILMAN"; then sha256sum "$FAILMAN" 2>&1; else echo "FAILED_MANIFEST_MISSING $FAILMAN"; fi

echo "ID31_SEQ68_AUDIT_COMPLETE"
