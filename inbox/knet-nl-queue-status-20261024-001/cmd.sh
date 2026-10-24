#!/bin/bash
set -o pipefail
echo STATUS_QUERY_NONCE=KNET_NL_STATUS_20261024_001
date -u '+REMOTE_UTC=%Y-%m-%dT%H:%M:%SZ'
hostname
echo QUEUE_BEGIN
timeout 40 squeue -u sunyiq -h -o '%i|%j|%T|%M|%l|%R'
queue_rc=$?
echo QUEUE_END
echo QUEUE_EXIT_CODE=$queue_rc
echo KNOWN_JOBS_BEGIN
timeout 40 sacct -X -n -P -S 2026-10-19 -j 245709,246090,245567 --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End
accounting_rc=$?
echo KNOWN_JOBS_END
echo ACCOUNTING_EXIT_CODE=$accounting_rc
echo SCIENTIFIC_SUBMISSIONS=0
date -u '+QUERY_FINISHED_UTC=%Y-%m-%dT%H:%M:%SZ'
if [ "$queue_rc" -ne 0 ]; then exit "$queue_rc"; fi
exit "$accounting_rc"
