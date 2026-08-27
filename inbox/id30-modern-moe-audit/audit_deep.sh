#!/bin/bash
# Bounded read-only search for relevant prepared assets outside the expected result roots.
set -o pipefail

REPO="${HOME}/neuralhydrology"

echo "=== REMOTE IDENTITY AND TIME ==="
date -Is 2>/dev/null || date
hostname
id -un

echo "=== RELEVANT HOME-LEVEL DIRECTORIES ==="
find "$HOME" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null \
  | grep -Ei 'neural|hydro|camels|lstm|transform|moe|mamba|fair' \
  | sort | sed -n '1,150p' || true

echo "=== EXACT EXPERIMENT ROOT SEARCH, LIMITED TO FOUR LEVELS ==="
find "$HOME" -mindepth 1 -maxdepth 4 -type d \
  \( -name '18_lstm_fair_531' -o -name '30_modern_transformer_moe' -o -name '*modern*transformer*' -o -name '*transformer*moe*' \) \
  -print 2>/dev/null | sort | sed -n '1,150p'

echo "=== EPOCH-30 CHECKPOINTS UNDER STANDARD RUN AND RESULT ROOTS ==="
for root in "$REPO/runs" "$REPO/results" "$HOME/runs" "$HOME/results"
do
  if [ -d "$root" ]; then
    echo "ROOT path=$root resolved=$(readlink -f "$root" 2>/dev/null || echo unresolved)"
    n=$(find "$root" -maxdepth 6 -type f -name 'model_epoch030.pt' 2>/dev/null | wc -l)
    echo "  epoch030_checkpoint_count=$n"
    find "$root" -maxdepth 6 -type f -name 'model_epoch030.pt' -print 2>/dev/null \
      | sort | sed -n '1,150p'
  else
    echo "MISSING root=$root"
  fi
done

echo "=== CAMELS-RELATED RESULT INVENTORY ==="
for root in \
  "$REPO/results/02_mamba_camels_us" \
  "$REPO/results/03_mamba_camelsh" \
  "$REPO/runs"
do
  if [ -d "$root" ]; then
    echo "ROOT $root"
    echo "  all_checkpoint_count=$(find "$root" -maxdepth 6 -type f \( -name 'model_epoch*.pt' -o -name '*.pth' \) 2>/dev/null | wc -l)"
    echo "  configuration_snapshot_count=$(find "$root" -maxdepth 6 -type f -name 'config.yml' 2>/dev/null | wc -l)"
    echo "  test_result_pickle_count=$(find "$root" -maxdepth 7 -type f -name 'test_results.p' 2>/dev/null | wc -l)"
    find "$root" -maxdepth 6 -type f \( -name 'model_epoch*.pt' -o -name '*.pth' -o -name 'config.yml' \) \
      -print 2>/dev/null | sort | sed -n '1,150p'
  else
    echo "MISSING $root"
  fi
done

echo "=== RELEVANT ARCHIVES, LIMITED TO THREE LEVELS ==="
find "$HOME" -mindepth 1 -maxdepth 3 -type f \
  \( -iname '*camels*.tar.gz' -o -iname '*lstm*.tar.gz' -o -iname '*transformer*.tar.gz' -o -iname '*moe*.tar.gz' \) \
  -printf '%p|%s bytes\n' 2>/dev/null | sort | sed -n '1,150p'

echo "=== SOURCE TREE PRESENCE FOR OLDER CAMELS MODELS ==="
if [ -d "$REPO" ]; then
  (
    cd "$REPO" || exit 0
    for p in \
      src/lstm_fair_531 \
      src/modern_transformer_moe \
      src/adversarial/baseline_531 \
      src/02_mamba_camels_us \
      src/_archive/02_mamba_camels_us
    do
      if [ -e "$p" ]; then
        echo "FOUND $p"
      else
        echo "MISSING $p"
      fi
    done
  )
fi

echo "=== BOUNDED SEARCH COMPLETE ==="
echo "No files were modified, no result pickle was opened, and no job was submitted."
