#!/bin/bash
# Third attempt. The second died because sbatch --export separates variables with
# commas, and the task list is full of commas, so PLATFORM_TASKS arrived as the
# single token "2017". The list now travels in a file and only its path, which has
# no commas, goes through --export.
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
mkdir -p "$ROOT/probe"

printf '%s' "2017,zhenjiang,complete_observation,17;2017,zhenjiang,hidden_target_minus_nanjing,17;2017,zhenjiang,hidden_target_minus_jiangyin,17;2020,zhenjiang,complete_observation,17;2020,zhenjiang,hidden_target_minus_nanjing,17;2020,zhenjiang,hidden_target_minus_jiangyin,17" > "$ROOT/probe/tasks_zj.txt"
printf '%s' "2017,jiangyin,complete_observation,17;2017,jiangyin,hidden_target_minus_xuliujing,17;2017,jiangyin,hidden_target_minus_wusongkou,17;2020,jiangyin,complete_observation,17;2020,jiangyin,hidden_target_minus_xuliujing,17;2020,jiangyin,hidden_target_minus_wusongkou,17" > "$ROOT/probe/tasks_jy.txt"
echo "  task files written: $(wc -c < "$ROOT/probe/tasks_zj.txt") and $(wc -c < "$ROOT/probe/tasks_jy.txt") bytes"

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
TASKS=$(cat "${PLATFORM_TASK_FILE}")
echo "TASK_COUNT=$(echo "$TASKS" | tr ';' '\n' | wc -l)"
cd "${ROOT}/repo"
python -u scripts/analysis/measure_platform_effect_v1.py \
  --tasks "$TASKS" \
  --reference-root "${ROOT}/ladder_tasks" \
  --scratch-root "${ROOT}/platform_scratch_$(hostname)_${SLURM_JOB_ID}" \
  --device cuda:0
echo "PLATFORM_PROBE_DONE"
SLURMEOF
sed -i 's/\r$//' "$ROOT/probe/platform.slurm"

echo "=== SUBMIT ==="
IDS=""
o=$(sbatch --parsable -p hgpu8 --nodelist=ngu201 --job-name=pf_zj -t 01:00:00 --export=ALL,PLATFORM_TASK_FILE=/data1/home/sunyiq/zhenjiang_oyv_v1/probe/tasks_zj.txt "$ROOT/probe/platform.slurm" 2>&1)
j=$(echo "$o" | grep -oE '^[0-9]+' || true); [ -n "$j" ] && { echo "  ngu201 -> $j"; IDS="$IDS $j"; } || echo "  ngu201 FAILED: $o"
o=$(sbatch --parsable -p hgpu8 --nodelist=ngu203 --job-name=pf_jy -t 01:00:00 --export=ALL,PLATFORM_TASK_FILE=/data1/home/sunyiq/zhenjiang_oyv_v1/probe/tasks_jy.txt "$ROOT/probe/platform.slurm" 2>&1)
j=$(echo "$o" | grep -oE '^[0-9]+' || true); [ -n "$j" ] && { echo "  ngu203 -> $j"; IDS="$IDS $j"; } || echo "  ngu203 FAILED: $o"
[ -n "$IDS" ] || { echo NONE_SUBMITTED; exit 1; }
echo "PLATFORM_JOB_IDS=$IDS"

sleep 60
for j in $IDS; do sacct -j "$j" -X --format=JobID%9,JobName%8,NodeList%8,State%11,ExitCode%7,Elapsed%9 2>&1 | tail -1; done
for j in $IDS; do
  echo "  -- $j head --"; [ -f "$ROOT/probe/platform_${j}.out" ] && head -4 "$ROOT/probe/platform_${j}.out" | sed 's/^/    /' || echo "    none"
  [ -s "$ROOT/probe/platform_${j}.err" ] && { echo "  -- $j err --"; tail -6 "$ROOT/probe/platform_${j}.err" | sed 's/^/    /'; }
done
echo "  n4_tasks: $(ls -1 "$ROOT/n4_tasks" 2>/dev/null | wc -l) / 1440"
echo "=== DONE ==="
