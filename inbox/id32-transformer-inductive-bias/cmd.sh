#!/usr/bin/env bash
# ID32 seq=3 : watch the six arms. Read-only, no waiting loop.
set -o pipefail
ID32=/data1/home/sunyiq/id32_transformer_inductive_bias_20260902/repo

echo "=== A. SACCT ==="
sacct -j 218680,218681,218682,218683,218684,218685 -X --format=JobID%10,JobName%12,State%12,ExitCode%8,Elapsed%10,NodeList%10 2>&1 || true

echo "=== B. PROGRESS ==="
for A in R01 T02 T03 T04 T05 L01; do
  D=$(ls -d $ID32/results/32_transformer_inductive_bias/_invocations/id32_${A}_s100_slurm* 2>/dev/null | head -1)
  echo "--- $A dir=${D:-none}"
  if [ -n "$D" ] && [ -f "$D/output.log" ]; then
    tail -c 300000 "$D/output.log" | grep -oE 'Epoch [0-9]+ average loss: [0-9.]+' | tail -2 || true
    tail -3 "$D/output.log" || true
  fi
done

echo "=== C. MANIFEST ==="
for A in R01 T02 T03 T04 T05 L01; do
  M=$(ls $ID32/results/32_transformer_inductive_bias/_invocations/id32_${A}_s100_slurm*/run_manifest.json 2>/dev/null | head -1)
  if [ -n "$M" ]; then
    echo "--- $A"
    grep -E '"(status|training_return_code)"' "$M" || true
  fi
done
echo "ID32_WATCH_SEQ3_COMPLETE"
