#!/usr/bin/env bash
set -eo pipefail
root=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1/plain_preflight_v1
sacct -n -P -j 228835 -o JobID,JobName,State,ExitCode,Elapsed,NodeList
squeue -h -j 228835 -o '%i|%j|%T|%P|%R'
find "$root/numerical_impact/runs" -maxdepth 3 -name completion.json -printf '%P\n' | sort
find "$root/numerical_impact/runs" -maxdepth 2 -name failure.json -exec cat {} \;
for f in "$root"/logs/*228835*; do
  echo "LOG=$f"
  tail -60 "$f"
done
first="$root/numerical_impact/runs/main_seed42__original_outlet_original_states__preflight_attempt01"
if [ -f "$first/completion.json" ]; then cat "$first/completion.json"; fi
if [ -f "$first/resources.json" ]; then cat "$first/resources.json"; fi
if [ -f "$first/load_ledger.json" ]; then cat "$first/load_ledger.json"; fi
