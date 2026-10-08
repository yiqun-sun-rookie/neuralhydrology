#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
PAYLOAD="$HOME/hpc_mailbox/inbox/hydrol85935-revision-20261008-001/payload/runner_v002.tar.gz"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
printf '%s  %s\n' '39c193ac17c322afd7df94a7987ed31f79ca6774adabb9b53ea5b6817d0904dc' "$PAYLOAD" | sha256sum -c -
mkdir -p "$ROOT/versions"
mkdir "$ROOT/versions/v002"
cp -a "$ROOT/code" "$ROOT/versions/v002/code"
tar -xzf "$PAYLOAD" -C "$ROOT/versions/v002"
cd "$ROOT/versions/v002"
sha256sum -c CODE.sha256
test ! -e "$ROOT/control/preflight_v002_submission_attempt"
date -Is > "$ROOT/control/preflight_v002_submission_attempt"
set +e
out=$(sbatch "$ROOT/versions/v002/preflight.sbatch" 2>&1)
submission_status=$?
set -e
printf '%s\n' "$out" | tee "$ROOT/control/preflight_v002_submission.txt"
test "$submission_status" -eq 0 || { echo "SUBMISSION_FAILED exit=$submission_status"; exit "$submission_status"; }
printf '%s\n' "$out" | grep -qE '^Submitted batch job [0-9]+$' || { echo SUBMISSION_NOT_CONFIRMED; exit 5; }
job=$(printf '%s\n' "$out" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
test "$(printf '%s\n' "$job" | wc -l)" -eq 1
printf '%s\n' "$job" > "$ROOT/control/preflight_v002_job_id"
squeue -j "$job" -o '%.18i %.14P %.35j %.10T %.12M %.8C %.20b %.30R'
