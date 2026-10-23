#!/bin/bash
# READ_ONLY_PACKET_FETCH batch 1/2: tar (no compression) | base64 of named packet files; no mutation
cd "/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001/attempts/infeasible_recovery_v002_20261015_001/reports" || exit 3
echo "PF_BEGIN"; tar -cf - "basin_pairs.json" | base64 -w 0; echo; echo "PF_END"
exit 0
