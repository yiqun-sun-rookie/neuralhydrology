#!/bin/bash
# OHN DA-vs-AR seq5: submit P1b (plan v2 §5.2): 12-setting DA grid + noda reference on tune_v0's held-out window
# (its test period 2006-10..2008-09; never the 1989-1999 test), then the selection job (afterany). Own root only.
set -o pipefail
NEW=/data1/home/sunyiq/ohn_da_vs_ar_531_20261021
OLD=/data1/home/sunyiq/openhydronet_531_20261015
cd "$NEW" || exit 1
date --iso-8601=seconds
[ -f logs/p1b_submitted ] && { echo "P1B_ALREADY_SUBMITTED: $(cat logs/p1b_submitted)"; exit 0; }

echo "=== CHECKS ==="
SRC=$(ls -td "$OLD"/runs/tune_v0_* | head -1); echo "tune_v0=$SRC"
grep -nE '^(test_start_date|test_end_date|train_start_date|train_end_date):' "$SRC/config.yml"
[ "$(wc -l < configs/grid/grid.txt)" -eq 12 ] || { echo GRID_NOT_12; exit 1; }
[ "$(wc -l < configs/tune_basins_100.txt)" -eq 100 ] || { echo TUNE_BASINS_NOT_100; exit 1; }
P=$(cat logs/partition_p1.txt); echo "partition=$P"
sinfo -p "$P" -N -h -O nodelist:10,statecompact:10,gresused:24 2>&1 | head -12

sed "s/^#SBATCH -p .*/#SBATCH -p $P/" slurm/p1b_grid.slurm > slurm/run_p1b_grid.slurm
sed "s/^#SBATCH -p .*/#SBATCH -p $P/" slurm/p1b_select.slurm > slurm/run_p1b_select.slurm

echo "=== SUBMIT GRID ==="
out=$(sbatch slurm/run_p1b_grid.slurm 2>&1); echo "$out" | head -3
GID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$GID" ] || { echo SUBMIT_FAILED grid; exit 1; }
echo "p1b_grid $GID $(date --iso-8601=seconds)" >> logs/submissions.txt

echo "=== SUBMIT SELECT (afterany $GID) ==="
sed -i "2i #SBATCH --dependency=afterany:$GID" slurm/run_p1b_select.slurm
out=$(sbatch slurm/run_p1b_select.slurm 2>&1); echo "$out" | head -3
SID=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$SID" ] || { echo SUBMIT_FAILED select; exit 1; }
echo "p1b_select $SID $(date --iso-8601=seconds)" >> logs/submissions.txt
echo "grid=$GID select=$SID" > logs/p1b_submitted
squeue -j "$GID,$SID" -h -o '%i %P %T %R' 2>&1 | head
echo "=== A1 SMOKE ==="
squeue -j 246201 -h -o '%i %P %T %R %M' 2>&1
grep -hE 'A1_TRAIN|SMOKE_A1|Traceback|Error' logs/ohn_a1_smoke-246201.* 2>/dev/null | tail -5
echo "SEQ5_DONE grid=$GID select=$SID"
