#!/bin/bash
# TUKF09-455: how many cards are actually free on each hgpu8 node. Read only, sinfo only.
set -o pipefail
echo "TIME=$(date -Is)"
echo "=== GRES TOTAL vs USED PER NODE ==="
sinfo -p hgpu8 -N -O "NodeHost:12,StateLong:14,Gres:16,GresUsed:22,CPUsState:16,FreeMem:12" 2>&1
echo "=== other gpu partitions ==="
sinfo -p hgpu4,hgpu2p,hgpu2 -N -O "NodeHost:12,StateLong:12,Gres:14,GresUsed:20,CPUsState:14" 2>&1 | head -14
echo "=== reservations ==="
sinfo -T 2>&1 | head -8
echo "=== start estimate ==="
squeue -u $USER --start 2>&1 | grep -E "223992|START"
echo TUKF09_455_GRES_DIAGNOSTIC
