#!/bin/bash
# FIX: A1+DA 246280_0 landed on ngu002 GPU0 again: 95 s/basin (healthy 21; task _1 on GPU1 20.8) -> would TIMEOUT at 6 h.
#  1) re-exclude ngu002 for OWN pending tasks 246280_[2-4] (GPU0 frees on cancel and would catch the next task)
#  2) scancel OWN 246280_0, move its partial copy aside (no deletion)
#  3) resubmit that one task with #SBATCH --exclude=ngu002 (same 3090 partitions, 6 h)
#  4) add the retry to OWN pending P3 246281 dependency. Nothing else touched.
set -o pipefail
NEW=/data1/home/sunyiq/ohn_da_vs_ar_531_20261021
cd "$NEW" || exit 1
date --iso-8601=seconds
[ -f logs/fix_ngu002_gpu0_a1da ] && { echo "ALREADY_DONE: $(cat logs/fix_ngu002_gpu0_a1da)"; exit 0; }
[ -f configs/tasks_p2_a1da.txt ] || { echo "NO_TASKS_FILE"; ls configs; exit 1; }

echo "=== 1) EXCLUDE ngu002 FOR PENDING A1+DA TASKS ==="
scontrol update jobid=246280 ExcNodeList=ngu002 2>&1 && echo "246280 ExcNodeList=ngu002 set"
squeue -j 246280 -h -o '%i|%T|%N' 2>&1 | head -5

echo "=== 2) CANCEL SLOW TASK ==="
ST=$(squeue -j 246280_0 -h -o '%T' 2>/dev/null)
echo "246280_0 state=${ST:-GONE}"
if [ "$ST" = "RUNNING" ] || [ "$ST" = "PENDING" ]; then scancel 246280_0 && echo "cancelled own 246280_0"; sleep 5; fi
for SRC_COPY in copies/p2/A1DA/a1_s100_*; do
  [ -e "$SRC_COPY" ] || continue
  mkdir -p copies/p2_stale
  mv "$SRC_COPY" "copies/p2_stale/A1DA_$(basename $SRC_COPY)_ngu002gpu0_$(date +%Y%m%dT%H%M%S)" && echo "moved partial copy aside: $SRC_COPY"
done
ls copies/p2_stale

echo "=== 3) RESUBMIT TASK 0 WITH EXCLUDE ==="
sed -e 's/^#SBATCH -p .*/#SBATCH -p hgpu2p,hgpu2/' -e 's/^#SBATCH -t .*/#SBATCH -t 06:00:00/' slurm/p2_da.slurm > slurm/run_p2_da_a1da_retry0.slurm
sed -i '2i #SBATCH --exclude=ngu002' slurm/run_p2_da_a1da_retry0.slurm
head -4 slurm/run_p2_da_a1da_retry0.slurm
out=$(sbatch --array=0 --export=ALL,TASKS=$NEW/configs/tasks_p2_a1da.txt slurm/run_p2_da_a1da_retry0.slurm 2>&1); echo "$out" | head -3
RID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$RID" ] || { echo "SUBMIT_FAILED a1da_retry0"; exit 1; }
echo "p2_da_a1da_retry0 $RID $(date --iso-8601=seconds) (replaces 246280_0, slow GPU ngu002:0)" >> logs/submissions.txt

echo "=== 4) RE-LINK P3 ==="
scontrol update jobid=246281 Dependency=afterany:246243_*,afterany:246280_*,afterany:246378_*,afterany:${RID}_* 2>&1
DEP=$(scontrol show job 246281 2>/dev/null | grep -oE 'Dependency=[^ ]*')
echo "$DEP"
echo "$DEP" | grep -q "$RID" || { echo "P3_RELINK_FAILED"; exit 1; }
echo "a1da_retry0=$RID" > logs/fix_ngu002_gpu0_a1da
squeue -j "$RID,246280,246281" -h -o '%i|%T|%R|%S' 2>&1 | head -8
echo "SEQ73_DONE a1da_retry0=$RID"
