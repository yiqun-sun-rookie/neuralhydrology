#!/bin/bash
# nature1st-attr-swap seq=98 -- READ-ONLY node audit. Is ngu002 (and any other
# excluded/unused node) actually usable right now? Our sbatch files all carry
# '#SBATCH --exclude=ngu002' on the strength of a note, not a fresh measurement.
# NO sbatch, NO scontrol update, nothing that changes state.
set -o pipefail
date "+wallclock %F %T %z"

echo "=== A. ALL GPU PARTITIONS I CAN USE ==="
sinfo -o '%.12P %.6a %.11l %.6D %.8t %.14C %N' 2>&1 | head -25

echo "=== B. NODE-BY-NODE, WITH GPU COUNT AND FREE CPUS ==="
sinfo -N -o '%.9N %.12P %.8t %.10e %.14C %.24G %.30E' 2>&1 | head -40

echo "=== C. ngu002 IN DETAIL (why is it excluded?) ==="
scontrol show node ngu002 2>&1 | head -30

echo "=== D. HAS ANYTHING RUN SUCCESSFULLY ON ngu002 LATELY? ==="
echo '-- my jobs on ngu002, last 30 days --'
sacct -S $(date -d '30 days ago' +%F) -u $USER -X --format=JobID%12,JobName%22,State%14,ExitCode%8,Elapsed%11,End%17,NodeList%9 2>&1 | grep -E 'ngu002|JobID|^---' | head -20 || echo '  (none of my jobs landed on ngu002)'

echo "=== E. MY PENDING JOB 215195 -- WHY IS IT WAITING, AND WOULD ngu002 HELP? ==="
squeue -j 215195 -o '%.10i %.22j %.9T %.10M %.30R %.20S %.12Q' 2>&1
echo '-- what it asked for --'
scontrol show job 215195 2>&1 | grep -E 'ExcNodeList|ReqNodeList|TRES=|Partition|JobState|Reason|StartTime' | head -8 || true

echo "=== F. WHO IS AHEAD OF ME IN hgpu2p ==="
squeue -p hgpu2p -o '%.10i %.9u %.9T %.10M %.20R %.10Q' 2>&1 | head -15

echo "=== G. OTHER PARTITIONS -- ANY IDLE GPU NODES? ==="
sinfo -o '%.12P %.8t %.6D %N' 2>&1 | grep -Ei 'idle|mix' | head -15 || true
echo "=== END seq=98 ==="
