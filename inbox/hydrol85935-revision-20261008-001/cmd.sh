#!/bin/bash
# READ_ONLY_EXPORT_STATE: state of resubmitted export 246828 and its packet dir; no mutation
W=/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/workflow_v010_20261012_001
echo "ES_STATE $(sacct -j 246828 -X -n -P -o State,ExitCode,Elapsed,NodeList 2>&1 | head -1)"
echo ES_OUT; tail -c 1500 $W/export-246828.out 2>&1; echo; echo ES_ERR; tail -c 1500 $W/export-246828.err 2>&1
echo; echo "ES_PACKET $(ls $W/hpc_packet_001 2>/dev/null | wc -l) files $(du -sm $W/hpc_packet_001 2>/dev/null | cut -f1) MB"
exit 0
