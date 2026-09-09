#!/bin/bash
# TUKF09-455: who is holding the hgpu8 cards, and when do they end. Read only.
set -o pipefail
echo "TIME=$(date -Is)"
echo "=== PARTITION ==="
sinfo -p hgpu8 -o "%.10P %.8t %.10N %.20C %.10G %.14l" 2>&1
echo "=== EVERY JOB ON hgpu8 ==="
squeue -p hgpu8 -o "%.10i %.9u %.18j %.9T %.11M %.11l %.7D %.10b %.9N %.20R" 2>&1
echo "=== GPU HOLDERS PER NODE ==="
for n in ngu201 ngu203; do echo "--- $n"; squeue -w $n -h -o "%.10i %.9u %.9T %.11M %.11l %.10b %.20j" 2>&1; done
echo "=== OUR JOB POSITION ==="
squeue -u $USER -o "%.10i %.12P %.20j %.9T %.11M %.11l %.10b %.20R %.12Q" 2>&1
echo "=== WHEN COULD IT START (slurm estimate) ==="
squeue -u $USER --start 2>&1 | head -8
echo "=== OTHER PARTITIONS WITH 8 GPUS ==="
sinfo -o "%.12P %.6a %.6D %.8t %.16N %.10G" 2>&1 | head -14
echo TUKF09_455_QUEUE_DIAGNOSTIC
