#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
DIAG="$ROOT/control/path_trace_20261009_001"
PAYLOAD="$HOME/hpc_mailbox/inbox/hydrol85935-revision-20261008-001/payload/path_trace_20261009_001.tar.gz"
test "$(readlink -f "$ROOT")" = "$ROOT"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
test ! -e "$DIAG"
test ! -e "$ROOT/diagnostics/path_trace_20261009_001"
date -Is
squeue -u "$USER" -o '%.18i %.14P %.35j %.10T %.12M %.8C %.20b %.30R'
# The previous coordinator stopped after a confirmed failed validation. No
# concurrent own compute stage is permitted before this diagnostic submission.
test "$(/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -c 'import json; print(json.load(open("/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/continuation_v003/status.json"))["phase"])')" = STOPPED_WITHOUT_RETRY
test -z "$(squeue -h -u "$USER" -o '%j' | grep '^hydrol85935-' || true)"
printf '%s  %s\n' '4b417535fb5aa5d07421173b18d75d7321756ac0a70a77b784880360f2c6b9dc' "$PAYLOAD" | sha256sum -c -
mkdir "$DIAG"
tar -xzf "$PAYLOAD" -C "$DIAG"
cd "$DIAG"
sha256sum -c PAYLOAD.sha256
cd "$ROOT"
sha256sum -c "$DIAG/EXPECTED_MODELS.sha256"
printf 'SUBMISSION_ATTEMPTED\n' > "$DIAG/submission_attempt"
set +e
timeout 120 sbatch "$DIAG/diagnose.sbatch" > "$DIAG/submission.out" 2> "$DIAG/submission.err"
rc=$?
set -e
cat "$DIAG/submission.out" "$DIAG/submission.err"
printf '%s\n' "$rc" > "$DIAG/submission_exit_code"
test "$rc" -eq 0
test "$(grep -cE '^Submitted batch job [0-9]+$' "$DIAG/submission.out")" -eq 1
sed -nE 's/^Submitted batch job ([0-9]+)$/\1/p' "$DIAG/submission.out" > "$DIAG/job_id"
printf 'READ_ONLY_NUMERICAL_DIAGNOSTIC_SUBMITTED job_id=%s\n' "$(cat "$DIAG/job_id")"
