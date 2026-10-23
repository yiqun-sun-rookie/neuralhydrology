#!/bin/bash
# READ_ONLY_QUEUE_AHEAD_EXPORT: pending jobs ahead of export 241344 on hgpu2p, running jobs and node states; no mutation
echo "QA_TIME $(date -u +%FT%TZ)"
squeue -j 241344 -h -o "%i|%T|%r|%Q|%S" 2>&1
sprio -j 241344 -h 2>&1 | head -2
echo "QA_PENDING"; squeue -p hgpu2p -t PD -h -o "%i|%j|%u|%Q|%r|%S|%l|%b" 2>&1 | sort -t"|" -k4 -nr | head -10
echo "QA_RUNNING"; squeue -p hgpu2p -t R -h -o "%i|%j|%u|%M|%l|%e|%N|%b" 2>&1 | head -24
echo "QA_NODES"; sinfo -p hgpu2p -h -N -o "%n %t %G %C" 2>&1 | head -12
exit 0
