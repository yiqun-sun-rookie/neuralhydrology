#!/bin/bash
# Set up a self-contained workspace. Never touches ~/neuralhydrology or ~/adv531.
set -o pipefail
ROOT=~/autoresearch64
BUNDLE=~/hpc_mailbox/inbox/autoresearch-64/payload/a64_bundle.tar.gz

echo "=== A. refuse to clobber ==="
if [ -e "$ROOT" ]; then echo "ABORT: $ROOT already exists"; ls -la "$ROOT" | head -5; exit 1; fi
echo "ok, $ROOT is free"

echo "=== B. bundle integrity ==="
ls -l "$BUNDLE" 2>&1 | head -2
sha256sum "$BUNDLE" 2>&1 | head -2
echo "expected b970dcf4a3dc255ce69da68f9dabd70f4b82277896f34c07b599e0cd58c92926"

echo "=== C. unpack ==="
mkdir -p "$ROOT" && cd "$ROOT" || exit 1
tar xzf "$BUNDLE" || { echo "UNPACK_FAILED"; exit 1; }
mkdir -p runs/unified_autoresearch
printf 'runs/\n__pycache__/\n*.pyc\n' > .gitignore

echo "=== D. git repo (fingerprinting needs a real HEAD) ==="
git init -q . && git config user.email "yiqun.sun.hydro.gee@gmail.com" && git config user.name "yiqun.sun"
git add -A && git commit -q -m "autoresearch64 workspace: unified_autoresearch package, frozen statics, basin list"
git log -1 --format="%h %s" 2>&1
git status --porcelain | wc -l

echo "=== E. layout ==="
find . -maxdepth 3 -type d -not -path "./.git*" | sort | head -20
echo "package files:"; find src/unified_autoresearch -name "*.py" | wc -l
echo "statics:"; wc -l src/fair_benchmark/frozen/bundle/track0_statics.csv 2>&1 | head -1
echo "basin list:"; wc -l examples/06-Finetuning/531_basin_list.txt 2>&1 | head -1
echo "score.py present? (must be absent):"; find src -name "score.py" | wc -l

echo "=== F. frozen selection hashes match the shipped inputs? ==="
sha256sum src/fair_benchmark/frozen/bundle/track0_statics.csv examples/06-Finetuning/531_basin_list.txt 2>&1
