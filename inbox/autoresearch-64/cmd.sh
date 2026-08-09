#!/bin/bash
set -o pipefail

EVIDENCE=~/autoresearch64/runs/unified_autoresearch/dlopen_fix_validation_20260809_seq21/evidence
PROBE="$EVIDENCE/PROBE_pandas.json"
ACCESS="$EVIDENCE/runs/pandas/logs/access.jsonl"
RUNTIME="$EVIDENCE/runs/pandas/logs/runtime-result.json"
PREFLIGHT="$EVIDENCE/runs/pandas/logs/dependency-preflight.json"

echo "=== EXISTENCE AND SIZES ==="
for FILE in "$PROBE" "$ACCESS" "$RUNTIME" "$PREFLIGHT"; do
  if [ -f "$FILE" ]; then
    stat -c '%n bytes=%s modified=%y' "$FILE"
  else
    echo "MISSING $FILE"
  fi
done

echo "=== PANDAS PROBE ==="
cat "$PROBE"
echo "=== PANDAS ACCESS LOG TAIL ==="
tail -60 "$ACCESS"
echo "=== PANDAS RUNTIME RESULT ==="
cat "$RUNTIME"
echo "=== PANDAS DEPENDENCY PREFLIGHT ==="
cat "$PREFLIGHT"
