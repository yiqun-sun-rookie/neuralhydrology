#!/usr/bin/env bash
# ID33 seq=4 : read-only cluster survey. Which 3090 capacity is actually free right now?
set -o pipefail
echo "=== STAMP ==="; date -Is

echo "=== A. ALL GPU PARTITIONS, NODE STATE ==="
sinfo -o "%.10P %.6a %.8D %.8t %.32N %.10l" 2>&1 | grep -E 'PARTITION|gpu' || true
echo "-- per-node detail with GRES and cpus --"
sinfo -N -o "%.10N %.10P %.9T %.5c %.14G %.28E" 2>&1 | grep -E 'NODELIST|ngu' || true
echo "-- drained / down reasons --"
sinfo -R 2>&1 | head -12 || true

echo "=== B. MY OWN QUEUE, WITH PREDICTED START ==="
squeue -u "$USER" -o "%.9i %.12j %.9P %.2t %.11M %.22R %.20S" 2>&1 || true

echo "=== C. WHAT ARE ngu003 / ngu009 DOING (hgpu2, SAME RTX 3090) ==="
scontrol show node ngu003 2>&1 | tr ' ' '\n' | grep -E 'NodeName|State|CPUAlloc|CPUTot|Gres|RealMemory|AllocMem' | head -10 || true
echo "--"
scontrol show node ngu009 2>&1 | tr ' ' '\n' | grep -E 'NodeName|State|CPUAlloc|CPUTot|Gres|RealMemory|AllocMem' | head -10 || true

echo "=== D. DOES THE ACCOUNT HAVE A CONCURRENT-JOB LIMIT? ==="
sacctmgr -n -P show assoc where user=$USER format=Account,Partition,MaxJobs,MaxSubmit,GrpTRES,MaxTRES 2>&1 | head -10 || echo "sacctmgr unavailable"
scontrol show config 2>&1 | grep -E 'MaxArraySize|MaxJobCount|DefaultTime|PriorityType|PreemptType' || true

echo "=== E. HOW MANY OF MY JOBS ARE RUNNING VS PENDING ==="
echo -n "running="; squeue -u "$USER" -h -t RUNNING -o "%i" 2>/dev/null | wc -l
echo -n "pending="; squeue -u "$USER" -h -t PENDING -o "%i" 2>/dev/null | wc -l

echo "=== F. ID33 T1 PROGRESS ==="
R=/data1/home/sunyiq/id33_transformer_recipe_repair_20260904/repo/results/33_transformer_recipe_repair
f=$(find "$R/T1" -name output.log -type f 2>/dev/null | head -1)
if test -n "$f"; then
  grep -E 'Epoch [0-9]+ average' "$f" 2>&1 | tail -4 || true
  grep 'Median validation metrics' "$f" 2>&1 | tail -2 || echo "  no validation yet"
else echo "  no output.log yet"; fi
echo ID33_SURVEY_SEQ4_COMPLETE
