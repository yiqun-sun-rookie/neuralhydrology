#!/bin/bash
# READ_ONLY_PACKET_FETCH batch 3/13: tar (no compression) | base64 of named packet files; no mutation
cd "/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v028_20261014_001/hpc_packet_001" || exit 3
echo "PF_BEGIN"; tar -cf - "rows_0017.jsonl.gz" "rows_0018.jsonl.gz" "rows_0019.jsonl.gz" "rows_0020.jsonl.gz" "rows_0021.jsonl.gz" "rows_0022.jsonl.gz" "rows_0023.jsonl.gz" "rows_0024.jsonl.gz" | base64 -w 0; echo; echo "PF_END"
exit 0
