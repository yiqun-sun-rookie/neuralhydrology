#!/bin/bash
# READ_ONLY_PACKET_LIST: names, sizes and sha256 of the packet files; no mutation
cd "E:/Program Files/Git/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001/attempts/infeasible_recovery_v002_20261015_001/reports" || { echo "PK_MISSING"; exit 3; }
echo "PK_BEGIN"
for f in *; do [ -f "$f" ] && echo "$f|$(stat -c %s "$f")|$(sha256sum "$f" | cut -d' ' -f1)"; done
echo "PK_END"
exit 0
