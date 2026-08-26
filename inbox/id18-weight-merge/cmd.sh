#!/bin/bash
set -o pipefail

JOB_ID=213416
LANDING=/data1/home/sunyiq/id18_ties_merge_20260826
SOURCE=${LANDING}/tm01_compact_results.tar.gz
DEST=/data1/home/sunyiq/hpc_mailbox/outbox/id18-weight-merge/tm01_compact_results_${JOB_ID}.tar.gz

echo "=== TM01 COMPACT RETRIEVAL PREFLIGHT ==="
date -Is
sacct -j "${JOB_ID}" -X --format=JobID%12,JobName%22,Partition%10,NodeList%10,State%14,ExitCode%8,Elapsed%10,Start%20,End%20 2>&1 || exit 1
[ -f "${SOURCE}" ] || { echo "COMPACT_SOURCE_MISSING"; exit 2; }
SOURCE_SHA=$(sha256sum "${SOURCE}" | awk '{print $1}')
SOURCE_SIZE=$(stat -c '%s' "${SOURCE}")
echo "source_sha256=${SOURCE_SHA} source_size=${SOURCE_SIZE}"

echo "=== ARCHIVE MEMBER AUDIT ==="
MEMBERS=$(tar -tzf "${SOURCE}") || exit 3
printf '%s\n' "${MEMBERS}"
if printf '%s\n' "${MEMBERS}" | grep -Eq '(^|/)\.\.(/|$)|^/'; then
    echo "UNSAFE_ARCHIVE_MEMBER"
    exit 4
fi
if printf '%s\n' "${MEMBERS}" | grep -Ev '^(analysis|protocol)(/|$)' | grep -q .; then
    echo "NONCOMPACT_ARCHIVE_MEMBER"
    exit 5
fi
if printf '%s\n' "${MEMBERS}" | grep -Eq 'test_results\.p|test_all_output\.p|model_epoch[0-9]+\.pt'; then
    echo "FORBIDDEN_RAW_OR_CHECKPOINT_MEMBER"
    exit 6
fi

mkdir -p "$(dirname "${DEST}")" || exit 7
if [ -e "${DEST}" ]; then
    DEST_SHA=$(sha256sum "${DEST}" | awk '{print $1}')
    [ "${DEST_SHA}" = "${SOURCE_SHA}" ] || { echo "DESTINATION_EXISTS_WITH_DIFFERENT_HASH"; exit 8; }
    echo "DESTINATION_ALREADY_MATCHES"
else
    cp "${SOURCE}" "${DEST}" || exit 9
fi
DEST_SHA=$(sha256sum "${DEST}" | awk '{print $1}')
[ "${DEST_SHA}" = "${SOURCE_SHA}" ] || { echo "COPIED_HASH_MISMATCH"; exit 10; }
echo "TM01_COMPACT_READY path=${DEST} sha256=${DEST_SHA} size=${SOURCE_SIZE}"
exit 0
