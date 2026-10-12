#!/usr/bin/env bash
set -eo pipefail
root=/data1/home/sunyiq/id25_regional_daily_storage_20261012_001
[ "$(cat "$root/CAMPAIGN_OWNER")" = 'id25-regional-daily-20261012' ] || exit 1
jobid=$(cat "$root/job_id.txt")
[[ "$jobid" =~ ^[0-9]+$ ]] || exit 1
sacct -j "$jobid" --format=JobID,State,ExitCode,Elapsed,NodeList -P -n
run="$root/runs/RDS01_s20261012"
if [ ! -f "$run/report.json" ]; then
 printf 'NOT_FINISHED\n'
 if [ -f "$run/status.json" ]; then cat "$run/status.json"; fi
 exit 0
fi
for file in best.pt last.pt report.json daily_states.npz monthly_predictions.npz metrics.jsonl status.json; do
 [ -s "$run/$file" ] || { printf 'MISSING_ARTIFACT=%s\n' "$file"; exit 1; }
done
archive="$root/results_export_v001.tar.gz"
if [ ! -f "$archive" ]; then
 tar -czf "$archive.tmp" -C "$root" \
  runs/RDS01_s20261012/best.pt runs/RDS01_s20261012/last.pt \
  runs/RDS01_s20261012/report.json runs/RDS01_s20261012/daily_states.npz \
  runs/RDS01_s20261012/monthly_predictions.npz runs/RDS01_s20261012/metrics.jsonl \
  runs/RDS01_s20261012/status.json config.json inputs/transforms.json \
  inputs/input_receipt.json submissions.tsv "logs/rds01-$jobid.out" "logs/rds01-$jobid.err"
 mv "$archive.tmp" "$archive"
fi
printf 'ARCHIVE_SHA256='
sha256sum "$archive" | awk '{print $1}'
printf 'ARTIFACT_BASE64_BEGIN\n'
base64 "$archive"
printf 'ARTIFACT_BASE64_END\n'
