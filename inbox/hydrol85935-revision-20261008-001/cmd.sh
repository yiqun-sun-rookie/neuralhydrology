#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
PAYLOAD="$HOME/hpc_mailbox/inbox/hydrol85935-revision-20261008-001/payload/runner_v001.tar.gz"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
printf '%s  %s\n' 'cf24bed3e569a014984e71990a02c5328db29249a3a8f71c6668b788d4c115d4' "$PAYLOAD" | sha256sum -c -
mkdir -p "$ROOT/versions"
mkdir "$ROOT/versions/v001"
cp -a "$ROOT/code" "$ROOT/versions/v001/code"
tar -xzf "$PAYLOAD" -C "$ROOT/versions/v001"
cd "$ROOT/versions/v001"
sha256sum -c CODE.sha256
test ! -e "$ROOT/control/preflight_v001_submission_attempt"
date -Is > "$ROOT/control/preflight_v001_submission_attempt"
out=$(sbatch "$ROOT/versions/v001/preflight.sbatch" 2>&1)
printf '%s\n' "$out" | tee "$ROOT/control/preflight_v001_submission.txt"
printf '%s\n' "$out" | grep -qE '^Submitted batch job [0-9]+$' || { echo SUBMISSION_NOT_CONFIRMED; exit 5; }
job=$(printf '%s\n' "$out" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
test "$(printf '%s\n' "$job" | wc -l)" -eq 1
printf '%s\n' "$job" > "$ROOT/control/preflight_v001_job_id"
squeue -j "$job" -o '%.18i %.14P %.35j %.10T %.12M %.8C %.20b %.30R'
