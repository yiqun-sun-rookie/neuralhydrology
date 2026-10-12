#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
"""Bound only the existing, pending, one-epoch diagnostic; never submit jobs."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

root = Path('/data1/home/sunyiq/zhenjiang_gradient_diagnostic_20261011_001')
spec = json.loads((root / 'diagnostic_spec.json').read_text())
job = str(json.loads((root / 'records/scheduler_jobs.json').read_text())['gradient_diagnostic'])
assert job.isdigit()
source = Path(spec['source_root']) if 'source_root' in spec else Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_recovery_001')
source_jobs = json.loads((source / 'records/scheduler_jobs.json').read_text())
source_job = str(source_jobs[spec['case']])
assert source_job.isdigit() and source_job != job
assert spec['replayed_epoch'] == 41 and spec['expected_saved_epoch'] == 40
assert spec['formal_checkpoint_write_allowed'] is False
assert spec['evaluation_values_read'] is False and spec['scientific_rules_changed'] is False
assert spec['admitted_training_phase_only'] == 'tuning_train'

def run(command):
    result = subprocess.run(command, capture_output=True, text=True, timeout=45)
    return {'command': command, 'returncode': result.returncode,
            'stdout': result.stdout, 'stderr': result.stderr}

def fields(result):
    assert result['returncode'] == 0, result
    return dict(re.findall(r'(\w+)=([^\s]+)', result['stdout']))

def save_new(path, value):
    with path.open('x', encoding='utf-8') as stream:
        json.dump(value, stream, ensure_ascii=False, sort_keys=True, indent=2)
        stream.write('\n')
        stream.flush()
        os.fsync(stream.fileno())

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

script = root / 'hpc/gradient_diagnostic.slurm'
replay = root / 'hpc/replay_gradient_diagnostic_20261011.py'
expected = {
    script: '8c6c90074458b2f4a873b4e32dec193dc88a367809a559ad0374f645d42c71fc',
    replay: '7b39e92b45e4f41ec5cb9078dbd885bd2df53e0dd3eaa73cfa1b3f0099d94421',
}
assert all(sha(path) == digest for path, digest in expected.items())
before = run(['scontrol', 'show', 'job', '-o', job])
before_fields = fields(before)
guard = run(['sacct', '-n', '-X', '-j', source_job, '--format=JobID,State,ExitCode', '-P'])
assert guard['returncode'] == 0
assert guard['stdout'].strip().split('|')[:3] == [source_job, 'FAILED', '1:0']
queue = run(['squeue', '-h', '-u', 'sunyiq', '-o', '%i|%j|%T|%R|%N'])
assert queue['returncode'] == 0
rows = [row.split('|') for row in queue['stdout'].splitlines()]
assert not any(row[0] == source_job for row in rows)
assert sum(row[0] == job for row in rows) == 1
assert sum(row[1] == spec['job_name'] for row in rows) == 1
expected_fields = {
    'JobId': job, 'JobName': spec['job_name'], 'UserId': 'sunyiq(2272)',
    'Partition': 'hgpu2p', 'NumCPUs': '4', 'NumTasks': '1',
    'TresPerNode': 'gpu:1', 'ExcNodeList': 'ngu[002,011]',
    'Dependency': '(null)', 'WorkDir': str(root), 'Command': str(script),
    'StdOut': str(root / 'logs' / (spec['job_name'] + '_' + job + '.out')),
    'StdErr': str(root / 'logs' / (spec['job_name'] + '_' + job + '.out')),
}
assert all(before_fields.get(key) == value for key, value in expected_fields.items())
attempt = root / 'records/diagnostic_time_limit_adjustment_20261012_001.attempt.json'
response = root / 'records/diagnostic_time_limit_adjustment_20261012_001.response.json'
record = {
    'schema': 'registered_one_epoch_diagnostic_resource_adjustment_v1',
    'checked_at_beijing': datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),
    'job_id': job, 'source_failed_job': source_job, 'source_root': str(source),
    'diagnostic_root': str(root), 'before': before, 'source_failure_guard': guard,
    'duplicate_guard': queue, 'script_and_replay_sha256': {str(p): h for p, h in expected.items()},
    'new_time_limit_minutes': 720, 'new_jobs_submitted': False,
    'formal_training_budget_changed': False, 'scientific_rules_changed': False,
    'evaluation_values_read': False,
    'reason': 'one-epoch isolated numerical diagnostic has no formal training writes; bound its scheduler reservation without resubmission',
    'time_limit_is_not_a_runtime_estimate': True,
    'shorter_reservation_improving_backfill_is_an_inference_not_a_guarantee': True,
}
if attempt.exists():
    record['status'] = 'prior_exclusive_attempt_exists_no_repeat'
    record['prior_attempt'] = json.loads(attempt.read_text())
    if response.exists():
        record['prior_response'] = json.loads(response.read_text())
elif before_fields.get('JobState') != 'PENDING':
    record['status'] = 'diagnostic_already_started_no_limit_change'
elif before_fields.get('TimeLimit') != 'UNLIMITED':
    record['status'] = 'already_bounded_no_limit_change'
else:
    assert before_fields.get('Reason') == 'Priority'
    assert before_fields.get('RunTime') == '00:00:00' and before_fields.get('NodeList') == '(null)'
    save_new(attempt, record)
    update = run(['scontrol', 'update', 'JobId=' + job, 'TimeLimit=720'])
    after = run(['scontrol', 'show', 'job', '-o', job])
    after_fields = fields(after)
    assert all(after_fields.get(key) == value for key, value in expected_fields.items())
    assert all(sha(path) == digest for path, digest in expected.items())
    record.update(update=update, after=after, scheduler_state_after=after_fields.get('JobState'),
                  time_limit_after=after_fields.get('TimeLimit'),
                  script_and_replay_unchanged=True)
    if after_fields.get('TimeLimit') == '12:00:00':
        record['status'] = 'existing_diagnostic_time_limit_verified_12_hours'
    else:
        record['status'] = 'time_limit_adjustment_not_confirmed_do_not_repeat'
    save_new(response, record)
print(json.dumps(record, sort_keys=True))
PY
