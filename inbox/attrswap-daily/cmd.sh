#!/bin/bash
# precip-swap -- install the corrected builder, rebuild era5l_precip under two new hard checks, resubmit the
# three era5l arms. The three chirps arms are left running: their build was verified correct
# (median ratio to Maurer 0.98, lag distribution identical to the value computed locally).
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap_daily_2026_09
M=$HOME/hpc_mailbox/inbox/attrswap-daily/payload

echo "=== A. INSTALL CORRECTED BUILDER ==="
echo "  before build_precip_swap.py $(sha256sum $R/hpc_deploy/build_precip_swap.py | cut -c1-16)"
cp "$M/build_precip_swap.py" "$M/pswap_rebuild_era5l.slurm" "$R/hpc_deploy/" || { echo COPY_FAILED; exit 1; }
sed -i 's/\r$//' "$R/hpc_deploy/build_precip_swap.py" "$R/hpc_deploy/pswap_rebuild_era5l.slurm"
echo "  after  build_precip_swap.py $(sha256sum $R/hpc_deploy/build_precip_swap.py | cut -c1-16)"
echo "--- 新增的两道硬检查与按名查列 ---"
grep -nE "RATIO_LO|LAG0_HARD_MIN|def prcp_index|V9 |V6-hard" "$R/hpc_deploy/build_precip_swap.py" | head -8
bash -n "$R/hpc_deploy/pswap_rebuild_era5l.slurm" && echo "  rebuild slurm 语法通过"

echo "=== B. SUBMIT REBUILD JOB ==="
out=$(sbatch "$R/hpc_deploy/pswap_rebuild_era5l.slurm" 2>&1); echo "$out"
RB=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$RB" ] || { echo SUBMIT_FAILED_REBUILD; exit 1; }

echo "=== C. RESUBMIT THE THREE era5l ARMS (afterok:$RB) ==="
for a in pswap_armP_era5l_s100 pswap_armP_era5l_s200 pswap_armP_era5l_s300; do
  sed -e "s|^#SBATCH -J pswap_arm|#SBATCH -J ${a}|" \
      -e "s|^#SBATCH --gres=gpu:1|#SBATCH --gres=gpu:1\n#SBATCH --dependency=afterok:${RB}|" \
      -e "s|^set -eo pipefail|set -eo pipefail\nCFG=${a}|" \
      "$R/hpc_deploy/pswap_train.slurm" > "$R/hpc_deploy/jobs/${a}.slurm"
  o=$(sbatch "$R/hpc_deploy/jobs/${a}.slurm" 2>&1)
  j=$(echo "$o" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
  if [ -z "$j" ]; then echo "SUBMIT_FAILED $a :: $o"; else echo "$a -> $j"; echo "$j" >> "$R/logs/job_ids.txt"; fi
done
echo "rebuild job: $RB"
echo "job ids now: $(tr '\n' ' ' < $R/logs/job_ids.txt)"

echo "=== D. QUEUE ==="
squeue -u "$USER" -o '%.11i %.24j %.9T %.10M %.9N %.16E' 2>&1 | grep -Ei 'pswap|JOBID' || echo '  (none)'
echo "=== E. CHIRPS 三臂进度（不受影响）==="
for g in "$R"/logs/slurm_pswap_armP_chirps*.out; do
  [ -f "$g" ] || continue
  e=$(grep -oE "Epoch [0-9]+ average loss" "$g" 2>/dev/null | tail -1) || true
  echo "  $(basename $g): ${e:-starting}"
done
echo "=== DONE ==="
