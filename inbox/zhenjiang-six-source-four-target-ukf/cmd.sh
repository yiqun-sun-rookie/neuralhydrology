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

# Read-only245929 attribution and first-complete-progress proof; no training imports.
import os,re
CASE='explicit_gru__historical_capacity'
TARGET_JOB='245929'
BASELINE726={'explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p0003': {'completed_epochs': 66, 'checkpoint_sha256': '28cdda150d4b85475669f535e424f21b823dc8757c90f40cd2a9d873bf5a85ed'}, 'explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p001': {'completed_epochs': 66, 'checkpoint_sha256': '59dbb7424baf415c3fefed201dabe1f554ca97d0b425dcb2eb52a6dd3a7d9e60'}, 'explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p003': {'completed_epochs': 66, 'checkpoint_sha256': 'd9ab97b562456a8ecb95959c98b49853ef11508010dd21de0ec4517e7654a1fa'}, 'explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p0003': {'completed_epochs': 66, 'checkpoint_sha256': '59b78f675e1eaa8f3d2e1677c7c89630065bc543341b83012c06cab88ed73b74'}, 'explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p001': {'completed_epochs': 66, 'checkpoint_sha256': '223676e95ab63cf184fe4c2e3c1b26f2f50a0be572afdd5b90ba95e8667a9551'}, 'explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p003': {'completed_epochs': 66, 'checkpoint_sha256': '1dbfbb2e3f0bfee024318ba5a5d4420f669c29f16a144d87330559daa643ccdf'}, 'explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p0003': {'completed_epochs': 66, 'checkpoint_sha256': 'efb53eaf6bf35f96170d7462e2517146da3cf9df0ff827e821fd3c4a0d90f47a'}, 'explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p001': {'completed_epochs': 65, 'checkpoint_sha256': 'f6c3371968d825405a6ab876db80cb0b2919bbb8b827ed67eab46b70dc537a2f'}, 'explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p003': {'completed_epochs': 65, 'checkpoint_sha256': '06b9c5625657cc304363ee17a69ee59323d5aa52bc51ae7d4bdf4b4e37d4cd27'}, 'explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p0003': {'completed_epochs': 65, 'checkpoint_sha256': '8445626d45ae05f8167f8511c5ae268118a74d30f680eed6212967baa4ca2204'}, 'explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p001': {'completed_epochs': 65, 'checkpoint_sha256': 'c83bb140f717de3864102d8b8cbbd956a0f04316a586ad45afd4cebc1712739f'}, 'explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p003': {'completed_epochs': 65, 'checkpoint_sha256': '032f67620d5ab60b5616a1d85a8da84271ce6da799930c5df16e36205e237612'}}
row=report['cases'][CASE]
root=Path(row['root']);record=root/'records'/CASE
detail=dict(job_id=row['job_id'],expected_job_id=TARGET_JOB,baseline_sequence=726,baseline_cumulative_case_epochs=116,baseline_members=BASELINE726,continuation_records={},changed_members=[],new_complete_member_epochs=0,hashed_new_checkpoint_files=0,unchanged_checkpoint_files_rehashed=0,training_executed=False,scheduler_submissions=0,node_live_pid_available=False,gpu_utilization_available=False)
def file_stat(p):
 st=p.stat();return dict(bytes=st.st_size,mtime_ns=st.st_mtime_ns,mtime_utc=datetime.datetime.fromtimestamp(st.st_mtime,datetime.timezone.utc).isoformat())
for name in ['continuation_after_245769.attempt.json','continuation_after_245769.response.json','continuation_after_245769.confirmed.json']:
 p=record/name
 if p.exists():
  raw=p.read_bytes();value=json.loads(raw)
  if isinstance(value.get('queue'),dict):
   value['queue']['stdout']='\n'.join(line for line in value['queue']['stdout'].splitlines() if str(root) in line or CASE in line)
  detail['continuation_records'][name]=dict(value=value,stat=file_stat(p),sha256=hashlib.sha256(raw).hexdigest())
env=dict(os.environ);env['TZ']='UTC';env['SLURM_TIME_FORMAT']='%Y-%m-%dT%H:%M:%S%z'
command=[SLURM/'sacct','-n','-X','-j','245769,245929','--format=JobID,State,ExitCode,Submit%32,Eligible%32,Start%32,End%32,ElapsedRaw,Timelimit,AllocCPUS,Partition%20,NodeList%30','-P']
result=subprocess.run(list(map(str,command)),capture_output=True,text=True,timeout=45,env=env)
detail['accounting_with_submit_utc_format']=dict(command=list(map(str,command)),read_only_environment_overrides=dict(TZ='UTC',SLURM_TIME_FORMAT=env['SLURM_TIME_FORMAT']),returncode=result.returncode,stdout=result.stdout,stderr=result.stderr)
command=[SLURM/'scontrol','-o','show','job',TARGET_JOB]
result=subprocess.run(list(map(str,command)),capture_output=True,text=True,timeout=45,env=env)
keep={'JobId','JobName','JobState','Reason','SubmitTime','EligibleTime','StartTime','EndTime','TimeLimit','RunTime','NumCPUs','NumNodes','NodeList','BatchHost','TRES','TresPerNode','Gres','Partition','ReqNodeList','ExcNodeList','BatchFlag'}
selected={}
for item in result.stdout.split():
 if '=' in item:
  k,v=item.split('=',1)
  if k in keep:selected[k]=v
detail['scontrol_selected_utc']=dict(command=list(map(str,command)),returncode=result.returncode,selected=selected,stderr=result.stderr)
detail['source_login_clock_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
logs=[];log_epochs={}
for path in (root/'logs').glob('*_'+TARGET_JOB+'.out'):
 with path.open('rb') as stream:
  stream.seek(max(0,path.stat().st_size-131072));tail=stream.read().decode('utf-8',errors='replace')
 parsed=[]
 for line in tail.splitlines():
  try:v=json.loads(line)
  except json.JSONDecodeError:continue
  if isinstance(v,dict) and v.get('run') in BASELINE726 and isinstance(v.get('epoch'),int):
   parsed.append(dict(member=v['run'],epoch=v['epoch']))
   log_epochs.setdefault(v['run'],set()).add(v['epoch'])
 logs.append(dict(path=str(path),stat=file_stat(path),max_tail_bytes=131072,complete_epoch_log_records=parsed,error_lines_in_tail=[line[:1200] for line in tail.splitlines() if re.search(r'Traceback|Error|Exception|out of memory|training_stopped|slurmstepd|Killed',line,re.I)][-10:]))
detail['new_job_log_samples']=logs
assert set(row['members'])==set(BASELINE726)
for member,current in row['members'].items():
 old=BASELINE726[member];n=current['completed_epochs'];pn=old['completed_epochs']
 detail['new_complete_member_epochs']+=n-pn
 if n>pn and row['job_id']==TARGET_JOB:
  folder=root/'runs'/member
  change=dict(member=member,baseline_epochs=pn,completed_epochs=n,baseline_checkpoint_sha256=old['checkpoint_sha256'],current_checkpoint_sha256=current['checkpoint_sha256_from_committed_head'],latest_event=current['new_epoch_event'],checkpoint_stat=file_stat(folder/'continuation.pt'),new_job_log_matches_current_epoch=n in log_epochs.get(member,set()))
  chain=[];head_sha=current['checkpoint_sha256_from_committed_head'];expected_n=n
  for _ in range(min(n-pn,32)):
   event=read(folder/'checkpoint_events'/(head_sha[:16]+'.json'))
   assert event['checkpoint_sha256']==head_sha and event['completed_epochs']==expected_n and event['previous_epochs']==expected_n-1
   chain.append(event);head_sha=event['previous_checkpoint_sha256'];expected_n-=1
  change['event_chain']=chain
  change['chain_reaches_726_checkpoint']=expected_n==pn and head_sha==old['checkpoint_sha256']
  if detail['hashed_new_checkpoint_files']==0 and change['new_job_log_matches_current_epoch']:
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
detail['total_current_branch_member_epochs']=sum(x['completed_epochs'] for x in row['members'].values())
detail['runtime_binding_matches_job']=bool(row.get('runtime_binding') and row['runtime_binding']['job_id']==TARGET_JOB)
binding=row.get('runtime_binding') or {}
detail['runtime_binding_matches_frozen_identity']=bool(binding.get('code_hash')==row['authorization']['code_hash'] and binding.get('protocol_sha256')==row['authorization']['protocol_sha256'] and binding.get('device_identity')==row['authorization']['device_identity'])
active=[x.split('|') for x in report['queue']['stdout'].splitlines() if len(x.split('|'))>=4 and x.split('|')[3]==str(root)]
detail['active_same_root_jobs']=active
detail['single_expected_running_job']=len(active)==1 and active[0][0]==TARGET_JOB and active[0][2]=='RUNNING'
detail['first_progress_verified']=bool(row['job_id']==TARGET_JOB and detail['new_complete_member_epochs']>0 and detail['runtime_binding_matches_job'] and detail['runtime_binding_matches_frozen_identity'] and detail['single_expected_running_job'] and not row['failure_records'] and any(x['chain_reaches_726_checkpoint'] and x['new_job_log_matches_current_epoch'] and x.get('new_checkpoint_byte_check',{}).get('matches_committed_head') and x.get('new_checkpoint_byte_check',{}).get('stable_during_read') for x in detail['changed_members']))
detail['source_checked_at_utc']=datetime.datetime.now(datetime.timezone.utc).isoformat()
report['target245929_first_progress']=detail
allowed_roots={x['root'] for x in report['cases'].values()}
report['queue']['stdout']='\n'.join(line for line in report['queue']['stdout'].splitlines() if len(line.split('|'))>=4 and line.split('|')[3] in allowed_roots)+'\n'
report['queue']['scope_filter_applied']=True

print(json.dumps(report,sort_keys=True),flush=True)

READ_FIXED200_003
