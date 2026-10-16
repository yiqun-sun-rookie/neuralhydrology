#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_graice_author_matched_20261016_001
test -f "$root/venv/runtime_ready"
grep -qx 'exit_code=0' "$root/env_status_v002.txt"
if [ -e "$root/submit_intent_v001.txt" ] || [ -e "$root/job_id.txt" ] || [ -e "$root/report.json" ]; then echo PREVIOUS_SUBMISSION_REQUIRES_RECEIPT_INSPECTION; exit 1; fi
if [ -n "$(squeue -h -u sunyiq -n id25_graice_m_261016 -o '%i')" ]; then echo ACTIVE_OWN_JOB_NO_DUPLICATE; exit 1; fi
date -u +%FT%TZ > "$root/submit_intent_v001.txt"
if sbatch "$root/code/hpc/graice_author_matched_b04_20261016.slurm" > "$root/submission_v001.txt" 2>&1; then
  cat "$root/submission_v001.txt"
else
  cat "$root/submission_v001.txt"
  exit 1
fi
jid=$(awk '/^Submitted batch job [0-9]+$/ {print $4}' "$root/submission_v001.txt")
test -n "$jid"
printf '%s\n' "$jid" > "$root/job_id.txt"
printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$jid" 'v001 reviewed B04, one fit per region, interface gate then train' >> "$root/submissions.tsv"
printf 'JOB_ID=%s\n' "$jid"
