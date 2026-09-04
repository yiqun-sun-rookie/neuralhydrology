#!/bin/bash
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
echo "=== STAMP ==="; date -Is
echo "=== A. SACCT 8 JOBS ==="
sacct -j 220490,220491,220492,220493,220494,220495,220658,220659 -X --format=JobID%10,JobName%12,State%12,ExitCode%8,Elapsed%11,NodeList%9,End%20 2>&1 || true
echo "=== B. MANIFEST STATUS ==="
for d in $ROOT/results/33_transformer_recipe_repair/_invocations/*/; do
  m="$d/run_manifest.json"
  [ -f "$m" ] || continue
  echo "--- $(basename $d)"
  grep -E '"(status|training_return_code|source_tree_sha256|source_tree_sha256_after|status_before|status_after)"' "$m" | head -8 || true
  grep -A3 '"data_access"' "$m" | head -6 || true
done
echo "=== C. PER-EPOCH MEDIAN VALIDATION NSE ==="
for a in T1 T2 T3 T4 T5 L33 C1 C2; do
  echo "--- $a"
  f=$(ls -1 $ROOT/results/33_transformer_recipe_repair/$a/*/output.log 2>/dev/null | head -1)
  if [ -n "$f" ]; then
    grep -E "Epoch [0-9]+ average loss|Median validation" "$f" | tail -70 || true
  else
    echo "  no output.log"
  fi
done
echo "=== D. FAILURE EVIDENCE (err tails for non-COMPLETED) ==="
sacct -j 220490,220491,220492,220493,220494,220495,220658,220659 -X -n -P --format=JobID,State 2>/dev/null | grep -vE 'COMPLETED|RUNNING|PENDING' || echo "  none non-terminal-bad"
echo "ID33_WATCH_COMPLETE"
