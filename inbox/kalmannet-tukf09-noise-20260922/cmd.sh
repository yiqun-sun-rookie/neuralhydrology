#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1

/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
import hashlib
import json
from pathlib import Path
import subprocess
import xml.etree.ElementTree as ET

phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_local_selection_remaining_453_20260930_attempt1/canary11')
job_id = '233308'
failed = ((4, '02202600'), (5, '02297310'), (6, '01139000'), (8, '02108000'))


def command(arguments):
    result = subprocess.run(arguments, text=True, capture_output=True, timeout=30)
    return {'exit_code': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def text_record(path, tail=6000):
    if path.is_symlink():
        raise RuntimeError('linked evidence is forbidden: ' + str(path))
    if not path.is_file():
        return None
    text = path.read_text(encoding='utf-8', errors='replace')
    return {'size_bytes': path.stat().st_size, 'sha256': digest(path), 'tail': text[-tail:]}


def json_record(path):
    record = text_record(path, tail=12000)
    if record is None:
        return None
    record['value'] = json.loads(path.read_text(encoding='utf-8'))
    record.pop('tail', None)
    return record


def xml_failures(path):
    if path.is_symlink() or not path.is_file():
        return None
    root = ET.parse(path).getroot()
    suites = list(root.iter('testsuite'))
    totals = {
        key: sum(int(suite.attrib.get(key, '0')) for suite in suites)
        for key in ('tests', 'failures', 'errors', 'skipped')
    }
    failures = []
    for case in root.iter('testcase'):
        for child in case:
            if child.tag in ('failure', 'error'):
                failures.append({
                    'classname': case.attrib.get('classname'),
                    'name': case.attrib.get('name'),
                    'kind': child.tag,
                    'message': child.attrib.get('message'),
                    'text_tail': (child.text or '')[-4000:],
                })
    return {'size_bytes': path.stat().st_size, 'sha256': digest(path), 'totals': totals, 'failures': failures}


if phase.is_symlink() or not phase.is_dir():
    raise SystemExit('isolated phase missing or linked')
submission = json.loads((phase / 'control/submission.json').read_text(encoding='utf-8'))
if submission.get('job_id') != job_id or submission.get('scheduler_submission_count') != 1:
    raise SystemExit('unique submission evidence changed')

rows = []
for index, basin in failed:
    root = phase / ('basin_' + basin)
    control = root / 'control'
    run = root / 'run'
    progress = run / 'progress/progress.jsonl'
    checkpoint_count = 0
    update_count = 0
    if progress.is_file() and not progress.is_symlink():
        for line in progress.read_text(encoding='utf-8').splitlines():
            event = json.loads(line)
            checkpoint_count += event.get('type') == 'checkpoint'
            update_count += event.get('type') == 'gradient_update'
    xml = {
        path.name: xml_failures(path)
        for path in sorted(control.glob('*.xml'))
    }
    rows.append({
        'array_index': index,
        'basin_id': basin,
        'control_files': sorted(path.name for path in control.iterdir()) if control.is_dir() else None,
        'checkpoints': checkpoint_count,
        'gradient_updates': update_count,
        'supervisor': json_record(run / 'supervisor.json'),
        'worker_stdout': text_record(run / 'stdout.log'),
        'worker_stderr': text_record(run / 'stderr.log'),
        'scheduler_stdout': text_record(phase / f'logs/task-{job_id}_{index}.out'),
        'scheduler_stderr': text_record(phase / f'logs/task-{job_id}_{index}.err'),
        'test_reports': xml,
        'result_files_present': sorted(
            path.name for path in (run / 'model').iterdir()
        ) if (run / 'model').is_dir() else [],
    })

print('CANARY11_FAILURE_READONLY_DIAGNOSTIC ' + json.dumps({
    'status': 'CANARY11_FAILURE_DIAGNOSTIC_READ_ONLY_NO_RETRY_NO_MUTATION',
    'job_id': job_id,
    'failed_array_indices': [index for index, _ in failed],
    'rows': rows,
    'sacct': command([
        'sacct', '-j', job_id, '--noheader', '--parsable2',
        '--format=JobIDRaw,JobName,State,ExitCode,Elapsed,AllocCPUS,MaxRSS',
    ]),
    'squeue': command(['squeue', '-j', job_id, '-h', '-o', '%i|%j|%T|%R|%M']),
    'scheduler_submission_count': 1,
    'scheduler_mutation_performed': False,
    'automatic_retry_performed': False,
    'model_execution_started_by_query': False,
    'evaluation_array_reads': 0,
    'formal_evaluation_performed': False,
    'later_wave_started': False,
}, sort_keys=True, separators=(',', ':')))
PY
