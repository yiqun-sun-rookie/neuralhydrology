#!/usr/bin/env bash
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

# Read-only attribution and first-progress evidence for245769; no training imports.
import os,time
CASE='explicit_gru__historical_capacity'
BASELINE711={'explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p0003': {'completed_epochs': 61, 'checkpoint_sha256': '250172543a7543a8e584e1c8a6b7147410cb430ee551242654d49e036399e94e'}, 'explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p001': {'completed_epochs': 61, 'checkpoint_sha256': '76e94f400360239aea5088ae64611c3393a1f8c3b932dbdddaf23b76174122bc'}, 'explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p003': {'completed_epochs': 61, 'checkpoint_sha256': '11d933ab1391de96519eb37999a2a37629ace246c61f88eee43888d45319be9c'}, 'explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p0003': {'completed_epochs': 61, 'checkpoint_sha256': '5de73f09d2527435c0d72a3515a5152cd49b492587f2cd4a6ebd5a1955ef7c40'}, 'explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p001': {'completed_epochs': 61, 'checkpoint_sha256': '807e6a5406c6745a2e011acab2b82c75ae632dc3153f2f82096729a55475fc18'}, 'explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p003': {'completed_epochs': 61, 'checkpoint_sha256': '970dbc6da99f939a090a6f732e4afab97ac918d9f785490c62317bb06cecc4f7'}, 'explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p0003': {'completed_epochs': 61, 'checkpoint_sha256': '16369651f0fac28cb6e4187370d0ef45a57de461b519af7a334a3ff2ed39bb71'}, 'explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p001': {'completed_epochs': 61, 'checkpoint_sha256': '56971d09e4f617b6060f8f0799f86c2a7c5220283cecad52a4b103cff23303d8'}, 'explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p003': {'completed_epochs': 61, 'checkpoint_sha256': '51e4eb28c34bd86df56d4bc47051856221916ee61009f222f24f61dd77a0d681'}, 'explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p0003': {'completed_epochs': 60, 'checkpoint_sha256': 'e6702b728a24dc412ea5001a2925c4d2a734d35e67c9bb3c4dff3f7598550c46'}, 'explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p001': {'completed_epochs': 60, 'checkpoint_sha256': 'e4ebd04827580f0b6a2e5919ce353a13591d1c381eeb38e01819a6dc12ebb57e'}, 'explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p003': {'completed_epochs': 60, 'checkpoint_sha256': 'a47cd544e07d3bd46a9d2256820887bbc019f293f5e4be7f81e57f9ca5e58f68'}}
row=report['cases'][CASE]
root=Path(row['root']);record=root/'records'/CASE
detail=dict(job_id=row['job_id'],expected_job_id='245769',baseline_sequence=711,baseline_cumulative58=58,baseline_members=BASELINE711,continuation_records={},changed_members=[],new_complete_member_epochs=0,hashed_new_checkpoint_files=0,unchanged_checkpoint_files_rehashed=0,training_executed=False,scheduler_submissions=0)
def file_stat(p):
 st=p.stat();return dict(bytes=st.st_size,mtime_ns=st.st_mtime_ns,mtime_utc=datetime.datetime.fromtimestamp(st.st_mtime,datetime.timezone.utc).isoformat())
for name in ['continuation_after_245560.attempt.json','continuation_after_245560.response.json','continuation_after_245560.confirmed.json']:
 p=record/name
 if p.exists():
  value=read(p)
  if isinstance(value.get('queue'),dict):
   value['queue']['stdout']='\n'.join(line for line in value['queue']['stdout'].splitlines() if str(root) in line or CASE in line)
  detail['continuation_records'][name]=dict(value=value,stat=file_stat(p))
env=dict(os.environ);env['TZ']='UTC';env['SLURM_TIME_FORMAT']='%Y-%m-%dT%H:%M:%S%z'
command=[SLURM/'sacct','-n','-X','-j','245560,245769','--format=JobID,State,ExitCode,Submit%32,Eligible%32,Start%32,End%32,ElapsedRaw,Timelimit,AllocCPUS,NodeList','-P']
result=subprocess.run(list(map(str,command)),capture_output=True,text=True,timeout=45,env=env)
detail['accounting_with_submit_utc_format']=dict(command=list(map(str,command)),read_only_environment_overrides=dict(TZ='UTC',SLURM_TIME_FORMAT=env['SLURM_TIME_FORMAT']),returncode=result.returncode,stdout=result.stdout,stderr=result.stderr)
detail['login_local_clock']=datetime.datetime.now().astimezone().isoformat()
for member,current in row['members'].items():
 old=BASELINE711[member];n=current['completed_epochs'];pn=old['completed_epochs']
 detail['new_complete_member_epochs']+=n-pn
 if n>pn:
  folder=root/'runs'/member
  change=dict(member=member,baseline_epochs=pn,completed_epochs=n,baseline_checkpoint_sha256=old['checkpoint_sha256'],current_checkpoint_sha256=current['checkpoint_sha256_from_committed_head'],latest_event=current['new_epoch_event'],checkpoint_stat=file_stat(folder/'continuation.pt'))
  chain=[];head_sha=current['checkpoint_sha256_from_committed_head'];expected_n=n
  for _ in range(min(n-pn,32)):
   event=read(folder/'checkpoint_events'/(head_sha[:16]+'.json'))
   assert event['checkpoint_sha256']==head_sha and event['completed_epochs']==expected_n and event['previous_epochs']==expected_n-1
   chain.append(event);head_sha=event['previous_checkpoint_sha256'];expected_n-=1
  change['event_chain']=chain
  change['chain_reaches_711_checkpoint']=expected_n==pn and head_sha==old['checkpoint_sha256']
  if detail['hashed_new_checkpoint_files']==0:
   path=folder/'continuation.pt';h=hashlib.sha256()
   head_before=(folder/'checkpoint_head.json').read_bytes()
   with path.open('rb') as stream:
    before=os.fstat(stream.fileno())
    for block in iter(lambda:stream.read(1024*1024),b''):h.update(block)
    after=os.fstat(stream.fileno())
   end=path.stat()
   stable=(before.st_ino,before.st_size,before.st_mtime_ns)==(after.st_ino,after.st_size,after.st_mtime_ns)==(end.st_ino,end.st_size,end.st_mtime_ns) and (folder/'checkpoint_head.json').read_bytes()==head_before
   change['new_checkpoint_byte_check']=dict(sha256=h.hexdigest(),bytes=before.st_size,stable_during_read=stable,matches_committed_head=h.hexdigest()==current['checkpoint_sha256_from_committed_head'])
   detail['hashed_new_checkpoint_files']+=1
  detail['changed_members'].append(change)
detail['total_current_member_epochs']=sum(x['completed_epochs'] for x in row['members'].values())
detail['runtime_binding_matches_job']=bool(row.get('runtime_binding') and row['runtime_binding']['job_id']=='245769')
active=[x.split('|') for x in report['queue']['stdout'].splitlines() if len(x.split('|'))>=4 and x.split('|')[3]==str(root)]
detail['active_same_root_jobs']=active
detail['single_expected_running_job']=len(active)==1 and active[0][0]=='245769' and active[0][2]=='RUNNING'
detail['first_progress_verified']=bool(row['job_id']=='245769' and detail['new_complete_member_epochs']>0 and detail['runtime_binding_matches_job'] and detail['single_expected_running_job'] and not row['failure_records'] and any(x['chain_reaches_711_checkpoint'] and x.get('new_checkpoint_byte_check',{}).get('matches_committed_head') and x.get('new_checkpoint_byte_check',{}).get('stable_during_read') for x in detail['changed_members']))
detail['source_checked_at_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
report['target245769_first_progress']=detail
allowed_roots={x['root'] for x in report['cases'].values()}
report['queue']['stdout']='\n'.join(line for line in report['queue']['stdout'].splitlines() if len(line.split('|'))>=4 and line.split('|')[3] in allowed_roots)+'\n'
report['queue']['scope_filter_applied']=True

print(json.dumps(report, sort_keys=True), flush=True)

READ_FIXED200_003
