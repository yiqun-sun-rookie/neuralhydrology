#!/bin/bash
set -o pipefail

MAILBOX=/data1/home/sunyiq/hpc_mailbox
STAGED_RESULT=/data1/home/sunyiq/.hpc_mailbox_staging/id18-weight-merge/result_6.txt
PERSISTENT_ARCHIVE=/data1/home/sunyiq/id18_output_ensemble_20260826/transport/base64_retrieval_v1/OE01_OUTPUT_ENSEMBLE_JOB212908_RESULTS.tar.gz

echo "=== ID18 SEQ6 SCHEDULING DIAGNOSTIC ==="
date -Is
hostname
echo "local_seq=$(cat ${MAILBOX}/inbox/id18-weight-merge/seq 2>/dev/null | tr -d '[:space:]')"
echo "remote_seq=$(git -C ${MAILBOX} show refs/remotes/origin/hpc-mailbox:inbox/id18-weight-merge/seq 2>/dev/null | tr -d '[:space:]')"
echo "result6_in_local_tree=$(test -f ${MAILBOX}/outbox/id18-weight-merge/result_6.txt && echo yes || echo no)"
ls -l "${STAGED_RESULT}" 2>/dev/null || echo "STAGED_RESULT_ABSENT"
ls -l "${PERSISTENT_ARCHIVE}" 2>/dev/null || echo "PERSISTENT_ARCHIVE_ABSENT"
echo "=== RELATED PROCESSES ==="
ps -eo pid,ppid,etimes,stat,cmd | grep -E 'hpc_runner_active|cmd_6[.]sh|git (fetch|push)' | grep -v grep || true
echo "=== RUNNER LOG ID18 TAIL ==="
grep -E 'id18-weight-merge|runner v2 started' ${MAILBOX}/runner2.log 2>/dev/null | tail -40 || true
echo "=== DIAGNOSTIC COMPLETE ==="
exit 0
