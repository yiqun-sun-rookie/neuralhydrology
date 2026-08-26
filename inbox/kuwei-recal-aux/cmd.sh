#!/bin/bash
# Cleanup: the formal runs completed LOCALLY. Cancel any pending kuwei jobs on the cluster.
set -o pipefail
echo "=== cancel pending kuwei jobs ==="
for J in $(squeue -u ${USER} -h -o "%i %j" | grep -E 'kuwei' | awk '{print $1}'); do
  scancel $J && echo "cancelled $J"
done
squeue -u ${USER} -h -o "%i %j %T" | grep -i kuwei || echo "(no kuwei jobs left)"
echo "=== keep ~/kuwei_paired for reference; no further jobs will be submitted ==="
echo "=== DONE ==="
