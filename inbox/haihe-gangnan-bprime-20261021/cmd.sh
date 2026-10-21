#!/bin/bash
# haihe Gangnan B': fix CRLF in tasks/configs, cancel OWN failing array 245971 + pending aggregate 245974,
# resubmit array (no smoke dependency: smoke 245970 COMPLETED with SMOKE_OK) + MKL-fixed aggregate (afterany).
# Touches only jobs 245971/245974 and files under ROOT. Idempotent via marker.
set -o pipefail
ROOT=/data1/home/sunyiq/haihe_gangnan_bprime
MARK="$ROOT/logs/crlf_fix_resubmitted"
cd "$ROOT" || exit 1
date -Is

if [ -f "$MARK" ]; then echo "ALREADY_DONE: $(cat $MARK)"; exit 0; fi

echo "=== CANCEL OWN JOBS 245971 245974 ==="
sacct -X -n -P -j 245970,245971,245974 --format=JobID,State,ExitCode,NodeList,Elapsed 2>&1
scancel 245971 245974 2>&1 && echo "scancel issued for 245971 245974"
sleep 5
squeue -j 245971,245974 -h -o '%i %T' 2>&1 || true

echo "=== SET ASIDE ANY RUN DIRS FROM FAILED TASKS (no deletion) ==="
N=$(find runs -maxdepth 1 -mindepth 1 -type d | wc -l)
echo "run dirs present: $N"
if [ "$N" -gt 0 ]; then
    mkdir -p runs_failed_crlf_245971
    find runs -maxdepth 1 -mindepth 1 -type d -exec mv {} runs_failed_crlf_245971/ \;
    ls runs_failed_crlf_245971 | head -30
fi
N_DONE=$(find done -maxdepth 1 -name '*.ok' | wc -l)
[ "$N_DONE" -eq 0 ] || { echo "UNEXPECTED_DONE_MARKERS $N_DONE"; exit 1; }

echo "=== STRIP CR ==="
echo "CR lines before: tasks=$(grep -c $'\r' configs/tasks.txt) yml=$(cat configs/*.yml | grep -c $'\r')"
sed -i 's/\r$//' configs/tasks.txt configs/*.yml
echo "CR lines after: tasks=$(grep -c $'\r' configs/tasks.txt) yml=$(cat configs/*.yml | grep -c $'\r')"
[ "$(grep -c $'\r' configs/tasks.txt)" -eq 0 ] || { echo "CR_STILL_PRESENT"; exit 1; }
N1=$(head -1 configs/tasks.txt)
[ -f "configs/$N1.yml" ] || { echo "FIRST_TASK_CONFIG_MISSING $N1"; exit 1; }
echo "first task resolves: configs/$N1.yml"
[ "$(wc -l < configs/tasks.txt)" -eq 24 ] || { echo "TASKS_NOT_24"; exit 1; }

echo "=== PARTITION ==="
BEST=hgpu8; BEST_FREE=-1
for P in hgpu2p hgpu2 hgpu4 hgpu8; do
    FREE=$(sinfo -p $P -N -h -O statecompact:10,gres:14,gresused:24 2>/dev/null | awk '
        $1 ~ /^(idle|mix)$/ { t=$2; u=$3; sub(/^gpu:/,"",t); sub(/\(.*/,"",t); sub(/,.*/,"",t);
                              sub(/^gpu:/,"",u); sub(/\(.*/,"",u); sub(/,.*/,"",u); f+=t-u }
        END { print f+0 }')
    echo "$P free_gpus=$FREE"
    if [ "$FREE" -gt "$BEST_FREE" ]; then BEST=$P; BEST_FREE=$FREE; fi
done
[ "$BEST_FREE" -gt 0 ] || BEST=hgpu8
echo "CHOSEN_PARTITION=$BEST"

sed "s/^#SBATCH -p .*/#SBATCH -p $BEST/" slurm/train_eval.slurm > slurm/run_train_eval.v2.slurm
sed "s/^#SBATCH -p .*/#SBATCH -p $BEST/" slurm/aggregate.slurm > slurm/run_aggregate.v2.slurm
sed -i '/^conda activate/a export MKL_SERVICE_FORCE_INTEL=1' slurm/run_aggregate.v2.slurm
sed -i '/^conda activate/a export MKL_THREADING_LAYER=GNU' slurm/run_aggregate.v2.slurm
grep -c '^export MKL_' slurm/run_aggregate.v2.slurm | grep -qx 2 || { echo "MKL_SED_FAILED"; exit 1; }

echo "=== SUBMIT ARRAY v2 ==="
out=$(sbatch slurm/run_train_eval.v2.slurm 2>&1); echo "$out" | head -5
ARRAY=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$ARRAY" ] || { echo "SUBMIT_FAILED array"; exit 1; }
echo "run_train_eval_v2 $ARRAY $(date -Is) replaces 245971 (CRLF)" >> logs/submissions.txt

echo "=== SUBMIT AGGREGATE v2 (afterany $ARRAY) ==="
sed -i "2i #SBATCH --dependency=afterany:$ARRAY" slurm/run_aggregate.v2.slurm
out=$(sbatch slurm/run_aggregate.v2.slurm 2>&1); echo "$out" | head -5
AGG=$(echo "$out" | grep -oE 'Submitted batch job [0-9]+' | grep -oE '[0-9]+')
[ -n "$AGG" ] || { echo "SUBMIT_FAILED aggregate"; exit 1; }
echo "run_aggregate_v2 $AGG $(date -Is) replaces 245974" >> logs/submissions.txt
echo "array=$ARRAY aggregate=$AGG" > "$MARK"

squeue -j $ARRAY,$AGG -h -o '%i %P %T %R' 2>&1 | head -10
echo "RESUBMITTED array=$ARRAY aggregate=$AGG"
