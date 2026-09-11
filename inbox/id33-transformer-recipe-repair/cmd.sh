#!/bin/bash
# seq=48 patrol: seed-replication stage 1 status + batch-3 common-window rescore output
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ROOT" || exit 1
echo "=== STAMP ==="; date -Iseconds
echo "=== A. SACCT ==="
sacct -j 225186,225187,225188,225189,225190,225191,225192,225193 -X --format=JobID,JobName%16,State,ExitCode,Elapsed,NodeList 2>&1 || true
echo "=== B. QUEUE ==="
squeue -u "$USER" -o "%.10i %.14j %.3t %.10M %.8N %R" 2>&1 | grep -E 'JOBID|id33_' || true
echo "=== C. RESCORE ==="
ls -la results/33_transformer_recipe_repair/_reports/common_window_rescore.json 2>&1 || true
tail -40 logs/33_transformer_recipe_repair/rescore-225186.out 2>/dev/null || true
tail -20 logs/33_transformer_recipe_repair/rescore-225186.err 2>/dev/null || true
echo "###RESCORE_JSON_BEGIN"
cat results/33_transformer_recipe_repair/_reports/common_window_rescore.json 2>/dev/null || true
echo; echo "###RESCORE_JSON_END"
echo "=== D. SEED-JOB PROGRESS (latest epoch line per arm) ==="
for d in results/33_transformer_recipe_repair/*_s[2-8]00/*/output.log; do
  [ -f "$d" ] || continue
  echo "-- $d"; grep 'Median validation metrics' "$d" | tail -1 || true
done
echo "=== E. ERR TAILS ==="
for j in 225187 225188 225189 225190 225191 225192 225193; do
  f=logs/33_transformer_recipe_repair/packed-$j.err; [ -f "$f" ] && { echo "-- $f"; tail -5 "$f" || true; }
done
echo "=== F. UTIL ==="
for j in 225187 225188 225189 225190 225191 225192 225193; do
  f=logs/33_transformer_recipe_repair/utilisation-$j.csv; [ -f "$f" ] || continue
  echo "-- $j lines=$(wc -l < "$f")"
  awk -F, 'NR>1 && $2+0==$2 {u+=$2; m+=$3; n++} END{if(n) printf "   mean_util=%.1f mean_mem=%.0f n=%d\n",u/n,m/n,n}' "$f" || true
done
