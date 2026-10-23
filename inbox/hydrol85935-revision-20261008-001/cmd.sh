#!/bin/bash
# READ_ONLY_EXPORT_FAIL: why export 241344 failed on icn218; packet dir state; no mutation
W=/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/workflow_v010_20261012_001
sacct -j 241344 -n -P -o JobID,State,ExitCode,Elapsed,Start,End,Partition,NodeList 2>&1
ls -la $W | grep -E "export|hpc_packet"
echo EF_ERR; tail -c 4000 $W/export-241344.err 2>&1
echo EF_OUT; tail -c 2000 $W/export-241344.out 2>&1
echo EF_PACKET; ls -la $W/hpc_packet_001 2>&1 | head
exit 0
