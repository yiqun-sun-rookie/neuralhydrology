#!/bin/bash
# a02b seq=8 : ship the lean bundle on its own branch from a scratch repo the
# mailbox runner never touches. The remote URL may carry a credential, so it is
# only ever held in a variable and never printed.
export LC_ALL=C
PKG=/data1/home/$USER/nature_1st_a02
MBD=/data1/home/$USER/hpc_mailbox
SHIP=/data1/home/$USER/.a02_ship
B="$PKG/runs/a02_lean_bundle.tar.gz"

echo "=== A SOURCE BUNDLE ==="
if [ ! -f "$B" ]; then
  echo "  missing, rebuilding"
  cd "$PKG/runs" && timeout 300 tar czf a02_lean_bundle.tar.gz \
    a02_*/config.json a02_*/best_model.pt a02_*/best_metrics.json \
    a02_*/train_history.jsonl a02_*/SHA256SUMS
fi
timeout 20 ls -la "$B" 2>&1 | sed 's/^/  /'
echo "  sha256: $(timeout 120 sha256sum "$B" | cut -d' ' -f1)"

echo "=== B SCRATCH REPO ==="
rm -rf "$SHIP"; mkdir -p "$SHIP"; cd "$SHIP" || exit 1
timeout 30 git init -q . 2>&1 | sed 's/^/  /'
cp "$B" ./a02_lean_bundle.tar.gz
timeout 300 git -c user.name=hpc -c user.email=hpc@local add -A 2>&1 | sed 's/^/  /'
timeout 300 git -c user.name=hpc -c user.email=hpc@local commit -q -m "a02 lean bundle: 12 runs x {config,best_model,best_metrics,train_history,SHA256SUMS}" 2>&1 | sed 's/^/  /'
echo "  committed: $(git rev-parse --short HEAD 2>/dev/null)"

echo "=== C PUSH TO ITS OWN BRANCH ==="
URL=$(git -C "$MBD" config --get remote.origin.url)
if [ -z "$URL" ]; then echo "  [FATAL] no remote url"; exit 1; fi
if timeout 900 git push -q "$URL" HEAD:refs/heads/a02-payload 2>&1 | sed 's|https://[^ ]*|<redacted>|g' | sed 's/^/  /'; then
  echo "  push exit=0"
else
  echo "  push exit=nonzero"
fi

echo "=== D CONFIRM ON REMOTE ==="
timeout 120 git ls-remote --heads "$URL" a02-payload 2>&1 | awk '{print "   sha="$1" ref="$2}'
