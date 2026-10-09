#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
CONT="$ROOT/control/continuation_v003"
PAYLOAD="$HOME/hpc_mailbox/inbox/hydrol85935-revision-20261008-001/payload/continuation_v003_20261009_001.tar.gz"
test "$(readlink -f "$ROOT")" = "$ROOT"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
test ! -e "$ROOT/versions/v003"
test ! -e "$ROOT/control/full_v003"
test ! -e "$ROOT/control/preflight_v003_submission_attempt"
test ! -e "$ROOT/control/formal_v003_attempt.json"
printf '%s  %s\n' '7ea6feb8df3a05e49170bb90c276f970a361d807ee18c23ef84ae0ee494cf897' "$PAYLOAD" | sha256sum -c -
mkdir "$CONT"
tar -xzf "$PAYLOAD" -C "$CONT"
cd "$CONT"
sha256sum -c CONTINUATION.sha256
mkdir "$ROOT/versions/v003"
cp -a "$ROOT/code" "$ROOT/versions/v003/code"
tar -xzf "$CONT/runner_v003.tar.gz" -C "$ROOT/versions/v003"
(cd "$ROOT/versions/v003" && sha256sum -c CODE.sha256)
mkdir "$ROOT/control/full_v003"
tar -xzf "$CONT/full_pipeline_v003_inputs_v001_runtime271.tar.gz" -C "$ROOT/control/full_v003"
cp "$CONT/FULL.sha256" "$ROOT/control/full_v003/FULL.sha256"
(cd "$ROOT/control/full_v003" && sha256sum -c FULL.sha256)
nohup /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -u "$CONT/continue_after_runtime.py" > "$ROOT/logs/continuation-v003.log" 2>&1 </dev/null &
pid=$!
printf '%s\n' "$pid" > "$CONT/coordinator_pid"
printf 'FINITE_CONTINUATION_STARTED pid=%s\n' "$pid"
