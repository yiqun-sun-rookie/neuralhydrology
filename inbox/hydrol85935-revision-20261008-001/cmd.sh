#!/bin/bash
# READ_ONLY_PACKET_FETCH batch 13/13: tar (no compression) | base64 of named packet files; no mutation
cd "/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v028_20261014_001/hpc_packet_001" || exit 3
echo "PF_BEGIN"; tar -cf - "rows_0097.jsonl.gz" "rows_0098.jsonl.gz" "rows_0099.jsonl.gz" "rows_0100.jsonl.gz" "rows_0101.jsonl.gz" "rows_0102.jsonl.gz" | base64 -w 0; echo; echo "PF_END"
exit 0
