#!/bin/bash
# Retry the platform measurement. The first attempt died of SIGPIPE: nvidia-smi
# prints one line per card and `| head -1` closed the pipe after the first, which
# under `set -eo pipefail` kills the whole script. Eight cards, eight lines, one
# reader. The 3090 launcher never hit it because it did not pipe at all.
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

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
nvidia-smi --query-gpu=index,name,driver_version --format=csv,noheader --id=0
cd "${ROOT}/repo"
python -u scripts/analysis/measure_platform_effect_v1.py \
  --tasks "${PLATFORM_TASKS}" \
  --reference-root "${ROOT}/ladder_tasks" \
  --scratch-root "${ROOT}/platform_scratch_$(hostname)_${SLURM_JOB_ID}" \
  --device cuda:0
echo "PLATFORM_PROBE_DONE"
SLURMEOF
sed -i 's/\r$//' "$ROOT/probe/platform.slurm"
echo "  launcher rewritten (no head, --id=0 instead)"

TASKS="2017,zhenjiang,complete_observation,17;2017,zhenjiang,hidden_target_minus_nanjing,17;2017,zhenjiang,hidden_target_minus_jiangyin,17;2020,zhenjiang,complete_observation,17;2020,zhenjiang,hidden_target_minus_nanjing,17;2020,zhenjiang,hidden_target_minus_jiangyin,17"
TASKS2="2017,jiangyin,complete_observation,17;2017,jiangyin,hidden_target_minus_xuliujing,17;2017,jiangyin,hidden_target_minus_wusongkou,17;2020,jiangyin,complete_observation,17;2020,jiangyin,hidden_target_minus_xuliujing,17;2020,jiangyin,hidden_target_minus_wusongkou,17"

echo "=== SUBMIT: six zhenjiang tasks on ngu201, six jiangyin tasks on ngu203 ==="
IDS=""
o=$(sbatch --parsable -p hgpu8 --nodelist=ngu201 --job-name=pf_zj -t 01:00:00 --export=ALL,PLATFORM_TASKS="$TASKS" "$ROOT/probe/platform.slurm" 2>&1)
j=$(echo "$o" | grep -oE '^[0-9]+' || true); [ -n "$j" ] && { echo "  ngu201 -> $j"; IDS="$IDS $j"; } || echo "  ngu201 FAILED: $o"
o=$(sbatch --parsable -p hgpu8 --nodelist=ngu203 --job-name=pf_jy -t 01:00:00 --export=ALL,PLATFORM_TASKS="$TASKS2" "$ROOT/probe/platform.slurm" 2>&1)
j=$(echo "$o" | grep -oE '^[0-9]+' || true); [ -n "$j" ] && { echo "  ngu203 -> $j"; IDS="$IDS $j"; } || echo "  ngu203 FAILED: $o"
[ -n "$IDS" ] || { echo NONE_SUBMITTED; exit 1; }
echo "PLATFORM_JOB_IDS=$IDS"

sleep 40
for j in $IDS; do sacct -j "$j" -X --format=JobID%9,JobName%8,NodeList%8,State%11,Elapsed%9 2>&1 | tail -1; done
echo "  n4_tasks: $(ls -1 "$ROOT/n4_tasks" 2>/dev/null | wc -l) / 1440"
echo "=== DONE ==="
