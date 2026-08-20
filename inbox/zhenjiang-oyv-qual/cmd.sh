#!/usr/bin/env bash
# zhenjiang gauge failure study :: independent audit of the ladder family
#
# The audit now takes a family argument. It still does not import either contract:
# the ladder arms are recognised by parsing their registered names and rebuilding
# the station set from the river order, so the re-derivation stays independent.
# Verified locally: its 960 task identifiers and all twelve masks match the
# contract exactly, derived by two different routes.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. UPDATE CLONE ==="
cd "$ROOT/repo" || { echo "REPO_MISSING"; exit 1; }
timeout 600 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" 2>&1 | tail -2
timeout 120 git reset -q --hard refs/remotes/origin/main
echo "bundle_commit=$(git rev-parse HEAD)"
echo "ladder_tasks=$(ls -1 "$ROOT/ladder_tasks" 2>/dev/null | wc -l)  v1_tasks=$(ls -1 "$ROOT/tasks" 2>/dev/null | wc -l)"
test -e "$ROOT/ladder_audit" && { echo "LADDER_AUDIT_ROOT_EXISTS, refusing"; exit 1; } || echo "ladder_audit_root_clear=true"

echo "=== B. LADDER IMPACT ARTIFACTS ==="
ls -1 "$ROOT/ladder_impact" 2>/dev/null || echo "(absent)"
grep -E '"arm_count"|"ladder_task_count"|"v1_task_count"' "$ROOT/ladder_impact/ladder_summary.json" 2>/dev/null || true

echo "=== C. SUBMIT THE LADDER AUDIT ==="
sed -i 's/\r$//' scripts/analysis/hpc/submit_independent_audit.slurm
AJ=$(sbatch --parsable \
    --export=ALL,AUDIT_FAMILY=ladder_v2,AUDIT_TASK_ROOT="$ROOT/ladder_tasks",AUDIT_EVAL_ROOT="$ROOT/ladder_impact",AUDIT_INFER_ROOT="$ROOT/ladder_impact",AUDIT_OUTPUT_SUBDIR=ladder_audit \
    scripts/analysis/hpc/submit_independent_audit.slurm 2>&1)
echo "ladder_audit_job=$AJ"
case "$AJ" in
    ''|*[!0-9]*) echo "SBATCH_FAILED"; exit 1 ;;
esac

echo "=== D. WAIT (max 80 min) ==="
for i in $(seq 1 480); do
    LEFT=$(squeue -j "$AJ" -h -o "%i" 2>/dev/null | wc -l)
    [ $((i % 60)) -eq 0 ] && echo "t=$((i * 10))s remaining=$LEFT"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done

echo "=== E. RESULT ==="
sacct -j "$AJ" -X --format=JobID%12,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1 | head -4
cat "$ROOT/ladder_audit/independent_audit_summary.json" 2>/dev/null || echo "(no summary)"
echo "--- mismatch kinds ---"
tail -n +2 "$ROOT/ladder_audit/mismatches.csv" 2>/dev/null | cut -d, -f1 | sort | uniq -c | head || echo "(no rows)"
echo "--- first rows if any ---"
head -4 "$ROOT/ladder_audit/mismatches.csv" 2>/dev/null || true
echo "--- stderr ---"
tail -12 "$ROOT/logs/independent_audit_${AJ}.err" 2>/dev/null || true
echo "=== END ==="
