#!/bin/bash
set +e
timeout --signal=KILL 30 bash 2>&1 <<'ORIGINAL_INPUT_IDENTITY_METADATA' | LC_ALL=C awk '
BEGIN {bytes=0; limited=0}
{
    if (bytes+length($0)+1 > 131072) {
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
candidate=$parent/forcing_swap_daily_2026_09/data_shadow/camels_us
weather=$candidate/basin_mean_forcing/era5l_caravan
attrroot=$parent/attr_swap_daily_2026_09/data_shadow/camels_us
sharedroot=$parent/neuralhydrology/data/camels_us
test "$(readlink -e "$parent")" = "$parent"
test ! -L "$candidate" && test -d "$candidate"
test "$(readlink -e "$candidate")" = "$candidate"
test ! -L "$weather" && test -d "$weather"
test "$(readlink -e "$weather")" = "$weather"
printf 'ORIGINAL_INPUT_IDENTITY_UTC='
date -u '+%Y-%m-%dT%H:%M:%SZ'
printf 'WEATHER_LITERAL=%s\nWEATHER_RESOLVED=%s\n' "$weather" "$(readlink -e "$weather")"
before=$(stat -c '%d|%i|%s|%Y|%Z|%h|%f' -- "$weather")
printf 'WEATHER_ROOT_BEFORE=%s\n' "$before"
for key in MAURER DISCHARGE ATTRIBUTES; do
    case "$key" in
        MAURER) link=$candidate/basin_mean_forcing/maurer ;;
        DISCHARGE) link=$candidate/usgs_streamflow ;;
        ATTRIBUTES) link=$candidate/camels_attributes_v2.0 ;;
    esac
    test -L "$link"
    text=$(readlink -- "$link")
    resolved=$(readlink -e -- "$link")
    printf 'LINK_%s_LITERAL=%s\nLINK_%s_TEXT=%s\nLINK_%s_RESOLVED=%s\n' \
        "$key" "$link" "$key" "$text" "$key" "$resolved"
    case "$resolved" in "$attrroot"/*|"$sharedroot"/*) ;; *)
        printf 'LINK_TARGET_OUTSIDE_REGISTERED_ROOTS_STOP\n'; exit 4 ;;
    esac
done
printf 'WEATHER_LIST_BEGIN\n'
set +e
LC_ALL=C timeout --signal=KILL 15 find -P "$weather" -mindepth 1 -maxdepth 2 \
    -printf '%y|%s|%n|%D|%i|%T@|%C@|%m|%P\n' | LC_ALL=C awk '
BEGIN {count=0; bytes=0; limited=0}
{
    if (count >= 600 || bytes+length($0)+1 > 98304) {
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
printf 'WEATHER_LIST_END\nFIND_EXIT=%s\nLIST_LIMITER_EXIT=%s\n' "${statuses[0]}" "${statuses[1]}"
if test "${statuses[1]}" != 0 && test "${statuses[1]}" != 42; then exit 6; fi
if test "${statuses[0]}" != 0 && ! { test "${statuses[0]}" = 141 && test "${statuses[1]}" = 42; }; then
    printf 'WEATHER_METADATA_SCAN_FAILED_NO_RETRY\n'; exit 6
fi
if test "${statuses[1]}" = 42; then exit 42; fi
after=$(stat -c '%d|%i|%s|%Y|%Z|%h|%f' -- "$weather")
printf 'WEATHER_ROOT_AFTER=%s\n' "$after"
test "$before" = "$after"
test "$(readlink -e "$weather")" = "$weather"
test "$(readlink -e "$candidate")" = "$candidate"
ORIGINAL_INPUT_IDENTITY_METADATA
outer_statuses=("${PIPESTATUS[@]}")
printf 'QUERY_EXIT=%s\nTOTAL_LIMITER_EXIT=%s\n' "${outer_statuses[0]}" "${outer_statuses[1]}"
if test "${outer_statuses[1]}" != 0; then
    printf 'ORIGINAL_INPUT_IDENTITY_TOTAL_OUTPUT_STOP\n'; exit 45
fi
if test "${outer_statuses[0]}" != 0; then
    printf 'ORIGINAL_INPUT_IDENTITY_QUERY_STOP\n'; exit "${outer_statuses[0]}"
fi
printf 'ORIGINAL_INPUT_IDENTITY_COMPLETE\n'
exit 0
