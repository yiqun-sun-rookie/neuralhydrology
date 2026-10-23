#!/bin/bash
# READ_ONLY_PACKET_FETCH batch 10/13: tar (no compression) | base64 of named packet files; no mutation
cd "/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v028_20261014_001/hpc_packet_001" || exit 3
echo "PF_BEGIN"; tar -cf - "rows_0072.jsonl.gz" "rows_0073.jsonl.gz" "rows_0074.jsonl.gz" "rows_0075.jsonl.gz" "rows_0076.jsonl.gz" "rows_0077.jsonl.gz" "rows_0078.jsonl.gz" "rows_0079.jsonl.gz" "rows_0080.jsonl.gz" | base64 -w 0; echo; echo "PF_END"
exit 0
