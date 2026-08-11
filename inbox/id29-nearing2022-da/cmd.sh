#!/bin/bash
# ID29 seq=196: read-only live progress, walltime-risk, and replacement-state audit.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
MAIN_JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238

echo "=== SNAPSHOT TIME ==="
date --iso-8601=seconds

echo "=== LIVE RUNNING PROGRESS AND WALLTIME PROJECTION ==="
python - "$MAIN_JOBS" <<'PY'
import json
from pathlib import Path
import re
import subprocess
import sys

parents = sys.argv[1]
running = subprocess.run(
    ['squeue', '-h', '-j', parents, '-t', 'RUNNING', '-o', '%i'],
    check=True, capture_output=True, text=True,
).stdout.split()
ansi = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')
epoch_pattern = re.compile(r'# Epoch\s+(\d+):\s*(\d+)%\|.*?\|\s*(\d+)/(\d+)')
generic_pattern = re.compile(r'(?<!Epoch\s)(\d+)%\|.*?\|\s*(\d+)/(\d+)')


def seconds(value):
    days = 0
    if '-' in value:
        day_text, value = value.split('-', 1)
        days = int(day_text)
    fields = [int(item) for item in value.split(':')]
    if len(fields) == 3:
        hours, minutes, secs = fields
    else:
        hours, minutes, secs = 0, fields[0], fields[1]
    return days * 86400 + hours * 3600 + minutes * 60 + secs


risk_jobs = []
for job in sorted(running):
    record = subprocess.run(
        ['scontrol', 'show', 'job', '-o', job], check=True, capture_output=True, text=True,
    ).stdout.strip()
    fields = dict(token.split('=', 1) for token in record.split() if '=' in token)
    stdout = Path(fields['StdOut'])
    payload = {
        'job': job,
        'name': fields['JobName'],
        'runtime': fields['RunTime'],
        'time_limit': fields['TimeLimit'],
        'stdout_exists': stdout.is_file(),
    }
    if stdout.is_file():
        size = stdout.stat().st_size
        with stdout.open('rb') as handle:
            handle.seek(max(0, size - 4 * 1024 * 1024))
            tail = ansi.sub('', handle.read().decode('utf-8', errors='replace')).replace('\r', '\n')
        epochs = list(epoch_pattern.finditer(tail))
        generic = list(generic_pattern.finditer(tail))
        payload['stdout_bytes'] = size
        if epochs:
            epoch, _, step, total = map(int, epochs[-1].groups())
            fraction = ((epoch - 1) + step / total) / 30
            projected = seconds(fields['RunTime']) / fraction if fraction > 0 else None
            limit = seconds(fields['TimeLimit'])
            risk = projected > limit
            payload.update({
                'epoch': epoch,
                'epoch_step': step,
                'epoch_total_steps': total,
                'thirty_epoch_fraction': round(fraction, 6),
                'projected_total_hours': round(projected / 3600, 2),
                'projected_slack_hours': round((limit - projected) / 3600, 2),
                'time_limit_risk': risk,
            })
            if risk:
                risk_jobs.append(job)
        elif generic:
            percent, step, total = map(int, generic[-1].groups())
            payload.update({'percent': percent, 'step': step, 'total': total})
    print(json.dumps(payload, sort_keys=True))
print(json.dumps({'time_limit_risk_jobs': sorted(risk_jobs), 'running_jobs': len(running)}, sort_keys=True))
PY

echo "=== MAIN AND REPLACEMENT STATES ==="
sacct -n -X -P -j "$MAIN_JOBS",202510,202511 \
  --format=JobIDRaw,JobName,State,ExitCode,Elapsed,Start,End,NodeList,Reason
squeue -h -j 202510,202511 -o '%i|%j|%T|%M|%R|%E' | sort

echo "=== FAILURE SUMMARY ==="
sacct -n -X -P -j "$MAIN_JOBS",202510,202511 --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' '$3 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/'

echo "=== FROZEN SAFETY BOUNDARY ==="
PAIR_PRESENT=0
for relative in \
  src/29_nearing2022_da_ar/scripts/prepare_warmup_target_pair.py \
  src/29_nearing2022_da_ar/scripts/analyze_warmup_target_pair.py \
  src/29_nearing2022_da_ar/hpc/run_warmup_target_pair.slurm \
  src/29_nearing2022_da_ar/hpc/analyze_warmup_target_pair.slurm \
  test/test_nearing2022_warmup_pair.py; do
  if test -e "$ROOT/$relative"; then PAIR_PRESENT=$((PAIR_PRESENT + 1)); fi
done
echo "paired_training_payload_present=$PAIR_PRESENT"
test "$PAIR_PRESENT" -eq 0
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = '202293|PENDING|JobHeldUser|N22-manifest'
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
echo "pair_training_submitted=false"
echo "registered_matrix_modified=false"
