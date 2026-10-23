#!/bin/bash
# READ_ONLY_PACKET_LIST: names, sizes and sha256 of the packet files; no mutation
cd "/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/workflow_v010_20261012_001/hpc_packet_001" || { echo "PK_MISSING"; exit 3; }
echo "PK_BEGIN"
for f in *; do [ -f "$f" ] && echo "$f|$(stat -c %s "$f")|$(sha256sum "$f" | cut -d' ' -f1)"; done
echo "PK_END"
exit 0
