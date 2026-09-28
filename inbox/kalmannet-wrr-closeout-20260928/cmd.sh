#!/usr/bin/env bash
set -eo pipefail
root=/data1/home/sunyiq/kalmannet_wrr_closeout_20260928_v1/plain_preflight_v1
stage="$root/formal_input_chunks_001"
payload=/data1/home/sunyiq/hpc_mailbox/inbox/kalmannet-wrr-closeout-20260928/formal_original_input_volumes_001
test -d "$root"
test ! -e "$stage"
echo '7ca0cefa159ba5421bb8cc05a7bb0347856fdd4f2d21f9e4f853c203ac11fb43  '"$payload/plain_original_inputs_01.tar" | sha256sum -c -
echo 'da807e50b023d2ef575177a1c5d4456e5da96865bd1f03a6e35bf4815390f802  '"$payload/plain_original_inputs_02.tar" | sha256sum -c -
echo 'adf6c01c692f7881fee4dcb33ef5a73bb6bb5dfaa2a50d0edfc8c1abd579c40e  '"$payload/plain_original_inputs_03.tar" | sha256sum -c -
mkdir "$stage"
tar --keep-old-files -xf "$payload/plain_original_inputs_01.tar" -C "$stage"
tar --keep-old-files -xf "$payload/plain_original_inputs_02.tar" -C "$stage"
tar --keep-old-files -xf "$payload/plain_original_inputs_03.tar" -C "$stage"
echo '855d76bcba7ca6fc05fec89108b382843597d4dc64e9a399385a63301cba66a8  '"$stage/opaque_delivery.py" | sha256sum -c -
echo 'ca5e0e183e8ff7776ea9fd2e716999e774931ba32a385942fd065b3969d453d0  '"$stage/delivery_catalogue.json" | sha256sum -c -
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B "$stage/opaque_delivery.py" install --catalogue "$stage/delivery_catalogue.json" --catalogue-sha256 ca5e0e183e8ff7776ea9fd2e716999e774931ba32a385942fd065b3969d453d0 --stage original --chunk-root "$stage" --manifest "$root/deployed_manifest.json" --execute-reviewed-opaque-action
cat "$root/formal_input_delivery_001_original/completion.json"
sha256sum "$root/deployed_manifest.json"
echo OPAQUE_ORIGINAL_INPUTS_DELIVERED_NO_MODEL_OR_SCORE_RUN
