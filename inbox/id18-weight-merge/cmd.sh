#!/bin/bash
set -o pipefail

JOB_ID=213416
LANDING=/data1/home/sunyiq/id18_ties_merge_20260826
SOURCE=${LANDING}/tm01_compact_results.tar.gz
DEST=/data1/home/sunyiq/hpc_mailbox/outbox/id18-weight-merge/tm01_compact_results_${JOB_ID}.tar.gz.b64.txt
EXPECTED_SHA=1f47dcd098051cc4476dff0cbbc63e1a5cee4a3ddbe65fbb5390686a188b715b

echo "=== TM01 BASE64 RETRIEVAL ==="
date -Is
sacct -j "${JOB_ID}" -X --format=JobID%12,JobName%22,Partition%10,NodeList%10,State%14,ExitCode%8,Elapsed%10 2>&1 || exit 1
[ -f "${SOURCE}" ] || { echo "COMPACT_SOURCE_MISSING"; exit 2; }
SOURCE_SHA=$(sha256sum "${SOURCE}" | awk '{print $1}')
[ "${SOURCE_SHA}" = "${EXPECTED_SHA}" ] || { echo "SOURCE_HASH_DRIFT=${SOURCE_SHA}"; exit 3; }

if [ -e "${DEST}" ]; then
    DECODED_SHA=$(base64 -d "${DEST}" | sha256sum | awk '{print $1}')
    [ "${DECODED_SHA}" = "${EXPECTED_SHA}" ] || { echo "EXISTING_BASE64_HASH_MISMATCH"; exit 4; }
    echo "BASE64_DESTINATION_ALREADY_MATCHES"
else
    base64 -w 76 "${SOURCE}" > "${DEST}" || exit 5
fi
DECODED_SHA=$(base64 -d "${DEST}" | sha256sum | awk '{print $1}')
[ "${DECODED_SHA}" = "${EXPECTED_SHA}" ] || { echo "BASE64_ROUNDTRIP_HASH_MISMATCH=${DECODED_SHA}"; exit 6; }
echo "TM01_BASE64_READY path=${DEST} text_size=$(stat -c '%s' "${DEST}") decoded_sha256=${DECODED_SHA}"
exit 0
