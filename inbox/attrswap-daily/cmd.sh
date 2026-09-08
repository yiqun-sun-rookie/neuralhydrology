#!/bin/bash
# forcing-swap -- why is the gate still pending? Partition occupancy, estimated start, limits.
# Also move the stale attempt-1 conversion report aside so the status command stops reporting its failure line.
set -o pipefail
date "+wallclock %F %T %z"
R=/data1/home/sunyiq/forcing_swap_daily_2026_09

echo "=== A. STALE REPORT CLEANUP (attempt 1 copy is already preserved) ==="
if [ -f "$R/logs/convert_verify.json" ] && [ -f "$R/logs/convert_verify.attempt1.json" ]; then
  if cmp -s "$R/logs/convert_verify.json" "$R/logs/convert_verify.attempt1.json"; then
    mv "$R/logs/convert_verify.json" "$R/logs/convert_verify.stale_attempt1.json"
    echo "  moved the stale attempt-1 report aside; the status command will show 'absent' until gate 223959 writes a new one"
  else
    echo "  convert_verify.json already differs from attempt 1 -- the new gate has written it, leaving it alone"
  fi
else
  echo "  nothing to clean"
fi

echo "=== B. MY JOBS + REASON ==="
squeue -u "$USER" -o '%.11i %.20j %.9T %.10M %.9N %.16E %.30R' 2>&1 | grep -Ei 'fswap|JOBID' || echo '  (none)'

echo "=== C. ESTIMATED START ==="
for j in 223959; do
  echo "  job $j start estimate: $(squeue -j $j -h --start -o '%S' 2>&1)"
done

echo "=== D. PARTITION OCCUPANCY (squeue only shows my own jobs on this cluster, so read sinfo) ==="
sinfo -o "%.10P %.6a %.6D %.6t %.30N" 2>&1 | head -20
echo "--- hgpu8 nodes in detail ---"
sinfo -p hgpu8 -N -o "%.9N %.6t %.20C %.20G %.30E" 2>&1 | head -10

echo "=== E. ANY LIMIT ON ME? ==="
sacctmgr -n show assoc user="$USER" format=Account,User,Partition,MaxJobs,MaxSubmit,GrpTRES,QOS 2>&1 | head -10

echo "=== F. WHAT ELSE OF MINE IS RUNNING (other channels' work counts against limits) ==="
squeue -u "$USER" -h -o '%T' 2>&1 | sort | uniq -c
echo "=== DONE ==="
