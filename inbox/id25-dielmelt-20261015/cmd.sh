#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_dielmelt_20261015_001
jid=$(cat "$root/job_id.txt")
state=$(sacct -j "$jid" --format=JobIDRaw,State -n -P | awk -F '|' -v j="$jid" '$1==j {print $2}')
test "$state" = COMPLETED
test -f "$root/output/report.json"
archive="$root/artifacts/dielmelt_results_v001.tar.gz"
if [ ! -f "$archive" ]; then
  tar -czf "$archive" -C "$root" output config.json input_manifest.json parent code logs job_id.txt submissions.tsv
fi
printf 'ARCHIVE_SHA256='
sha256sum "$archive" | cut -d ' ' -f 1
echo ARTIFACT_BASE64_BEGIN
base64 "$archive"
echo ARTIFACT_BASE64_END
