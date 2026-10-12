#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
test "$(readlink -f "$ROOT")" = "$ROOT"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
PAYLOAD="$HOME/hpc_mailbox/inbox/hydrol85935-revision-20261008-001/payload/migration_probe_20261012_002.tar.gz"
test "$(sha256sum "$PAYLOAD" | cut -d' ' -f1)" = 010afb4e5aa72c8ff7cc9551b7c276f919da15bad7a7619767748c73c4059e5d
DEST="$ROOT/control/migration_probe_20261012_002"
test ! -e "$DEST"
mkdir "$DEST"
tar -xzf "$PAYLOAD" -C "$DEST"
cd "$DEST"
sha256sum -c FILES.sha256
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python submit.py
