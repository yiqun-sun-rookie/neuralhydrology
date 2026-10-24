#!/bin/bash
# Read-only: why is own A1+DA 246280 still Resources-pending? Free 3090s and start estimate.
set -o pipefail
date --iso-8601=seconds
for P in hgpu2p hgpu2; do sinfo -p $P -N -h -O nodelist:10,statecompact:8,gres:14,gresused:24 2>/dev/null; done
squeue -j 246280,246281 -h --start -o '%i|%T|%R|%S|%l' 2>&1 | head -4
echo "SEQ70_DONE"
