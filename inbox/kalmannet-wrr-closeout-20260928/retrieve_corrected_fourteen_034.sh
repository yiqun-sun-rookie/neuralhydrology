#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
plain="$parent/plain_preflight_v1"
archive="$parent/corrected_fourteen_metadata_001.tar.gz"
if [ -e "$archive" ] || [ -L "$archive" ]; then echo REFUSE_EXISTING_ARCHIVE; exit 64; fi
jobs=$(cat "$parent/corrected_launch_001/all_jobids.txt")
if ! [[ "$jobs" =~ ^[0-9]+(,[0-9]+){13}$ ]]; then echo INVALID_JOB_INDEX; exit 64; fi
status=$(sacct -n -X -P -j "$jobs" -o JobID,State,ExitCode)
printf '%s\n' "$status"
count=$(printf '%s\n' "$status" | awk -F'|' '$1 ~ /^[0-9]+$/ && $2 == "COMPLETED" && $3 == "0:0" {n++} END {print n+0}')
if [ "$count" -ne 14 ]; then echo REQUIRE_FOURTEEN_COMPLETED; exit 65; fi
directories=()
for model in main_seed43 main_seed44 compact_seed42 compact_seed43 compact_seed44 learned_noise hand_tuned; do
 for variant in corrected_outlet_original_states corrected_outlet_corrected_states; do
  relative="numerical_impact/runs/${model}__${variant}__formal_attempt01"
  test -s "$plain/$relative/completion.json"
  test ! -e "$plain/$relative/failure.json"
  test ! -L "$plain/$relative"
  directories+=("$relative")
 done
done
cd "$plain"
find "${directories[@]}" -type f -name '*.json' -print0 | sort -z | tar --null -czf "$archive" -T -
printf 'PLAIN_RECEIPTS_SHA256='
sha256sum "$archive" | cut -d' ' -f1
echo BEGIN_PLAIN_RECEIPTS_TAR_GZ
base64 "$archive"
echo END_PLAIN_RECEIPTS_TAR_GZ
echo FOURTEEN_METADATA_ONLY_NO_ARRAY_DESERIALIZATION_NO_RESULT_ACCEPTANCE
