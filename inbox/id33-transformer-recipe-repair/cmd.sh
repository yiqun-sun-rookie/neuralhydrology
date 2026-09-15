#!/bin/bash
# seq=58 collect: ID34 stage-1 verdict (225539) + K1 8-seed results (225548-50) + per-basin tables.
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ROOT" || exit 1
echo "=== STAMP ==="; date -Iseconds
echo "=== A. JOB STATES ==="
sacct -j 225539,225548,225549,225550 -X --format=JobID%10,JobName%14,State%12,ExitCode%8,Elapsed%10,NodeList%8 2>&1 || true
echo "=== B. ID34 STAGE-1 REPORT ==="
R=results/34_path_signature_runoff/_reports/stage1_residual_diagnostic.json
if [ -f "$R" ]; then cat "$R"; else echo "NO REPORT"; echo "-- out tail --"; tail -n 40 logs/34_path_signature_runoff/stage1-225539.out 2>/dev/null; echo "-- err tail --"; tail -n 25 logs/34_path_signature_runoff/stage1-225539.err 2>/dev/null; fi
echo "=== C. K1 MANIFESTS ==="
for d in results/33_transformer_recipe_repair/_invocations/id33_K1*; do
  [ -f "$d/run_manifest.json" ] || continue
  printf "%s " "$(basename $d)"; python -c "import json,sys; m=json.load(open('$d/run_manifest.json')); print(m.get('status'), m.get('training_return_code'), (m.get('data_access') or {}).get('status'))"
done
echo "=== D. K1 EPOCH-30 MEDIANS ==="
for a in K1 K1_s200 K1_s300 K1_s400 K1_s500 K1_s600 K1_s700 K1_s800; do
  d=$(ls -d results/33_transformer_recipe_repair/$a/*_2026_09* 2>/dev/null | tail -1)
  [ -n "$d" ] || { echo "$a NONE"; continue; }
  grep 'Epoch 30 average' "$d/output.log" 2>/dev/null | sed -E "s/.*NSE: ([0-9.\-]+).*/$a epoch30_median=\1/" || echo "$a no epoch30 line"
done
echo "=== E. K1 PER-BASIN EPOCH-30 TABLES ==="
for a in K1 K1_s200 K1_s300 K1_s400 K1_s500 K1_s600 K1_s700 K1_s800; do
  d=$(ls -d results/33_transformer_recipe_repair/$a/*_2026_09* 2>/dev/null | tail -1)
  f="$d/validation/model_epoch030/validation_metrics.csv"
  [ -f "$f" ] || { echo "###ARM $a NOFILE"; continue; }
  echo "###ARM $a rows=$(wc -l < "$f")"; cat "$f"
done
echo "=== F. ERR TAILS ==="
for j in 225548 225549 225550; do echo "-- $j --"; tail -n 4 logs/33_transformer_recipe_repair/packed-$j.err 2>/dev/null; done
