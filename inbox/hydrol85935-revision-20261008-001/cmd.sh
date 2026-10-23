#!/bin/bash
# READ_ONLY_PACKET_FETCH batch 6/13: tar (no compression) | base64 of named packet files; no mutation
cd "/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v028_20261014_001/hpc_packet_001" || exit 3
echo "PF_BEGIN"; tar -cf - "rows_0040.jsonl.gz" "rows_0041.jsonl.gz" "rows_0042.jsonl.gz" "rows_0043.jsonl.gz" "rows_0044.jsonl.gz" "rows_0045.jsonl.gz" "rows_0046.jsonl.gz" | base64 -w 0; echo; echo "PF_END"
exit 0
