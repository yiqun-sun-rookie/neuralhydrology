#!/bin/bash
# precip-selfrule-v05 seq=5: cancel only this task's unsatisfiable dependent array and preserve accounting.
set -o pipefail

date "+wallclock %F %T %z"
hostname

echo "=== BEFORE ==="
squeue -j 231222 -o "%.22i %.24j %.10P %.2t %.10M %.6D %R" || true

scancel 231222
cancel_exit=$?
echo "SCANCEL_EXIT=$cancel_exit"

echo "=== AFTER ==="
squeue -j 231222 -o "%.22i %.24j %.10P %.2t %.10M %.6D %R" || true
sacct -j 231221,231222 --format=JobID,JobName%24,State,ExitCode,Elapsed,NodeList%14 -P || true
exit "$cancel_exit"