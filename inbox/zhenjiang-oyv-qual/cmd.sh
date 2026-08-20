#!/usr/bin/env bash
# zhenjiang gauge failure study :: ladder audit, retry with a family-correct comparison
# The previous attempt completed all 960 re-inferences in 13 minutes and then died
# comparing a horizon-keyed table against an event-keyed merge. Only that
# comparison changed; every check before it is unaltered.
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. UPDATE CLONE ==="
cd "$ROOT/repo" || exit 1
timeout 600 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" 2>&1 | tail -2
timeout 200 git reset -q --hard refs/remotes/origin/main
echo "bundle_commit=$(git rev-parse --short HEAD)  files=$(find . -type f -not -path './.git/*' | wc -l)"
test -e "$ROOT/ladder_audit" && { echo "LADDER_AUDIT_ROOT_EXISTS"; ls -1 "$ROOT/ladder_audit"; } || echo "ladder_audit_clear=true"

echo "=== B. SUBMIT ==="
sed -i 's/\r$//' scripts/analysis/hpc/submit_independent_audit.slurm
AJ=$(sbatch --parsable \
    --export=ALL,AUDIT_FAMILY=ladder_v2,AUDIT_TASK_ROOT="$ROOT/ladder_tasks",AUDIT_EVAL_ROOT="$ROOT/ladder_impact",AUDIT_INFER_ROOT="$ROOT/ladder_impact",AUDIT_OUTPUT_SUBDIR=ladder_audit \
    scripts/analysis/hpc/submit_independent_audit.slurm 2>&1)
echo "ladder_audit_job=$AJ"
case "$AJ" in ''|*[!0-9]*) echo "SBATCH_FAILED"; exit 1 ;; esac

echo "=== C. WAIT (max 70 min) ==="
for i in $(seq 1 420); do
    LEFT=$(squeue -j "$AJ" -h -o "%i" 2>/dev/null | wc -l)
    [ $((i % 60)) -eq 0 ] && echo "t=$((i * 10))s remaining=$LEFT"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done

echo "=== D. RESULT ==="
sacct -j "$AJ" -X --format=JobID%12,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1 | head -4
cat "$ROOT/ladder_audit/independent_audit_summary.json" 2>/dev/null || echo "(no summary)"
echo "--- mismatch kinds ---"
tail -n +2 "$ROOT/ladder_audit/mismatches.csv" 2>/dev/null | cut -d, -f1 | sort | uniq -c | head || echo "(no rows)"
echo "--- first rows if any ---"
head -4 "$ROOT/ladder_audit/mismatches.csv" 2>/dev/null || true
echo "--- stderr tail ---"
tail -14 "$ROOT/logs/independent_audit_${AJ}.err" 2>/dev/null || true
echo "=== END ==="
