#!/bin/bash
# nature1st-attr-swap seq=100 -- READ-ONLY. Did armJ start? And can I identify the
# GPU model on the idle nodes WITHOUT submitting anything?
set -o pipefail
date "+wallclock %F %T %z"

echo "=== A. armJ NOW ==="
squeue -j 215195 -o '%.10i %.22j %.9T %.10M %.9N %.26R %.20S' 2>&1
sacct -j 215195 -X --format=JobID%10,State%12,Elapsed%11,NodeList%9 2>&1

echo "=== B. WHOLE hgpu2p QUEUE (is anything ahead of me?) ==="
squeue -p hgpu2p -o '%.10i %.9u %.9T %.10M %.9N %.18R %.10Q' 2>&1 | head -12
echo '-- gpu allocation per hgpu2p node --'
scontrol show node ngu001 ngu004 ngu005 ngu006 ngu007 ngu008 ngu010 ngu011 2>&1 | grep -E 'NodeName|AllocTRES|State=' | paste - - - 2>/dev/null | head -10 || true

echo "=== C. GPU MODEL WITHOUT SUBMITTING: any record on shared filesystem? ==="
echo '-- old node-test outputs that may name the card --'
grep -ril 'NVIDIA\|GeForce\|RTX\|A100\|A800\|V100\|Tesla' /data1/home/sunyiq/hpc_mailbox/outbox/*.out 2>/dev/null | head -5 || echo '  (none)'
for f in $(ls -t /data1/home/sunyiq/hpc_mailbox/outbox/slurm_*.out 2>/dev/null | head -8); do
  hit=$(grep -m1 -E 'NVIDIA|GeForce|RTX|A100|A800|V100|Tesla' "$f" 2>/dev/null || true)
  [ -n "$hit" ] && printf '  %-52s %s
' "$(basename $f)" "$hit"
done
echo '-- any nvidia-smi capture anywhere in my logs --'
grep -rh -m1 -E 'NVIDIA-SMI|Product Name|GeForce RTX|A800|A100' /data1/home/sunyiq/nature_1st/logs/attr_swap/*.err 2>/dev/null | head -3 || echo '  (nothing in arm logs)'

echo "=== D. DOES SLURM RECORD A GPU TYPE ANYWHERE? ==="
scontrol show config 2>&1 | grep -iE 'GresTypes|AccountingStorageTRES' | head -4 || true
sacct -j 206175,211317 -X --format=JobID%10,NodeList%9,AllocTRES%60 2>&1 | head -6
echo "=== END seq=100 ==="
