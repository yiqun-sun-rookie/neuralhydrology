#!/bin/bash
# a02b seq=6 : inventory one run dir, then build a lean bundle and drop it for shipping.
export LC_ALL=C
PKG=/data1/home/$USER/nature_1st_a02
MB=/data1/home/$USER/hpc_mailbox/outbox

echo "=== A ONE RUN DIR, FILE SIZES ==="
timeout 25 ls -la "$PKG/runs/a02_preceding_s43/" 2>&1 | sed 's/^/  /'

echo "=== B BUILD LEAN BUNDLE ==="
cd "$PKG/runs" || exit 1
rm -f a02_lean_bundle.tar.gz
timeout 300 tar czf a02_lean_bundle.tar.gz \
  a02_*/config.json a02_*/best_model.pt a02_*/best_metrics.json \
  a02_*/train_history.jsonl a02_*/SHA256SUMS 2>&1 | head -5
echo "  built:"; timeout 20 ls -la a02_lean_bundle.tar.gz 2>&1 | sed 's/^/    /'
echo "  members: $(timeout 60 tar tzf a02_lean_bundle.tar.gz 2>/dev/null | wc -l)"
echo "  sha256:  $(timeout 120 sha256sum a02_lean_bundle.tar.gz | cut -d' ' -f1)"

echo "=== C DROP FOR SHIPPING (atomic) ==="
mkdir -p "$MB"
timeout 120 cp a02_lean_bundle.tar.gz "$MB/.tmp_a02_lean_bundle.tar.gz" && \
  mv "$MB/.tmp_a02_lean_bundle.tar.gz" "$MB/a02_lean_bundle.tar.gz" && echo "  dropped OK"
timeout 20 ls -la "$MB/a02_lean_bundle.tar.gz" 2>&1 | sed 's/^/  /'
echo "  NOTE: authoritative copy stays at $PKG/runs/a02_lean_bundle.tar.gz"
