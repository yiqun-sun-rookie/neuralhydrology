#!/usr/bin/env bash
set -eo pipefail
python3 - <<'DIAGNOSE_MISSING_WRAPPER'
import datetime,fcntl,hashlib,json,os,socket,subprocess
from pathlib import Path
root=Path('/data1/home/sunyiq/zhenjiang_complete_comparison_fixed200_20261019_003/sqrt_gru_recovery')
case='explicit_gru__historical_capacity';job='252379'
record=root/'records'/case
expected=json.loads(r"""{"explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p0003": {"anchor_sha256": "5550be2ad8d7db9b3cae78bed3f29d0ff1f312528a298b3b30d3090bd370d11c", "checkpoint_sha256": "a3d6114438379fa6bb8bb9a3d6d601348d489f030115a6562e90d7241b41e02e", "completed_epochs": 114}, "explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p001": {"anchor_sha256": "4ade17fd33699559371783b0c24aaceab612365c441379816b8c3400940307e1", "checkpoint_sha256": "26e4d2865461bba244e60101e5ab925dd40bb5cb8716284e565aa4425bca87af", "completed_epochs": 114}, "explicit_gru__historical_capacity__tune_branch__encoder_fixed__s101__lr0p003": {"anchor_sha256": "11856601a76b3eb8c78665ea07880d1ea9756c81e452abbc10b8f0941ca26205", "checkpoint_sha256": "3e3b075174c434f0079495d1b0a841c552c38b650407a7c1a49679e3e6003889", "completed_epochs": 114}, "explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p0003": {"anchor_sha256": "99e8daef9c657b6bfff7de2ba00e2422d9fe3775c637f478f1f8ff46b36896e3", "checkpoint_sha256": "6798e9c1cef0a9b686b51db6b27e58b82d4dc314efc90f25c50558f30e7a6d48", "completed_epochs": 114}, "explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p001": {"anchor_sha256": "1099ad456f0a933885265d94a5dd60ec81b5b0de26a01835f257966d33f55610", "checkpoint_sha256": "1e841b45f1d448bd458396bd65d111b454f1757d687970f6f6edd299cb85025c", "completed_epochs": 114}, "explicit_gru__historical_capacity__tune_branch__encoder_joint__s101__lr0p003": {"anchor_sha256": "7f913119608a215f93c79f6a8f4954dc23d67f265bd566b0fa911747e27d2b57", "checkpoint_sha256": "902e04390ad7ed30978f7dbaee547772a3451e7bf03658f405afad9ebeda07ab", "completed_epochs": 114}, "explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p0003": {"anchor_sha256": "a448485c3d5c76a48f2423a9780edc21bc27bbed466c4529adb8d7f47500d15b", "checkpoint_sha256": "be8f6dccfb37040ec9394123b864476999ad1d47effd4aed6f4ad6bf910622e8", "completed_epochs": 114}, "explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p001": {"anchor_sha256": "b61be87a8a2c48cdb472ead2faefaf5536522b13959665e4ce079adf3cbd8778", "checkpoint_sha256": "65e7b9c5c0ca5854651a34d0c34bc56bb7fc6054250b1e4112ccf16f87773a1f", "completed_epochs": 114}, "explicit_gru__historical_capacity__tune_branch__filter_fixed__s101__lr0p003": {"anchor_sha256": "377845e59485972ab455bde9d5f4175e88650ce631f5f95830ace82c837d85fb", "checkpoint_sha256": "ed9c2452dc68aed0fa065db8883e71703a896b04ab90ad44049924681ff704c1", "completed_epochs": 113}, "explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p0003": {"anchor_sha256": "668a0e2bce5d56d2ba74fb0c131cb5e03c187fd0f101667042ac7402a0059e23", "checkpoint_sha256": "eb5df930b6df782f0c0db6c6474db23b893c5e9c5acfb6de244f3edeae447a84", "completed_epochs": 113}, "explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p001": {"anchor_sha256": "36ceefea026683c616149164178c8f91ecfc1bb6a312a60949310c0de5ada8cb", "checkpoint_sha256": "b7049cd727db7b651c7a2244aeb1304804847e341d33f8ed3e98c27371e9b694", "completed_epochs": 113}, "explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p003": {"anchor_sha256": "aa98f6aa23ba4cdfc9b77a681c19acc1985a4ffd8226eb10ab7da9783a167ee7", "checkpoint_sha256": "b6daabecf1d1920e45e79ac85c07c3e9a178e83ae7ab807e39f3982a4408598b", "completed_epochs": 113}}""")
slurm=Path('/usr/local/globle/softs/slurm/19.05.4.1/bin')
folder=record/'repairs/missing_wrapper_252379_20261029_001'
folder.mkdir(parents=True,exist_ok=False)
def sha(raw):return hashlib.sha256(raw).hexdigest()
def query(args):
 p=subprocess.run([str(x) for x in args],capture_output=True,text=True,timeout=45)
 return {'command':[str(x) for x in args],'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
report={'schema':'003-native-missing-wrapper-diagnosis-v1','at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'host':socket.gethostname(),'case':case,'job_id':job,'root':str(root),'root_resolved':str(root.resolve()),'training_mutated':False,'job_submitted':False,'checkpoint_tensors_loaded':False,'files':{},'heads':{},'errors':[]}
report['queue']=query([slurm/'squeue','-h','-u','sunyiq','-o','%i|%j|%T|%Z|%o'])
report['same_case_queue_rows']=[x for x in report['queue']['stdout'].splitlines() if case in x or str(root) in x or x.startswith(job+'|')]
report['accounting']=query([slurm/'sacct','-n','-X','-j',job,'--format=JobID,State,ExitCode,Start,End,NodeList','-P'])
paths={
 'wrapper':root/'hpc/run_fixed200_case.py',
 'pre_guard_wrapper':root/'hpc/run_fixed200_case_before_external_20261028.py',
 'admitted_guard_source':root.parent/'external_gru_foundation_20261028_001/run_fixed200_case_external_guard.py',
 'submitter':root/'hpc/submit_fixed200_continuation.py',
 'slurm_template':root/'hpc/fixed200_case.slurm',
 'authorization':root/'records/authorization.json',
 'scheduler_jobs':root/'records/scheduler_jobs.json',
 'reservation':record/'external_final_foundation_20261028.json',
 'reservation_receipt':record/'external_final_foundation_reservation_verified_20261028.json',
 'runtime_binding':record/('runtime_binding_'+job+'.json'),
 'slice_end':record/('scheduler_slice_end_'+job+'.json'),
 'job_log':root/('logs/zj003_'+case+'_'+job+'.out')}
for label,path in paths.items():
 item={'path':str(path),'exists':path.exists(),'is_symlink':path.is_symlink()}
 if path.is_symlink():item['symlink_target']=os.readlink(path)
 if path.is_file():
  raw=path.read_bytes();item.update(bytes=len(raw),sha256=sha(raw))
  (folder/(label+'.preserved')).write_bytes(raw)
 report['files'][label]=item
report['hpc_directory_entries']=sorted(p.name for p in (root/'hpc').iterdir()) if (root/'hpc').is_dir() else None
report['writer_lock_available']=False
lock_path=record/'writer.lock'
if lock_path.exists():
 with lock_path.open('r+') as handle:
  try:
   fcntl.flock(handle,fcntl.LOCK_EX|fcntl.LOCK_NB);report['writer_lock_available']=True;fcntl.flock(handle,fcntl.LOCK_UN)
  except BlockingIOError:pass
else:report['writer_lock_absent']=True
for member,old in expected.items():
 r=root/'runs'/member;dest=folder/'heads'/member;dest.mkdir(parents=True)
 try:
  head_raw=(r/'checkpoint_head.json').read_bytes();head=json.loads(head_raw);anchor_raw=(r/'continuation_anchor.json').read_bytes()
  event_raw=(r/'checkpoint_events'/(head['checkpoint_sha256'][:16]+'.json')).read_bytes();event=json.loads(event_raw)
  (dest/'checkpoint_head.json').write_bytes(head_raw);(dest/'continuation_anchor.json').write_bytes(anchor_raw);(dest/'checkpoint_event.json').write_bytes(event_raw)
  report['heads'][member]={'head':head,'event':event,'anchor_sha256':sha(anchor_raw),'continuation_exists':(r/'continuation.pt').is_file(),'continuation_bytes':(r/'continuation.pt').stat().st_size if (r/'continuation.pt').is_file() else None,'matches_pre_submission_baseline':head['completed_epochs']==old['completed_epochs'] and head['checkpoint_sha256']==old['checkpoint_sha256'] and head['anchor_sha256']==old['anchor_sha256']==sha(anchor_raw)}
 except Exception as exc:report['errors'].append({'member':member,'error':repr(exc)})
report['all_heads_match_pre_submission_baseline']=len(report['heads'])==len(expected) and all(h['matches_pre_submission_baseline'] for h in report['heads'].values())
report['training_failure_files']=[str(p) for p in (root/'runs').glob('*/failure.json')]
report['expected_guard_sha256']='4157613be568d36e5dc322b2f39da81434d30dd7eba9c7491252e209244168ba'
report['scientific_sources_changed_or_loaded']=False
report_path=folder/'DIAGNOSIS.json'
with report_path.open('x') as f:json.dump(report,f,sort_keys=True,indent=2);f.write(chr(10))
print('GRU_MISSING_WRAPPER_DIAGNOSIS_JSON '+json.dumps(report,sort_keys=True),flush=True)

DIAGNOSE_MISSING_WRAPPER

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
print(json.dumps(report, sort_keys=True), flush=True)

READ_FIXED200_003
