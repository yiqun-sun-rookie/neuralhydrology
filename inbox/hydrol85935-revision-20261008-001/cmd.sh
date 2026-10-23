#!/bin/bash
# READ_ONLY_PACKET_FETCH batch 7/13: tar (no compression) | base64 of named packet files; no mutation
cd "/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v028_20261014_001/hpc_packet_001" || exit 3
echo "PF_BEGIN"; tar -cf - "rows_0047.jsonl.gz" "rows_0048.jsonl.gz" "rows_0049.jsonl.gz" "rows_0050.jsonl.gz" "rows_0051.jsonl.gz" "rows_0052.jsonl.gz" "rows_0053.jsonl.gz" "rows_0054.jsonl.gz" | base64 -w 0; echo; echo "PF_END"
exit 0
