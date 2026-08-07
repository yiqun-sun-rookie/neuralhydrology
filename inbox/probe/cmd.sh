#!/bin/bash
# liveness probe only
echo "ALIVE $(hostname) $(date -Iseconds)"
echo "--- runner processes ---"
pgrep -af "hpc_runner_active|runner2.sh" 2>&1 | head -5
echo "--- staging dirs (which channels are mid-flight) ---"
ls -la "$HOME/.hpc_mailbox_staging" 2>&1 | head -12
