#!/usr/bin/env bash
# zhenjiang out-of-year validation :: step 13, audit retry with a fixed comparator
#
# The first audit pass reported 1920 mismatches, four per task across all 480
# tasks. Every one was a comparator fault: the normalisation statistics are
# stored as float32 and were being compared against a float64 recomputation at a
# 1e-12 tolerance. Rounding the recomputation to float32 reproduces every
# recorded value bit for bit, so nothing numerical was ever different.
#
# Only the comparator changed. No registered rule, no statistic, no result. The
# first pass is kept at independent_audit/ as evidence; this retry writes to
# independent_audit_r2/.
#
# The consequence of the fault was that re-inference was skipped for every task,
# so the strongest check has not yet run at all. That is what this retry is for.
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. UPDATE CLONE ==="
cd "$ROOT/repo" || { echo "REPO_MISSING"; exit 1; }
timeout 600 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" 2>&1 | tail -3
timeout 120 git reset -q --hard refs/remotes/origin/main
echo "bundle_commit=$(git rev-parse HEAD)"
test -d "$ROOT/independent_audit" && echo "first_pass_preserved=true" || echo "first_pass_preserved=false"
test -e "$ROOT/independent_audit_r2" && echo "RETRY_ROOT_ALREADY_EXISTS" || echo "retry_root_clear=true"

echo "=== B. SUBMIT AUDIT RETRY ==="
AJ=$(sbatch --parsable --export=ALL,AUDIT_OUTPUT_SUBDIR=independent_audit_r2 \
    scripts/analysis/hpc/submit_independent_audit.slurm 2>&1)
echo "audit_retry_job=$AJ"
case "$AJ" in
    ''|*[!0-9]*) echo "SBATCH_FAILED"; exit 1 ;;
esac

echo "=== C. WAIT (max 95 min) ==="
for i in $(seq 1 570); do
    LEFT=$(squeue -j "$AJ" -h -o "%i" 2>/dev/null | wc -l)
    [ $((i % 60)) -eq 0 ] && echo "t=$((i * 10))s remaining=$LEFT"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done

echo "=== D. AUDIT RETRY RESULT ==="
sacct -j "$AJ" -X --format=JobID%12,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1 | head -4
cat "$ROOT/independent_audit_r2/independent_audit_summary.json" 2>/dev/null || true
echo "--- mismatch kinds ---"
tail -n +2 "$ROOT/independent_audit_r2/mismatches.csv" 2>/dev/null | cut -d, -f1 | sort | uniq -c | head -10 || echo "(no mismatch rows)"
echo "--- first mismatch rows, if any ---"
head -6 "$ROOT/independent_audit_r2/mismatches.csv" 2>/dev/null || true
echo "--- stderr tail ---"
tail -20 "$ROOT/logs/independent_audit_${AJ}.err" 2>/dev/null || true
echo "=== END ==="
