#!/bin/bash
set -o pipefail

SOURCE=/data1/home/sunyiq/hpc_mailbox/outbox/id18-weight-merge/OE01_OUTPUT_ENSEMBLE_JOB212908_RESULTS.tar.gz
EXPECTED_SHA256=7eee884b074a88084aa392c7e3320bd340c454ae763264c6f3dffb3cb6fa8349
PART_DIR=/data1/home/sunyiq/hpc_mailbox/outbox/id18-weight-merge/oe01-job212908-result-7eee884b-parts

echo "=== RESULT ARCHIVE TRANSPORT ==="
date -Is
hostname
[ -f "${SOURCE}" ] || { echo "SOURCE_ARCHIVE_MISSING=${SOURCE}"; exit 1; }
ACTUAL_SHA256=$(sha256sum "${SOURCE}" | awk '{print $1}')
ARCHIVE_BYTES=$(wc -c < "${SOURCE}" | tr -d '[:space:]')
echo "source=${SOURCE}"
echo "archive_bytes=${ARCHIVE_BYTES}"
echo "expected_sha256=${EXPECTED_SHA256}"
echo "actual_sha256=${ACTUAL_SHA256}"
[ "${ACTUAL_SHA256}" = "${EXPECTED_SHA256}" ] || { echo "SOURCE_HASH_MISMATCH"; exit 1; }

[ ! -e "${PART_DIR}" ] || { echo "PART_DIRECTORY_ALREADY_EXISTS=${PART_DIR}"; exit 2; }
mkdir -p "${PART_DIR}" || exit 1
split -b 20m -d -a 3 "${SOURCE}" "${PART_DIR}/part_" || exit 1
printf '%s  %s\n' "${EXPECTED_SHA256}" "OE01_OUTPUT_ENSEMBLE_JOB212908_RESULTS.tar.gz" \
    > "${PART_DIR}/archive.sha256"
printf '%s\n' "${ARCHIVE_BYTES}" > "${PART_DIR}/archive.bytes"
(cd "${PART_DIR}" && sha256sum part_* > parts.sha256) || exit 1

echo "=== TRANSPORT PARTS ==="
find "${PART_DIR}" -maxdepth 1 -type f -printf '%f %s bytes\n' | sort
echo "=== PART HASHES ==="
cat "${PART_DIR}/parts.sha256"
echo "=== TRANSPORT READY ==="
exit 0
