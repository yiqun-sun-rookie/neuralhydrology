#!/usr/bin/env bash
set -euo pipefail
export PYTHONNOUSERSITE=1 PYTHONDONTWRITEBYTECODE=1

/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python -B - <<'PY'
import json
from pathlib import Path
import subprocess

phase = Path('/data1/home/sunyiq/kalmannet_tukf09_scaled_noise_local_selection_remaining_453_20260930_attempt1/canary11')
job_id = '233308'
canaries = (
    ('01052500', 7), ('01031500', 8), ('01162500', 9), ('01022500', 10),
    ('02202600', 11), ('02297310', 12), ('01139000', 13), ('02296500', 15),
    ('02108000', 17), ('04040500', 18), ('01411300', 20),
)


def command(arguments):
    result = subprocess.run(arguments, text=True, capture_output=True, timeout=30)
    return {'exit_code': result.returncode, 'stdout': result.stdout, 'stderr': result.stderr}


def load_json(path):
    if path.is_symlink():
        raise RuntimeError('linked evidence is forbidden: ' + str(path))
    return json.loads(path.read_text(encoding='utf-8')) if path.is_file() else None


if phase.is_symlink() or not phase.is_dir():
    raise SystemExit('isolated canary phase missing or linked')
submission = load_json(phase / 'control/submission.json')
attempt = load_json(phase / 'control/submission_attempt.json')
if (
    submission is None
    or attempt is None
    or submission.get('status') != 'CANARY11_ARRAY_SUBMISSION_CONFIRMED_NOT_MODEL_COMPLETION'
    or attempt.get('status') != 'CANARY11_ARRAY_SUBMISSION_CONSUMED_OUTCOME_UNKNOWN_UNTIL_RECEIPT'
    or submission.get('job_id') != job_id
    or submission.get('scheduler_submission_count') != 1
    or attempt.get('maximum_scheduler_submissions') != 1
):
    raise SystemExit('unique submission evidence changed')

rows = []
for index, (basin, dimension) in enumerate(canaries):
    root = phase / ('basin_' + basin)
    control = root / 'control'
    run = root / 'run'
    model = run / 'model'
    progress = run / 'progress'
    if root.is_symlink() or control.is_symlink() or not control.is_dir():
        raise SystemExit('basin evidence root missing or linked: ' + basin)
    gate = load_json(control / 'canary_gate.json')
    started = load_json(model / 'started.json')
    progress_complete = load_json(progress / 'progress_complete.json')
    summary = load_json(model / 'summary.json')
    progress_path = progress / 'progress.jsonl'
    events = []
    incomplete_tail = False
    if progress_path.is_symlink():
        raise SystemExit('linked progress evidence is forbidden: ' + basin)
    if progress_path.is_file():
        raw = progress_path.read_bytes()
        incomplete_tail = bool(raw) and not raw.endswith(b'\n')
        complete_lines = raw.splitlines()[:-1] if incomplete_tail else raw.splitlines()
        for line in complete_lines:
            events.append(json.loads(line))
    checkpoint_events = sum(event.get('type') == 'checkpoint' for event in events)
    update_events = sum(event.get('type') == 'gradient_update' for event in events)
    result_files = {
        name: {
            'exists': path.is_file() and not path.is_symlink(),
            'size_bytes': path.stat().st_size if path.is_file() and not path.is_symlink() else None,
        }
        for name, path in (
            ('history.npz', model / 'history.npz'),
            ('summary.json', model / 'summary.json'),
            ('manifest.final.sha256.json', model / 'manifest.final.sha256.json'),
        )
    }
    rows.append({
        'array_index': index,
        'basin_id': basin,
        'state_dimension': dimension,
        'control_files': sorted(path.name for path in control.iterdir()),
        'gate_passed': gate is not None and gate.get('status') == 'CANARY11_NODE_GATE_PASSED_MODEL_MAY_START' and gate.get('total_tests') == 102,
        'model_started': started is not None and started.get('status') == 'CANARY11_MODEL_STARTED',
        'progress_event_lines': len(events),
        'checkpoints': checkpoint_events,
        'gradient_updates': update_events,
        'progress_incomplete_tail': incomplete_tail,
        'progress_complete': progress_complete is not None and progress_complete.get('status') == 'CANARY11_PROGRESS_COMPLETE',
        'summary_complete': summary is not None and summary.get('status') == 'CANARY11_SINGLE_BASIN_COMPLETE_NOT_FORMAL_EVALUATION',
        'result_files': result_files,
        'evaluation_array_reads': 0 if summary is None else summary.get('evaluation_array_reads'),
    })

errors = []
for path in sorted((phase / 'logs').glob('*.err')):
    if path.is_symlink():
        raise SystemExit('linked scheduler log is forbidden')
    if path.stat().st_size:
        errors.append({'name': path.name, 'size_bytes': path.stat().st_size, 'tail': path.read_text(encoding='utf-8', errors='replace')[-2000:]})

squeue = command(['squeue', '-j', job_id, '-h', '-o', '%i|%j|%T|%R|%M'])
sacct = command([
    'sacct', '-j', job_id, '--noheader', '--parsable2',
    '--format=JobIDRaw,JobName,State,ExitCode,Elapsed,AllocCPUS,MaxRSS',
])
report = {
    'status': 'CANARY11_READ_ONLY_STATUS_NOT_TERMINAL_AUDIT',
    'job_id': job_id,
    'scheduler_submission_count': 1,
    'squeue': squeue,
    'sacct': sacct,
    'canaries': rows,
    'counts': {
        'basins': len(rows),
        'node_gates_passed': sum(row['gate_passed'] for row in rows),
        'models_started': sum(row['model_started'] for row in rows),
        'progress_complete': sum(row['progress_complete'] for row in rows),
        'summaries_complete': sum(row['summary_complete'] for row in rows),
        'total_checkpoints': sum(row['checkpoints'] for row in rows),
        'total_gradient_updates': sum(row['gradient_updates'] for row in rows),
        'complete_result_triplets': sum(all(item['exists'] for item in row['result_files'].values()) for row in rows),
        'nonempty_error_logs': len(errors),
    },
    'nonempty_error_logs': errors,
    'evaluation_array_reads': 0,
    'formal_evaluation_performed': False,
    'transfer_library_constructed': False,
    'scheduler_mutation_performed': False,
    'model_execution_started_by_query': False,
}
print('CANARY11_READ_ONLY_STATUS ' + json.dumps(report, sort_keys=True, separators=(',', ':')))
PY
