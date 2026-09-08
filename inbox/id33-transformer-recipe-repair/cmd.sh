#!/bin/bash
# seq=34 deploy the reproducibility probe and submit both conditions.
# Deploy is gated on the in-flight check that batch 1 was destroyed for lacking.
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
PAYLOAD=~/hpc_mailbox/payload/id33-transformer-recipe-repair/id33_repro_probe_v01.tar.gz

echo "=== STAMP ==="; date -Iseconds

echo "=== A. IN-FLIGHT GATE ==="
INFLIGHT=$(squeue -u "$USER" -h -t RUNNING,CONFIGURING -o "%j" 2>/dev/null | grep -c '^id33_' || true)
echo "id33_in_flight_count=${INFLIGHT}"
if [ "${INFLIGHT}" != "0" ]; then echo "REFUSING TO DEPLOY: id33 job in flight"; exit 1; fi
echo "no id33 job in flight; safe to deploy"

echo "=== B. EXTRACT PAYLOAD ==="
ls -la "$PAYLOAD" 2>&1 || { echo "PAYLOAD MISSING"; exit 1; }
cd "$ROOT" || exit 1
tar -xzf "$PAYLOAD" -C "$ROOT"
sed -i 's/\r$//' src/transformer_recipe_repair/hpc/submit_repro_probe.slurm
echo "-- deployed hashes (must match local) --"
sha256sum src/transformer_recipe_repair/configs/repro_probe.yml \
          src/transformer_recipe_repair/scripts/deterministic_train.py \
          src/transformer_recipe_repair/hpc/submit_repro_probe.slurm

echo "=== C. UNTOUCHED: the eight registered configs and the registry ==="
sha256sum src/transformer_recipe_repair/registry/experiments.csv \
          src/transformer_recipe_repair/configs/t2.yml \
          src/transformer_recipe_repair/hpc/submit_packed_arms.slurm

echo "=== D. EXISTING AUDIT STILL PASSES ==="
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
python -m src.transformer_recipe_repair.scripts.audit_configs 2>&1 | tail -5 || true

echo "=== E. SUBMIT BOTH CONDITIONS ==="
mkdir -p logs/33_transformer_recipe_repair results/33_transformer_recipe_repair/_repro_probe
OUT1=$(sbatch --export=ALL,DET=1 --job-name=id33_repro_det src/transformer_recipe_repair/hpc/submit_repro_probe.slurm 2>&1)
echo "$OUT1"
J1=$(echo "$OUT1" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$J1" ] || { echo "SUBMIT_FAILED det"; exit 1; }

OUT2=$(sbatch --export=ALL,DET=0 --job-name=id33_repro_ctl src/transformer_recipe_repair/hpc/submit_repro_probe.slurm 2>&1)
echo "$OUT2"
J2=$(echo "$OUT2" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true)
[ -n "$J2" ] || { echo "SUBMIT_FAILED control (det job $J1 IS RUNNING)"; exit 1; }

echo "deterministic_job=$J1 control_job=$J2"

echo "=== F. QUEUE STATE ==="
sleep 20
squeue -u "$USER" -o "%.10i %.18j %.3t %.10M %.9N %R" 2>&1 | grep -E 'JOBID|id33_repro' || true
