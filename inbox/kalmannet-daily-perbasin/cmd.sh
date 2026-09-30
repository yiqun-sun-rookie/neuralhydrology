#!/usr/bin/env bash
# sequence=253
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
printf '%s\n' 'SLZ_REPAIR_BEGIN 2118a2430dcd51044d3c11c3108c35a6556cf9ee3c997c8ed1c0dc7a2c9fed89 253 9'
printf '%s\n' 'OUTPUT_ROOT_RESOLVED=/data1/home/sunyiq/kalmannet_daily_camels_slz_survey_development_20260928_v1'
printf '%s\n' 'AGGREGATE_SHA256=ffc8c51ed3c5fd5defeae4b7dcf9b36e06c4f04bbce6898d2483be0d76b09c92'
printf '%s\n' 'COMPLETION_SHA256=591dc01c42da5f6ba7a004f90ef826ac4f5218e1013ea1f6c7bacd2dadbefe0c'
check "$OUTPUT_ROOT/part_a/source_seed_20260922_epoch_history.json" 521838 'f5712b39de1dc325d5054e5447a24c57d20d82f9c5f07bb22fca11b096dfd1c6'
printf '%s\n' 'CHUNK_BEGIN part_a/source_seed_20260922_epoch_history.json 448361 73477 521838 f5712b39de1dc325d5054e5447a24c57d20d82f9c5f07bb22fca11b096dfd1c6'
dd if="$OUTPUT_ROOT/part_a/source_seed_20260922_epoch_history.json" bs=65536 iflag=skip_bytes,count_bytes skip=448361 count=73477 status=none | base64 --wrap=0
printf '\n'
printf '%s\n' 'CHUNK_END part_a/source_seed_20260922_epoch_history.json 448361 73477 521838 f5712b39de1dc325d5054e5447a24c57d20d82f9c5f07bb22fca11b096dfd1c6'
check "$OUTPUT_ROOT/part_a/source_seed_20260922_epoch_history.json" 521838 'f5712b39de1dc325d5054e5447a24c57d20d82f9c5f07bb22fca11b096dfd1c6'
check "$OUTPUT_ROOT/aggregate.json" 407042 'ffc8c51ed3c5fd5defeae4b7dcf9b36e06c4f04bbce6898d2483be0d76b09c92'
check "$OUTPUT_ROOT/completion.json" 375 '591dc01c42da5f6ba7a004f90ef826ac4f5218e1013ea1f6c7bacd2dadbefe0c'
printf '%s\n' 'TRANSFER_COMPLETE 2118a2430dcd51044d3c11c3108c35a6556cf9ee3c997c8ed1c0dc7a2c9fed89 253 9'
