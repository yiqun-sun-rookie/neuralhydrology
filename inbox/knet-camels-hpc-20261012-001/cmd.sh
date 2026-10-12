#!/bin/bash
set -eo pipefail
TASK_ROOT=/data1/home/sunyiq/knet_camels_hpc_20261012_001
PAYLOAD=/data1/home/sunyiq/hpc_mailbox/inbox/knet-camels-hpc-20261012-001/payload/v1
[ -f "$TASK_ROOT/OWNER.txt" ] || { echo OWNER_MISSING; exit 1; }
grep -q 'knet-camels-hpc-20261012-001' "$TASK_ROOT/OWNER.txt" || { echo OWNER_DIFFERS; exit 1; }
[ ! -e "$TASK_ROOT/receipts/submission.txt" ] || { echo ALREADY_SUBMITTED_RECEIPT_PRESENT; cat "$TASK_ROOT/receipts/submission.txt"; exit 1; }
printf '%s  %s\n' '9ed451cf74667409dd0b0ddfc20eb89686e7cac6c6b02968443e5149ad87bc01' "$PAYLOAD/recipe.tar.gz" | sha256sum -c -
printf '%s  %s\n' '66c9409afbbeff581d03f6a3967532392eddc300d3ec984d90f016ec1d41ecb6' "$PAYLOAD/probe_report.py" | sha256sum -c -
printf '%s  %s\n' '84c4cfc8d36882fa8fafb924a1d1cb4de4a09793566c652938051649ac1c96af' "$PAYLOAD/compatibility.slurm" | sha256sum -c -
[ ! -e "$TASK_ROOT/template" ] || { echo TEMPLATE_ALREADY_EXISTS; exit 1; }
mkdir "$TASK_ROOT/template"
tar -xzf "$PAYLOAD/recipe.tar.gz" -C "$TASK_ROOT/template"
[ ! -e "$TASK_ROOT/probe_report.py" ] || { echo PROBE_ENTRY_ALREADY_EXISTS; exit 1; }
cp "$PAYLOAD/probe_report.py" "$TASK_ROOT/probe_report.py"
cp "$PAYLOAD/compatibility.slurm" "$TASK_ROOT/compatibility.slurm"
printf 'DEPLOYED_ROOT=%s
' "$TASK_ROOT"
out=$(sbatch "$TASK_ROOT/compatibility.slurm" 2>&1)
printf '%s
' "$out"
jid=$(printf '%s
' "$out" | sed -n 's/^Submitted batch job \([0-9][0-9]*\)$/\1/p')
[ -n "$jid" ] || { echo SUBMIT_FAILED_NO_UNIQUE_JOB_ID; exit 1; }
[ "$(printf '%s
' "$jid" | wc -l)" -eq 1 ] || { echo SUBMIT_AMBIGUOUS; exit 1; }
( set -o noclobber; printf 'jobid=%s
%s
' "$jid" "$out" > "$TASK_ROOT/receipts/submission.txt" )
printf 'jobid=%s
' "$jid"
squeue -j "$jid" -h -o '%i|%j|%T|%P|%C|%R'
