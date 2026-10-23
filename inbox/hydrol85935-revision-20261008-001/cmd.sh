#!/bin/bash
# READ_ONLY_QUEUE_AHEAD: identify pending jobs ahead of 241337 on hgpu2p; no mutation
echo "QA_TIME $(date -u +%FT%TZ)"
squeue -p hgpu2p -t PD -h -o "%i|%j|%Q|%r|%S|%l|%b" 2>&1 | sort -t"|" -k3 -nr | head -8
echo "QA_RUNNING_END"; squeue -p hgpu2p -t R -h -o "%i|%j|%u|%M|%l|%e" 2>&1 | head -20
exit 0
