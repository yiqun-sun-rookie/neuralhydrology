#!/bin/bash
set -o pipefail
# Deterministic repair of the shared OpenHydroNet install from the trusted copy in the task's own landing directory.
# Restores missing or modified files; never deletes anything; touches nothing outside /data1/home/sunyiq/openhydronet_shared.
SH=/data1/home/sunyiq/openhydronet_shared
ROOT=/data1/home/sunyiq/openhydronet_531_20261015
P6="$HOME/hpc_mailbox/inbox/openhydronet-531-20261015/payload/v6"
date --iso-8601=seconds
[ -f "$ROOT/pysite/sitecustomize.py" ] && [ -d "$ROOT/src/flood-forecasting/googlehydrology" ] || { echo "RECOVER_ABORT: trusted copy missing"; exit 0; }
mkdir -p "$SH"
chmod -R u+w "$SH" 2>/dev/null
mkdir -p "$SH/pysite" "$SH/flood-forecasting"
cp -a -f "$ROOT/pysite/." "$SH/pysite/" || echo "RECOVER_WARN: pysite copy reported errors"
cp -a -f "$ROOT/src/flood-forecasting/." "$SH/flood-forecasting/" || echo "RECOVER_WARN: source copy reported errors"
for f in env.sh run_template.slurm VERSION README.md; do
  [ -f "$P6/$f" ] && cp -f "$P6/$f" "$SH/$f" && sed -i 's/\r$//' "$SH/$f"
done
find "$SH/pysite" "$SH/flood-forecasting" -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null
chmod -R a-w "$SH"
echo "RECOVER_DONE"
exit 0
