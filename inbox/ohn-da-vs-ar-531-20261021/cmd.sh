#!/bin/bash
# FIX: 246243_0 on ngu002 GPU IDX:0 runs 71.7 s/basin vs 21 s/basin on healthy cards (same node GPU 1, same code)
# -> would TIMEOUT at 6 h. Per PLAYBOOK (ngu002 history; exclude only via #SBATCH / scontrol, never sbatch CLI):
#  1) exclude ngu002 for OWN pending arrays 246243 / 246279 / 246280
#  2) scancel OWN task 246243_0; move its partial copy aside (no deletion)
#  3) resubmit that one task with #SBATCH --exclude=ngu002
#  4) add the retry to OWN pending P3 246281 dependency. Nothing else touched.
set -o pipefail
NEW=/data1/home/sunyiq/ohn_da_vs_ar_531_20261021
cd "$NEW" || exit 1
date --iso-8601=seconds
[ -f logs/fix_ngu002_gpu0 ] && { echo "ALREADY_DONE: $(cat logs/fix_ngu002_gpu0)"; exit 0; }

echo "=== 1) EXCLUDE ngu002 FOR PENDING TASKS ==="
for J in 246243 246279 246280; do
  scontrol update jobid=$J ExcNodeList=ngu002 2>&1 && echo "$J ExcNodeList=ngu002 set"
  scontrol show job ${J} 2>/dev/null | grep -oE 'ExcNodeList=[^ ]*' | sort -u | head -2
done

echo "=== 2) CANCEL SLOW TASK ==="
ST=$(squeue -j 246243_0 -h -o '%T' 2>/dev/null)
echo "246243_0 state=${ST:-GONE}"
if [ "$ST" = "RUNNING" ] || [ "$ST" = "PENDING" ]; then
  scancel 246243_0 && echo "cancelled own 246243_0"
  sleep 5
fi
SRC_COPY=copies/p2/E1/id18_nse_1510_225843
if [ -e "$SRC_COPY" ]; then
  mkdir -p copies/p2_stale
  mv "$SRC_COPY" "copies/p2_stale/E1_id18_nse_1510_225843_ngu002gpu0_$(date +%Y%m%dT%H%M%S)" && echo "moved partial copy aside"
fi
ls copies/p2_stale

echo "=== 3) RESUBMIT TASK 0 WITH EXCLUDE ==="
sed -e 's/^#SBATCH -p .*/#SBATCH -p hgpu2p/' -e 's/^#SBATCH -t .*/#SBATCH -t 06:00:00/' slurm/p2_da.slurm > slurm/run_p2_da_e_retry0.slurm
sed -i '2i #SBATCH --exclude=ngu002' slurm/run_p2_da_e_retry0.slurm
head -4 slurm/run_p2_da_e_retry0.slurm
out=$(sbatch --array=0 --export=ALL,TASKS=$NEW/configs/tasks_p2_e.txt slurm/run_p2_da_e_retry0.slurm 2>&1); echo "$out" | head -3
RID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$RID" ] || { echo "SUBMIT_FAILED retry0"; exit 1; }
echo "p2_da_e_retry0 $RID $(date --iso-8601=seconds) (replaces 246243_0, slow GPU ngu002:0)" >> logs/submissions.txt

echo "=== 4) RE-LINK P3 ==="
scontrol update jobid=246281 Dependency=afterany:246243_*,afterany:246280_*,afterany:${RID}_* 2>&1
DEP=$(scontrol show job 246281 2>/dev/null | grep -oE 'Dependency=[^ ]*')
echo "$DEP"
echo "$DEP" | grep -q "$RID" || { echo "P3_RELINK_FAILED"; exit 1; }
echo "retry0=$RID" > logs/fix_ngu002_gpu0
squeue -j "$RID,246243,246279,246280,246281" -h -o '%i|%T|%R' 2>&1 | head -10
echo "SEQ19_DONE retry0=$RID"
