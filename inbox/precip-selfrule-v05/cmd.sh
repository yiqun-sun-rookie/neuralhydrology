#!/bin/bash
# precip-selfrule-v05 seq=2: identify the exact frozen C4 assets and repository state.
# Read-only; no compute job is submitted.
set -o pipefail
ROOT=/data1/home/sunyiq/precip_input_da_2026_09
REPO=$HOME/neuralhydrology

date "+wallclock %F %T %z"
hostname

echo "=== A. C4 ASSET HASHES ==="
for d in "$ROOT/base/C4" "$ROOT/base/C4_s200" "$ROOT/base/C4_s300"; do
  echo "DIR $d"
  for rel in model_epoch030.pt config.yml train_data/train_data_scaler.yml; do
    if [ -f "$d/$rel" ]; then
      sha256sum "$d/$rel"
    else
      echo "MISSING $d/$rel"
    fi
  done
done

echo "=== B. REPOSITORY STATE ==="
git -C "$REPO" rev-parse HEAD
git -C "$REPO" branch --show-current
git -C "$REPO" status --short -- neuralhydrology/modelzoo/cudalstm.py neuralhydrology/modelzoo/inputlayer.py neuralhydrology/modelzoo/__init__.py neuralhydrology/modelzoo/head.py neuralhydrology/utils/config.py neuralhydrology/datautils/utils.py neuralhydrology/datasetzoo/camelsus.py

echo "=== C. CONFIG SEMANTICS ==="
for d in "$ROOT/base/C4" "$ROOT/base/C4_s200" "$ROOT/base/C4_s300"; do
  echo "DIR $d"
  grep -E '^(model|hidden_size|seq_length|predict_last_n|output_dropout|train_start_date|train_end_date|seed):' "$d/config.yml" || true
done

echo "=== DONE READ-ONLY ASSET CHECK ==="