#!/bin/bash
# Measure the A800's effect on the reported error, using the idle hgpu8 nodes.
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. SYNC ==="
cd "$ROOT/repo" || exit 1
D=$(git status --porcelain | grep -v '^?? ' | head -3); [ -n "$D" ] && { echo "dirty:"; echo "$D"; exit 1; }
timeout 180 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" || { echo FETCH_FAILED; exit 1; }
git reset -q --hard refs/remotes/origin/main
echo "  head: $(git log --oneline -1)"
G=$(sha256sum scripts/analysis/measure_platform_effect_v1.py | cut -d' ' -f1)
[ "$G" = "da58d08059944882c48a5b84aa32c1e9ec262688b204227ef0548075ee6e7161" ] && echo "  script identity ok" || { echo "  MISMATCH $G"; exit 1; }

echo "=== B. WRITE THE LAUNCHER ==="
mkdir -p "$ROOT/probe"
cat > "$ROOT/probe/platform.slurm" <<'SLURMEOF'
#!/usr/bin/env bash
#SBATCH -J zj_platform
#SBATCH -N 1
#SBATCH -n 1
#SBATCH --cpus-per-task=4
#SBATCH --gres=gpu:1
#SBATCH -t 01:00:00
#SBATCH -o /data1/home/sunyiq/zhenjiang_oyv_v1/probe/platform_%j.out
#SBATCH -e /data1/home/sunyiq/zhenjiang_oyv_v1/probe/platform_%j.err
set -eo pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
source /data1/home/${USER}/miniconda3/etc/profile.d/conda.sh || source $HOME/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export MKL_THREADING_LAYER=GNU
export MKL_SERVICE_FORCE_INTEL=1
export PYTHONPATH="${ROOT}/pysite:${PYTHONPATH:-}"
echo "NODE=$(hostname)"
nvidia-smi --query-gpu=name,driver_version --format=csv,noheader | head -1
cd "${ROOT}/repo"
python -u scripts/analysis/measure_platform_effect_v1.py \
  --tasks "${PLATFORM_TASKS}" \
  --reference-root "${ROOT}/ladder_tasks" \
  --scratch-root "${ROOT}/platform_scratch_$(hostname)_${SLURM_JOB_ID}" \
  --device cuda:0
SLURMEOF
sed -i 's/\r$//' "$ROOT/probe/platform.slurm"

# Twelve finished tasks spanning both targets, four conditions and two folds, so a
# platform effect cannot hide behind one particular arm.
TASKS="2017,zhenjiang,complete_observation,17;2017,zhenjiang,hidden_target_minus_nanjing,17;2017,zhenjiang,hidden_target_minus_jiangyin,17;2020,zhenjiang,complete_observation,17;2020,zhenjiang,hidden_target_minus_nanjing,17;2020,zhenjiang,hidden_target_minus_jiangyin,17;2017,jiangyin,complete_observation,17;2017,jiangyin,hidden_target_minus_xuliujing,17;2017,jiangyin,hidden_target_minus_wusongkou,17;2020,jiangyin,complete_observation,17;2020,jiangyin,hidden_target_minus_xuliujing,17;2020,jiangyin,hidden_target_minus_wusongkou,17"

echo "=== C. SUBMIT TO THE IDLE A800 NODES, AND A 3090 CONTROL ==="
IDS=""
for spec in "hgpu8 ngu201" "hgpu8 ngu203"; do
  set -- $spec
  out=$(sbatch --parsable -p "$1" --nodelist="$2" --job-name="pf_$2" -t 01:00:00 --export=ALL,PLATFORM_TASKS="$TASKS" "$ROOT/probe/platform.slurm" 2>&1)
  j=$(echo "$out" | grep -oE '^[0-9]+' || true)
  if [ -n "$j" ]; then echo "  $1/$2 -> $j"; IDS="$IDS $j"; else echo "  $1/$2 FAILED: $out"; fi
done
[ -n "$IDS" ] || { echo NONE_SUBMITTED; exit 1; }
echo "PLATFORM_JOB_IDS=$IDS"

echo "=== D. IMMEDIATE STATE ==="
sleep 25
for j in $IDS; do sacct -j "$j" -X --format=JobID%9,JobName%10,NodeList%8,State%11 2>&1 | tail -1; done
echo "  n4_tasks: $(ls -1 "$ROOT/n4_tasks" 2>/dev/null | wc -l) / 1440"
echo "=== DONE ==="
