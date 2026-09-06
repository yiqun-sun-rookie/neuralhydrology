#!/usr/bin/env bash
set -o pipefail
echo "=== STAMP ==="; date -Is
ID33=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ID33" || exit 1
echo "=== A. SACCT ==="
sacct -j 222800,222801,220658,220659 -X --format=JobID%10,JobName%18,NodeList%10,State%14,ExitCode%8,Elapsed%12,Start%20,End%20 2>&1 || true
echo "=== B. MANIFESTS ==="
for d in results/33_transformer_recipe_repair/_invocations/*/; do
  m="$d/run_manifest.json"
  [ -f "$m" ] || continue
  echo "-- $(basename $d)"
  grep -oE '"(status|training_return_code|source_config_sha256|source_impl_sha256|source_config_sha256_post|source_impl_sha256_post|validation_median_nse)"[^,}]*' "$m" | sed 's/^/   /' || true
  grep -A4 '"data_access"' "$m" | grep -oE '"status"[^,}]*' | sed 's/^/   data_access /' || true
done
echo "=== C. PER-EPOCH MEDIAN NSE ==="
for a in T1 T2 T3 T4 T5 L33; do
  d=$(ls -1d results/33_transformer_recipe_repair/$a/*/ 2>/dev/null | tail -1)
  [ -n "$d" ] || { echo "-- $a NO_RUNDIR"; continue; }
  echo "-- $a $d"
  grep -hE 'Epoch [0-9]+ average validation loss|Median validation metrics|NSE: ' "$d/output.log" 2>/dev/null | tail -40 | sed 's/^/   /' || true
  echo "   epoch dirs: $(ls -1d $d/validation/model_epoch* 2>/dev/null | wc -l)"
done
echo "=== D. ERR TAILS ==="
for j in 222800 222801; do
  echo "-- $j"
  tail -20 logs/33_transformer_recipe_repair/*${j}*.err 2>/dev/null | sed 's/^/   /' || true
done
echo DONE
