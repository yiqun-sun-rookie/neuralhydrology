#!/bin/bash
# ID29 seq=229: read-only diagnosis of failed isolated audit job 202727.
set -o pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
JOB_ID=202727
FINAL="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics/partial_numerical_audit_seq227_v1"
STDOUT="$ROOT/closure_20260810/logs/N22-part-audit5_$JOB_ID.out"
STDERR="$ROOT/closure_20260810/logs/N22-part-audit5_$JOB_ID.err"

echo "=== JOB RECORD ==="
sacct -n -X -P -j "$JOB_ID" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList,Reason
scontrol show job -o "$JOB_ID" || true

echo "=== OUTPUT PATHS ==="
for path in "$STDOUT" "$STDERR"; do
  if test -f "$path"; then
    stat -c '%n|%s|%y' "$path"
    sha256sum "$path"
  else
    echo "missing=$path"
  fi
done

echo "=== STDOUT TAIL ==="
if test -f "$STDOUT"; then
  tail -n 120 "$STDOUT"
fi
echo "=== STDERR TAIL ==="
if test -f "$STDERR"; then
  tail -n 160 "$STDERR"
fi

echo "=== FINAL AND STAGING INVENTORY ==="
if test -e "$FINAL"; then
  find "$FINAL" -maxdepth 3 -printf '%p|%y|%s\n' | sort
else
  echo "final_exists=false"
fi
find "$(dirname "$FINAL")" -maxdepth 1 -name 'partial_numerical_audit_seq227_v1.preparing-*' -printf '%p|%y\n' | sort
for staging in "$(dirname "$FINAL")"/partial_numerical_audit_seq227_v1.preparing-*; do
  if test -d "$staging"; then
    find "$staging" -maxdepth 2 -type f -printf '%p|%s\n' -exec sha256sum {} \;
  fi
done

echo "=== FROZEN BOUNDARY ==="
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
echo "registered_matrix_modified=false"
echo "frozen_acceptance_modified=false"
echo "diagnostic_only=true"
exit 0
