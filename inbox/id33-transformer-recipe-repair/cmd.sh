#!/usr/bin/env bash
set -o pipefail
echo "=== STAMP ==="; date -Is
ID33=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ID33"
echo "=== A. JOBS ==="
sacct -j 222800,222801 -X --format=JobID%9,JobName%9,State%11,ExitCode%7,Elapsed%10,NodeList%8 2>&1 || true
squeue -j 222800,222801 -o "%.9i %.10j %.2t %.11M %.20R" 2>&1 || true
echo "=== B. PER-ARM EPOCH PROGRESS ==="
for a in T1 T2 T3 T4 T5 L33; do
  d=$(ls -1d results/33_transformer_recipe_repair/$a/*/ 2>/dev/null | tail -1)
  if [ -z "$d" ]; then echo "  $a: no run dir"; continue; fi
  ep=$(ls -1d "$d"validation/model_epoch* 2>/dev/null | wc -l)
  echo "  $a: $d  validation_epochs=$ep"
  grep -h "Median validation metrics" -A1 "$d"output.log 2>/dev/null | grep -o "NSE: [0-9.-]*" | tail -3 || true
done
echo "=== C. GPU UTILISATION ==="
for f in logs/33_transformer_recipe_repair/utilisation-*.csv; do
  test -f "$f" || continue
  n=$(( $(wc -l < "$f") - 1 ))
  echo "  $f samples=$n"
  [ "$n" -gt 0 ] && awk -F, 'NR>1{u+=$2;m+=$3;c++} END{if(c)printf("    gpu_util mean=%.1f%%  mem mean=%.0f MiB\n",u/c,m/c)}' "$f"
done
echo "=== D. ERRORS ==="
for f in logs/33_transformer_recipe_repair/*2228*.err; do test -f "$f" && { echo "-- $f"; tail -15 "$f" 2>&1; }; done || true
echo DONE
