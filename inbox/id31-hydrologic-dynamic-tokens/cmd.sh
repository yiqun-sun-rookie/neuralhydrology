#!/usr/bin/env bash
set -eo pipefail

SOURCE=/data1/home/sunyiq/id30_modern_transformer_moe_20260827/repo

test -d "$SOURCE/.git"
cd "$SOURCE"

echo "=== SOURCE REVISION AND WORKTREE ==="
git rev-parse HEAD
git status --porcelain

echo "=== REQUIRED SOURCE FILES ==="
required_files=(
  neuralhydrology/modelzoo/__init__.py
  neuralhydrology/modelzoo/modern_causal_transformer.py
  neuralhydrology/training/__init__.py
  neuralhydrology/training/regularization.py
  neuralhydrology/utils/config.py
  neuralhydrology/datasetzoo/camelsus_track0_bundle.py
  src/modern_transformer_moe/scripts/audit_configs.py
  src/modern_transformer_moe/scripts/candidate_safe_data.py
)
for path in "${required_files[@]}"; do
  test -f "$path"
  git ls-files --error-unmatch "$path" >/dev/null
  sha256sum "$path"
done

echo "=== CANDIDATE-SAFE DATA ROOTS ==="
for path in \
  data/camels_us_track0_development_forcing_v01 \
  data/camels_us_track0_supervision_v01; do
  test -d "$path"
  printf '%s -> %s\n' "$path" "$(readlink -f "$path")"
done

echo "=== CANDIDATE-SAFE MANIFESTS ==="
find data/camels_us_track0_development_forcing_v01 \
     data/camels_us_track0_supervision_v01 \
     -maxdepth 2 -type f \( -iname '*manifest*' -o -iname '*.sha256' \) \
     -print0 | sort -z | xargs -0 -r sha256sum

echo "ID31_READ_ONLY_PREFLIGHT_PASS"
