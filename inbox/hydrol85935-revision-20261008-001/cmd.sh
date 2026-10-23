#!/bin/bash
# READ_ONLY_VALIDATE_LOG: show validate job 241337 stdout/stderr and stage_results listing; no mutation
S=/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v009_20261012_001
wc -c $S/logs/validate-241337_4294967294.out $S/logs/validate-241337_4294967294.err
echo VL_OUT_HEAD; head -c 3000 $S/logs/validate-241337_4294967294.out
echo; echo VL_OUT_TAIL; tail -c 6000 $S/logs/validate-241337_4294967294.out
echo; echo VL_STAGE; ls -lt $S/stage_results | head -8
exit 0
