#!/bin/bash
# ID29 seq=121: audit hyperparameter dependency, source readiness, and measured assimilation throughput; read-only.
set -eo pipefail

ROOT=/data1/home/sunyiq/nearing2022_da
JOBS=202214,202215,202216,202222,202226,202227,202228,202229,202230,202238,202293,202294,202315

echo "=== HYPERPARAMETER JOB CONTRACT ==="
source ~/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
cd "$ROOT"
export PYTHONPATH="$ROOT${PYTHONPATH:+:$PYTHONPATH}"
python - <<'PY'
import json
from pathlib import Path
import re
import subprocess
import sys

import pandas as pd

root = Path('/data1/home/sunyiq/nearing2022_da')
scripts = root / 'src/29_nearing2022_da_ar/scripts'
sys.path.insert(0, str(scripts))
from prepare_evaluation_run import resolve_source_run

def job_record(job):
    return subprocess.run(
        ['scontrol', 'show', 'job', '-dd', '-o', str(job)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()

record = job_record(202228)
fields = {}
for token in record.split():
    if '=' in token:
        key, value = token.split('=', 1)
        fields[key] = value

registry_root = root / 'src/29_nearing2022_da_ar/registry'
training = pd.read_csv(registry_root / 'experiment_registry.csv', keep_default_na=False, dtype=str)
evaluations = pd.read_csv(registry_root / 'evaluation_registry.csv', keep_default_na=False, dtype=str)
hyper = pd.read_csv(registry_root / 'assimilation_hyperparameter_registry.csv', keep_default_na=False, dtype=str)

sources = sorted(hyper['source_exp_id'].unique())
assert sources == ['N22-BS-SIM-F00-S0']
source_row = training.loc[training['exp_id'] == sources[0]].iloc[0]
source_run = resolve_source_run(root, training, sources[0])
required = [source_run / 'config.yml', source_run / 'model_epoch030.pt', source_run / 'output.log',
            source_run / 'train_data/train_data_scaler.yml']
source_ready = all(path.is_file() for path in required)

print(json.dumps({
    'job_id': 202228,
    'job_state': fields.get('JobState'),
    'dependency': fields.get('Dependency'),
    'array_task_id': fields.get('ArrayTaskId'),
    'array_task_throttle': fields.get('ArrayTaskThrottle'),
    'time_limit': fields.get('TimeLimit'),
    'cpus_per_task': fields.get('CPUs/Task'),
    'tres_per_node': fields.get('TresPerNode'),
    'registry_rows': len(hyper),
    'unique_source_exp_ids': sources,
    'source_slurm_job_id': source_row['slurm_job_id'],
    'source_run': str(source_run),
    'source_complete_roles': source_ready,
    'source_required_files': [str(path) for path in required],
    'held_out_basin_files': sorted(hyper['test_basin_file'].unique()),
}, sort_keys=True))

records = subprocess.run(
    ['sacct', '-n', '-P', '-j', '202222', '--format=JobID,State,ExitCode,ElapsedRaw,Elapsed'],
    check=True,
    capture_output=True,
    text=True,
).stdout.splitlines()
accounting = {}
for raw in records:
    parts = raw.split('|')
    if len(parts) >= 5 and re.fullmatch(r'202222_\d+', parts[0]):
        accounting[parts[0]] = {
            'state': parts[1], 'exit_code': parts[2], 'elapsed_seconds': int(parts[3]), 'elapsed': parts[4]
        }

measured = []
for _, row in evaluations.loc[evaluations['slurm_job_id'].str.startswith('202222_', na=False)].iterrows():
    item = accounting.get(row['slurm_job_id'])
    if item and item['state'] == 'COMPLETED':
        measured.append({
            'slurm_task': row['slurm_job_id'],
            'eval_id': row['eval_id'],
            'family': row['family'],
            'evaluation_mode': row['evaluation_mode'],
            'lead': row['lead'],
            'test_holdout': row['test_holdout'],
            **item,
        })
print(json.dumps({'completed_202222_tasks': measured}, sort_keys=True))

assimilation_seconds = sorted(item['elapsed_seconds'] for item in measured if item['evaluation_mode'] == 'assimilation')
if assimilation_seconds:
    print(json.dumps({
        'measured_full_531_basin_assimilation_tasks': len(assimilation_seconds),
        'min_seconds': assimilation_seconds[0],
        'median_seconds': assimilation_seconds[len(assimilation_seconds) // 2],
        'max_seconds': assimilation_seconds[-1],
        'hyperparameter_basin_count': sum(1 for line in (root / hyper.iloc[0]['test_basin_file']).read_text().splitlines() if line.strip()),
        'throughput_note': 'The hyperparameter rows vary assimilation epochs and cannot be timed by basin-count scaling alone.',
    }, sort_keys=True))
PY

echo "=== CURRENT ID29 GPU LOAD ==="
squeue -h -j "$JOBS" -t RUNNING -o '%i|%j|%b|%M|%R' | sort

echo "=== ACTIVE FAILURE STATES ==="
FAILURES=$(sacct -n -P -j "$JOBS" --format=JobIDRaw,JobName,State,ExitCode | \
  awk -F'|' '$1 !~ /\./ && $3 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE)/')
printf '%s\n' "$FAILURES"
test -z "$FAILURES"

echo "=== SAFETY BOUNDARY ==="
test "$(squeue -h -j 202293 -o '%i|%T|%r|%j')" = "202293|PENDING|JobHeldUser|N22-manifest"
test "$(squeue -h -j 202315 -o '%i|%T|%r|%j')" = "202315|PENDING|Dependency|N22-gate"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_gate.json"
test ! -e "$ROOT/closure_20260810/aggregation/final_reproduction_differences.csv"
