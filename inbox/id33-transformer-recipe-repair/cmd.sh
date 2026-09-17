#!/bin/bash
# seq=66 read-only: G1 job states, per-arm epoch progress, any errors.
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ROOT" || exit 1
echo "=== STAMP ==="; date -Iseconds
echo "=== A. JOBS ==="
sacct -j 226118,226119,226120 -X --format=JobID%10,JobName%12,State%12,ExitCode%8,Elapsed%10,NodeList%8 2>&1
echo "=== B. PER-ARM PROGRESS (last epoch line) ==="
for a in G1 G1_s200 G1_s300 G1_s400 G1_s500 G1_s600 G1_s700 G1_s800; do
  d=$(ls -d results/33_transformer_recipe_repair/$a/*_2026_09* 2>/dev/null | tail -1)
  [ -n "$d" ] || { echo "$a: not started"; continue; }
  last=$(grep -E 'Epoch [0-9]+ average validation' "$d/output.log" 2>/dev/null | tail -1 | sed -E 's/.*Epoch ([0-9]+) .*NSE: ([0-9.\-]+).*/ep\1 NSE=\2/')
  echo "$a: ${last:-no epoch yet}"
done
echo "=== C. MANIFESTS SO FAR ==="
for d in results/33_transformer_recipe_repair/_invocations/id33_G1*; do [ -f "$d/run_manifest.json" ] && printf "%s " "$(basename $d)" && python -c "import json; m=json.load(open('$d/run_manifest.json')); print(m.get('status'), m.get('training_return_code'), (m.get('data_access') or {}).get('status'))"; done
echo "=== D. ERR TAILS ==="
for j in 226118 226119 226120; do echo "-- $j --"; tail -n 3 logs/33_transformer_recipe_repair/packed-$j.err 2>/dev/null | grep -vE 'FutureWarning|weights_only|torch.load'; done
