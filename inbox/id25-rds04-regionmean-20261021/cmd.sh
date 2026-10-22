#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_regional_regionmean_rds04_20261021_001
stage="$root/resource_compatibility_v001"
payload=/data1/home/sunyiq/hpc_mailbox/inbox/id25-rds04-regionmean-20261021/payload/id25_apply_cpu_partitions_v001.py
mkdir -p "$stage"
test ! -f "$stage/apply_result.json"
printf '%s  %s\n' 'cdcc125995613af264f817a427cd14a38ba2653636fc03dbc246e6ee20dd30e9' "$payload" | sha256sum -c -
cp "$payload" "$stage/id25_apply_cpu_partitions_v001.py"
for node in icn273 icn274 icn275 icn277; do timeout 30 scontrol -o show node "$node"; done > "$stage/cpu_node_metadata_before.txt"
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - "$stage/cpu_node_metadata_before.txt" <<'PYMETADATA'
from pathlib import Path
import sys
lines=Path(sys.argv[1]).read_text().splitlines()
assert len(lines)==4
for line in lines:
    assert 'Arch=x86_64' in line and 'OS=Linux' in line, 'Unexpected CPU architecture/OS'
print('CPU_NODE_METADATA_COMPATIBLE_NO_NUMERICAL_PREFLIGHT')
PYMETADATA
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python "$stage/id25_apply_cpu_partitions_v001.py" --partitions hcpu48,hcpu48y
echo START_ESTIMATE_AFTER
 timeout 30 squeue --start -j 246090 -o '%i|%T|%r|%S|%Q|%R' || true
cat "$stage/cpu_node_metadata_before.txt"
echo NO_CANCELLATION_NO_NEW_SUBMISSION_NO_PREFLIGHT
