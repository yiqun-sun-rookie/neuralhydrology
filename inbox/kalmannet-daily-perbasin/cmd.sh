#!/usr/bin/env bash
# sequence=249
set -euo pipefail
readonly OUTPUT_ROOT='/data1/home/sunyiq/kalmannet_daily_camels_slz_survey_development_20260928_v1'
guard() {
  local low=${1,,}
  case "$low" in *formal-evaluation*|*formal_evaluation*|*phase_a_results*|*unseal_*) echo 'REFUSING_RESTRICTED_PATH' >&2; exit 41;; esac
}
pin() {
  guard "$1"
  local resolved
  resolved=$(readlink -f -- "$1")
  guard "$resolved"
  [[ "$resolved" == "$1" ]] || { echo 'REFUSING_UNREGISTERED_FINAL_TARGET' >&2; exit 42; }
}
check() {
  local file=$1 size=$2 expected=$3 actual
  pin "$file"
  [[ -f "$file" && $(stat -c '%s' -- "$file") == "$size" ]] || { echo 'REFUSING_SIZE_OR_TYPE' >&2; exit 43; }
  actual=$(sha256sum -- "$file")
  actual=${actual%% *}
  [[ "$actual" == "$expected" ]] || { echo 'REFUSING_SHA256' >&2; exit 44; }
}
pin "$OUTPUT_ROOT"
[[ -d "$OUTPUT_ROOT" ]]
check "$OUTPUT_ROOT/aggregate.json" 407042 'ffc8c51ed3c5fd5defeae4b7dcf9b36e06c4f04bbce6898d2483be0d76b09c92'
check "$OUTPUT_ROOT/completion.json" 375 '591dc01c42da5f6ba7a004f90ef826ac4f5218e1013ea1f6c7bacd2dadbefe0c'
printf '%s\n' 'SLZ_REPAIR_BEGIN 2118a2430dcd51044d3c11c3108c35a6556cf9ee3c997c8ed1c0dc7a2c9fed89 249 5'
printf '%s\n' 'OUTPUT_ROOT_RESOLVED=/data1/home/sunyiq/kalmannet_daily_camels_slz_survey_development_20260928_v1'
printf '%s\n' 'AGGREGATE_SHA256=ffc8c51ed3c5fd5defeae4b7dcf9b36e06c4f04bbce6898d2483be0d76b09c92'
printf '%s\n' 'COMPLETION_SHA256=591dc01c42da5f6ba7a004f90ef826ac4f5218e1013ea1f6c7bacd2dadbefe0c'
check "$OUTPUT_ROOT/basins/12447390/starts/2004-10-01.npz" 170863 '584d65bcba205115d976cbc8855c91f3322e63892ca45d21058ab1c788c2ee35'
printf '%s\n' 'CHUNK_BEGIN basins/12447390/starts/2004-10-01.npz 168731 2132 170863 584d65bcba205115d976cbc8855c91f3322e63892ca45d21058ab1c788c2ee35'
dd if="$OUTPUT_ROOT/basins/12447390/starts/2004-10-01.npz" bs=65536 iflag=skip_bytes,count_bytes skip=168731 count=2132 status=none | base64 --wrap=0
printf '\n'
printf '%s\n' 'CHUNK_END basins/12447390/starts/2004-10-01.npz 168731 2132 170863 584d65bcba205115d976cbc8855c91f3322e63892ca45d21058ab1c788c2ee35'
check "$OUTPUT_ROOT/basins/12447390/starts/2004-10-01.npz" 170863 '584d65bcba205115d976cbc8855c91f3322e63892ca45d21058ab1c788c2ee35'
check "$OUTPUT_ROOT/basins/12447390/starts/2005-10-01.npz" 116513 '58dac443b2be731cfdaa248c86002dae20217ffc91bf1251494a52e9584e84ee'
printf '%s\n' 'CHUNK_BEGIN basins/12447390/starts/2005-10-01.npz 0 116513 116513 58dac443b2be731cfdaa248c86002dae20217ffc91bf1251494a52e9584e84ee'
dd if="$OUTPUT_ROOT/basins/12447390/starts/2005-10-01.npz" bs=65536 iflag=skip_bytes,count_bytes skip=0 count=116513 status=none | base64 --wrap=0
printf '\n'
printf '%s\n' 'CHUNK_END basins/12447390/starts/2005-10-01.npz 0 116513 116513 58dac443b2be731cfdaa248c86002dae20217ffc91bf1251494a52e9584e84ee'
check "$OUTPUT_ROOT/basins/12447390/starts/2005-10-01.npz" 116513 '58dac443b2be731cfdaa248c86002dae20217ffc91bf1251494a52e9584e84ee'
check "$OUTPUT_ROOT/basins/12447390/starts/2006-10-01.npz" 62090 '283b45f8349fa71259679d8bf488d6f0f9e386e0e64a5da54cf0dc52e528159f'
printf '%s\n' 'CHUNK_BEGIN basins/12447390/starts/2006-10-01.npz 0 62090 62090 283b45f8349fa71259679d8bf488d6f0f9e386e0e64a5da54cf0dc52e528159f'
dd if="$OUTPUT_ROOT/basins/12447390/starts/2006-10-01.npz" bs=65536 iflag=skip_bytes,count_bytes skip=0 count=62090 status=none | base64 --wrap=0
printf '\n'
printf '%s\n' 'CHUNK_END basins/12447390/starts/2006-10-01.npz 0 62090 62090 283b45f8349fa71259679d8bf488d6f0f9e386e0e64a5da54cf0dc52e528159f'
check "$OUTPUT_ROOT/basins/12447390/starts/2006-10-01.npz" 62090 '283b45f8349fa71259679d8bf488d6f0f9e386e0e64a5da54cf0dc52e528159f'
check "$OUTPUT_ROOT/part_a/records.json" 798515 '5c89a5d91b89226d03345987a80e18f1bb0b15ff25656930e4acc3b5a5aedb0c'
printf '%s\n' 'CHUNK_BEGIN part_a/records.json 0 469265 798515 5c89a5d91b89226d03345987a80e18f1bb0b15ff25656930e4acc3b5a5aedb0c'
dd if="$OUTPUT_ROOT/part_a/records.json" bs=65536 iflag=skip_bytes,count_bytes skip=0 count=469265 status=none | base64 --wrap=0
printf '\n'
printf '%s\n' 'CHUNK_END part_a/records.json 0 469265 798515 5c89a5d91b89226d03345987a80e18f1bb0b15ff25656930e4acc3b5a5aedb0c'
check "$OUTPUT_ROOT/part_a/records.json" 798515 '5c89a5d91b89226d03345987a80e18f1bb0b15ff25656930e4acc3b5a5aedb0c'
check "$OUTPUT_ROOT/aggregate.json" 407042 'ffc8c51ed3c5fd5defeae4b7dcf9b36e06c4f04bbce6898d2483be0d76b09c92'
check "$OUTPUT_ROOT/completion.json" 375 '591dc01c42da5f6ba7a004f90ef826ac4f5218e1013ea1f6c7bacd2dadbefe0c'
printf '%s\n' 'TRANSFER_COMPLETE 2118a2430dcd51044d3c11c3108c35a6556cf9ee3c997c8ed1c0dc7a2c9fed89 249 5'
