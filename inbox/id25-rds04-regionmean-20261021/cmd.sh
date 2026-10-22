#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_regional_regionmean_rds04_20261021_001
stage="$root/resource_compatibility_v003"
payload=/data1/home/sunyiq/hpc_mailbox/inbox/id25-rds04-regionmean-20261021/payload/id25_apply_cpu_execution_partitions_v003.py
mkdir -p "$stage"
test ! -f "$stage/apply_result.json"
printf '%s  %s\n' '70de31f5423d1314c3610c9e8716297a95b2af9fda41449298df78ea60b2f9b0' "$payload" | sha256sum -c -
cp "$payload" "$stage/id25_apply_cpu_execution_partitions_v003.py"
timeout 30 scontrol -o show node 'ngu[001-002,004-008,010-011]' > "$stage/cpu_node_metadata_before.txt"
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - "$stage/cpu_node_metadata_before.txt" <<'PYMETADATA'
from pathlib import Path
import sys
lines=Path(sys.argv[1]).read_text().splitlines()
assert len(lines)==9
for line in lines:
    assert 'Arch=x86_64' in line and 'OS=Linux' in line
print('CPU_NODE_METADATA_COMPATIBLE_NO_NUMERICAL_PREFLIGHT')
print(Path(sys.argv[1]).read_text())
PYMETADATA
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python "$stage/id25_apply_cpu_execution_partitions_v003.py" --partitions hgpu2p,hcpu48y,hcpu48
timeout 30 squeue --start -j 246090 -o '%i|%T|%r|%S|%Q|%R' || true
printf 'CPU_EXECUTION_ONLY_NO_NEW_GPU_REQUEST_NO_NEW_SUBMISSION\n'
