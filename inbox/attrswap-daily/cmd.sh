#!/bin/bash
# READ-ONLY: why has the precip-swap gate not started? Reason code, estimated start, partition capacity.
set -o pipefail
date "+wallclock %F %T %z"
echo "=== A. MY JOBS WITH REASON ==="
squeue -u "$USER" -o '%.11i %.24j %.9T %.10M %.9N %.16E %.28R' 2>&1 | grep -Ei 'pswap|JOBID' || echo '  (none)'
echo "=== B. ESTIMATED START ==="
echo "  gate 224421: $(squeue -j 224421 -h --start -o '%S' 2>&1)"
echo "=== C. hgpu8 CAPACITY ==="
sinfo -p hgpu8 -N -o "%.9N %.8t %.20C %.10G" 2>&1
echo "=== D. OTHER GPU PARTITIONS ==="
for p in hgpu4 hgpu2p hgpu2; do echo "--- $p ---"; sinfo -p "$p" -N -o "%.9N %.8t %.20C %.10G" 2>&1 | head -8; done
echo "=== E. MY OVERALL QUEUE FOOTPRINT ==="
squeue -u "$USER" -h -o '%T' 2>&1 | sort | uniq -c
echo "=== DONE ==="
