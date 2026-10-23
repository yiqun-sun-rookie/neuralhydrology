#!/bin/bash
# READ_ONLY_PACKET_FETCH batch 4/13: tar (no compression) | base64 of named packet files; no mutation
cd "/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v028_20261014_001/hpc_packet_001" || exit 3
echo "PF_BEGIN"; tar -cf - "rows_0025.jsonl.gz" "rows_0026.jsonl.gz" "rows_0027.jsonl.gz" "rows_0028.jsonl.gz" "rows_0029.jsonl.gz" "rows_0030.jsonl.gz" "rows_0031.jsonl.gz" | base64 -w 0; echo; echo "PF_END"
exit 0
