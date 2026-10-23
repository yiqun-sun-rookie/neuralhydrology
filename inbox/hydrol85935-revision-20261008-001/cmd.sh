#!/bin/bash
# READ_ONLY_TEMPORAL_REPORT_FETCH: emit the three final report files as gzip+base64; no mutation
T=/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001/attempts/infeasible_recovery_v002_20261015_001
cd "$T/reports" || exit 3
echo "TF_TIME $(date -u +%FT%TZ)"
echo "TF_BEGIN"; tar -czf - basin_pairs.json coverage_and_summary.json cross_environment_reconstruction.json | base64 -w 0; echo; echo "TF_END"
exit 0
