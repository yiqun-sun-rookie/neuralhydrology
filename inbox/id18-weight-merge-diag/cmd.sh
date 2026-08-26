#!/bin/bash
set -o pipefail

STAGED_RESULT=/data1/home/sunyiq/.hpc_mailbox_staging/id18-weight-merge/result_6.txt
PERSISTENT_ARCHIVE=/data1/home/sunyiq/id18_output_ensemble_20260826/transport/base64_retrieval_v1/OE01_OUTPUT_ENSEMBLE_JOB212908_RESULTS.tar.gz

echo "=== ID18 SEQ6 READ-ONLY DIAGNOSTIC ==="
date -Is
hostname
ls -l "${STAGED_RESULT}" 2>/dev/null || echo "STAGED_RESULT_ABSENT"
ls -l "${PERSISTENT_ARCHIVE}" 2>/dev/null || echo "PERSISTENT_ARCHIVE_ABSENT"
echo "=== STAGED RESULT TAIL ==="
tail -n 12 "${STAGED_RESULT}" 2>/dev/null || true
echo "=== RELATED PROCESSES ==="
pgrep -af 'cmd_6.sh|git.*push|hpc_runner_active' || true
echo "=== MAILBOX EXACT STATUS ==="
git -C /data1/home/sunyiq/hpc_mailbox status --short -- \
    inbox/id18-weight-merge outbox/id18-weight-merge 2>/dev/null || true
echo "=== DIAGNOSTIC COMPLETE ==="
exit 0
