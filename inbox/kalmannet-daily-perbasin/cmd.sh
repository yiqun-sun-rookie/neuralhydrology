#!/usr/bin/env bash
# sequence=246
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
printf '%s\n' 'SLZ_REPAIR_BEGIN 2118a2430dcd51044d3c11c3108c35a6556cf9ee3c997c8ed1c0dc7a2c9fed89 246 2'
printf '%s\n' 'OUTPUT_ROOT_RESOLVED=/data1/home/sunyiq/kalmannet_daily_camels_slz_survey_development_20260928_v1'
printf '%s\n' 'AGGREGATE_SHA256=ffc8c51ed3c5fd5defeae4b7dcf9b36e06c4f04bbce6898d2483be0d76b09c92'
printf '%s\n' 'COMPLETION_SHA256=591dc01c42da5f6ba7a004f90ef826ac4f5218e1013ea1f6c7bacd2dadbefe0c'
check "$OUTPUT_ROOT/basins/02092500/starts/2003-10-01.npz" 228731 '3206fb162e5b1aedb71227eb3f11f5c9678d7309a3fd450a4a02c811bbff69d3'
printf '%s\n' 'CHUNK_BEGIN basins/02092500/starts/2003-10-01.npz 25900 202831 228731 3206fb162e5b1aedb71227eb3f11f5c9678d7309a3fd450a4a02c811bbff69d3'
dd if="$OUTPUT_ROOT/basins/02092500/starts/2003-10-01.npz" bs=65536 iflag=skip_bytes,count_bytes skip=25900 count=202831 status=none | base64 --wrap=0
printf '\n'
printf '%s\n' 'CHUNK_END basins/02092500/starts/2003-10-01.npz 25900 202831 228731 3206fb162e5b1aedb71227eb3f11f5c9678d7309a3fd450a4a02c811bbff69d3'
check "$OUTPUT_ROOT/basins/02092500/starts/2003-10-01.npz" 228731 '3206fb162e5b1aedb71227eb3f11f5c9678d7309a3fd450a4a02c811bbff69d3'
check "$OUTPUT_ROOT/basins/02092500/starts/2004-10-01.npz" 173791 'dd27fbce0d5845f16771bf7b310909fd8bd96843b14d00a498cb911dce3bb7c9'
printf '%s\n' 'CHUNK_BEGIN basins/02092500/starts/2004-10-01.npz 0 173791 173791 dd27fbce0d5845f16771bf7b310909fd8bd96843b14d00a498cb911dce3bb7c9'
dd if="$OUTPUT_ROOT/basins/02092500/starts/2004-10-01.npz" bs=65536 iflag=skip_bytes,count_bytes skip=0 count=173791 status=none | base64 --wrap=0
printf '\n'
printf '%s\n' 'CHUNK_END basins/02092500/starts/2004-10-01.npz 0 173791 173791 dd27fbce0d5845f16771bf7b310909fd8bd96843b14d00a498cb911dce3bb7c9'
check "$OUTPUT_ROOT/basins/02092500/starts/2004-10-01.npz" 173791 'dd27fbce0d5845f16771bf7b310909fd8bd96843b14d00a498cb911dce3bb7c9'
check "$OUTPUT_ROOT/basins/02092500/starts/2005-10-01.npz" 118188 '4a2f0752a752db431ff6b6a1d46898ec0a94cdd2b5d622b26a991798626cbf1e'
printf '%s\n' 'CHUNK_BEGIN basins/02092500/starts/2005-10-01.npz 0 118188 118188 4a2f0752a752db431ff6b6a1d46898ec0a94cdd2b5d622b26a991798626cbf1e'
dd if="$OUTPUT_ROOT/basins/02092500/starts/2005-10-01.npz" bs=65536 iflag=skip_bytes,count_bytes skip=0 count=118188 status=none | base64 --wrap=0
printf '\n'
printf '%s\n' 'CHUNK_END basins/02092500/starts/2005-10-01.npz 0 118188 118188 4a2f0752a752db431ff6b6a1d46898ec0a94cdd2b5d622b26a991798626cbf1e'
check "$OUTPUT_ROOT/basins/02092500/starts/2005-10-01.npz" 118188 '4a2f0752a752db431ff6b6a1d46898ec0a94cdd2b5d622b26a991798626cbf1e'
check "$OUTPUT_ROOT/basins/02092500/starts/2006-10-01.npz" 62239 'df55909ecc5c8c3d2505e7063899cdcee4632f39e70f535427cd263ad28a45ae'
printf '%s\n' 'CHUNK_BEGIN basins/02092500/starts/2006-10-01.npz 0 62239 62239 df55909ecc5c8c3d2505e7063899cdcee4632f39e70f535427cd263ad28a45ae'
dd if="$OUTPUT_ROOT/basins/02092500/starts/2006-10-01.npz" bs=65536 iflag=skip_bytes,count_bytes skip=0 count=62239 status=none | base64 --wrap=0
printf '\n'
printf '%s\n' 'CHUNK_END basins/02092500/starts/2006-10-01.npz 0 62239 62239 df55909ecc5c8c3d2505e7063899cdcee4632f39e70f535427cd263ad28a45ae'
check "$OUTPUT_ROOT/basins/02092500/starts/2006-10-01.npz" 62239 'df55909ecc5c8c3d2505e7063899cdcee4632f39e70f535427cd263ad28a45ae'
check "$OUTPUT_ROOT/basins/12447390/starts/2000-10-01.npz" 387342 '6c8f4b8e1a34501106f5be989dbe3dab28d2385d68d81681eed5638918af0295'
printf '%s\n' 'CHUNK_BEGIN basins/12447390/starts/2000-10-01.npz 0 92951 387342 6c8f4b8e1a34501106f5be989dbe3dab28d2385d68d81681eed5638918af0295'
dd if="$OUTPUT_ROOT/basins/12447390/starts/2000-10-01.npz" bs=65536 iflag=skip_bytes,count_bytes skip=0 count=92951 status=none | base64 --wrap=0
printf '\n'
printf '%s\n' 'CHUNK_END basins/12447390/starts/2000-10-01.npz 0 92951 387342 6c8f4b8e1a34501106f5be989dbe3dab28d2385d68d81681eed5638918af0295'
check "$OUTPUT_ROOT/basins/12447390/starts/2000-10-01.npz" 387342 '6c8f4b8e1a34501106f5be989dbe3dab28d2385d68d81681eed5638918af0295'
check "$OUTPUT_ROOT/aggregate.json" 407042 'ffc8c51ed3c5fd5defeae4b7dcf9b36e06c4f04bbce6898d2483be0d76b09c92'
check "$OUTPUT_ROOT/completion.json" 375 '591dc01c42da5f6ba7a004f90ef826ac4f5218e1013ea1f6c7bacd2dadbefe0c'
printf '%s\n' 'TRANSFER_COMPLETE 2118a2430dcd51044d3c11c3108c35a6556cf9ee3c997c8ed1c0dc7a2c9fed89 246 2'
