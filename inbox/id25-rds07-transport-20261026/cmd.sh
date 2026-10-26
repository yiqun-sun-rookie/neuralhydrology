#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_regional_transport_rds07_20261026_001
job=$(cat "$root/job_id.txt")
case "$job" in ''|*[!0-9]*) exit 1 ;; esac
timeout 30 sacct -n -X -j "$job" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,NodeList -P > "$root/final_sacct.txt"
grep -E "^$job\|.*\|COMPLETED\|0:0\|" "$root/final_sacct.txt"
grep -q '"state": "COMPLETED"' "$root/output/report.json"
for arm in transport direct_history; do
  grep -q '"state": "FROZEN"' "$root/output/$arm/selection.json"
  grep -q '"optimizer_steps": 20' "$root/output/$arm/report.json"
done
archive="$root/rds07_completed_v001.tar.gz"
test ! -e "$archive"
tar -czf "$archive" -C "$root" output final_sacct.txt source_manifest.json config.json inputs/input_receipt.json inputs/transforms.json provenance code hpc ops logs submissions.tsv job_id.txt submission_intent.initial resource_adaptation_v004 submission_intent.memory_default_v004 pre_repair_sacct_v002.txt pre_repair_sacct_v004.txt failed_submission_247680_v004.txt
sha256sum "$archive"
wc -c "$archive"
echo ARCHIVE_BASE64_BEGIN
base64 "$archive"
echo ARCHIVE_BASE64_END
