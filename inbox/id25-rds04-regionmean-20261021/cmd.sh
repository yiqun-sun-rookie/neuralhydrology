#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_regional_regionmean_rds04_20261021_001
job=$(cat "$root/job_id.txt")
timeout 30 sacct -n -X -j "$job" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,NodeList -P > "$root/final_sacct.txt"
grep -E "^$job\|.*\|COMPLETED\|0:0\|" "$root/final_sacct.txt"
grep -q '"state": "COMPLETED"' "$root/output/status.json"
grep -q '"state": "FROZEN"' "$root/output/selection.json"
test -f "$root/report.json"
archive="$root/rds04_completed_v001.tar.gz"
tar -czf "$archive" -C "$root" output report.json runtime.json final_sacct.txt source_manifest.json config.json inputs/input_receipt.json inputs/transforms.json provenance code hpc logs submissions.tsv
sha256sum "$archive"
wc -c "$archive"
echo ARCHIVE_BASE64_BEGIN
base64 "$archive"
echo ARCHIVE_BASE64_END
