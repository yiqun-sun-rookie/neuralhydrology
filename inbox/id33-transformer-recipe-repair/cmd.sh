#!/bin/bash
set -o pipefail
echo "=== QUEUE ==="
squeue -u "$USER" -o "%.10i %.16j %.10T %.10M %.9R" 2>&1 | head -20
echo "=== ID33 JOBS SINCE 09-03 ==="
sacct -X -n -P -S 2026-09-03 --format=JobID,JobName,State,ExitCode,Elapsed 2>&1 | grep -i id33 || echo "  none"
echo "ID33_PROBE_DONE"
