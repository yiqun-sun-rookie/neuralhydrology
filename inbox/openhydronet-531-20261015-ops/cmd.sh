#!/bin/bash
set -o pipefail
# read-only ops probe: my own eval process
date --iso-8601=seconds
ps -u sunyiq -o pid,etimes,pcpu,rss,nice,args --sort=-etimes 2>/dev/null | grep -E "ohn_eval|runner|cmd_" | grep -v grep | cut -c1-220 | head -10
echo "--- load / mem"
uptime
free -g | head -2
ls -la /data1/home/sunyiq/openhydronet_531_20261015/results/ 2>/dev/null
ls -la ~/.hpc_mailbox_staging/openhydronet-531-20261015/ 2>/dev/null | tail -3
exit 0
