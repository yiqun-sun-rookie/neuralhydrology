#!/usr/bin/env bash
set -eo pipefail
parent=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1
plain="$parent/plain_preflight_v1"
code="$plain/formal_input_chunks_001"
staging="$plain/corrected_input_chunks_001"
receipt="$plain/formal_input_delivery_001_corrected_states"
target="$plain/inputs/repo/docs/plans/wrr-hamid-evaluation-20260927-v1/test_states_001/test_corrected_cpu.pt"
chunk=/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/corrected_file10_part001.bin
for absent in "$staging" "$receipt" "$target"; do
  if [ -e "$absent" ] || [ -L "$absent" ]; then echo "REFUSE_EXISTING=$absent"; exit 64; fi
done
active=$(squeue -h -u sunyiq -o '%i|%j|%T|%Z' | awk -F'|' '$4 ~ "^/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1(/|$)" {print}')
if [ -n "$active" ]; then printf 'REFUSE_ACTIVE_TASK_JOBS\n%s\n' "$active"; exit 64; fi
printf '%s  %s\n' 855d76bcba7ca6fc05fec89108b382843597d4dc64e9a399385a63301cba66a8 "$code/opaque_delivery.py" ca5e0e183e8ff7776ea9fd2e716999e774931ba32a385942fd065b3969d453d0 "$code/delivery_catalogue.json" fe81db8c7bbea43e2f8040ea004e8f8bbf5ddf2107cd5b73369643f3e68c3087 "$plain/deployed_manifest.json" 7c9f21f4ab69840a3f87064ff9aec15222f48b124ac61c6f65d21a39ac07df60 "$chunk" | sha256sum --strict --check -
test "$(stat -c %s "$chunk")" -eq 316764
mkdir "$staging"
cp -n "$chunk" "$staging/file10_part001.bin"
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B "$code/opaque_delivery.py" install --catalogue "$code/delivery_catalogue.json" --catalogue-sha256 ca5e0e183e8ff7776ea9fd2e716999e774931ba32a385942fd065b3969d453d0 --stage corrected_states --chunk-root "$staging" --manifest "$plain/deployed_manifest.json" --execute-reviewed-opaque-action
printf '%s  %s\n' 7c9f21f4ab69840a3f87064ff9aec15222f48b124ac61c6f65d21a39ac07df60 "$target" | sha256sum --strict --check -
test "$(stat -c %s "$target")" -eq 316764
test ! -e "$receipt/failure.json"
echo BEGIN_CORRECTED_STATE_DELIVERY
sha256sum "$receipt/completion.json"
base64 "$receipt/completion.json"
echo END_CORRECTED_STATE_DELIVERY
echo OPAQUE_DELIVERY_ONLY_NO_MODEL_NO_ADMISSION
