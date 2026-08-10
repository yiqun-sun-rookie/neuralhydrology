#!/bin/bash
# ID29 seq=55: return the formal autoregression archive through the guaranteed result channel.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
RUN="$ROOT/results/29_nearing2022_da_ar/nearing2022_autoregression_lead1_holdout0.0_seed0_2026_0808_1648_ep30"
ARTDIR=/data1/home/sunyiq/hpc_mailbox/outbox/id29-nearing2022-da/artifacts/closure_20260810
METADIR="$ROOT/closure_20260810/artifact_manifests/existing_autoregression_seq55"
OUT="$ARTDIR/existing_autoregression_epoch030_seq55.tar.gz"
FILES=(
  config.yml
  model_epoch030.pt
  output.log
  train_data/train_data_scaler.yml
  test/model_epoch030/test_results.p
  test/model_epoch030/test_metrics.csv
)

echo "=== PREFLIGHT ==="
test -d "$RUN"
test ! -e "$OUT"
mkdir -p "$ARTDIR" "$METADIR"
for rel in "${FILES[@]}"; do test -f "$RUN/$rel"; done

echo "=== INTERNAL MANIFEST ==="
(
  cd "$RUN"
  sha256sum "${FILES[@]}"
) | tee "$METADIR/files.sha256"

echo "=== PACKAGE ==="
tar -czf "$OUT" -C "$RUN" "${FILES[@]}" -C "$METADIR" files.sha256
sha256sum "$OUT"
stat -c 'archive_bytes=%s' "$OUT"
echo "archive_members=$(tar -tzf "$OUT" | wc -l)"

echo "=== ARCHIVE_BASE64_BEGIN ==="
base64 -w 76 "$OUT"
echo "=== ARCHIVE_BASE64_END ==="
