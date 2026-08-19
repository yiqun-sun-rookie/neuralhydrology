#!/bin/bash
# id23-dlimm seq=3 : why is 205449 pending; what partitions can actually take a CPU-only job.
set -o pipefail

echo "=== SECTION A: my job ==="
squeue -j 205449 -o "%.10i %.12P %.10T %.20r %.20S %.10L" 2>&1 | head -4 || true
sacct -j 205449 -X --format=JobID%10,Partition%10,State%12,Submit%20,Start%20 2>&1 | head -4 || true

echo "=== SECTION B: hcpu48 state ==="
sinfo -p hcpu48 -o "%P %a %D %t %N" 2>&1 | head -10 || true
echo "queued on hcpu48: $(squeue -p hcpu48 -h -o '%i' 2>/dev/null | wc -l)"

echo "=== SECTION C: all partitions, idle counts ==="
sinfo -o "%P %a %D %t" 2>&1 | head -25 || true

echo "=== SECTION D: can hgpu2p take a job with no gres? ==="
scontrol show partition hgpu2p 2>&1 | tr ' ' '\n' | grep -E "^(Name|State|TotalNodes|TotalCPUs|MaxTime|DefMemPerNode|QoS|AllowGroups)=" | head -10 || true

echo "=== SECTION E: my queue overall ==="
squeue -u "$USER" -o "%.10i %.12P %.14j %.10T %.20r" 2>&1 | head -12 || true
echo "=== DONE ==="
