#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
CONT="$ROOT/control/continuation_v004"
PAYLOAD="$HOME/hpc_mailbox/inbox/hydrol85935-revision-20261008-001/payload/continuation_v004_20261011_001.tar.gz"
test "$(readlink -f "$ROOT")" = "$ROOT"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
test ! -e "$CONT"
test ! -e "$ROOT/versions/v004"
test ! -e "$ROOT/control/full_v004"
test ! -e "$ROOT/control/preflight_v004_submission_attempt"
test ! -e "$ROOT/control/formal_v004_attempt.json"
test ! -e "$ROOT/control/full_v003/jobs.json"
test ! -e "$ROOT/control/formal_v003_attempt.json"
date -Is
active=$(squeue -h -u "$USER" -o '%i %T' | awk '$1 ~ /^(237696|237883|237904|237936|238679|238886)$/ {print}')
test -z "$active" || { printf '%s\n' "$active"; exit 5; }
old_pid=$(cat "$ROOT/control/continuation_v003/coordinator_pid")
if ps -p "$old_pid" -o pid,args; then echo OLD_COORDINATOR_PID_PRESENT; exit 5; fi
printf '%s  %s\n' '02455676c1ea6bf06e73625b55f1e594356fdfd05a6e702e40a7acd1d8887973' "$PAYLOAD" | sha256sum -c -
mkdir "$CONT"
tar -xzf "$PAYLOAD" -C "$CONT"
cd "$CONT"
sha256sum -c CONTINUATION.sha256
mkdir "$ROOT/versions/v004"
cp -a "$ROOT/code" "$ROOT/versions/v004/code"
tar -xzf "$CONT/runner_v004.tar.gz" -C "$ROOT/versions/v004"
(cd "$ROOT/versions/v004" && sha256sum -c CODE.sha256)
mkdir "$ROOT/control/full_v004"
tar -xzf "$CONT/full_pipeline_v004_inputs_v001_runtime271.tar.gz" -C "$ROOT/control/full_v004"
cp "$CONT/FULL.sha256" "$ROOT/control/full_v004/FULL.sha256"
(cd "$ROOT/control/full_v004" && sha256sum -c FULL.sha256)
nohup /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -u "$CONT/continue_after_runtime.py" > "$ROOT/logs/continuation-v004.log" 2>&1 </dev/null &
pid=$!
printf '%s\n' "$pid" > "$CONT/coordinator_pid"
printf 'FINITE_CONTINUATION_STARTED version=v004 pid=%s\n' "$pid"
