#!/usr/bin/env bash
# ID33 : how much of the A800 am I actually holding and using? Read-only.
set -o pipefail
echo "=== STAMP ==="; date -Is

echo "=== A. WHAT C1 AND C2 HOLD (full TRES, not truncated) ==="
for J in 220658 220659; do
  echo "--- job $J ---"
  scontrol show job "$J" 2>/dev/null | tr ' ' '\n' | grep -E '^(JobId|JobState|NumNodes|NumCPUs|TresPerNode|TRES|Gres|NodeList|StartTime)=' || true
done

echo "=== B. NODE ngu201 TOTALS: how many GPUs exist and how many are allocated ==="
scontrol show node ngu201 2>/dev/null | tr ' ' '\n' | grep -E '^(NodeName|State|CPUAlloc|CPUTot|CfgTRES|AllocTRES|Gres)=' || true

echo "=== C. LIVE GPU USE INSIDE MY OWN ALLOCATION ==="
for J in 220658 220659; do
  echo "--- job $J: nvidia-smi from inside the allocation ---"
  timeout 60 srun --overlap --jobid="$J" -n1 \
    nvidia-smi --query-gpu=index,name,memory.total,memory.used,utilization.gpu,utilization.memory \
    --format=csv,noheader 2>&1 | head -10 || echo "  srun --overlap unavailable on this job"
done

echo "=== D. FOR CONTRAST, A 3090 ARM (T5 still running) ==="
timeout 60 srun --overlap --jobid=220494 -n1 \
  nvidia-smi --query-gpu=index,name,memory.total,memory.used,utilization.gpu \
  --format=csv,noheader 2>&1 | head -6 || echo "  unavailable"

echo "=== E. WHO ELSE IS ON ngu201 (count only, PrivateData hides other users) ==="
squeue -w ngu201 -h -o "%i %u %b" 2>&1 | head -12 || true
echo -n "  visible jobs on ngu201: "; squeue -w ngu201 -h -o "%i" 2>/dev/null | wc -l

echo "=== F. MY TOTAL GPU FOOTPRINT RIGHT NOW ==="
squeue -u "$USER" -h -t RUNNING -o "%i %j %b %D %R" 2>&1 || true
echo ID33_GPU_FOOTPRINT_COMPLETE
