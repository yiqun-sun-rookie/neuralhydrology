#!/bin/bash
set -eo pipefail
root=/data1/home/sunyiq/id25_graice_lstmnosif_20261015_001
jid=$(cat "$root/job_id.txt")
state=$(sacct -j "$jid" --format=JobIDRaw,State -n -P | awk -F '|' -v j="$jid" '$1==j {print $2}')
test "$state" = COMPLETED
test -f "$root/report.json"
test -f "$root/selection.json"
archive="$root/artifacts/graice_results_v001.tar.gz"
if [ ! -f "$archive" ]; then
  tar -czf "$archive" -C "$root" runs comparison predictions.npz selection.json report.json status.json regional_completion.json interface_check.json interface_check config.json payload_manifest.json provenance code logs job_id.txt submissions.tsv runtime_requirements.txt
fi
printf 'ARCHIVE_SHA256='
sha256sum "$archive" | cut -d ' ' -f 1
echo ARTIFACT_BASE64_BEGIN
base64 "$archive"
echo ARTIFACT_BASE64_END
