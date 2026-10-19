#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_graice_shared_probe_20261019_001
job_id=$(tr -d '\r\n' < "$root/job_id.txt")
test "$job_id" = 245137
test -f "$root/probe_output/gpu_preflight.json"
test -f "$root/probe_output/supervisor.json"
mkdir -p "$root/artifacts"
test ! -e "$root/artifacts/gpu_probe_receipts_v001.tar.gz"
set +e
timeout 30 sacct -S 2026-10-18 -j "$job_id" --format=JobIDRaw,JobName%32,Account,Partition,State,ExitCode,Elapsed,Start,End,NodeList -n -P > "$root/artifacts/sacct_245137_v001.txt" 2>&1
sacct_exit=$?
timeout 30 scontrol -o show job "$job_id" > "$root/artifacts/scontrol_245137_v001.txt" 2>&1
scontrol_exit=$?
set -e
printf 'SACCT_EXIT=%s\n' "$sacct_exit"
cat "$root/artifacts/sacct_245137_v001.txt"
printf 'SCONTROL_EXIT=%s\n' "$scontrol_exit"
cat "$root/artifacts/scontrol_245137_v001.txt"
tar -czf "$root/artifacts/gpu_probe_receipts_v001.tar.gz" -C "$root" \
    hpc/probe_v002.slurm authorization_policy.json probe_authorization.json \
    allocation.json job_id.txt submissions.tsv sbatch_reply.txt sbatch_error.txt \
    provenance/deployment_manifest.json provenance/cpu_contract.json \
    provenance/independent_review_followup_v002.md \
    logs/probe_245137.out logs/probe_245137.err probe_output \
    artifacts/sacct_245137_v001.txt artifacts/scontrol_245137_v001.txt
printf 'ARCHIVE_SHA256='
sha256sum "$root/artifacts/gpu_probe_receipts_v001.tar.gz" | cut -d' ' -f1
printf 'ARCHIVE_BYTES='
wc -c < "$root/artifacts/gpu_probe_receipts_v001.tar.gz"
printf 'BEGIN_ARCHIVE_BASE64\n'
base64 "$root/artifacts/gpu_probe_receipts_v001.tar.gz"
printf 'END_ARCHIVE_BASE64\n'
echo RECEIPTS_COLLECTED_NO_NUMERICAL_RERUN
