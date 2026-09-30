#!/usr/bin/env bash
# sequence=247
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
printf '%s\n' 'SLZ_REPAIR_BEGIN 2118a2430dcd51044d3c11c3108c35a6556cf9ee3c997c8ed1c0dc7a2c9fed89 247 3'
printf '%s\n' 'OUTPUT_ROOT_RESOLVED=/data1/home/sunyiq/kalmannet_daily_camels_slz_survey_development_20260928_v1'
printf '%s\n' 'AGGREGATE_SHA256=ffc8c51ed3c5fd5defeae4b7dcf9b36e06c4f04bbce6898d2483be0d76b09c92'
printf '%s\n' 'COMPLETION_SHA256=591dc01c42da5f6ba7a004f90ef826ac4f5218e1013ea1f6c7bacd2dadbefe0c'
check "$OUTPUT_ROOT/basins/12447390/starts/2000-10-01.npz" 387342 '6c8f4b8e1a34501106f5be989dbe3dab28d2385d68d81681eed5638918af0295'
printf '%s\n' 'CHUNK_BEGIN basins/12447390/starts/2000-10-01.npz 92951 294391 387342 6c8f4b8e1a34501106f5be989dbe3dab28d2385d68d81681eed5638918af0295'
dd if="$OUTPUT_ROOT/basins/12447390/starts/2000-10-01.npz" bs=65536 iflag=skip_bytes,count_bytes skip=92951 count=294391 status=none | base64 --wrap=0
printf '\n'
printf '%s\n' 'CHUNK_END basins/12447390/starts/2000-10-01.npz 92951 294391 387342 6c8f4b8e1a34501106f5be989dbe3dab28d2385d68d81681eed5638918af0295'
check "$OUTPUT_ROOT/basins/12447390/starts/2000-10-01.npz" 387342 '6c8f4b8e1a34501106f5be989dbe3dab28d2385d68d81681eed5638918af0295'
check "$OUTPUT_ROOT/basins/12447390/starts/2001-10-01.npz" 333480 '959bd5da974cd966f8efbe89ea86366dbcfe2a5af84c3e69a74c57e82bc9d7c6'
printf '%s\n' 'CHUNK_BEGIN basins/12447390/starts/2001-10-01.npz 0 333480 333480 959bd5da974cd966f8efbe89ea86366dbcfe2a5af84c3e69a74c57e82bc9d7c6'
dd if="$OUTPUT_ROOT/basins/12447390/starts/2001-10-01.npz" bs=65536 iflag=skip_bytes,count_bytes skip=0 count=333480 status=none | base64 --wrap=0
printf '\n'
printf '%s\n' 'CHUNK_END basins/12447390/starts/2001-10-01.npz 0 333480 333480 959bd5da974cd966f8efbe89ea86366dbcfe2a5af84c3e69a74c57e82bc9d7c6'
check "$OUTPUT_ROOT/basins/12447390/starts/2001-10-01.npz" 333480 '959bd5da974cd966f8efbe89ea86366dbcfe2a5af84c3e69a74c57e82bc9d7c6'
check "$OUTPUT_ROOT/basins/12447390/starts/2002-10-01.npz" 278768 '84ba793e4f2b4bc0b39b29f54e23f540debd5f4f2b5e4b2a504ce070f4cb81ca'
printf '%s\n' 'CHUNK_BEGIN basins/12447390/starts/2002-10-01.npz 0 22129 278768 84ba793e4f2b4bc0b39b29f54e23f540debd5f4f2b5e4b2a504ce070f4cb81ca'
dd if="$OUTPUT_ROOT/basins/12447390/starts/2002-10-01.npz" bs=65536 iflag=skip_bytes,count_bytes skip=0 count=22129 status=none | base64 --wrap=0
printf '\n'
printf '%s\n' 'CHUNK_END basins/12447390/starts/2002-10-01.npz 0 22129 278768 84ba793e4f2b4bc0b39b29f54e23f540debd5f4f2b5e4b2a504ce070f4cb81ca'
check "$OUTPUT_ROOT/basins/12447390/starts/2002-10-01.npz" 278768 '84ba793e4f2b4bc0b39b29f54e23f540debd5f4f2b5e4b2a504ce070f4cb81ca'
check "$OUTPUT_ROOT/aggregate.json" 407042 'ffc8c51ed3c5fd5defeae4b7dcf9b36e06c4f04bbce6898d2483be0d76b09c92'
check "$OUTPUT_ROOT/completion.json" 375 '591dc01c42da5f6ba7a004f90ef826ac4f5218e1013ea1f6c7bacd2dadbefe0c'
printf '%s\n' 'TRANSFER_COMPLETE 2118a2430dcd51044d3c11c3108c35a6556cf9ee3c997c8ed1c0dc7a2c9fed89 247 3'
