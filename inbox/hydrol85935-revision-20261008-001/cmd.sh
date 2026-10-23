#!/bin/bash
# READ_ONLY_PACKET_FETCH batch 5/13: tar (no compression) | base64 of named packet files; no mutation
cd "/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v028_20261014_001/hpc_packet_001" || exit 3
echo "PF_BEGIN"; tar -cf - "rows_0032.jsonl.gz" "rows_0033.jsonl.gz" "rows_0034.jsonl.gz" "rows_0035.jsonl.gz" "rows_0036.jsonl.gz" "rows_0037.jsonl.gz" "rows_0038.jsonl.gz" "rows_0039.jsonl.gz" | base64 -w 0; echo; echo "PF_END"
exit 0
