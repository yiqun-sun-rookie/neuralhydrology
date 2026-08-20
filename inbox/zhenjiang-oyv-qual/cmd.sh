#!/usr/bin/env bash
# zhenjiang gauge failure study :: status, and chain the ladder evaluation when full
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. LADDER 206431 ==="
DONE=$(ls -1 "$ROOT/ladder_tasks" 2>/dev/null | wc -l)
V1=$(ls -1 "$ROOT/tasks" 2>/dev/null | wc -l)
echo "ladder_tasks=$DONE of 960   v1_tasks=$V1 of 480"
sacct -j 206431 -X --format=State%14 --noheader 2>/dev/null | sort | uniq -c | head -8 || true
squeue -j 206431 -h -o '%.14i %.9T %.8M %.20R' 2>/dev/null | head -4 || true
echo "--- failed, timed out or node failed ---"
sacct -j 206431 -X --format=JobID%16,NodeList%9,State%14,ExitCode%8 --noheader 2>/dev/null \
    | grep -vE 'COMPLETED|PENDING|RUNNING' | head -10 || echo "(none)"
echo "--- condition coverage ---"
ls -1 "$ROOT/ladder_tasks" 2>/dev/null | sed 's/.*__\(zhenjiang\|jiangyin\)__//; s/__seed_.*//' | sort | uniq -c || true

if [ "$DONE" -ne 960 ]; then
    echo "=== B. NOT FULL YET, NOT CHAINING ==="
    echo "=== END ==="
    exit 0
fi

echo "=== B. UPDATE CLONE AND SUBMIT THE LADDER EVALUATION ==="
cd "$ROOT/repo" || exit 1
timeout 600 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" 2>&1 | tail -2
timeout 120 git reset -q --hard refs/remotes/origin/main
echo "bundle_commit=$(git rev-parse HEAD)"
if [ -e "$ROOT/ladder_impact" ]; then
    echo "LADDER_IMPACT_ROOT_EXISTS, refusing to resubmit"
else
    sed -i 's/\r$//' scripts/analysis/hpc/submit_ladder_impact.slurm
    EJ=$(sbatch --parsable scripts/analysis/hpc/submit_ladder_impact.slurm 2>&1)
    echo "ladder_eval_job=$EJ"
    case "$EJ" in
        ''|*[!0-9]*) echo "SBATCH_FAILED"; exit 1 ;;
    esac
    for i in $(seq 1 120); do
        LEFT=$(squeue -j "$EJ" -h -o "%i" 2>/dev/null | wc -l)
        [ "$LEFT" -eq 0 ] && break
        sleep 10
    done
    sacct -j "$EJ" -X --format=JobID%12,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1 | head -4
    echo "=== C. LADDER RESULT ==="
    tail -80 "$ROOT/logs/ladder_impact_${EJ}.out" 2>/dev/null || true
    echo "--- stderr ---"
    tail -12 "$ROOT/logs/ladder_impact_${EJ}.err" 2>/dev/null || true
fi
echo "=== END ==="
