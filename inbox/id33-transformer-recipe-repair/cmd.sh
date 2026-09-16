#!/bin/bash
# seq=63 ID35 smoke, take 2 (mkdir before writing the slurm file). Files already deployed by seq=62.
set -o pipefail
ROOT=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo
cd "$ROOT" || exit 1
echo "=== STAMP ==="; date -Iseconds
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh; conda activate nh_final
mkdir -p src/grace_input_runoff/hpc logs/35_grace_input_runoff results/35_grace_input_runoff/_smoke
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
OUT=$(sbatch src/grace_input_runoff/hpc/smoke.slurm 2>&1); echo "$OUT"
J=$(echo "$OUT" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+' || true); [ -n "$J" ] || { echo "SUBMIT_FAILED"; exit 1; }
echo "smoke_job=$J"
echo "=== WAIT (max 20 min) ==="
for i in $(seq 1 120); do
  ST=$(sacct -j "$J" -X -n --format=State 2>/dev/null | head -1 | tr -d ' ')
  case "$ST" in RUNNING|PENDING|"") sleep 10;; *) echo "state=$ST after ${i}0s"; break;; esac
done
sacct -j "$J" -X --format=JobID%10,State%12,ExitCode%8,Elapsed%10,NodeList%8 2>&1
echo "=== SMOKE OUTPUT ==="
grep -vE 'Evaluation:|it/s\]|Epoch 1:' logs/35_grace_input_runoff/smoke-$J.out 2>/dev/null | tail -25
echo "-- err tail --"; tail -n 15 logs/35_grace_input_runoff/smoke-$J.err 2>/dev/null | grep -vE 'FutureWarning|weights_only|torch.load'
echo "-- run dir --"
D=$(ls -d results/35_grace_input_runoff/_smoke/grace_input_runoff_G1_SMOKE_* 2>/dev/null | tail -1); echo "run_dir=$D"
grep -cE 'grace_twsa_mm' "$D/config.yml" 2>/dev/null | xargs -I{} echo "grace column in saved config: {}"
grep -E 'Epoch 1 average|Median validation' "$D/output.log" 2>/dev/null | tail -3
ls "$D"/model_epoch*.pt 2>/dev/null
python -c "import json;d=json.load(open('results/35_grace_input_runoff/_smoke/smoke.json'));print('failed=',d['training_failed']);print('weights=',d['weight_sha256'])" 2>/dev/null
