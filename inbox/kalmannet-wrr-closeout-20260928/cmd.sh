#!/usr/bin/env bash
set -eo pipefail
root=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
sacct -n -P -j 228823 -o JobID,JobName,State,ExitCode,Elapsed,NodeList
if [ -f "$root/counter_metrics_001/metrics.json" ]; then
  cat "$root/counter_metrics_001/metrics.json"
  sha256sum "$root/counter_metrics_001/metrics.json"
fi
cat "$root/logs/counter-metrics-228823.out"
cat "$root/logs/counter-metrics-228823.err"
