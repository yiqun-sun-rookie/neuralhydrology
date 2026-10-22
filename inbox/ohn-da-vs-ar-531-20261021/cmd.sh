#!/bin/bash
# Read-only: why does an idle healthy ngu001 not start own Priority-pending jobs? Time limits, reservations, start estimates.
set -o pipefail
date --iso-8601=seconds
echo "=== OWN TIME LIMITS ==="
squeue -j 246243,246378,246279,246280,246281 -h -o '%i|%l|%P|%R|%S' 2>&1 | head -10
echo "=== RESERVATIONS ==="
scontrol show reservation 2>&1 | grep -E 'ReservationName|Nodes=|StartTime' | head -12
echo "=== NGU001 ==="
scontrol show node ngu001 2>&1 | grep -oE '(State|Reason|AvailableFeatures|Partitions|Gres|CfgTRES|AllocTRES)=[^ ]*' | head -10
echo "=== START ESTIMATES hgpu2p pending (all users, anonymized) ==="
squeue -p hgpu2p -h -t PD -o '%Q|%l|%D|%b|%S|%R' --sort=-p 2>&1 | head -16
echo "SEQ25_DONE"
