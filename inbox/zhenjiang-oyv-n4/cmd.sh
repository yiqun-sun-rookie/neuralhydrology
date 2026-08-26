#!/bin/bash
set -o pipefail
echo "=== WHY IS 213599 NOT STARTING ==="
squeue -j 213598,213599 -h -o "  %.20i %.9T %.20r %.20S %.10N" 2>/dev/null || true
echo "=== hgpu8 OCCUPANCY ==="
sinfo -p hgpu8 -N -o "%.9N %.11T %.6C %.10G" 2>&1 || true
echo "  my running on hgpu8: $(squeue -u "$USER" -h -t RUNNING -p hgpu8 -o '%i' 2>/dev/null | wc -l)"
echo "=== MY LIMITS (would a cap explain it?) ==="
sacctmgr -n -P show assoc user="$USER" format=Account,Partition,GrpTRES,MaxJobs,MaxSubmit,GrpJobs 2>&1 | head -5 || echo "  unreadable"
scontrol show job 213599 2>/dev/null | grep -oE '(JobState=[A-Za-z]+|Reason=[A-Za-z]+|ArrayTaskThrottle=[0-9]+)' | head -5
echo "=== PROGRESS ==="
echo "  n4_tasks: $(ls -1 /data1/home/sunyiq/zhenjiang_oyv_v1/n4_tasks 2>/dev/null | wc -l) / 1440"
echo "=== DONE ==="
