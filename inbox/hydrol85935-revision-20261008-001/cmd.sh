#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
test "$(readlink -f "$ROOT")" = "$ROOT"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
PAYLOAD="$HOME/hpc_mailbox/inbox/hydrol85935-revision-20261008-001/payload/migration_gate_v005_20261012_002.tar.gz"
test "$(sha256sum "$PAYLOAD" | cut -d' ' -f1)" = d4922718657dfbbe82f6093a66d6b65b128c2d46148507f6413dc7e72a841977
test "$(sha256sum "$ROOT/versions/v004/CODE.sha256" | cut -d' ' -f1)" = 9b4b4fd7f3b49da4eda0b6e371d5a26bd68625800d5f084998e07569c22e68ac
DEST="$ROOT/control/migration_gate_v005_20261012_002"
test ! -e "$DEST"
test ! -e "$ROOT/versions/v005"
test ! -e "$ROOT/execution/v005"
test ! -e "$ROOT/control/migration_gate_v005.json"
mkdir "$DEST"
tar -xzf "$PAYLOAD" -C "$DEST"
cp -a "$ROOT/versions/v004" "$ROOT/versions/v005"
cd "$ROOT/versions/v005"
sha256sum --quiet -c CODE.sha256
cd "$DEST"
sha256sum -c FILES.sha256
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python submit.py
