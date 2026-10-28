#!/bin/bash
# OHN latent-UKF pilot seq88 (read-only): chunks 02 and 03 of the transfer package. Nothing written.
X=/data1/home/sunyiq/ohn_da_vs_ar_531_20261021/ukf_xfer_20261028
date --iso-8601=seconds
for c in 02 03; do
  echo "=== CHUNK_${c}_BASE64_BEGIN ==="
  base64 -w 0 "$X/chunk_$c"; echo
  echo "=== CHUNK_${c}_BASE64_END ==="
done
echo "SEQ88_DONE"
