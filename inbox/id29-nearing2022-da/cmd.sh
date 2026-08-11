#!/bin/bash
# ID29 seq=178: retain target audit and repair the scheduler-record diagnostic.
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

echo "=== SERVER OUTPUT-TARGET AUDIT ==="
python - <<'PY'
import hashlib
import json
from pathlib import Path

import pandas as pd
import yaml

root = Path('/data1/home/sunyiq/nearing2022_da')
registry = root / 'src/29_nearing2022_da_ar/registry'
training_path = registry / 'experiment_registry.csv'
evaluation_path = registry / 'evaluation_registry.csv'
hyper_path = registry / 'assimilation_hyperparameter_registry.csv'
training = pd.read_csv(training_path, keep_default_na=False, dtype=str).set_index('exp_id')
evaluations = pd.read_csv(evaluation_path, keep_default_na=False, dtype=str)
hyper = pd.read_csv(hyper_path, keep_default_na=False, dtype=str)


def file_record(path):
    payload = path.read_bytes()
    return {'path': str(path.relative_to(root)), 'bytes': len(payload), 'sha256': hashlib.sha256(payload).hexdigest()}


literal_dirs = evaluations['run_dir'].astype(str).str.replace('\\', '/', regex=False).tolist()
direct = evaluations[evaluations['family'].isin({'basin_simulation', 'basin_autoregression'})]
source_rows = training.loc[direct['source_exp_id']]
runtime_patterns = []
for row in source_rows.itertuples():
    config = yaml.safe_load((root / row.config_path).read_text(encoding='utf-8'))
    runtime_patterns.append(
        str(config['run_dir']).replace('\\', '/').rstrip('/') + '/' + str(config['experiment_name']) + '_*_ep30'
    )

logical_evaluation_targets = []
for row in evaluations.itertuples():
    if row.family in {'basin_simulation', 'basin_autoregression'}:
        value = str(training.loc[row.source_exp_id, 'run_dir'])
    else:
        value = str(row.run_dir)
    logical_evaluation_targets.append(value.replace('\\', '/'))
logical_all_targets = logical_evaluation_targets + hyper['run_dir'].astype(str).str.replace('\\', '/', regex=False).tolist()

payload = {
    'registries': [file_record(training_path), file_record(evaluation_path), file_record(hyper_path)],
    'training_rows': len(training),
    'training_unique_registered_run_dirs': training['run_dir'].nunique(),
    'evaluation_rows': len(evaluations),
    'evaluation_literal_unique_run_dirs': len(set(literal_dirs)),
    'evaluation_literal_duplicate_groups': sum(count > 1 for count in pd.Series(literal_dirs).value_counts()),
    'direct_basin_rows': len(direct),
    'direct_unique_source_exp_ids': direct['source_exp_id'].nunique(),
    'direct_unique_source_config_paths': source_rows['config_path'].nunique(),
    'direct_unique_registered_source_run_dirs': source_rows['run_dir'].nunique(),
    'direct_unique_runtime_patterns': len(set(runtime_patterns)),
    'resolved_evaluation_targets': len(logical_evaluation_targets),
    'resolved_unique_evaluation_targets': len(set(logical_evaluation_targets)),
    'resolved_casefold_unique_evaluation_targets': len({item.casefold() for item in logical_evaluation_targets}),
    'evaluation_plus_hyperparameter_targets': len(logical_all_targets),
    'unique_evaluation_plus_hyperparameter_targets': len(set(logical_all_targets)),
    'casefold_unique_evaluation_plus_hyperparameter_targets': len({item.casefold() for item in logical_all_targets}),
}
assert payload['training_rows'] == payload['training_unique_registered_run_dirs'] == 46
assert payload['evaluation_rows'] == 180
assert payload['evaluation_literal_unique_run_dirs'] == 162
assert payload['evaluation_literal_duplicate_groups'] == 2
assert payload['direct_basin_rows'] == 20
assert payload['direct_unique_source_exp_ids'] == 20
assert payload['direct_unique_source_config_paths'] == 20
assert payload['direct_unique_registered_source_run_dirs'] == 20
assert payload['direct_unique_runtime_patterns'] == 20
assert payload['resolved_evaluation_targets'] == payload['resolved_unique_evaluation_targets'] == 180
assert payload['resolved_casefold_unique_evaluation_targets'] == 180
assert payload['evaluation_plus_hyperparameter_targets'] == payload['unique_evaluation_plus_hyperparameter_targets'] == 840
assert payload['casefold_unique_evaluation_plus_hyperparameter_targets'] == 840
expected_hashes = {
    'src/29_nearing2022_da_ar/registry/experiment_registry.csv':
        '6366d468d671a2af39c2a136b984ca4ee9ebfc1106618b945287bdaabe629d64',
    'src/29_nearing2022_da_ar/registry/evaluation_registry.csv':
        '37b312dbd362399a9771f2233d1e1139ea25d5339d1bbc7a806fa75be30b9215',
    'src/29_nearing2022_da_ar/registry/assimilation_hyperparameter_registry.csv':
        '7cb7f10ce13c41c1b064148b27a707ccaab56f87fa40c289d6833bc7c57b09a7',
}
assert {row['path']: row['sha256'] for row in payload['registries']} == expected_hashes
print(json.dumps(payload, sort_keys=True))
PY

echo "=== DIRECT-EVALUATION JOB PAYLOAD ==="
python - <<'PY'
import hashlib
import json
from pathlib import Path
import subprocess

root = Path('/data1/home/sunyiq/nearing2022_da')
live_script = root / 'src/29_nearing2022_da_ar/hpc/run_registered_evaluation_array.slurm'
live_prepare = root / 'src/29_nearing2022_da_ar/scripts/prepare_evaluation_run.py'
record = subprocess.run(
    ['scontrol', 'show', 'job', '-dd', '-o', '202238'], check=True, capture_output=True, text=True,
).stdout.strip()
record_fields = dict(token.split('=', 1) for token in record.split() if '=' in token)
spooled = subprocess.run(
    ['scontrol', 'write', 'batch_script', '202238', '/dev/stdout'], capture_output=True, text=True,
)
markers = ['prepare_evaluation_run.py', 'SKIPPED_COMPLETED', 'python -m neuralhydrology.nh_run evaluate']
payload = {
    'job_id': '202238',
    'job_command': record_fields.get('Command'),
    'job_work_dir': record_fields.get('WorkDir'),
    'job_dependency': record_fields.get('Dependency'),
    'job_environment': record_fields.get('Environment'),
    'job_record_contains_expected_command': str(live_script) in record,
    'job_record_contains_expected_batch_file': 'basin_direct_evaluation_batch.txt' in record,
    'spooled_script_retrieval_returncode': spooled.returncode,
    'spooled_script_bytes': len(spooled.stdout.encode()),
    'spooled_script_sha256': hashlib.sha256(spooled.stdout.encode()).hexdigest() if spooled.stdout else None,
    'spooled_script_markers': {marker: marker in spooled.stdout for marker in markers},
    'live_script_sha256': hashlib.sha256(live_script.read_bytes()).hexdigest(),
    'live_prepare_sha256': hashlib.sha256(live_prepare.read_bytes()).hexdigest(),
}
assert payload['live_prepare_sha256'] == '6e47896c2b3011fe8e93a561f7545397d5a4ddee70b09b38a520f08530646ccf'
print(json.dumps(payload, sort_keys=True))
if spooled.returncode != 0:
    print(json.dumps({'spooled_script_retrieval_stderr': spooled.stderr.strip()}, sort_keys=True))
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
