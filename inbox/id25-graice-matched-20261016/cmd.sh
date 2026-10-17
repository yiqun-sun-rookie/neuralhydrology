#!/bin/bash
set -euo pipefail
root=/data1/home/sunyiq/id25_graice_author_matched_20261016_001
jid=$(cat "$root/job_id.txt")
test "$jid" = 244024
state=$(timeout 30 sacct -j "$jid" --format=JobIDRaw,State,ExitCode -n -P | awk -F '|' -v j="$jid" '$1==j {print $1 "|" $2 "|" $3}')
test "$state" = '244024|COMPLETED|0:0'
export PYTHONDONTWRITEBYTECODE=1
"$root/venv/bin/python" - "$root" <<'PY'
import json,sys
from pathlib import Path
r=Path(sys.argv[1]); report=json.loads((r/'report.json').read_text()); selection=json.loads((r/'selection.json').read_text())
assert report['state']=='COMPLETED' and report['job_id']=='244024'
assert selection['state']=='FROZEN' and len(selection['regions'])==119
assert all(x['state']=='SELECTED' and x['optimizer_steps']>0 for x in selection['regions'])
print('B04_COMPLETION_AND_FROZEN_119_REGIONS_CONFIRMED')
PY
mkdir -p "$root/artifacts"
archive="$root/artifacts/graice_author_matched_results_v001.tar.gz"
if [ ! -f "$archive" ]; then
  files=(runs config.json source_manifest.json code provenance logs job_id.txt submissions.tsv interface_check.json runtime.json status.json report.json selection.json predictions.npz comparison regional_completion.json requirements_installed_v002.txt)
  for name in "${files[@]}"; do test -e "$root/$name"; done
  for name in setup_env_v001.sh setup_env_v002.sh env_status_v001.txt env_status_v002.txt; do
    if [ -e "$root/$name" ]; then files+=("$name"); fi
  done
  test ! -e "$archive.partial"
  tar -czf "$archive.partial" -C "$root" "${files[@]}"
  mv "$archive.partial" "$archive"
fi
printf 'SLURM_COMPLETION=%s\n' "$state"
printf 'ARCHIVE_SHA256='
sha256sum "$archive" | cut -d ' ' -f 1
printf 'ARTIFACT_BASE64_BEGIN\n'
base64 "$archive"
printf 'ARTIFACT_BASE64_END\n'
