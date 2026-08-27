#!/bin/bash
exec bash inbox/id30-modern-moe-audit/audit_deep.sh
# Read-only inventory for the CAMELS-US modern causal Transformer and sparse mixture-of-experts work.
set -o pipefail

REPO="${HOME}/neuralhydrology"

echo "=== REMOTE IDENTITY AND TIME ==="
date -Is 2>/dev/null || date
hostname
id -un

echo "=== PROJECT REPOSITORY ==="
if [ ! -d "$REPO" ]; then
  echo "MISSING $REPO"
else
  (
    cd "$REPO" || exit 0
    echo "path=$(pwd)"
    echo "branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
    echo "commit=$(git rev-parse HEAD 2>/dev/null || echo unknown)"
    echo "tracked_and_untracked_change_count=$(git status --porcelain 2>/dev/null | wc -l)"
  )
fi

echo "=== STORAGE ==="
df -h /data1 2>&1 | sed -n '1,3p'

echo "=== DATA ROOT CANDIDATES ==="
for p in \
  "$REPO/data/camels_us" \
  "$REPO/data/CAMELS_US" \
  "$HOME/data/camels_us" \
  "/data1/home/sunyiq/data/camels_us"
do
  if [ -d "$p" ]; then
    echo "FOUND path=$p resolved=$(readlink -f "$p" 2>/dev/null || echo unresolved)"
    if [ -d "$p/basin_mean_forcing/maurer" ]; then
      n_forcing=$(find "$p/basin_mean_forcing/maurer" -type f 2>/dev/null | wc -l)
      echo "  maurer_forcing_directory=yes files=$n_forcing"
    else
      echo "  maurer_forcing_directory=no"
    fi
    if [ -d "$p/camels_attributes_v2.0" ]; then
      echo "  camels_attribute_directory=yes"
    else
      echo "  camels_attribute_directory=no"
    fi
    if [ -d "$p/usgs_streamflow" ]; then
      echo "  supervised_streamflow_target_directory=yes contents_not_read"
    else
      echo "  supervised_streamflow_target_directory=no"
    fi
  else
    echo "MISSING path=$p"
  fi
done

echo "=== REPOSITORY DATA LINKS AND TOP-LEVEL ENTRIES ==="
if [ -d "$REPO/data" ]; then
  find "$REPO/data" -mindepth 1 -maxdepth 1 -printf '%y %p -> %l\n' 2>/dev/null | sort | sed -n '1,100p'
else
  echo "MISSING $REPO/data"
fi

echo "=== FROZEN ALLOWED INPUT MANIFESTS ==="
if [ -d "$REPO" ]; then
  (
    cd "$REPO" || exit 0
    for f in \
      src/fair_benchmark/frozen/track0_forcing_only_basins.txt \
      src/adversarial/baseline_531/data/531_basin_list.txt \
      src/fair_benchmark/frozen/bundle/track0_statics.csv \
      src/fair_benchmark/frozen/MANIFEST.sha256
    do
      if [ -f "$f" ]; then
        bytes=$(wc -c < "$f")
        lines=$(wc -l < "$f")
        digest=$(sha256sum "$f" | awk '{print $1}')
        echo "FOUND file=$f bytes=$bytes lines=$lines sha256=$digest"
      else
        echo "MISSING file=$f"
      fi
    done
  )
fi

echo "=== HISTORICAL LONG SHORT-TERM MEMORY CHECKPOINTS ==="
if [ -d "$REPO/results/18_lstm_fair_531" ]; then
  (
    cd "$REPO" || exit 0
    find results/18_lstm_fair_531 -maxdepth 3 -type f -name 'model_epoch030.pt' -print 2>/dev/null | sort | while IFS= read -r f
    do
      bytes=$(wc -c < "$f")
      digest=$(sha256sum "$f" | awk '{print $1}')
      echo "CHECKPOINT path=$f bytes=$bytes sha256=$digest"
    done
    echo "checkpoint_count=$(find results/18_lstm_fair_531 -maxdepth 3 -type f -name 'model_epoch030.pt' 2>/dev/null | wc -l)"
    echo "test_result_pickle_count=$(find results/18_lstm_fair_531 -maxdepth 5 -type f -name 'test_results.p' 2>/dev/null | wc -l)"
  )
else
  echo "MISSING $REPO/results/18_lstm_fair_531"
fi

echo "=== MODERN TRANSFORMER AND MIXTURE-OF-EXPERTS SOURCE ==="
if [ -d "$REPO" ]; then
  (
    cd "$REPO" || exit 0
    for f in \
      src/modern_transformer_moe/README.md \
      src/modern_transformer_moe/registry/experiments.csv \
      src/modern_transformer_moe/registry/development_run_bindings.json \
      src/modern_transformer_moe/configs/baseline_lstm_s100.yml \
      src/modern_transformer_moe/configs/dense_d128_l4_s100.yml \
      src/modern_transformer_moe/configs/dense_d256_l4_s100.yml \
      src/modern_transformer_moe/configs/dense_d256_l8_s100.yml \
      src/modern_transformer_moe/configs/moe_selected_s100.yml
    do
      if [ -f "$f" ]; then
        echo "FOUND file=$f sha256=$(sha256sum "$f" | awk '{print $1}')"
      else
        echo "MISSING file=$f"
      fi
    done
    if [ -f src/modern_transformer_moe/registry/experiments.csv ]; then
      echo "--- experiment registry rows ---"
      sed -n '1,12p' src/modern_transformer_moe/registry/experiments.csv
    fi
    if [ -f src/modern_transformer_moe/registry/development_run_bindings.json ]; then
      echo "--- development bindings ---"
      sed -n '1,100p' src/modern_transformer_moe/registry/development_run_bindings.json
    fi
  )
fi

echo "=== MODERN TRANSFORMER AND MIXTURE-OF-EXPERTS RESULT ARTIFACTS ==="
if [ -d "$REPO/results/30_modern_transformer_moe" ]; then
  (
    cd "$REPO" || exit 0
    find results/30_modern_transformer_moe -maxdepth 7 -type f \
      \( -name 'model_epoch030.pt' -o -name 'epoch030_metrics.json' -o -name 'validation_metrics.csv' -o -name 'validation_results.p' -o -name 'router_diagnostics_epoch030.json' \) \
      -print 2>/dev/null | sort | sed -n '1,150p'
    echo "epoch030_checkpoint_count=$(find results/30_modern_transformer_moe -maxdepth 7 -type f -name 'model_epoch030.pt' 2>/dev/null | wc -l)"
    echo "epoch030_metric_artifact_count=$(find results/30_modern_transformer_moe -maxdepth 7 -type f -name 'epoch030_metrics.json' 2>/dev/null | wc -l)"
    echo "router_diagnostic_count=$(find results/30_modern_transformer_moe -maxdepth 7 -type f -name 'router_diagnostics_epoch030.json' 2>/dev/null | wc -l)"
  )
else
  echo "MISSING $REPO/results/30_modern_transformer_moe"
fi

echo "=== OTHER TOP-LEVEL RELEVANT RESULT DIRECTORIES ==="
if [ -d "$REPO/results" ]; then
  find "$REPO/results" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | grep -Ei 'lstm|transformer|moe|fair|camels' | sort | sed -n '1,100p' || true
fi

echo "=== CURRENT USER JOBS ==="
squeue -h -u "$(id -un)" -o '%i|%T|%P|%j|%M|%R' 2>&1 | sed -n '1,100p' || true

echo "=== AUDIT COMPLETE ==="
echo "No repository files were modified, no sealed evaluation answer was read, and no job was submitted."
