#!/usr/bin/env bash
set -euo pipefail

phase='/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_rehearsal_20260922/full_budget_recovery_v2r7_20260927'
job='228078'
basin='01047000'

printf '=== EXACT NEW JOB STATUS ===\n'
date -u '+UTC=%Y-%m-%dT%H:%M:%SZ'
accounting="$(sacct -X -j "$job" -P -n --format=JobID,JobName,Partition,AllocCPUS,ReqCPUS,AllocTRES,ReqTRES,ElapsedRaw,State,ExitCode)"
if [[ -n "$accounting" ]]; then printf '%s\n' "$accounting"; else printf 'NO_ACCOUNTING_ROW\n'; fi
queue="$(squeue -j "$job" -h -o '%i|%j|%T|%P|%R')"
if [[ -n "$queue" ]]; then printf '%s\n' "$queue"; else printf 'NOT_IN_ACTIVE_QUEUE\n'; fi

printf '=== EXCLUSIVE NEW PHASE ===\n'
if [[ ! -d "$phase" || -L "$phase" || "$(realpath -e "$phase")" != "$phase" ]]; then
  printf 'NEW_PHASE_DIRECTORY_ABSENT_OR_LINKED\n'
  exit 1
fi
printf 'NEW_PHASE_DIRECTORY_PRESENT\n'
if [[ -e "$phase/basin_01142500" || -L "$phase/basin_01142500" ]]; then printf 'SECOND_BASIN_PATH_PRESENT\n'; else printf 'SECOND_BASIN_PATH_ABSENT\n'; fi
for relative in \
  control/deployed.json \
  basin_01047000/control/submission_attempt.json \
  basin_01047000/control/submission.json \
  basin_01047000/control/job_gate.json \
  basin_01047000/run/supervisor.json \
  basin_01047000/run/model/started.json \
  basin_01047000/run/model/manifest.final.sha256.json; do
  target="$phase/$relative"
  if [[ -f "$target" && ! -L "$target" ]]; then
    printf 'FILE %s\n' "$relative"
    sha256sum "$target"
    if [[ "$relative" == 'basin_01047000/control/submission.json' ]]; then
      /data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - "$target" <<'PY'
import json
from pathlib import Path
import re
import sys

record = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
stdout = record.get('stdout', '')
job_lines = re.findall(r'(?m)^Submitted batch job ([0-9]+)$', stdout)
print('SUBMISSION_BASIN=' + str(record.get('basin_id')))
print('SUBMISSION_ARCHIVE_SHA256=' + str(record.get('archive_sha256')))
print('SUBMISSION_MANIFEST_SHA256=' + str(record.get('bundle_manifest_sha256')))
print('SUBMISSION_RETURNCODE=' + str(record.get('returncode')))
print('SUBMISSION_JOB_IDS=' + ','.join(job_lines))
PY
    fi
  else
    printf 'MISSING %s\n' "$relative"
  fi
done

printf '=== EXACT JOB LOG TAILS ===\n'
for suffix in out err; do
  target="$phase/logs/job-$job.$suffix"
  if [[ -f "$target" && ! -L "$target" ]]; then
    printf 'LOG %s\n' "$suffix"
    tail -n 30 "$target"
  else
    printf 'MISSING job-%s.%s\n' "$job" "$suffix"
  fi
done
printf 'READ_ONLY_EXACT_JOB_STATUS_COMPLETE\n'
