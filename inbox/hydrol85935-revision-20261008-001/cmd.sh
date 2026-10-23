#!/bin/bash
# READ_ONLY_PACKET_FETCH batch 8/13: tar (no compression) | base64 of named packet files; no mutation
cd "/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v028_20261014_001/hpc_packet_001" || exit 3
echo "PF_BEGIN"; tar -cf - "rows_0055.jsonl.gz" "rows_0056.jsonl.gz" "rows_0057.jsonl.gz" "rows_0058.jsonl.gz" "rows_0059.jsonl.gz" "rows_0060.jsonl.gz" "rows_0061.jsonl.gz" "rows_0062.jsonl.gz" "rows_0063.jsonl.gz" | base64 -w 0; echo; echo "PF_END"
exit 0
