#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ROOT" || exit 1
echo "=== STAMP ==="; date +%FT%T%z
echo "=== A. SACCT ==="
sacct -j 224310,224311,224312 -X --format=JobID%12,JobName%18,State%10,ExitCode%8,Elapsed%10,NodeList%15 2>&1 | head -12
echo "=== B. LATEST RUN DIRS (batch3 = 0909/0910) ==="
for a in T1 T2 T3 T4 T5 L33 C3 C4 C5; do
  d=$(ls -d results/33_transformer_recipe_repair/$a/*_2026_09[01]* 2>/dev/null | tail -1)
  [ -n "$d" ] || { echo "-- $a: NO_BATCH3_DIR"; continue; }
  echo "-- $a: $d"
  grep 'Median validation metrics' "$d/output.log" 2>/dev/null | tail -2 || true
done
echo "=== C. MANIFESTS ==="
ls -1 results/33_transformer_recipe_repair/_invocations/ 2>/dev/null | grep -E 'slurm2243' || echo NONE
for m in results/33_transformer_recipe_repair/_invocations/*slurm2243*/run_manifest.json; do
  [ -f "$m" ] || continue
  echo "-- $m"
  python -c "import json,sys;d=json.load(open(sys.argv[1]));print(' status=%s rc=%s data_access=%s'%(d.get('status'),d.get('training_return_code'),(d.get('data_access') or {}).get('status')))" "$m" 2>&1 | head -3
done
echo "=== D. UTILISATION ==="
for j in 224310 224311 224312; do
  f=logs/33_transformer_recipe_repair/utilisation-$j.csv
  [ -f "$f" ] || { echo "-- $j: NONE"; continue; }
  echo "-- $j lines=$(wc -l < "$f")"
  awk -F, 'NR>1{u+=$2;m+=$3;n++}END{if(n)printf("   mean_util=%.1f mean_mem=%.0f peak_mem_field4=%s n=%d\n",u/n,m/n,$4,n)}' "$f"
done
echo "=== E. ERR TAILS ==="
for j in 224310 224311 224312; do
  f=logs/33_transformer_recipe_repair/packed-$j.err
  [ -f "$f" ] && { echo "-- $f"; tail -5 "$f" || true; }
done
