#!/bin/bash
# Exact read-only inventory of the three discovered long short-term memory result roots.
set -o pipefail

echo "=== REMOTE IDENTITY AND TIME ==="
date -Is 2>/dev/null || date
hostname
id -un

echo "=== DISCOVERED LONG SHORT-TERM MEMORY RESULT ROOTS ==="
for root in \
  "$HOME/adv531/results/18_lstm_fair_531" \
  "$HOME/id18_e04_20260809/results/18_lstm_fair_531" \
  "$HOME/v09_strict/neuralhydrology/results/18_lstm_fair_531"
do
  echo "--- root=$root ---"
  if [ ! -d "$root" ]; then
    echo "MISSING"
    continue
  fi
  echo "resolved=$(readlink -f "$root" 2>/dev/null || echo unresolved)"
  echo "epoch030_checkpoint_count=$(find "$root" -maxdepth 4 -type f -name 'model_epoch030.pt' 2>/dev/null | wc -l)"
  echo "config_snapshot_count=$(find "$root" -maxdepth 4 -type f -name 'config.yml' 2>/dev/null | wc -l)"
  echo "scaler_count=$(find "$root" -maxdepth 4 -type f -path '*/train_data/train_data_scaler.yml' 2>/dev/null | wc -l)"
  echo "validation_result_pickle_count=$(find "$root" -maxdepth 6 -type f -name 'validation_results.p' 2>/dev/null | wc -l)"
  echo "test_result_pickle_count=$(find "$root" -maxdepth 6 -type f -name 'test_results.p' 2>/dev/null | wc -l)"
  find "$root" -maxdepth 4 -type f -name 'model_epoch030.pt' -print 2>/dev/null | sort | while IFS= read -r f
  do
    bytes=$(wc -c < "$f")
    digest=$(sha256sum "$f" | awk '{print $1}')
    echo "CHECKPOINT path=$f bytes=$bytes sha256=$digest"
  done
  echo "run_directories:"
  find "$root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort | sed -n '1,50p'
done

echo "=== ADVERSARIAL CLONE READINESS ==="
ADV="$HOME/adv531"
if [ -d "$ADV" ]; then
  (
    cd "$ADV" || exit 0
    echo "path=$(pwd)"
    echo "branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
    echo "commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "change_count=$(git status --porcelain 2>/dev/null | wc -l)"
    for p in \
      data/camels_us \
      src/lstm_fair_531 \
      src/modern_transformer_moe \
      src/fair_benchmark/frozen/track0_forcing_only_basins.txt \
      src/fair_benchmark/frozen/bundle/track0_statics.csv
    do
      if [ -e "$p" ]; then
        echo "FOUND $p resolved=$(readlink -f "$p" 2>/dev/null || echo not_a_link)"
      else
        echo "MISSING $p"
      fi
    done
  )
else
  echo "MISSING $ADV"
fi

echo "=== SINGLE OLDER 531-BASIN EPOCH-30 MODEL CONFIGURATION ==="
OLD="$HOME/neuralhydrology/results/05_full_531_basins/reproduce_531_nse074_2025_1129_2145_ep30"
if [ -d "$OLD" ]; then
  echo "root=$OLD"
  for f in "$OLD/model_epoch030.pt" "$OLD/config.yml" "$OLD/train_data/train_data_scaler.yml"
  do
    if [ -f "$f" ]; then
      echo "FOUND file=$f bytes=$(wc -c < "$f") sha256=$(sha256sum "$f" | awk '{print $1}')"
    else
      echo "MISSING file=$f"
    fi
  done
  if [ -f "$OLD/config.yml" ]; then
    echo "--- selected configuration fields ---"
    grep -E '^(model|seed|dataset|data_dir|train_start_date|train_end_date|validation_start_date|validation_end_date|test_start_date|test_end_date|seq_length|hidden_size|batch_size|epochs|dynamic_inputs|static_attributes):' "$OLD/config.yml" || true
  fi
else
  echo "MISSING $OLD"
fi

echo "=== EXACT INVENTORY COMPLETE ==="
echo "No checkpoint or result payload was opened, no file was modified, and no job was submitted."
