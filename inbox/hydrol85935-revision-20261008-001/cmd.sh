#!/bin/bash
# READ_ONLY_PACKET_FETCH batch 1/13: tar (no compression) | base64 of named packet files; no mutation
cd "/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v028_20261014_001/hpc_packet_001" || exit 3
echo "PF_BEGIN"; tar -cf - "index.json" "ledger_history.jsonl.gz" "manifest.json" "rows_0001.jsonl.gz" "rows_0002.jsonl.gz" "rows_0003.jsonl.gz" "rows_0004.jsonl.gz" "rows_0005.jsonl.gz" "rows_0006.jsonl.gz" "rows_0007.jsonl.gz" "rows_0008.jsonl.gz" | base64 -w 0; echo; echo "PF_END"
exit 0
