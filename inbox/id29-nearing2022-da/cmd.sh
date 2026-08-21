#!/bin/bash
# ID29: CONFIRM the 204860_6 stall with hard evidence (file mtime + GPU state + process),
# then, only if confirmed, scancel and resubmit excluding the suspect nodes.
set -o pipefail
ROOT=/data1/home/sunyiq/nearing2022_da
SCRIPT="$ROOT/src/29_nearing2022_da_ar/hpc/run_registered_training_array.slurm"
BATCH=src/29_nearing2022_da_ar/registry/time_split_remaining_training_batch.txt

echo "=== TIME ==="; date --iso-8601=seconds

echo "=== EVIDENCE 1: log file mtime (is anything still being written?) ==="
SO=$(scontrol show job 204860_6 2>/dev/null | tr ' ' '\n' | sed -n 's/^StdOut=//p' | head -1)
echo "stdout=$SO"
if [ -n "$SO" ] && [ -f "$SO" ]; then
  stat -c 'bytes=%s  mtime=%y  age_seconds=%Y' "$SO"
  NOW=$(date +%s); MT=$(stat -c %Y "$SO"); echo "seconds_since_last_write=$((NOW-MT))"
fi
SE=$(scontrol show job 204860_6 2>/dev/null | tr ' ' '\n' | sed -n 's/^StdErr=//p' | head -1)
[ -n "$SE" ] && [ -f "$SE" ] && { echo "stderr:"; stat -c '  bytes=%s mtime=%y' "$SE"; echo "  tail:"; tail -n 12 "$SE" 2>/dev/null | sed 's/^/    /' || true; }

echo "=== EVIDENCE 2: what the process is doing on the node ==="
NODE=$(squeue -h -j 204860_6 -o '%N' 2>/dev/null)
echo "node=$NODE"
if [ -n "$NODE" ]; then
  srun --jobid=204860 --nodes=1 --ntasks=1 -w "$NODE" --overlap \
    bash -c 'echo "--- nvidia-smi ---"; nvidia-smi --query-gpu=index,utilization.gpu,memory.used,memory.total --format=csv 2>&1 | head -6;
             echo "--- python procs ---"; ps -eo pid,etimes,stat,pcpu,args | grep -E "[n]h_run|[p]ython -u" | head -5' 2>&1 | head -20 || echo "  srun probe failed (may be busy/denied)"
fi

echo "=== EVIDENCE 3: checkpoints already on disk for this coordinate ==="
AR="$ROOT/closure_20260810/time_split/autoregression"
find "$AR" -maxdepth 2 -path '*lead2_holdout0.75_seed0*' -name 'model_epoch*.pt' -printf '  %TY-%Tm-%Td %TH:%TM  %f  %p\n' 2>/dev/null | sort | tail -5 || echo "  none"

echo "=== END EVIDENCE seq marker ==="
date --iso-8601=seconds
exit 0
