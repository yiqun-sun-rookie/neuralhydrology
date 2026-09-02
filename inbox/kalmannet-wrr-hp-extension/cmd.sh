#!/bin/bash
set -o pipefail
echo "=== TIME ==="; date -Is
echo "=== ALL_MY_JOBS ==="
squeue -u "$USER" -o '%i|%j|%T|%P|%M|%R|%S' 2>&1 || true
echo "=== RUNNING_COUNT_BY_JOBNAME ==="
squeue -u "$USER" -h -t RUNNING -o '%j' 2>/dev/null | sort | uniq -c || true
echo "=== PENDING_COUNT_BY_JOBNAME ==="
squeue -u "$USER" -h -t PENDING -o '%j|%R' 2>/dev/null | sort | uniq -c || true
echo "=== PARTITION_STATE ==="
sinfo -o "%.10P %.6a %.6D %.6t %.30N" 2>&1 | grep -E 'PARTITION|hgpu' || true
echo "=== GPU_ALLOC_DETAIL (hgpu2p nodes: who holds the cards) ==="
for n in ngu001 ngu004 ngu005 ngu006 ngu007 ngu008 ngu010 ngu011; do
  echo -n "$n: "; scontrol show node "$n" 2>/dev/null | tr '\n' ' ' | grep -oE 'CPUAlloc=[0-9]+ .*AllocTRES=[^ ]*' | head -1 || echo "?"
done
echo "=== JOBS_STARTED_TODAY (mine, any partition) ==="
sacct -X -n -P -u "$USER" -S "$(date +%Y-%m-%d)" --format=JobID,JobName,Partition,State,Elapsed,Start,NodeList 2>&1 | tail -30 || true
echo "=== MY_ARRAY_ONLY ==="
squeue -j 218659 -h -o '%i|%T|%R' 2>&1 | sort | uniq -c || true
