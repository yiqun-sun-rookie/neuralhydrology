#!/bin/bash
# READ_ONLY_PACKET_FETCH batch 12/13: tar (no compression) | base64 of named packet files; no mutation
cd "/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v028_20261014_001/hpc_packet_001" || exit 3
echo "PF_BEGIN"; tar -cf - "rows_0088.jsonl.gz" "rows_0089.jsonl.gz" "rows_0090.jsonl.gz" "rows_0091.jsonl.gz" "rows_0092.jsonl.gz" "rows_0093.jsonl.gz" "rows_0094.jsonl.gz" "rows_0095.jsonl.gz" "rows_0096.jsonl.gz" | base64 -w 0; echo; echo "PF_END"
exit 0
