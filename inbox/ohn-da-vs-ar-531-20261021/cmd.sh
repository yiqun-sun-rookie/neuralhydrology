#!/bin/bash
# OHN DA-vs-AR seq11: A1 training on RTX 3090 projects to 17-22 h (smoke 0.7 s/update) - too close to the 24 h limit
# set in seq8, and limits cannot be raised. Cancel OWN still-pending A1 train 246242, A1+DA 246244, P3 246245 and
# resubmit them (A1 train with 36 h), re-linking dependencies. Aborts if any of these has started. Nothing else touched.
set -o pipefail
NEW=/data1/home/sunyiq/ohn_da_vs_ar_531_20261021
cd "$NEW" || exit 1
date --iso-8601=seconds
[ -f logs/p2_resubmitted_a1 ] && { echo "ALREADY_DONE: $(cat logs/p2_resubmitted_a1)"; exit 0; }
for J in 246242 246244 246245; do
  ST=$(squeue -j $J -h -o '%T' 2>/dev/null | sort -u | tr '\n' ' ')
  echo "job $J states: ${ST:-GONE}"
  case "$ST" in *RUNNING*|*COMPLETING*) echo "STARTED_ALREADY $J - aborting, nothing cancelled"; exit 1 ;; esac
  [ -z "$ST" ] && { echo "JOB_GONE $J - aborting"; exit 1; }
done
EID=246243
scancel 246245 246244 246242 && echo "cancelled own pending 246245 246244 246242"
sleep 3
squeue -j 246242,246244,246245 -h -o '%i %T' 2>&1 | head

P=$(cat logs/partition_p1.txt)
sub() {  # sub <tag> <sbatch args...>; sets JID
  local tag=$1; shift
  local out; out=$(sbatch "$@" 2>&1); echo "$out" | head -3
  JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
  [ -n "$JID" ] || { echo "SUBMIT_FAILED $tag"; exit 1; }
  echo "$tag $JID $(date --iso-8601=seconds) (resubmit, 36h)" >> logs/submissions.txt
}
sed -e "s/^#SBATCH -p .*/#SBATCH -p $P/" -e 's/^#SBATCH --array=0-4%4/#SBATCH --array=0-4%3/' \
    -e 's/^#SBATCH -t .*/#SBATCH -t 1-12:00:00/' slurm/p2_a1_train.slurm > slurm/run_p2_a1_train_v2.slurm
grep -nE '^#SBATCH -(t|p) |--array' slurm/run_p2_a1_train_v2.slurm
sub p2_a1_train_v2 slurm/run_p2_a1_train_v2.slurm; AID=$JID
sed -e "s/^#SBATCH -p .*/#SBATCH -p $P/" -e 's/^#SBATCH -t .*/#SBATCH -t 06:00:00/' slurm/p2_da.slurm > slurm/run_p2_da_a1da_v2.slurm
sed -i "2i #SBATCH --dependency=afterany:$AID" slurm/run_p2_da_a1da_v2.slurm
sub p2_da_a1da_v2 --array=0-4%3 --export=ALL,TASKS=$NEW/configs/tasks_p2_a1da.txt slurm/run_p2_da_a1da_v2.slurm; DID=$JID
sed -e "s/^#SBATCH -p .*/#SBATCH -p $P/" slurm/p3_score.slurm > slurm/run_p3_score_v2.slurm
sed -i "2i #SBATCH --dependency=afterany:$EID:$DID" slurm/run_p3_score_v2.slurm
sub p3_score_v2 slurm/run_p3_score_v2.slurm; PID=$JID
echo "a1train=$AID a1da=$DID p3=$PID e_da=$EID" > logs/p2_resubmitted_a1
squeue -j "$AID,$DID,$PID,$EID,246240" -h -o '%i|%T|%l|%R' 2>&1 | head
for J in $DID $PID; do scontrol show job $J 2>/dev/null | grep -oE 'Dependency=[^ ]*' | head -1; done
echo "=== GRID PROGRESS ==="
sacct -X -n -P -j 246239 --format=JobID,State,Elapsed 2>&1 | head -16
echo "SEQ11_DONE a1train=$AID a1da=$DID p3=$PID"
