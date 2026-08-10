#!/bin/bash
# ID29 seq=118: parse bounded log tails and conservatively project training walltime risk; read-only.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315

echo "=== BOUNDED PROGRESS AND WALLTIME PROJECTION ==="
python - <<'PY'
import json
from pathlib import Path
import re
import subprocess

parents = '202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315'
running = subprocess.run(
    ['squeue', '-h', '-j', parents, '-t', 'RUNNING', '-o', '%i'],
    check=True,
    capture_output=True,
    text=True,
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
    elif len(fields) == 2:
        hours, minutes, secs = 0, fields[0], fields[1]
    else:
        raise ValueError(value)
    return days * 86400 + hours * 3600 + minutes * 60 + secs

for job in sorted(running):
    record = subprocess.run(
        ['scontrol', 'show', 'job', '-o', job],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    fields = {}
    for token in record.split():
        if '=' in token:
            key, value = token.split('=', 1)
            fields[key] = value
    stdout = Path(fields['StdOut'])
    size = stdout.stat().st_size
    with stdout.open('rb') as handle:
        handle.seek(max(0, size - 4 * 1024 * 1024))
        text = ansi.sub('', handle.read().decode('utf-8', errors='replace')).replace('\r', '\n')
    epochs = list(epoch_pattern.finditer(text))
    generic = list(generic_pattern.finditer(text))
    payload = {
        'job': job,
        'name': fields['JobName'],
        'runtime': fields['RunTime'],
        'time_limit': fields['TimeLimit'],
        'stdout_bytes': size,
    }
    if epochs:
        match = epochs[-1]
        epoch, percent, step, total = map(int, match.groups())
        fraction = ((epoch - 1) + step / total) / 30
        runtime_seconds = seconds(fields['RunTime'])
        limit_seconds = seconds(fields['TimeLimit'])
        projected_seconds = runtime_seconds / fraction if fraction > 0 else None
        payload.update({
            'epoch': epoch,
            'epoch_step': step,
            'epoch_total_steps': total,
            'thirty_epoch_fraction': round(fraction, 6),
            'conservative_projected_total_hours': round(projected_seconds / 3600, 2),
            'projected_slack_hours': round((limit_seconds - projected_seconds) / 3600, 2),
            'time_limit_risk': projected_seconds > limit_seconds,
        })
    elif generic:
        percent, step, total = map(int, generic[-1].groups())
        payload.update({'last_generic_percent': percent, 'last_generic_step': step, 'last_generic_total': total})
    else:
        lines = [line.strip()[:300] for line in text.splitlines() if line.strip()]
        payload['last_nonempty_line'] = lines[-1] if lines else ''
    print(json.dumps(payload, sort_keys=True))
PY

echo "=== ACTIVE FAILURE STATES ==="
FAILURES=$(sacct -n -P -j "$JOBS" --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' '$1 !~ /\./ && $3 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/')
printf '%s\n' "$FAILURES"
test -z "$FAILURES"

echo "=== CHECKPOINT POLICY ==="
grep -q '^save_weights_every: 1$' "$ROOT/src/29_nearing2022_da_ar/configs/full_reproduction/time_split/autoregression/lead_1_holdout_0.5_seed_0.yml"
grep -q '^epochs: 30$' "$ROOT/src/29_nearing2022_da_ar/configs/full_reproduction/time_split/autoregression/lead_1_holdout_0.5_seed_0.yml"
echo "epoch_checkpoints=every_epoch"
echo "target_epoch=30"

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
