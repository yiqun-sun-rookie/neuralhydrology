#!/bin/bash
# precip-swap -- install the corrected SLURM templates and resubmit on hgpu4.
# Root cause of the 3-second failure of gate 224441: the inline environment guard contained a backslash literal
# that lost one level of escaping when the template was written through a shell heredoc, so python received
# .replace('\','/') and raised SyntaxError before importing anything. The partition was NOT at fault.
# The corrected templates use pathlib.as_posix() and contain no backslash literals at all.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap_daily_2026_09
M=$HOME/hpc_mailbox/inbox/attrswap-daily/payload

echo "=== A. CANCEL THE SIX ORPHANED ARMS (explicit ids only, never -u) ==="
for j in $(tail -n +2 "$R/logs/job_ids.txt"); do
  st=$(sacct -j "$j" -X -n --format=State 2>/dev/null | head -1 | tr -d ' ')
  case "$st" in
    PENDING) scancel "$j" && echo "  已取消 $j（依赖永不可满足）";;
    RUNNING) echo "  $j 正在运行 —— 停下报告"; exit 1;;
    *) echo "  $j 状态 $st —— 不动";;
  esac
done
mv "$R/logs/job_ids.txt" "$R/logs/job_ids.hgpu4_attempt1.txt"

echo "=== B. INSTALL CORRECTED TEMPLATES ==="
for f in pswap_gate.slurm pswap_train.slurm; do
  echo "  before $f $(sha256sum $R/hpc_deploy/$f 2>/dev/null | cut -c1-16)"
  cp "$M/$f" "$R/hpc_deploy/$f" || { echo COPY_FAILED; exit 1; }
  sed -i 's/\r$//' "$R/hpc_deploy/$f"
  echo "  after  $f $(sha256sum $R/hpc_deploy/$f | cut -c1-16)"
done
echo "--- 确认新模板里没有反斜杠字面量，且分区为 hgpu4 ---"
for f in pswap_gate.slurm pswap_train.slurm; do
  n=$(grep -c '\\' "$R/hpc_deploy/$f" || true)
  echo "  $f: 反斜杠出现 $n 次（续行符除外应为 0-2）; $(grep -m1 '^#SBATCH -p' $R/hpc_deploy/$f)"
done
echo "--- 语法检查 ---"
bash -n "$R/hpc_deploy/pswap_gate.slurm" && echo "  gate 语法通过"
bash -n "$R/hpc_deploy/pswap_train.slurm" && echo "  train 语法通过"
echo "--- 单独预演环境守卫（不提交作业，在登录节点上只验语法能否解析）---"
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh 2>/dev/null
conda activate nh_final 2>/dev/null
python -u -c "
import pathlib
src = open('$R/hpc_deploy/pswap_gate.slurm').read()
i = src.index('import pathlib, torch')
j = src.index('\" || exit 4')
compile(src[i:j], 'guard', 'exec')
print('  环境守卫代码块可编译')
"

echo "=== C. SUBMIT GATE ==="
out=$(sbatch "$R/hpc_deploy/pswap_gate.slurm" 2>&1); echo "$out"
GATE=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$GATE" ] || { echo SUBMIT_FAILED_GATE; exit 1; }
echo "$GATE" > "$R/logs/job_ids.txt"

echo "=== D. SUBMIT 6 ARMS (afterok:$GATE) ==="
for a in pswap_armP_chirps_s100 pswap_armP_chirps_s200 pswap_armP_chirps_s300 \
         pswap_armP_era5l_s100 pswap_armP_era5l_s200 pswap_armP_era5l_s300; do
  sed -e "s|^#SBATCH -J pswap_arm|#SBATCH -J ${a}|" \
      -e "s|^#SBATCH --gres=gpu:1|#SBATCH --gres=gpu:1\n#SBATCH --dependency=afterok:${GATE}|" \
      -e "s|^set -eo pipefail|set -eo pipefail\nCFG=${a}|" \
      "$R/hpc_deploy/pswap_train.slurm" > "$R/hpc_deploy/jobs/${a}.slurm"
  o=$(sbatch "$R/hpc_deploy/jobs/${a}.slurm" 2>&1)
  j=$(echo "$o" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
  if [ -z "$j" ]; then echo "SUBMIT_FAILED $a :: $o"; else echo "$a -> $j"; echo "$j" >> "$R/logs/job_ids.txt"; fi
done
echo "job ids: $(tr '\n' ' ' < $R/logs/job_ids.txt)"

echo "=== E. QUEUE ==="
squeue -u "$USER" -o '%.11i %.24j %.9T %.16E %.24R' 2>&1 | grep -Ei 'pswap|JOBID' || echo '  (none)'
sinfo -p hgpu4 -N -o "%.9N %.8t %.14C %.8G" 2>&1
echo "=== DONE ==="
