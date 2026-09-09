#!/bin/bash
# precip-swap -- move the gate and six arms from hgpu8 to hgpu4.
# Reason: on hgpu8 the gate sat PENDING with reason (Priority) and an estimated start of 2026-09-15 (six days
# out) despite 86 idle CPUs, i.e. fair-share priority, not capacity. hgpu4 has two fully idle nodes.
# Only the partition line changes; the frozen contract, configs, data and code are untouched.
# All seven jobs go to the same partition so the six arms stay mutually comparable.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/precip_swap_daily_2026_09

echo "=== A. CANCEL THE SEVEN hgpu8 JOBS (explicit ids only, never -u) ==="
for j in $(cat "$R/logs/job_ids.txt"); do
  st=$(sacct -j "$j" -X -n --format=State 2>/dev/null | head -1 | tr -d ' ')
  case "$st" in
    PENDING) scancel "$j" && echo "  已取消 $j（PENDING，从未启动）";;
    RUNNING) echo "  $j 正在运行 —— 不取消，停下报告"; exit 1;;
    *) echo "  $j 状态 $st —— 不动";;
  esac
done
mv "$R/logs/job_ids.txt" "$R/logs/job_ids.hgpu8_attempt.txt"

echo "=== B. SWITCH PARTITION IN THE TWO TEMPLATES ==="
for f in "$R/hpc_deploy/pswap_gate.slurm" "$R/hpc_deploy/pswap_train.slurm"; do
  echo "  before $(basename $f) $(sha256sum $f | cut -c1-16)"
  sed -i 's|^#SBATCH -p hgpu8$|#SBATCH -p hgpu4|' "$f"
  echo "  after  $(basename $f) $(sha256sum $f | cut -c1-16)"
  grep -nE '^#SBATCH (-p|--cpus-per-task|--gres)' "$f"
done

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

echo "=== E. QUEUE + ESTIMATE ==="
squeue -u "$USER" -o '%.11i %.24j %.9T %.16E %.26R' 2>&1 | grep -Ei 'pswap|JOBID' || echo '  (none)'
echo "  gate $GATE 预估启动: $(squeue -j $GATE -h --start -o '%S' 2>&1)"
echo "=== F. hgpu4 卡型（登记用）==="
sinfo -p hgpu4 -N -o "%.9N %.8t %.20C %.10G" 2>&1
echo "=== DONE ==="
