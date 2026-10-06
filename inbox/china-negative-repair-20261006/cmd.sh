#!/bin/bash
set +e
timeout --signal=KILL 20 bash 2>&1 <<'ORIGINAL_INPUT_METADATA_ONLY' | LC_ALL=C awk '
BEGIN {bytes=0; limited=0}
{
    if (bytes+length($0)+1 > 7168) {
        print "TOTAL_OUTPUT_TRUNCATED=1"; limited=1; exit 45
    }
    print; bytes+=length($0)+1
}
END {
    if (!limited) print "TOTAL_OUTPUT_TRUNCATED=0"
    printf "TOTAL_BODY_OUTPUT_BYTES=%d\n", bytes
}'
set -eo pipefail
test "$(id -un)" = sunyiq
parent=/data1/home/sunyiq
candidate=/data1/home/sunyiq/forcing_swap_daily_2026_09/data_shadow/camels_us
test "$(readlink -e "$parent")" = "$parent"
printf 'ORIGINAL_INPUT_METADATA_UTC='
date -u '+%Y-%m-%dT%H:%M:%SZ'
printf 'CANDIDATE_LITERAL=%s\n' "$candidate"
if ! test -e "$candidate" && ! test -L "$candidate"; then
    printf 'CANDIDATE_ABSENT_NO_CONTENT_READ\n'
    exit 3
fi
if test -L "$candidate" || ! test -d "$candidate"; then
    printf 'CANDIDATE_NOT_ORDINARY_DIRECTORY_STOP\n'
    exit 4
fi
resolved=$(readlink -e "$candidate")
printf 'CANDIDATE_RESOLVED=%s\n' "$resolved"
test -n "$resolved"
test "$resolved" = "$candidate"
case "$resolved" in "$parent"/*) ;; *) exit 5 ;; esac
printf 'METADATA_LIST_BEGIN\n'
set +e
LC_ALL=C timeout 10 find -P "$candidate" -maxdepth 2 -printf '%y|%s|%P\n' | LC_ALL=C awk '
BEGIN {count=0; bytes=0; limited=0}
{
    if (count >= 40 || bytes+length($0)+1 > 6144) {
        print "METADATA_TRUNCATED=1"; limited=1; exit 42
    }
    print; count++; bytes+=length($0)+1
}
END {
    if (!limited) print "METADATA_TRUNCATED=0"
    printf "METADATA_EMITTED_ENTRIES=%d\nMETADATA_EMITTED_BYTES=%d\n", count, bytes
}'
statuses=("${PIPESTATUS[@]}")
set -e
printf 'METADATA_LIST_END\nFIND_EXIT=%s\nLIMITER_EXIT=%s\n' "${statuses[0]}" "${statuses[1]}"
if test "${statuses[1]}" != 0 && test "${statuses[1]}" != 42; then exit 6; fi
if test "${statuses[0]}" != 0 && ! { test "${statuses[0]}" = 141 && test "${statuses[1]}" = 42; }; then
    printf 'METADATA_SCAN_FAILED_NO_RETRY\n'
    exit 6
fi
if test "${statuses[1]}" = 42; then exit 42; fi
ORIGINAL_INPUT_METADATA_ONLY
outer_statuses=("${PIPESTATUS[@]}")
printf 'QUERY_EXIT=%s\nTOTAL_LIMITER_EXIT=%s\n' "${outer_statuses[0]}" "${outer_statuses[1]}"
if test "${outer_statuses[1]}" != 0; then
    printf 'ORIGINAL_INPUT_METADATA_TOTAL_OUTPUT_STOP\n'
    exit 45
fi
if test "${outer_statuses[0]}" = 42; then
    printf 'ORIGINAL_INPUT_METADATA_PARTIAL_ONLY\n'
    exit 42
fi
if test "${outer_statuses[0]}" != 0; then
    printf 'ORIGINAL_INPUT_METADATA_QUERY_STOP\n'
    exit "${outer_statuses[0]}"
fi
printf 'ORIGINAL_INPUT_METADATA_COMPLETE\n'
exit 0
