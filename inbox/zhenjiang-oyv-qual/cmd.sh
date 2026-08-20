#!/usr/bin/env bash
# zhenjiang gauge failure study :: step 15
# The seq 14 worker was killed mid-loop and its truncated staging file was pushed
# as the result, so the runner will not retry it. Collect what those two jobs
# produced, then submit the 960 task ladder that completes the design.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. JOB STATES ==="
for J in 206418 206419; do
    sacct -j "$J" -X --format=JobID%10,JobName%14,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1 | sed -n '3p' || true
done
squeue -u "$USER" -h -o '%.10i %.14j %.9T %.11M %.20R' 2>&1 | grep -E 'zj_oyv|zj_ladder' || echo "none of ours queued"

echo "=== B. REMOVAL IMPACT, THE MAIN TABLE ==="
tail -70 "$ROOT/logs/removal_impact_206418.out" 2>/dev/null || echo "(impact log absent)"
echo "--- impact stderr ---"
tail -8 "$ROOT/logs/removal_impact_206418.err" 2>/dev/null || true

echo "=== C. AUDIT R3 IF FINISHED ==="
cat "$ROOT/independent_audit_r3/independent_audit_summary.json" 2>/dev/null || echo "(audit r3 not finished)"
tail -n +2 "$ROOT/independent_audit_r3/mismatches.csv" 2>/dev/null | cut -d, -f1 | sort | uniq -c | head || true

echo "=== D. UPDATE CLONE AND SUBMIT THE LADDER ==="
cd "$ROOT/repo" || exit 1
timeout 600 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" 2>&1 | tail -2
timeout 120 git reset -q --hard refs/remotes/origin/main
echo "bundle_commit=$(git rev-parse HEAD)"
if [ -d "$ROOT/ladder_tasks" ] && [ -n "$(ls -A "$ROOT/ladder_tasks" 2>/dev/null)" ]; then
    echo "LADDER_ROOT_NOT_EMPTY, refusing to submit"
else
    LJ=$(sbatch --parsable scripts/modeling/hpc/submit_zhenjiang_ladder_v2.slurm 2>&1)
    echo "ladder_array_job=$LJ"
    case "$LJ" in
        ''|*[!0-9]*) echo "SBATCH_FAILED" ;;
        *) printf '%s\n' "$LJ" > "$ROOT/ladder_array_jobid" ;;
    esac
fi

echo "=== E. EARLY LADDER PROGRESS (15 min) ==="
LJ=$(cat "$ROOT/ladder_array_jobid" 2>/dev/null || echo "")
if [ -n "$LJ" ]; then
    for i in $(seq 1 90); do
        LEFT=$(squeue -j "$LJ" -h -o "%i" 2>/dev/null | wc -l)
        DONE=$(ls -1 "$ROOT/ladder_tasks" 2>/dev/null | wc -l)
        [ $((i % 30)) -eq 0 ] && echo "t=$((i * 10))s queue=$LEFT done=$DONE"
        [ "$LEFT" -eq 0 ] && break
        sleep 10
    done
    echo "ladder_done=$(ls -1 "$ROOT/ladder_tasks" 2>/dev/null | wc -l) of 960"
    sacct -j "$LJ" -X --format=State%14 --noheader 2>/dev/null | sort | uniq -c | head -6 || true
fi
echo "=== END ==="
