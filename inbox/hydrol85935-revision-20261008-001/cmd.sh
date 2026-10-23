#!/bin/bash
# READ_ONLY_TEMPORAL_REPORT_LIST: list temporal final report files; no mutation
T=/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001/attempts/infeasible_recovery_v002_20261015_001
echo "TR_TIME $(date -u +%FT%TZ)"
ls -l "$T/reports/" 2>&1 | head -30
for f in "$T"/reports/*.json; do echo "TR_SHA $(sha256sum "$f")"; done 2>&1 | head -20
exit 0
