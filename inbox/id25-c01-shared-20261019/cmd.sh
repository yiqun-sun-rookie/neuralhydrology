#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_graice_shared_c01_20261019_001
job_id=$(tr -d '\r\n' < "$root/job_id.txt")
case "$job_id" in ''|*[!0-9]*) echo INVALID_JOB_ID; exit 1;; esac
test -f "$root/report.json"
test -f "$root/output/selection.json"
test -f "$root/output/best.keras"
test -f "$root/output/predictions.npz"
test -f "$root/comparison/acceptance_metrics.json"
mkdir -p "$root/artifacts"
archive="$root/artifacts/c01_completed_${job_id}_v002.tar.gz"
accounting=$(timeout 30 sacct -X -S 2026-10-18 -j "$job_id" --format=JobIDRaw,State,ExitCode -n -P)
printf '%s\n' "$accounting"
if ! printf '%s\n' "$accounting" | grep -Eq "^${job_id}[|]COMPLETED[|]0:0([|]|$)"; then
    echo EXACT_COMPLETED_ACCOUNTING_REQUIRED; exit 1
fi
printf '%s\n' "$accounting" > "$root/artifacts/final_sacct_${job_id}.txt"
if test ! -e "$archive"; then
    tar -czf "$archive" -C "$root" \
        package hpc ops provenance resource_adaptation_v002 scalers inputs/reference.npz \
        source_manifest.json authorization_policy.json runtime.json attempts \
        output comparison report.json logs job_id.txt submissions.tsv \
        "artifacts/final_sacct_${job_id}.txt"
fi
printf 'ARCHIVE_SHA256='
sha256sum "$archive" | cut -d' ' -f1
printf 'ARCHIVE_BYTES='
wc -c < "$archive"
printf 'BEGIN_ARCHIVE_BASE64\n'
base64 "$archive"
printf 'END_ARCHIVE_BASE64\n'
echo C01_RESULTS_COLLECTED_NO_NEW_FIT
