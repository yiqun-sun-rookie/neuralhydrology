#!/bin/bash
# a02b seq=9 : same as seq=8 but without `git -C` (HPC git is too old for it).
export LC_ALL=C
PKG=/data1/home/$USER/nature_1st_a02
MBD=/data1/home/$USER/hpc_mailbox
SHIP=/data1/home/$USER/.a02_ship
B="$PKG/runs/a02_lean_bundle.tar.gz"

echo "  git version: $(git --version)"
URL=$(cd "$MBD" && git config --get remote.origin.url)
if [ -z "$URL" ]; then echo "  [FATAL] no remote url"; exit 1; fi
echo "  remote url resolved: yes (host=$(echo "$URL" | sed 's|.*@||; s|/.*||'))"

echo "=== A PUSH ==="
cd "$SHIP" || { echo "  [FATAL] scratch repo missing"; exit 1; }
echo "  head=$(git rev-parse --short HEAD)  file=$(ls -l a02_lean_bundle.tar.gz | awk '{print $5}')"
timeout 1200 git push "$URL" HEAD:refs/heads/a02-payload 2>&1 | sed 's|https://[^ ]*|<redacted>|g' | sed 's/^/  /'
echo "  push_rc=$?"

echo "=== B CONFIRM ON REMOTE ==="
timeout 180 git ls-remote --heads "$URL" a02-payload 2>&1 | awk '{print "   sha="$1" ref="$2}'
