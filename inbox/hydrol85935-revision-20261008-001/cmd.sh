#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
job=$(cat "$ROOT/control/backend_v002_job_id")
case "$job" in *[!0-9]*|'') exit 3;; esac
date -Is
sacct -j "$job" --format=JobIDRaw,State,ExitCode,Elapsed,MaxRSS -P
if squeue -j "$job" -o '%.18i %.12P %.30j %.10T %.12M %.30R'; then :; else printf 'Job retired; use accounting above\n'; fi
for p in "$ROOT/logs/backend-$job.out" "$ROOT/logs/backend-$job.err"; do
 if [ -f "$p" ]; then printf '%s\n' "$p"; tail -n 40 "$p"; fi
done
