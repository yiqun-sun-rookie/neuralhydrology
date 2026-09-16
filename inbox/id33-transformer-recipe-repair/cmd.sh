#!/bin/bash
# seq=62 ID35 G1: deploy GRACE feature + arm, audit, run a 5-basin/1-epoch SMOKE on GPU, wait, report.
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
PAYLOAD=~/hpc_mailbox/payload/id33-transformer-recipe-repair/id35_g1_v01.tar.gz
echo "=== STAMP ==="; date -Iseconds
echo "=== A. IN-FLIGHT GATE (id33 arm jobs) + WHOSE JOBS ARE RUNNING ==="
INFLIGHT=$(squeue -u "$USER" -h -t RUNNING,CONFIGURING -o "%j" 2>/dev/null | grep -c '^id33_' || true)
echo "id33_in_flight_count=${INFLIGHT}"; [ "${INFLIGHT}" = "0" ] || { echo "REFUSING"; exit 1; }
squeue -u "$USER" -o "%.10i %.18j %.3t %.10M %.9N %R" 2>&1 | head -20 || true
echo "idle gpu nodes:"; sinfo -p hgpu2p,hgpu2 -N -h -o "%.10N %.8T" 2>&1 | grep -c idle || true
echo "=== B. EXTRACT + HASHES ==="
cd "$ROOT" || exit 1
tar -xzf "$PAYLOAD" -C "$ROOT"
sha256sum src/grace_input_runoff/features/grace_twsa_daily_v01.p src/transformer_recipe_repair/configs/g1.yml \
          src/transformer_recipe_repair/scripts/audit_configs.py src/transformer_recipe_repair/registry/experiments.csv
echo "g1 configs: $(ls src/transformer_recipe_repair/configs/g1*.yml | wc -l)"
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh; conda activate nh_final
echo "=== C. AUDIT ==="
python -m src.transformer_recipe_repair.scripts.audit_configs 2>&1 | tail -3
echo "=== D. SMOKE JOB (5 basins, 1 epoch, GPU) ==="
mkdir -p logs/35_grace_input_runoff results/35_grace_input_runoff/_smoke
cat > src/grace_input_runoff/hpc/smoke.slurm <<'SL'
#!/usr/bin/env bash
#SBATCH --job-name=id35_smoke
#SBATCH --partition=hgpu2p
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH --exclude=ngu002,ngu005
#SBATCH --time=00:30:00
#SBATCH --output=logs/35_grace_input_runoff/smoke-%j.out
#SBATCH --error=logs/35_grace_input_runoff/smoke-%j.err
set -eo pipefail
cd /data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh; conda activate nh_final
export MKL_THREADING_LAYER=GNU MKL_SERVICE_FORCE_INTEL=1 PYTHONUNBUFFERED=1 CUBLAS_WORKSPACE_CONFIG=":4096:8"
python -u -m src.transformer_recipe_repair.scripts.deterministic_train \
  --config-file src/grace_input_runoff/configs/g1_smoke.yml --gpu 0 --label smoke \
  --digest-dir results/35_grace_input_runoff/_smoke --deterministic
echo "=== SMOKE DONE ==="
SL
mkdir -p src/grace_input_runoff/hpc
OUT=$(sbatch src/grace_input_runoff/hpc/smoke.slurm 2>&1); echo "$OUT"
J=$(echo "$OUT" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true); [ -n "$J" ] || { echo "SUBMIT_FAILED"; exit 1; }
echo "smoke_job=$J"
echo "=== E. WAIT (max 20 min) ==="
for i in $(seq 1 120); do
  ST=$(sacct -j "$J" -X -n --format=State 2>/dev/null | head -1 | tr -d ' ')
  case "$ST" in RUNNING|PENDING|"") sleep 10;; *) echo "state=$ST after ${i}0s"; break;; esac
done
sacct -j "$J" -X --format=JobID%10,State%12,ExitCode%8,Elapsed%10 2>&1
echo "=== F. SMOKE OUTPUT ==="
grep -vE 'Evaluation:|it/s\]' logs/35_grace_input_runoff/smoke-$J.out 2>/dev/null | tail -25
echo "-- err tail --"; tail -n 12 logs/35_grace_input_runoff/smoke-$J.err 2>/dev/null | grep -vE 'FutureWarning|weights_only'
echo "-- run dir + inputs seen by the model --"
D=$(ls -d results/35_grace_input_runoff/_smoke/grace_input_runoff_G1_SMOKE_* 2>/dev/null | tail -1); echo "run_dir=$D"
grep -E 'grace_twsa_mm' "$D/config.yml" 2>/dev/null | head -2
grep -E 'Epoch 1 average|Median validation' "$D/output.log" 2>/dev/null | tail -3
ls "$D"/*.pt 2>/dev/null | head -3
cat results/35_grace_input_runoff/_smoke/smoke.json 2>/dev/null | head -20
