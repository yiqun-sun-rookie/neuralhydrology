#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
job=$(cat "$ROOT/control/preflight_v001_job_id")
case "$job" in *[!0-9]*|'') echo INVALID_OWN_JOB_ID; exit 3;; esac
date -Is
printf '=== own preflight status ===\n'
squeue -j "$job" -o '%.18i %.14P %.35j %.10T %.12M %.8C %.20b %.30R'
sacct -j "$job" --format=JobIDRaw,JobName,State,ExitCode,Elapsed,AllocCPUS,MaxRSS -P
if squeue -j "$job" --start; then :; else printf 'Start forecast unavailable\n'; fi
printf '=== own output ===\n'
for p in "$ROOT/logs/preflight-$job.out" "$ROOT/logs/preflight-$job.err" "$ROOT/logs/data_identity-$job.txt"; do
  if [ -f "$p" ]; then printf '%s\n' "$p"; tail -n 35 "$p"; fi
done
for p in "$ROOT/preflight/v001/preflight/original_s100_01022500/report.json" "$ROOT/preflight/v001/control/preflight_failure.json"; do
  if [ -f "$p" ]; then printf '%s\n' "$p"; cat "$p"; fi
done
printf '=== current resources ===\n'
sinfo -p hgpu2p,hgpu4,hgpu8 -N -O NodeList:20,Partition:12,StateLong:16,CPUsState:24,GresUsed:40
