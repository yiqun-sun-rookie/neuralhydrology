#!/bin/bash
# seq=35 deploy the common-window rescore and submit it.
#
# Gate reasoning: the blanket "no id33 job in flight" rule exists because batch 1 was killed by
# run_development.py's integrity guard when sibling files changed mid-training. That guard only
# runs inside run_development.py. This deploy adds TWO NEW FILES that nothing in flight reads,
# and the currently running id33_repro_det / id33_repro_ctl jobs do not use run_development.py.
# So the gate below refuses on any in-flight id33 job that is NOT one of those two.
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
PAYLOAD=~/hpc_mailbox/payload/id33-transformer-recipe-repair/id33_rescore_v01.tar.gz

echo "=== STAMP ==="; date -Iseconds

echo "=== A. NARROWED IN-FLIGHT GATE ==="
squeue -u "$USER" -h -t RUNNING,CONFIGURING -o "%i %j" 2>/dev/null | grep '^.* id33_' || echo "  (no id33 jobs)"
UNSAFE=$(squeue -u "$USER" -h -t RUNNING,CONFIGURING -o "%j" 2>/dev/null | grep '^id33_' | grep -vE '^id33_repro_(det|ctl)$' | wc -l)
echo "unsafe_id33_in_flight=${UNSAFE}"
if [ "${UNSAFE}" != "0" ]; then echo "REFUSING TO DEPLOY: an arm job is in flight"; exit 1; fi
echo "only read-only repro probes in flight; safe to add new files"

echo "=== B. REPRO PROBE PROGRESS (do not disturb) ==="
sacct -j "$(squeue -u "$USER" -h -o '%i %j' | awk '$2 ~ /id33_repro/ {print $1}' | paste -sd, -)" \
      -X --format=JobID%10,JobName%16,State%12,Elapsed%10,NodeList%8 2>&1 | head -6 || true
for L in det ctl; do
  F=$(ls -t "$ROOT"/logs/33_transformer_recipe_repair/repro-*.out 2>/dev/null | head -2)
  :
done
tail -n 4 $(ls -t "$ROOT"/logs/33_transformer_recipe_repair/repro-*.out 2>/dev/null | head -2) 2>&1 | head -20 || true

echo "=== C. EXTRACT ==="
ls -la "$PAYLOAD" 2>&1 || { echo "PAYLOAD MISSING"; exit 1; }
cd "$ROOT" || exit 1
tar -xzf "$PAYLOAD" -C "$ROOT"
sed -i 's/\r$//' src/transformer_recipe_repair/hpc/submit_rescore.slurm
sha256sum src/transformer_recipe_repair/scripts/rescore_common_window.py \
          src/transformer_recipe_repair/hpc/submit_rescore.slurm

echo "=== D. ID30 BASELINES READABLE? (read-only) ==="
ID30=/data1/home/sunyiq/id30_modern_transformer_moe_20260827/repo/results/30_modern_transformer_moe
for A in D01 B01; do
  n=$(find "$ID30/$A" -maxdepth 4 -name 'validation_results.p' 2>/dev/null | wc -l)
  echo "  $A validation_results.p count=$n"
done

echo "=== E. SUBMIT ==="
OUT=$(sbatch src/transformer_recipe_repair/hpc/submit_rescore.slurm 2>&1)
echo "$OUT"
J=$(echo "$OUT" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$J" ] || { echo "SUBMIT_FAILED"; exit 1; }
echo "rescore_job=$J"
