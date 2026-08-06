#!/bin/bash
echo "=== runner2 multi-channel smoke ==="
echo "channel=probe  host=$(hostname)  time=$(date -Iseconds)"
echo "--- active runner ---"
pgrep -af "hpc_runner_active" || pgrep -af "runner" || echo "(none)"
echo "--- channels present ---"
ls -d ~/hpc_mailbox/inbox/*/ 2>/dev/null
echo "--- concurrency proof: sleep 45s then report ---"
sleep 45
echo "woke at $(date -Iseconds)  (if another channel got a result during this, concurrency works)"
