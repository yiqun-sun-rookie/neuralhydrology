#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
adaptive="$parent/adaptive_preflight_v1"
job=$(cat "$parent/adaptive_prepare_jobid.txt")
if ! [[ "$job" =~ ^[0-9]+$ ]]; then exit 64; fi
sacct -n -X -P -j "$job" -o JobID,JobName,State,ExitCode,Elapsed,NodeList
squeue -h -j "$job" -o '%i|%j|%T|%Z|%R'
state=$(sacct -n -X -P -j "$job" -o State | head -n 1 | cut -d'|' -f1)
for log in "$parent/logs/adaptive-prepare-$job.out" "$parent/logs/adaptive-prepare-$job.err"; do
  if [ -f "$log" ]; then echo "LOG=$log"; tail -n 8 "$log"; fi
done
if [ "$state" != COMPLETED ]; then echo "NO_RECEIPT_ARCHIVE_STATE=$state"; exit 0; fi
cd "$adaptive"
for case_id in matched_fixed_test matched_selected_test; do
  test -s "adaptive_comparison/runs/${case_id}__preflight_attempt01/completion.json"
done
test -s adaptive_comparison/selection_attempt01/selection_frozen.json
archive="$parent/adaptive_test_preflight_receipts_001.tar.gz"
if [ -e "$archive" ] || [ -L "$archive" ]; then echo REFUSE_EXISTING_ARCHIVE; exit 64; fi
find adaptive_comparison/runs/matched_fixed_test__preflight_attempt01 adaptive_comparison/runs/matched_selected_test__preflight_attempt01 adaptive_comparison/selection_attempt01 -type f \( -name '*.json' -o -name 'physical_plain_*.py' \) -print0 | sort -z | tar --null --transform='s|^adaptive_comparison/selection_attempt01/|adaptive_comparison/runs/selection_attempt01/|' -czf "$archive" -T -
echo TRANSPORT_PATH_ALIAS_ONLY_SELECTION_BYTES_UNCHANGED
printf 'ADAPTIVE_RECEIPTS_SHA256='
sha256sum "$archive" | cut -d' ' -f1
echo BEGIN_ADAPTIVE_RECEIPTS_TAR_GZ
base64 "$archive"
echo END_ADAPTIVE_RECEIPTS_TAR_GZ
