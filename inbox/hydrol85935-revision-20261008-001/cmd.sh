#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
SETUP=/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/runtime_setup_20261009_001
PAYLOAD="$HOME/hpc_mailbox/inbox/hydrol85935-revision-20261008-001/payload/runtime_setup_20261009_001.tar.gz"
test "$(readlink -f "$ROOT")" = "$ROOT"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
test ! -e "$ROOT/runtime_torch271cu118"
printf '%s  %s\n' '13757c5ee6ce8b8cef1701bb657eaf18df827d65bd760c6fd1db1efcc97ab3db' "$PAYLOAD" | sha256sum -c -
df -Pk "$ROOT"
available=$(df -Pk "$ROOT" | awk 'NR==2 {print $4}')
test "$available" -ge 15728640
squeue -u sunyiq -o '%.18i %.35j %.10T %.12M %.8C %.20b %.30R'
mkdir "$SETUP"
tar -xzf "$PAYLOAD" -C "$SETUP"
cd "$SETUP"
sha256sum -c SETUP.sha256
nohup bash "$SETUP/download_then_submit.sh" > "$ROOT/logs/runtime-download-20261009.log" 2>&1 </dev/null &
pid=$!
printf '%s\n' "$pid" > "$SETUP/download_pid"
printf 'DOWNLOAD_SUPERVISOR_STARTED pid=%s\n' "$pid"
