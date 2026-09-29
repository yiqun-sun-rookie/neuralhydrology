#!/usr/bin/env bash
set -eo pipefail
target=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1/three_method_analysis_002/job_231134
if [ "$#" -ne 1 ]; then echo REQUIRE_EXACT_SAVED_ARRAY_NAME; exit 64; fi
case "$1" in
  800) name=paired_800.npz; expected=1ebe862bed927aee7fc69045637e6eb59c72633846735c3e40edaefb4076561b ;;
  400) name=paired_400.npz; expected=82725f6be89041c1eca971a08038d057e98ed9dba902fc07e701c53bf7575fdb ;;
  1600) name=paired_1600.npz; expected=f1ef746a04ef5ae24c3734cdf88e1e9f4d28a3e88f225e7542721ba284b3f577 ;;
  domain) name=domain_sy2_differences.npz; expected=7d61c54ff9befbc3a25cc0a1f573da7760427a8d5120b515ad2e918093710438 ;;
  *) echo UNREGISTERED_ARRAY; exit 64 ;;
esac
state=$(sacct -n -X -P -j 231134 -o JobID,State,ExitCode | awk -F'|' '$1==231134 {print $2 "|" $3}')
test "$state" = 'COMPLETED|0:0'
test -f "$target/analysis.json"
test ! -e "$target/failure.json"
file="$target/$name"
test -f "$file"
test ! -L "$file"
bytes=$(stat -c %s "$file")
test "$bytes" -le 30000000
printf '%s  %s\n' "$expected" "$file" | sha256sum --strict --check -
printf '\nBEGIN_SAVED_SAMPLING_FILE=%s\n' "$name"
printf '%s  %s\n' "$expected" "$file"
base64 "$file"
printf 'END_SAVED_SAMPLING_FILE=%s\n' "$name"
printf '%s  %s\n' "$expected" "$file" | sha256sum --strict --check -
