#!/bin/bash
# seq=54 scheduled watch: seed-wave status only (read-only)
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ROOT" || exit 1
date -Iseconds
echo "=== SACCT ==="
sacct -j 225187,225190,225191,225192,225199,225200,225201 -X -o JobID,JobName%14,State,ExitCode,Elapsed,NodeList -P 2>&1 || true
echo "=== QUEUE ==="
squeue -u "$USER" -o "%.10i %.14j %.3t %.10M %.8N %R" 2>&1 | grep -E 'JOBID|id33_' || true
echo "=== EPOCH PROGRESS ==="
for d in results/33_transformer_recipe_repair/*_s[2-8]00/*/; do
  n=$(ls -d "$d"validation/model_epoch0* 2>/dev/null | wc -l)
  echo "$d epochs_validated=$n"
done 2>/dev/null || true
echo "=== MANIFESTS ==="
for m in results/33_transformer_recipe_repair/_invocations/*_s[2-8]00_slurm*/run_manifest.json; do
  echo "-- $m"; grep -oE '"status": *"[A-Z_]+"|"training_return_code": *[0-9-]+' "$m" | head -3 || true
done 2>/dev/null || true
echo "=== EPOCH30 MEDIANS (if any) ==="
for f in results/33_transformer_recipe_repair/*_s[2-8]00/*/validation/model_epoch030/validation_metrics.csv; do
  echo "-- $f"; python3 -c "
import csv,statistics,sys
r=list(csv.DictReader(open('$f')));k=[c for c in r[0] if c.lower()=='nse'][0]
v=[float(x[k]) for x in r if x[k] not in ('','nan')];print(len(v),statistics.median(v))" 2>&1 || true
done 2>/dev/null || true
echo "=== ERR TAILS ==="
for f in $(ls -t logs/33_transformer_recipe_repair/packed-2251*.err 2>/dev/null | head -7); do echo "-- $f"; tail -3 "$f" || true; done
