#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_graice_shared_probe_20261019_001
test -f "$root/authorization_policy.json"
test -f "$root/hpc/probe_v002.slurm"
test ! -e "$root/probe_output"
exec 9>"$root/submission.lock"
flock -n 9 || { echo 'Another submit command holds this experiment lock'; exit 70; }
if test -e "$root/submission_intent.json" || test -e "$root/job_id.txt"; then
    echo 'Submission intent or job ID already exists; do not resubmit'
    cat "$root/job_id.txt" 2>/dev/null || true
    exit 71
fi
queue=$(timeout 30 squeue -h -u sunyiq -n id25_c01_probe_261019 -o '%i|%j|%T')
accounting=$(timeout 30 sacct -n -X -u sunyiq --name=id25_c01_probe_261019 -S 2026-10-18 --format=JobIDRaw,JobName%32,State,ExitCode -P)
printf 'existing_queue=%s\nexisting_accounting=%s\n' "$queue" "$accounting"
if test -n "$queue" || test -n "$accounting"; then
    echo 'Existing exact-name job found; do not submit'
    exit 72
fi
printf '{"job_name":"id25_c01_probe_261019","created_utc":"%s","full_training":false}\n' "$(date -u +%FT%TZ)" > "$root/submission_intent.json"
set +e
sbatch --parsable "$root/hpc/probe_v002.slurm" > "$root/sbatch_reply.txt" 2> "$root/sbatch_error.txt"
rc=$?
set -e
cat "$root/sbatch_reply.txt"
cat "$root/sbatch_error.txt"
if test "$rc" -ne 0; then
    echo "submission_failed_exit=$rc; preserved intent for exact reconciliation"
    exit "$rc"
fi
job_id=$(cut -d';' -f1 "$root/sbatch_reply.txt" | tr -d '\r\n')
case "$job_id" in ''|*[!0-9]*) echo 'Ambiguous sbatch result; preserve intent, do not retry'; exit 73;; esac
printf '%s\n' "$job_id" > "$root/job_id.txt"
printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$job_id" id25_c01_probe_261019 >> "$root/submissions.tsv"
timeout 30 squeue -j "$job_id" -o '%i|%j|%T|%R'
