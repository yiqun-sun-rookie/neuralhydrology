#!/bin/bash
# nature1st-attr-swap seq=99 -- READ-ONLY. Two questions:
#  (1) do hgpu4 / hgpu2 / hgpu8 carry the SAME gpu model as hgpu2p? If not, moving
#      armJ there breaks comparability with the eight arms already run on hgpu2p.
#  (2) what is job 215178 (my own job blocking armJ), and are hgpu2p's GPUs actually
#      all busy, or only its CPUs partly used?
set -o pipefail
date "+wallclock %F %T %z"

echo "=== A. GPU MODEL PER PARTITION (the decisive question) ==="
for n in ngu001 ngu004 ngu005 ngu006 ngu007 ngu008 ngu010 ngu011 ngu003 ngu009 ngu101 ngu102 ngu104 ngu201 ngu202 ngu203 ; do
  line=$(scontrol show node $n 2>/dev/null | tr '
' ' ')
  part=$(echo "$line" | grep -oE 'Partitions=[^ ]+' | cut -d= -f2)
  gres=$(echo "$line" | grep -oE 'Gres=[^ ]+' | cut -d= -f2)
  st=$(echo "$line"   | grep -oE 'State=[^ ]+' | cut -d= -f2)
  agres=$(echo "$line"| grep -oE 'AllocTRES=[^ ]*' | cut -d= -f2)
  printf '  %-8s %-10s %-14s %-12s alloc=%s
' "$n" "$part" "$gres" "$st" "${agres:-none}"
done

echo "=== B. WHICH NODES DID THE EIGHT FINISHED ARMS RUN ON? ==="
sacct -S 2026-08-18 -u $USER -X --format=JobID%10,JobName%24,State%11,NodeList%9,Elapsed%11 2>&1 | grep -E 'q_ctrl|q_treat|q_arm|JobID|^---' | head -14 || true

echo "=== C. ARE hgpu2p GPUs ACTUALLY ALL TAKEN? ==="
echo '-- gres alloc vs total, per hgpu2p node --'
sinfo -p hgpu2p -N -o '%.9N %.8t %.16G %.34e' 2>&1 | head -12
echo '-- running jobs in hgpu2p and their gpu request --'
squeue -p hgpu2p -t RUNNING -o '%.10i %.9u %.20j %.10M %.8N %.14b' 2>&1 | head -15

echo "=== D. WHAT IS JOB 215178 (blocking armJ)? ==="
scontrol show job 215178 2>&1 | grep -E 'JobName|JobState|Reason|Partition|StartTime|TRES=|NumNodes|TimeLimit|WorkDir' | head -10 || true

echo "=== E. IF I ALSO OFFERED hgpu4/hgpu2, WHEN WOULD armJ START? (simulation, no change) ==="
echo '-- current estimate on hgpu2p only --'
squeue -j 215195 -o '%.10i %.9T %.20S %.24R' 2>&1
echo '-- idle GPU capacity elsewhere right now --'
sinfo -p hgpu4,hgpu2,hgpu8 -N -o '%.9N %.10P %.8t %.16G %.14C' 2>&1 | head -14
echo "=== END seq=99 ==="
