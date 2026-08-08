#!/bin/bash
# ID29 seq=6: diagnose why 201856/201857 vanished, fix the log-dir issue, resubmit only if they are really dead.
cd ~/hpc_mailbox || exit 1
ROOT=/data1/home/sunyiq/nearing2022_da

echo "=== A: what happened to the two jobs ==="
sacct -j 201856,201857 --format=JobID%12,JobName%12,State%14,ExitCode%8,Elapsed%10,Start%20,Reason%20 2>&1 | head -12

echo "=== B: anything of mine in the queue right now ==="
squeue -u "$USER" -o "%.10i %.10P %.12j %.8T %.10M %R" 2>&1

echo "=== C: does the log dir exist ==="
ls -ld "$ROOT/logs" 2>&1
ls -la "$ROOT/logs" 2>/dev/null | head -6

echo "=== D: create it ==="
mkdir -p "$ROOT/logs" && echo "  logs dir ready: $(ls -ld $ROOT/logs | awk '{print $1, $NF}')"

echo "=== E: resubmit if and only if nothing of mine is queued/running ==="
LEFT=$(squeue -u "$USER" -h -o "%i" 2>/dev/null | wc -l)
if [ "$LEFT" -ne 0 ]; then
  echo "  SKIP: $LEFT job(s) still active, not resubmitting"
else
  SIM=$(sbatch --parsable inbox/id29_simulation.slurm 2>&1)
  echo "  sim_jobid=$SIM"
  AR=$(sbatch --parsable inbox/id29_autoregression.slurm 2>&1)
  echo "  ar_jobid=$AR"
  sleep 45
  echo "--- queue after resubmit ---"
  squeue -u "$USER" -o "%.10i %.10P %.12j %.8T %.10M %R" 2>&1
  echo "--- first lines of each log ---"
  for j in $SIM $AR; do
    echo "  [job $j out]"; head -4 "$ROOT/logs"/*_${j}.out 2>&1 | head -6
    echo "  [job $j err]"; grep -viE "it/s|%\|" "$ROOT/logs"/*_${j}.err 2>/dev/null | head -4
  done
fi
