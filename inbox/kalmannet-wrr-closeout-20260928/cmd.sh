#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
plain="$parent/plain_preflight_v1"
adaptive="$parent/adaptive_preflight_v1"
plain_archive="$parent/plain_original_eight_metadata_001.tar.gz"
adaptive_archive="$parent/adaptive_two_test_metadata_001.tar.gz"
for target in "$plain_archive" "$adaptive_archive"; do
  if [ -e "$target" ] || [ -L "$target" ]; then echo "REFUSE_EXISTING_ARCHIVE=$target"; exit 64; fi
done
plain_dirs=()
for model in main_seed43 main_seed44 compact_seed42 compact_seed43 compact_seed44 learned_noise hand_tuned adaptive; do
  relative="numerical_impact/runs/${model}__original_outlet_original_states__formal_attempt01"
  test -s "$plain/$relative/completion.json"
  test ! -e "$plain/$relative/failure.json"
  plain_dirs+=("$relative")
done
adaptive_dirs=()
for case_id in matched_fixed_test matched_selected_test; do
  relative="adaptive_comparison/runs/${case_id}__formal_attempt01"
  test -s "$adaptive/$relative/completion.json"
  test ! -e "$adaptive/$relative/failure.json"
  adaptive_dirs+=("$relative")
done
cd "$plain"
find "${plain_dirs[@]}" -type f -name '*.json' -print0 | sort -z | tar --null -czf "$plain_archive" -T -
cd "$adaptive"
find "${adaptive_dirs[@]}" -type f \( -name '*.json' -o -name 'physical_plain_*.py' \) -print0 | sort -z | tar --null -czf "$adaptive_archive" -T -
echo 'ORIGINAL_EIGHT_METADATA_ONLY_AND_ADAPTIVE_TWO_TEST_METADATA_SOURCE_BYTES_ONLY'
printf 'PLAIN_RECEIPTS_SHA256='
sha256sum "$plain_archive" | cut -d' ' -f1
echo BEGIN_PLAIN_RECEIPTS_TAR_GZ
base64 "$plain_archive"
echo END_PLAIN_RECEIPTS_TAR_GZ
printf 'ADAPTIVE_RECEIPTS_SHA256='
sha256sum "$adaptive_archive" | cut -d' ' -f1
echo BEGIN_ADAPTIVE_RECEIPTS_TAR_GZ
base64 "$adaptive_archive"
echo END_ADAPTIVE_RECEIPTS_TAR_GZ
