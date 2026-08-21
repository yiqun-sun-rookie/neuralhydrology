#!/usr/bin/env bash
# Read-only provenance extraction for the Zhenjiang six-hour Datong-removal comparison.
set -o pipefail
ROOT=/data1/home/sunyiq/zhenjiang_oyv_v1
IMPACT="$ROOT/ladder_impact"

echo "=== A. OUTPUT ROOT IDENTITY ==="
test -d "$IMPACT" || { echo "MISSING_LADDER_IMPACT"; exit 1; }
find "$IMPACT" -maxdepth 1 -type f -printf '%f\t%s bytes\n' | sort
sha256sum \
  "$IMPACT/completion_manifest.json" \
  "$IMPACT/ladder_summary.json" \
  "$IMPACT/ladder_cost_summary.csv" \
  "$IMPACT/ladder_fold_costs.csv" \
  "$IMPACT/ladder_task_errors.csv"

echo "=== B. COMPLETION MANIFEST ==="
cat "$IMPACT/completion_manifest.json"

echo "=== C. HEADLINE SUMMARY ==="
cat "$IMPACT/ladder_summary.json"

echo "=== D. SIX-HOUR SUMMARY ROW ==="
head -n 1 "$IMPACT/ladder_cost_summary.csv"
grep '^hidden_target,zhenjiang,hidden_target_minus_datong,6,' "$IMPACT/ladder_cost_summary.csv"

echo "=== E. SIX-HOUR FOLD ROWS ==="
head -n 1 "$IMPACT/ladder_fold_costs.csv"
grep '^hidden_target,zhenjiang,hidden_target_minus_datong,6,' "$IMPACT/ladder_fold_costs.csv"

echo "=== F. MATCHED TASK ERRORS ==="
head -n 1 "$IMPACT/ladder_task_errors.csv"
grep -E '^(ladder_v2|oyv_v1),[0-9]+,zhenjiang,(hidden_target|hidden_target_minus_datong),[0-9]+,6,' "$IMPACT/ladder_task_errors.csv"

echo "=== G. JOB STATE ==="
sacct -j 207556,207599 -X --format=JobID%12,State%12,ExitCode%8,Elapsed%10 | head -6
echo "=== END ==="
