#!/bin/bash
# ID29 seq=5: launch the two training arms of the full 531-basin reproduction.
# User approved running this reproduction on HPC. Submit and report only - do NOT wait 11 hours here.
cd ~/hpc_mailbox || exit 1

echo "=== SUBMIT arm 1: simulation (531 basins, 30 epochs, target NSE 0.796) ==="
SIM=$(sbatch --parsable inbox/id29_simulation.slurm 2>&1)
echo "  sim_jobid=$SIM"

echo "=== SUBMIT arm 2: autoregression lag 1 (target NSE 0.879) ==="
AR=$(sbatch --parsable inbox/id29_autoregression.slurm 2>&1)
echo "  ar_jobid=$AR"

echo "=== QUEUE ==="
sleep 20
squeue -u "$USER" -o "%.10i %.10P %.12j %.8T %.10M %.10l %.6D %R" 2>&1

echo "=== EARLY PROGRESS (60s in) ==="
sleep 40
for j in $SIM $AR; do
  echo "--- job $j ---"
  tail -3 /data1/home/sunyiq/nearing2022_da/logs/*_${j}.out 2>/dev/null
  tail -3 /data1/home/sunyiq/nearing2022_da/logs/*_${j}.err 2>/dev/null | grep -viE "it/s|%\|" | head -3
done

echo "=== NOTE ==="
echo "arm 3 (data assimilation) depends on arm 1 finishing; submit it after sim_jobid=$SIM completes."
