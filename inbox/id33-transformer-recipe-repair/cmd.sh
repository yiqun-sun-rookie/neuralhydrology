#!/usr/bin/env bash
# ID33 seq=8 : diagnose L33 (220495) FAILED-after-30-epochs. Read only. No resubmission.
set -o pipefail
ID33=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ID33" 2>/dev/null || { echo NO_LANDING; exit 0; }
echo "=== A. STAMP ==="; date -Is
echo "=== B. MANIFEST ==="
cat results/33_transformer_recipe_repair/_invocations/id33_L33_s100_slurm220495/run_manifest.json 2>&1 | head -80 || true
echo "=== C. SLURM ERR TAIL ==="
for F in $(ls logs/33_transformer_recipe_repair/*220495* 2>/dev/null; ls results/33_transformer_recipe_repair/_invocations/id33_L33_s100_slurm220495/*.err 2>/dev/null; ls ~/*220495* 2>/dev/null); do
  echo "--- $F"; tail -40 "$F" 2>&1 || true
done
echo "=== D. RUNDIR TAIL ==="
for R in $(ls -d results/33_transformer_recipe_repair/L33/*/ 2>/dev/null); do
  echo "--- $R"; tail -30 "$R/output.log" 2>&1 || true
  echo "  epoch30 metrics file:"; ls -la "$R"validation/model_epoch030/ 2>&1 || true
done
echo "=== E. SEARCH FOR TRACEBACK ==="
grep -rn -m5 -A15 'Traceback' results/33_transformer_recipe_repair/L33/ 2>/dev/null | head -60 || true
echo ID33_SEQ8_COMPLETE
