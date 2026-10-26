#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'READ_ONLY_PROGRESS'
import json,subprocess,datetime
from pathlib import Path
root=Path('/data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003/sqrt_gru_recovery')
case='explicit_gru__historical_capacity'
slurm=Path('/usr/local/globle/softs/slurm/19.05.4.1/bin')
job=str(json.loads((root/'records/scheduler_jobs.json').read_bytes())[case])
result={'schema':'fixed200-running-progress-diagnosis-v1','at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'case':case,'job_id':job,'read_only':True,'training_tensors_loaded':False}
for key,cmd in [('queue',[str(slurm/'squeue'),'-h','-j',job,'-o','%i|%T|%N']),('sstat',[str(slurm/'sstat'),'-j',job+'.batch','--format=JobID,AveCPU,AveRSS,MaxRSS','-P'])]:
    p=subprocess.run(cmd,capture_output=True,text=True,timeout=60)
    result[key]={'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
rows=[line.split('|') for line in result['queue']['stdout'].splitlines() if line.startswith(job+'|')]
if len(rows)==1 and rows[0][1]=='RUNNING' and ',' not in rows[0][2] and '[' not in rows[0][2]:
    node=rows[0][2]
    try:
        p=subprocess.run(['ssh','-o','BatchMode=yes','-o','ConnectTimeout=10',node,'python','-B','-'],input="import os,json,time\nfrom pathlib import Path\nroot=Path('/data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003/sqrt_gru_recovery')\ncase='explicit_gru__historical_capacity'\ndef snapshot():\n    out={}\n    for p in Path('/proc').iterdir():\n        if not p.name.isdigit():continue\n        try:\n            if p.stat().st_uid!=os.getuid():continue\n            cmd=(p/'cmdline').read_bytes().replace(b'\\0',b' ').decode(errors='replace')\n            if 'run_fixed200_case.py' not in cmd or case not in cmd:continue\n            cwd=(p/'cwd').resolve()\n            if cwd!=root:continue\n            stat=(p/'stat').read_text();fields=stat[stat.rfind(')')+2:].split()\n            io={}\n            try:io={line.split(':')[0]:int(line.split(':')[1]) for line in (p/'io').read_text().splitlines()}\n            except OSError:pass\n            try:wchan=(p/'wchan').read_text().strip()\n            except OSError:wchan=None\n            out[p.name]={'pid':int(p.name),'cwd':str(cwd),'command':cmd.strip(),'state':fields[0],'cpu_ticks':int(fields[11])+int(fields[12]),'wchan':wchan,'io':io,'cgroup':(p/'cgroup').read_text().strip()}\n        except (OSError,ValueError,IndexError):continue\n    return out\nfirst=snapshot();time.sleep(5);second=snapshot();hz=os.sysconf('SC_CLK_TCK')\nfor pid,item in second.items():\n    if pid in first:\n        item['cpu_seconds_delta_5s']=(item['cpu_ticks']-first[pid]['cpu_ticks'])/hz\n        item['io_delta_5s']={k:item['io'].get(k,0)-first[pid]['io'].get(k,0) for k in item['io']}\nprint(json.dumps({'schema':'fixed200-readonly-process-progress-v1','at_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),'sample_seconds':5,'processes':second}))\n",capture_output=True,text=True,timeout=45)
        result['node_process_sample']={'node':node,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
    except subprocess.TimeoutExpired as exc:result['node_process_sample']={'node':node,'timeout_seconds':45}
print(json.dumps(result),flush=True)

READ_ONLY_PROGRESS
set -eo pipefail
python3 - <<'READ_FIXED200_003'
"""Read fixed-200 allocation and committed-epoch evidence without loading tensors.

Example on HPC: python -B read_status.py
Reads the two activated cases, checkpoint heads/events and small record files.
Prints a status snapshot only; no scheduler submission or source writes.
"""
import datetime
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path('/data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003')
SLURM = Path('/usr/local/globle/softs/slurm/19.05.4.1/bin')
CASES = {'legacy_lstm__historical_capacity': 'base',
         'explicit_gru__historical_capacity': 'sqrt_gru_recovery'}


def read(path):
    return json.loads(path.read_bytes())


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def query(command):
    result = subprocess.run(list(map(str, command)), capture_output=True, text=True, timeout=45)
    return {'command': list(map(str, command)), 'returncode': result.returncode,
            'stdout': result.stdout, 'stderr': result.stderr}


report = {'schema': 'fixed200-activation-status-v1', 'root': str(ROOT),
          'checked_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'checkpoints_loaded': False, 'evaluation_values_read': False, 'cases': {}, 'errors': []}
report['queue'] = query([SLURM / 'squeue', '-h', '-u', 'sunyiq', '-o', '%i|%j|%T|%Z|%e|%l|%N|%R'])
for case, variant in CASES.items():
    runtime = ROOT / variant
    record = runtime / 'records' / case
    try:
        initial = read(record / 'activation_starting_members.json')
        job = str(read(runtime / 'records/scheduler_jobs.json')[case])
        auth = read(runtime / 'records/authorization.json')
        row = {'case': case, 'root': str(runtime), 'job_id': job,
               'authorization_sha256': sha(runtime / 'records/authorization.json'),
               'authorization': auth, 'migration_manifest': read(record / 'migration_manifest.json'),
               'data_preparation_complete': read(runtime / 'records/data_preparation_complete.json'),
               'scheduler_script': (runtime / 'hpc/fixed200_case.slurm').read_text(),
               'device_identity': auth['device_identity'], 'members': {},
               'queue_rows': [line for line in report['queue']['stdout'].splitlines() if line.startswith(job + '|')],
               'failure_records': {}}
        allocation = record / ('runtime_binding_' + job + '.json')
        if allocation.exists():
            row['runtime_binding'] = read(allocation)
            assert row['runtime_binding']['device_identity'] == auth['device_identity']
        for name in ('progress.json', 'training_complete.json', 'selected_rates_2021.json',
                     'scheduler_slice_end_' + job + '.json', 'submission_context_repair.confirmed.json'):
            if (record / name).exists():
                row[name] = read(record / name)
        source_outcome = record / 'tune_foundation_group_outcome.json'
        if source_outcome.exists():
            source = read(source_outcome)
            row['tuning_foundation_source'] = {'seal_epochs': source['seal']['epochs'],
                'members': {name: {'epochs': value['epochs'], 'best_epoch': value['best_epoch'],
                           'checkpoint_sha256': value['checkpoint_sha256']}
                            for name, value in source['members'].items()}}
            assert row['tuning_foundation_source']['seal_epochs'] == 400
        for member, start in initial.items():
            folder = runtime / 'runs' / member
            head = read(folder / 'checkpoint_head.json')
            anchor = read(folder / 'continuation_anchor.json')
            assert anchor['initial_checkpoint_sha256'] == start['checkpoint_sha256']
            assert anchor['initial_epochs'] == start['completed_epochs']
            assert sha(folder / 'config.json') == start['config_sha256']
            assert sha(folder / 'migration_source.json') == start['receipt_sha256']
            n = head['completed_epochs']
            assert start['completed_epochs'] <= n <= 200
            item = {'initial_epochs': start['completed_epochs'], 'completed_epochs': n,
                    'new_complete_epochs': n - start['completed_epochs'],
                    'checkpoint_sha256_from_committed_head': head['checkpoint_sha256'],
                    'initial_identity_and_config_preserved': True}
            if n > start['completed_epochs']:
                event = read(folder / 'checkpoint_events' / (head['checkpoint_sha256'][:16] + '.json'))
                assert event['checkpoint_sha256'] == head['checkpoint_sha256']
                assert event['completed_epochs'] == n and event['previous_epochs'] == n - 1
                assert event['anchor_sha256'] == head['anchor_sha256'] == sha(folder / 'continuation_anchor.json')
                item['new_epoch_event'] = event
            if (folder / 'failure.json').exists():
                row['failure_records'][member] = read(folder / 'failure.json')
            row['members'][member] = item
        row['new_complete_member_epochs'] = sum(v['new_complete_epochs'] for v in row['members'].values())
        row['members_with_new_complete_epoch'] = sum(v['new_complete_epochs'] > 0 for v in row['members'].values())
        row['tune_branch_200_complete_members'] = sum(v['completed_epochs'] == 200 for v in row['members'].values())
        row['actual_training_progress_confirmed'] = bool(row.get('runtime_binding') and row['new_complete_member_epochs'] > 0)
        row['logs'] = []
        for path in (runtime / 'logs').glob('*_' + job + '.out'):
            with path.open('rb') as handle:
                handle.seek(max(0, path.stat().st_size - 7000))
                row['logs'].append({'path': str(path), 'tail': handle.read().decode('utf-8', errors='replace')})
        report['cases'][case] = row
    except Exception as error:
        report['errors'].append({'case': case, 'type': type(error).__name__, 'message': str(error)})
jobs = [v['job_id'] for v in report['cases'].values()]
if jobs:
    report['accounting'] = query([SLURM / 'sacct', '-n', '-X', '-j', ','.join(jobs),
                                  '--format=JobID,State,ExitCode,Start,End,NodeList', '-P'])
report['summary'] = {'cases': len(report['cases']),
    'cases_with_new_complete_epoch': sum(v['actual_training_progress_confirmed'] for v in report['cases'].values()),
    'new_complete_member_epochs': sum(v['new_complete_member_epochs'] for v in report['cases'].values()),
    'members_with_new_complete_epoch': sum(v['members_with_new_complete_epoch'] for v in report['cases'].values()),
    'tune_branch_200_complete_members': sum(v['tune_branch_200_complete_members'] for v in report['cases'].values()),
    'failure_files': sum(len(v['failure_records']) for v in report['cases'].values())}
print(json.dumps(report, sort_keys=True), flush=True)

READ_FIXED200_003
