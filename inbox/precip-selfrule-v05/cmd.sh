#!/bin/bash
# precip-selfrule-v05 seq=11: make the retry array wait for the currently running original task.
set -eo pipefail

date "+wallclock %F %T %z"
echo "=== BEFORE ==="
squeue -j 231259,231273 -o "%.22i %.24j %.10P %.2t %.10M %.6D %R" || true

running_retry=$(squeue -h -j 231273 -t RUNNING -o "%i" 2>/dev/null | head -1)
if test -z "$running_retry"; then
  scontrol update JobId=231273 Dependency=afterany:231259_2
  echo "DEPENDENCY_UPDATED=afterany:231259_2"
else
  echo "RETRY_ALREADY_RUNNING=$running_retry; LEFT_UNCHANGED"
fi

echo "=== AFTER ==="
squeue -j 231259,231273 -o "%.22i %.24j %.10P %.2t %.10M %.6D %R" || true
scontrol show job 231273 -o 2>/dev/null | sed -n 's/.*Dependency=\([^ ]*\).*/Dependency=\1/p' || true