#!/bin/bash
# READ_ONLY_PACKET_FETCH batch 2/13: tar (no compression) | base64 of named packet files; no mutation
cd "/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v028_20261014_001/hpc_packet_001" || exit 3
echo "PF_BEGIN"; tar -cf - "rows_0009.jsonl.gz" "rows_0010.jsonl.gz" "rows_0011.jsonl.gz" "rows_0012.jsonl.gz" "rows_0013.jsonl.gz" "rows_0014.jsonl.gz" "rows_0015.jsonl.gz" "rows_0016.jsonl.gz" | base64 -w 0; echo; echo "PF_END"
exit 0
