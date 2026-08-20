#!/usr/bin/env bash
# zhenjiang out-of-year validation :: step 14
# Two jobs, both batch, nothing computed on this node:
#   1. the removal impact measurement, which is the main line of the study and
#      has been sitting unread inside the 480 prediction packages
#   2. the third audit pass, whose replay path now uses the stored float32
#      statistics instead of a float64 recomputation
set -o pipefail

ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1

echo "=== A. UPDATE CLONE ==="
cd "$ROOT/repo" || { echo "REPO_MISSING"; exit 1; }
timeout 600 git fetch -q origin "+refs/heads/main:refs/remotes/origin/main" 2>&1 | tail -3
timeout 120 git reset -q --hard refs/remotes/origin/main
echo "bundle_commit=$(git rev-parse HEAD)"
test -e "$ROOT/removal_impact" && echo "IMPACT_ROOT_EXISTS" || echo "impact_root_clear=true"
test -e "$ROOT/independent_audit_r3" && echo "R3_ROOT_EXISTS" || echo "r3_root_clear=true"

echo "=== B. SUBMIT BOTH ==="
IJ=$(sbatch --parsable scripts/analysis/hpc/submit_removal_impact.slurm 2>&1)
echo "impact_job=$IJ"
AJ=$(sbatch --parsable --export=ALL,AUDIT_OUTPUT_SUBDIR=independent_audit_r3 \
    scripts/analysis/hpc/submit_independent_audit.slurm 2>&1)
echo "audit_r3_job=$AJ"
for J in "$IJ" "$AJ"; do
    case "$J" in
        ''|*[!0-9]*) echo "SBATCH_FAILED for $J"; exit 1 ;;
    esac
done

echo "=== C. WAIT (max 90 min) ==="
for i in $(seq 1 540); do
    LEFT=$(( $(squeue -j "$IJ" -h -o "%i" 2>/dev/null | wc -l) + $(squeue -j "$AJ" -h -o "%i" 2>/dev/null | wc -l) ))
    [ $((i % 60)) -eq 0 ] && echo "t=$((i * 10))s remaining=$LEFT"
    [ "$LEFT" -eq 0 ] && break
    sleep 10
done

echo "=== D. REMOVAL IMPACT ==="
sacct -j "$IJ" -X --format=JobID%12,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1 | head -4
tail -60 "$ROOT/logs/removal_impact_${IJ}.out" 2>/dev/null || true
echo "--- impact stderr ---"
tail -10 "$ROOT/logs/removal_impact_${IJ}.err" 2>/dev/null || true

echo "=== E. AUDIT R3 ==="
sacct -j "$AJ" -X --format=JobID%12,NodeList%9,State%12,ExitCode%8,Elapsed%10 2>&1 | head -4
cat "$ROOT/independent_audit_r3/independent_audit_summary.json" 2>/dev/null || true
echo "--- mismatch kinds ---"
tail -n +2 "$ROOT/independent_audit_r3/mismatches.csv" 2>/dev/null | cut -d, -f1 | sort | uniq -c | head -10 || echo "(none)"
echo "--- first rows if any ---"
head -4 "$ROOT/independent_audit_r3/mismatches.csv" 2>/dev/null || true
echo "=== END ==="
