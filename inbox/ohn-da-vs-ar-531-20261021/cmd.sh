#!/bin/bash
# OHN DA-vs-AR seq6: deploy v3 (P2/P3 scripts) into OWN root, then submit P2 + P3 as a dependency chain:
#   A1 train (5 seeds, afterok A1 smoke 246201) | E-arm DA 15 tasks (afterany P1b select 246240)
#   A1+DA 5 tasks (afterany A1 train) | P3 score (afterany E-DA and A1+DA). Each array throttled to 3.
set -o pipefail
CH=ohn-da-vs-ar-531-20261021
NEW=/data1/home/sunyiq/ohn_da_vs_ar_531_20261021
PAY=$HOME/hpc_mailbox/inbox/$CH/payload/payload_v3.tar.gz
EXP_SHA=6319e23ff63fac3e519a4a524ef5fafe0196824b07dd42d728c0ad83770047bf
cd "$NEW" || exit 1
date --iso-8601=seconds
[ -f logs/p2_submitted ] && { echo "P2_ALREADY_SUBMITTED: $(cat logs/p2_submitted)"; exit 0; }

echo "=== DEPLOY V3 ==="
GOT=$(sha256sum "$PAY" | cut -d' ' -f1); [ "$GOT" = "$EXP_SHA" ] || { echo "PAYLOAD_SHA_MISMATCH $GOT"; exit 1; }
[ -e stage_v3 ] && { echo STAGE_V3_EXISTS; exit 1; }
tar -xzf "$PAY" -C "$NEW" 2>&1 | grep -v 'implausibly old' || true
(cd stage_v3 && sha256sum -c MANIFEST_v3.sha256 > ../logs/manifest_v3.txt 2>&1) || { echo MANIFEST_V3_FAILED; cat logs/manifest_v3.txt; exit 1; }
echo "manifest v3 OK $(grep -c ': OK$' logs/manifest_v3.txt) files"
[ -e code_v2 ] || cp -a code code_v2
cp stage_v3/code/*.py code/
cp -n stage_v3/slurm/*.slurm slurm/
cp -n stage_v3/configs/tasks_p2_*.txt configs/
wc -l configs/tasks_p2_e.txt configs/tasks_p2_a1da.txt

echo "=== STATE OF UPSTREAM JOBS ==="
squeue -j 246201,246239,246240 -h -o '%i %P %T %R %M' 2>&1 | head -8
sacct -X -n -P -j 246201 --format=JobID,State,ExitCode,Elapsed 2>&1

P=$(cat logs/partition_p1.txt); echo "partition=$P"
mk() {  # mk <src.slurm> <dst.slurm> <dependency>
  sed "s/^#SBATCH -p .*/#SBATCH -p $P/" "slurm/$1" > "slurm/$2"
  sed -i "2i #SBATCH --dependency=$3" "slurm/$2"
}
sub() {  # sub <tag> <sbatch args...>; sets JID
  local tag=$1; shift
  touch "logs/submission_started_$tag"
  local out; out=$(sbatch "$@" 2>&1); echo "$out" | head -3
  JID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
  [ -n "$JID" ] || { echo "SUBMIT_FAILED $tag"; exit 1; }
  echo "$tag $JID $(date --iso-8601=seconds)" >> logs/submissions.txt
}

echo "=== SUBMIT ==="
mk p2_a1_train.slurm run_p2_a1_train.slurm afterok:246201
sed -i 's/^#SBATCH --array=0-4%4/#SBATCH --array=0-4%3/' slurm/run_p2_a1_train.slurm
sub p2_a1_train slurm/run_p2_a1_train.slurm; AID=$JID
mk p2_da.slurm run_p2_da_e.slurm afterany:246240
sub p2_da_e --array=0-14%3 --export=ALL,TASKS=$NEW/configs/tasks_p2_e.txt slurm/run_p2_da_e.slurm; EID=$JID
mk p2_da.slurm run_p2_da_a1da.slurm afterany:$AID
sub p2_da_a1da --array=0-4%3 --export=ALL,TASKS=$NEW/configs/tasks_p2_a1da.txt slurm/run_p2_da_a1da.slurm; DID=$JID
mk p3_score.slurm run_p3_score.slurm afterany:$EID:$DID
sub p3_score slurm/run_p3_score.slurm; PID=$JID
echo "a1train=$AID e_da=$EID a1da=$DID p3=$PID" > logs/p2_submitted
head -4 slurm/run_p2_da_e.slurm slurm/run_p3_score.slurm
squeue -j "$AID,$EID,$DID,$PID" -h -o '%i %P %T %R' 2>&1 | head -10
echo "SEQ6_DONE a1train=$AID e_da=$EID a1da=$DID p3=$PID"
