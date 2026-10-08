#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
PAYLOAD="$HOME/hpc_mailbox/inbox/hydrol85935-revision-20261008-001/payload/assets_20261008_001.tar.gz"
test -f "$PAYLOAD"
printf '%s  %s\n' 'c3ede9ebfc9e4c9e807f81d909a9347254474aa768724af6ebf66f921b104fdd' "$PAYLOAD" | sha256sum -c -
if [ -e "$ROOT" ] || [ -L "$ROOT" ]; then echo ROOT_ALREADY_EXISTS; exit 3; fi
mkdir "$ROOT"
printf '%s\n' hydrol85935_revision_20261008_001 > "$ROOT/OWNER"
mkdir "$ROOT/logs" "$ROOT/control" "$ROOT/execution"
cp "$PAYLOAD" "$ROOT/control/assets_20261008_001.tar.gz"
tar -xzf "$ROOT/control/assets_20261008_001.tar.gz" -C "$ROOT"
cd "$ROOT"
sha256sum -c ASSETS.sha256
printf '=== current queue - read only ===\n'
squeue -u "$USER" -o '%.18i %.14P %.35j %.10T %.12M %.8C %.20b %.30R'
printf '=== partition rules ===\n'
scontrol show partition hgpu2p
printf '=== existing waiting task scheduling constraints - read only ===\n'
if scontrol show job 237173; then :; else printf 'Original pending job no longer in live scheduler\n'; fi
printf 'ASSETS_DEPLOYED %s\n' "$ROOT"
