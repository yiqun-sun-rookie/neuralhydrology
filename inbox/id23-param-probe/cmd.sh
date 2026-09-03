#!/bin/bash
# Untracked files in outbox/ do not survive the runner; embed the artifact as base64 in this result.
set -o pipefail
ROOT=/data1/home/sunyiq/id23_param_probe
TMP=$(mktemp -d)
tar czf "$TMP/out.tar.gz" -C "$ROOT" out
echo "TAR_SHA256 $(sha256sum "$TMP/out.tar.gz" | cut -d' ' -f1)"
echo "TAR_BYTES $(wc -c < "$TMP/out.tar.gz")"
echo "=====BEGIN_B64====="
base64 -w 76 "$TMP/out.tar.gz"
echo "=====END_B64====="
rm -rf "$TMP"
