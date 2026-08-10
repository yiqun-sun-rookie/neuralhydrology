#!/bin/bash
# ID29 seq=173: read-only 30-minute matrix and replacement-audit refresh.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
MAIN_JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315
REPAIR_JOBS=202510,202511
DIAGNOSTIC_ROOT="$ROOT/results/29_nearing2022_da_ar/formal_closure/diagnostics"
DATA_V2="$DIAGNOSTIC_ROOT/author_v13_training_data_port_all531_v2"
MASK_V2="$DIAGNOSTIC_ROOT/author_v13_warmup_isolation_all531_v2"
SUBMISSION_RECEIPT="$DIAGNOSTIC_ROOT/warmup_target_repair_submission_01.json"

echo "=== SNAPSHOT TIME ==="
date --iso-8601=seconds

source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"

echo "=== REGISTERED COMPLETE-ROLE COUNTS ==="
python - <<'PY'
from collections import Counter
import json
from pathlib import Path
import sys

import pandas as pd

root = Path('/data1/home/sunyiq/nearing2022_da')
scripts = root / 'src/29_nearing2022_da_ar/scripts'
sys.path.insert(0, str(scripts))
from aggregate_registered_results import _registered_run
from prepare_evaluation_run import resolve_source_run
from verify_registered_closure import _metrics_path

registry = root / 'src/29_nearing2022_da_ar/registry'
training = pd.read_csv(registry / 'experiment_registry.csv', keep_default_na=False, dtype=str)
evaluations = pd.read_csv(registry / 'evaluation_registry.csv', keep_default_na=False, dtype=str)
hyper = pd.read_csv(registry / 'assimilation_hyperparameter_registry.csv', keep_default_na=False, dtype=str)


def complete(paths):
    return all(path.is_file() for path in paths)


training_done = Counter()
for _, row in training.iterrows():
    try:
        run = resolve_source_run(root, training, row['exp_id'])
        if complete([
            run / 'config.yml', run / 'model_epoch030.pt', run / 'output.log',
            run / 'train_data/train_data_scaler.yml',
        ]):
            training_done[row['family']] += 1
    except (FileNotFoundError, KeyError, ValueError):
        pass

evaluation_done = Counter()
for _, row in evaluations.iterrows():
    try:
        run = _registered_run(root, training, row)
        result = run / row['result_file']
        reference_run = resolve_source_run(root, training, row['reference_exp_id'])
        reference = reference_run / 'test/model_epoch030/test_results.p'
        if complete([
            run / 'config.yml', run / 'model_epoch030.pt', run / 'output.log', result,
            _metrics_path(result), reference, _metrics_path(reference),
        ]):
            evaluation_done[row['family']] += 1
    except (FileNotFoundError, KeyError, ValueError):
        pass

hyper_done = 0
for _, row in hyper.iterrows():
    try:
        run = Path(row['run_dir'])
        run = run if run.is_absolute() else root / run
        result = run / row['result_file']
        reference_run = resolve_source_run(root, training, row['source_exp_id'])
        reference = reference_run / 'test/model_epoch030/test_results.p'
        if complete([
            run / 'config.yml', run / 'model_epoch030.pt', run / 'output.log', result,
            _metrics_path(result), reference, _metrics_path(reference),
        ]):
            hyper_done += 1
    except (FileNotFoundError, KeyError, ValueError):
        pass

print(json.dumps({
    'training_complete': sum(training_done.values()),
    'training_total': len(training),
    'training_by_family': dict(sorted(training_done.items())),
    'evaluation_complete': sum(evaluation_done.values()),
    'evaluation_total': len(evaluations),
    'evaluation_by_family': dict(sorted(evaluation_done.items())),
    'hyperparameter_complete': hyper_done,
    'hyperparameter_total': len(hyper),
}, sort_keys=True))
PY

echo "=== LIVE MAIN PROGRESS ==="
python - <<'PY'
import json
from pathlib import Path
import re
import subprocess

parents = '202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315'
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


for job in sorted(running):
    record = subprocess.run(
        ['scontrol', 'show', 'job', '-o', job], check=True, capture_output=True, text=True,
    ).stdout.strip()
    fields = dict(token.split('=', 1) for token in record.split() if '=' in token)
    stdout = Path(fields['StdOut'])
    payload = {
        'job': job, 'name': fields['JobName'], 'runtime': fields['RunTime'],
        'time_limit': fields['TimeLimit'], 'stdout_exists': stdout.is_file(),
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
            payload.update({
                'epoch': epoch, 'epoch_step': step, 'epoch_total_steps': total,
                'thirty_epoch_fraction': round(fraction, 6),
                'projected_total_hours': round(projected / 3600, 2),
                'projected_slack_hours': round((limit - projected) / 3600, 2),
                'time_limit_risk': projected > limit,
            })
        elif generic:
            percent, step, total = map(int, generic[-1].groups())
            payload.update({'percent': percent, 'step': step, 'total': total})
    print(json.dumps(payload, sort_keys=True))
PY

echo "=== REPLACEMENT AUDIT STATES ==="
sacct -n -X -P -j "$REPAIR_JOBS" --format=JobID,JobName,State,ExitCode,Elapsed,Start,End,NodeList
squeue -h -j "$REPAIR_JOBS" -o '%i|%j|%T|%M|%R|%E' | sort

echo "=== REPLACEMENT RECEIPT AND OUTPUTS ==="
test -f "$SUBMISSION_RECEIPT"
test "$(sha256sum "$SUBMISSION_RECEIPT" | awk '{print $1}')" = \
  18e6aeeee3321427d0f851d68d2cbbfb02f8d13e477f6f96dd5f22eed1d4d2a1
sha256sum "$SUBMISSION_RECEIPT"
find "$DIAGNOSTIC_ROOT" -maxdepth 1 -mindepth 1 \
  \( -name 'author_v13_training_data_port_all531_v2*' -o -name 'author_v13_warmup_isolation_all531_v2*' \) \
  -printf '%f|%y\n' | sort

for final in "$DATA_V2" "$MASK_V2"; do
  if test -d "$final"; then
    test -f "$final/audit.json"
    test -f "$final/diagnostic_receipt.json"
    sha256sum "$final/audit.json" "$final/diagnostic_receipt.json"
    cat "$final/audit.json"
    cat "$final/diagnostic_receipt.json"
  else
    echo "absent|$final"
  fi
done

echo "=== MAIN JOB STATES AND FAILURE GATE ==="
squeue -h -j "$MAIN_JOBS" -o '%i|%T|%M|%l|%R|%j' | sort
MAIN_FAILURES=$(sacct -n -X -P -j "$MAIN_JOBS" --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' '$3 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/')
printf '%s\n' "$MAIN_FAILURES"
test -z "$MAIN_FAILURES"

echo "=== FROZEN SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = '202293|PENDING|JobHeldUser|N22-manifest'
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
echo "registered_matrix_modified=false"
