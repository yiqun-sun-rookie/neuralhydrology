#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import contextlib,datetime,io,json,os,pathlib,subprocess
ORIGINAL=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_002')
ROOTS={'legacy_lstm__small':pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261008_recovery_002'),'explicit_gru__historical_capacity':pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_004'),'explicit_gru__small':ORIGINAL,'legacy_lstm__historical_capacity':ORIGINAL}
SOURCE='import datetime\nimport hashlib\nimport json\nimport pathlib\nimport re\nimport subprocess\n\nROOT = pathlib.Path.cwd()\nUTC = datetime.timezone.utc\nBEIJING = datetime.timezone(datetime.timedelta(hours=8))\nERRORS = []\n\n\ndef relative(path):\n    return path.relative_to(ROOT).as_posix()\n\n\ndef error(path, exc):\n    record = {\'path\': relative(path), \'error_type\': type(exc).__name__, \'error\': str(exc)[:1200]}\n    ERRORS.append(record)\n    return record\n\n\ndef metadata(path):\n    try:\n        stat = path.stat()\n        moment = datetime.datetime.fromtimestamp(stat.st_mtime, UTC)\n        return {\'exists\': True, \'bytes\': stat.st_size, \'mtime_ns\': stat.st_mtime_ns,\n                \'mtime_utc\': moment.isoformat(), \'mtime_beijing\': moment.astimezone(BEIJING).isoformat()}\n    except FileNotFoundError:\n        return {\'exists\': False}\n    except Exception as exc:\n        return {\'exists\': None, \'error\': error(path, exc)}\n\n\ndef read_json(path):\n    info = metadata(path)\n    record = {\'path\': relative(path), \'stat\': info}\n    if not info.get(\'exists\'):\n        return record, None\n    try:\n        raw = path.read_bytes()\n        record[\'sha256\'] = hashlib.sha256(raw).hexdigest()\n        value = json.loads(raw)\n        record[\'json_valid\'] = True\n        return record, value\n    except Exception as exc:\n        record[\'json_valid\'] = False\n        record[\'error\'] = error(path, exc)\n        return record, None\n\n\ndef json_record(path):\n    record, value = read_json(path)\n    if value is not None:\n        record[\'value\'] = value\n    return record\n\n\ndef run_command(command):\n    try:\n        result = subprocess.run(command, capture_output=True, text=True, timeout=30)\n        return {\'command\': command, \'returncode\': result.returncode,\n                \'stdout\': result.stdout[:60000], \'stderr\': result.stderr[:10000],\n                \'stdout_truncated\': len(result.stdout) > 60000}\n    except Exception as exc:\n        return {\'command\': command, \'error_type\': type(exc).__name__, \'error\': str(exc)[:1200]}\n\n\nnow = datetime.datetime.now(UTC)\nreport = {\'status\': \'read_only_training_snapshot\', \'root\': str(ROOT),\n          \'checked_at_utc\': now.isoformat(), \'checked_at_beijing\': now.astimezone(BEIJING).isoformat(),\n          \'evaluation_values_read\': False, \'data_inputs_read\': False,\n          \'checkpoints_loaded\': False, \'checkpoint_stat_only\': True}\n\njob_record, job_mapping = read_json(ROOT / \'records/scheduler_jobs.json\')\nreport[\'scheduler_jobs_file\'] = job_record\nreport[\'scheduler_jobs\'] = job_mapping\njob_ids = []\nif isinstance(job_mapping, dict):\n    for key, value in job_mapping.items():\n        if re.fullmatch(r\'[0-9]+\', str(value)):\n            job_ids.append(str(value))\n        else:\n            ERRORS.append({\'path\': \'records/scheduler_jobs.json\', \'error\': \'invalid job id\', \'key\': str(key)})\njob_ids = sorted(set(job_ids), key=int)\nreport[\'own_job_ids\'] = job_ids\nreport[\'scheduler_queries\'] = []\nif job_ids:\n    own_ids = \',\'.join(job_ids)\n    report[\'scheduler_queries\'] = [\n        run_command([\'squeue\', \'-h\', \'-j\', own_ids, \'-o\', \'%i|%j|%T|%R|%M|%N|%b\']),\n        run_command([\'sacct\', \'-n\', \'-X\', \'-j\', own_ids,\n                     \'--format=JobID,JobName,State,ExitCode,Elapsed,NodeList,Reason\', \'-P\'])]\n\nreport[\'identities\'] = {}\nfor name in [\'records/authorization.json\', \'records/data_preparation_complete.json\',\n             \'configs/protocol-v3.json\', \'configs/registry-v3.json\']:\n    record, value = read_json(ROOT / name)\n    if isinstance(value, dict):\n        record[\'binding_fields\'] = {key: value[key] for key in\n            (\'status\', \'protocol_sha256\', \'code_hash\', \'scientific_factors_sha256\',\n             \'execution_policy\', \'evaluation_values_read\', \'evaluation_year_reads\',\n             \'source_files\', \'training_authority\', \'version\') if key in value}\n        if name.endswith(\'registry-v3.json\'):\n            record[\'logical_runs\'] = len(value.get(\'runs\', []))\n            record[\'gates\'] = len(value.get(\'gates\', []))\n    report[\'identities\'][name] = record\ntry:\n    source_files = sorted([*ROOT.joinpath(\'src\').glob(\'*.py\'),\n                           *ROOT.joinpath(\'scripts\').glob(\'*.py\'),\n                           *ROOT.joinpath(\'vendor/pytides\').glob(\'*.py\')])\n    hashes = {relative(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in source_files}\n    canonical = json.dumps(hashes, sort_keys=True, separators=(\',\', \':\'), allow_nan=False).encode()\n    report[\'actual_code_identity\'] = {\'code_hash\': hashlib.sha256(canonical).hexdigest(),\n                                      \'source_file_count\': len(hashes)}\n    authorization_record, authorization = read_json(ROOT / \'records/authorization.json\')\n    authorized_hash = authorization.get(\'code_hash\') if isinstance(authorization, dict) else None\n    report[\'actual_code_identity\'][\'authorized_code_hash\'] = authorized_hash\n    report[\'actual_code_identity\'][\'matches_authorized_code\'] = (\n        report[\'actual_code_identity\'][\'code_hash\'] == authorized_hash) if authorized_hash else None\nexcept Exception as exc:\n    report[\'actual_code_identity\'] = {\'error_type\': type(exc).__name__, \'error\': str(exc)[:1200]}\n\nreport[\'cases\'] = {}\ncase_names = [key for key in (job_mapping or {}) if key != \'preparation\'] if isinstance(job_mapping, dict) else []\ncase_names = sorted(set(case_names) | {path.parent.name for path in ROOT.joinpath(\'records\').glob(\'*/progress.json\')})\nfor case in case_names:\n    if not re.fullmatch(r\'[A-Za-z0-9_]+\', case):\n        ERRORS.append({\'case\': case, \'error\': \'unsafe case name ignored\'})\n        continue\n    folder = ROOT / \'records\' / case\n    detail = {\'progress\': json_record(folder / \'progress.json\'),\n              \'training_complete\': json_record(folder / \'training_complete.json\'),\n              \'selected_rates\': json_record(folder / \'selected_rates_2021.json\'),\n              \'allocations\': [json_record(path) for path in sorted(folder.glob(\'allocation_*.json\'))],\n              \'outcomes\': []}\n    for path in sorted(folder.glob(\'*_outcome.json\')):\n        record, value = read_json(path)\n        if isinstance(value, dict):\n            members = value.get(\'members\', {})\n            seal = value.get(\'seal\', {})\n            if not isinstance(members, dict):\n                record[\'error\'] = error(path, ValueError(\'outcome members are not an object\'))\n                detail[\'outcomes\'].append(record)\n                continue\n            record.update(status=value.get(\'status\'), member_count=len(members), seal=seal)\n            record[\'members\'] = {}\n            for member, result in members.items():\n                if not isinstance(result, dict):\n                    record[\'members\'][member] = {\'error\': \'member result is not an object\'}\n                    continue\n                values = result.get(\'validation_mae\', [])\n                record[\'members\'][member] = {key: result.get(key) for key in\n                    (\'status\', \'epochs\', \'budget_final\', \'best_epoch\', \'method\',\n                     \'learning_rate\', \'checkpoint_sha256\', \'checkpoint_path\')}\n                record[\'members\'][member][\'validation_history_length\'] = len(values) if isinstance(values, list) else None\n        detail[\'outcomes\'].append(record)\n    report[\'cases\'][case] = detail\n\nreport[\'runs\'] = {}\nfor folder in sorted(ROOT.joinpath(\'runs\').glob(\'*\')):\n    if not folder.is_dir():\n        continue\n    detail = {\'continuation_checkpoint_stat\': metadata(folder / \'continuation.pt\'),\n              \'temporary_continuation_stat\': metadata(folder / \'continuation.pt.tmp\'),\n              \'best_checkpoint_stat\': metadata(folder / \'best.pt\'),\n              \'epoch_checkpoint_stats\': {path.name: metadata(path) for path in sorted(folder.glob(\'epoch_*.pt\'))},\n              \'first_optimizer_step\': json_record(folder / \'first_optimizer_step.json\'),\n              \'failure\': json_record(folder / \'failure.json\')}\n    config_record, config = read_json(folder / \'config.json\')\n    if isinstance(config, dict):\n        effective = config.get(\'effective_config\', {})\n        config_record[\'binding_fields\'] = {key: effective.get(key) for key in\n            (\'code_hash\', \'training_data_hash\', \'normalization_hash\', \'parent_hash\',\n             \'parent_run_id\', \'device_identity\', \'scheduler_continuation\', \'learning_rate\')}\n        config_record[\'registration\'] = config.get(\'registration\')\n        config_record[\'protocol_sha256\'] = config.get(\'protocol_sha256\')\n    detail[\'config\'] = config_record\n    path = folder / \'metrics.json\'\n    metrics = {\'path\': relative(path), \'stat\': metadata(path)}\n    if metrics[\'stat\'].get(\'exists\'):\n        try:\n            # Histories precede bulky per-batch training metrics. Read just this prefix.\n            with path.open(\'rb\') as stream:\n                prefix = stream.read(131072).decode(\'utf-8\')\n            match = re.search(r\'"validation_mae_cm"\\s*:\\s*\', prefix)\n            if match is None:\n                raise ValueError(\'validation history missing from metrics prefix\')\n            values, end = json.JSONDecoder().raw_decode(prefix[match.end():])\n            if not isinstance(values, list):\n                raise ValueError(\'validation history is not a list\')\n            metrics.update(completed_epochs=len(values), validation_history_length=len(values), full_validation_mae_cm=values,\n                           recent_validation_mae_cm=values[-5:],\n                           validation_history_sha256=hashlib.sha256(json.dumps(values, separators=(\',\', \':\')).encode()).hexdigest(),\n                           validation_prefix_parsed=True, full_json_validity_checked=False)\n        except Exception as exc:\n            metrics[\'error\'] = error(path, exc)\n    detail[\'metrics\'] = metrics\n    report[\'runs\'][folder.name] = detail\n\nreport[\'logs\'] = []\nfor path in sorted(ROOT.joinpath(\'logs\').glob(\'*.out\')):\n    item = {\'path\': relative(path), \'stat\': metadata(path)}\n    try:\n        with path.open(\'rb\') as stream:\n            stream.seek(max(0, path.stat().st_size - 20000))\n            tail = stream.read().decode(\'utf-8\', errors=\'replace\')\n        item[\'tail\'] = tail\n        item[\'error_lines_in_tail\'] = [line[:1800] for line in tail.splitlines() if\n            re.search(r\'Traceback|Error|Exception|CUDA|out of memory|training_stopped|slurmstepd|Killed\', line, re.I)][-15:]\n    except Exception as exc:\n        item[\'error\'] = error(path, exc)\n    report[\'logs\'].append(item)\n\nreport[\'summary\'] = {\'case_count\': len(report[\'cases\']), \'run_directories\': len(report[\'runs\']),\n    \'runs_with_completed_epoch_history\': sum(bool(v[\'metrics\'].get(\'completed_epochs\')) for v in report[\'runs\'].values()),\n    \'completed_member_epochs\': sum(v[\'metrics\'].get(\'completed_epochs\', 0) for v in report[\'runs\'].values()),\n    \'runs_with_failure_file\': sum(v[\'failure\'][\'stat\'].get(\'exists\') is True for v in report[\'runs\'].values()),\n    \'complete_case_records\': sum(v[\'training_complete\'][\'stat\'].get(\'exists\') is True for v in report[\'cases\'].values())}\nreport[\'read_errors\'] = ERRORS\nreport[\'finished_at_utc\'] = datetime.datetime.now(UTC).isoformat()\nprint(json.dumps(report, ensure_ascii=True, sort_keys=True))'
REUSED_PARENT=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_recovery_001')
snapshots={}
for folder in sorted(set(ROOTS.values()) | {REUSED_PARENT},key=str):
 if not (folder/'records/scheduler_jobs.json').exists():raise ValueError('registered continuation job mapping unavailable: '+str(folder))
 os.chdir(folder);stream=io.StringIO()
 with contextlib.redirect_stdout(stream):exec(compile(SOURCE,'registered_read_only_training_snapshot','exec'),{})
 snapshots[str(folder)]=json.loads(stream.getvalue())
original=snapshots[str(ORIGINAL)];result=dict(original);result['cases']={};result['runs']={};result['logs']=[];result['scheduler_jobs']={'preparation':original['scheduler_jobs']['preparation']};result['case_roots']={k:str(v) for k,v in ROOTS.items()};result['read_errors']=[]
for case,folder in ROOTS.items():
 snap=snapshots[str(folder)];result['cases'][case]=snap['cases'][case];result['runs'].update({k:v for k,v in snap['runs'].items() if k.startswith(case+'__')});job=str(snap['scheduler_jobs'][case]);result['scheduler_jobs'][case]=job
 result['logs'] += [v for v in snap['logs'] if v['path'].endswith('_'+job+'.out')]
result['reused_completed_group_run_roots']={}
for rid,run in snapshots[str(REUSED_PARENT)]['runs'].items():
 if rid.startswith('explicit_gru__historical_capacity__tune_foundation__'):
  assert rid not in result['runs'] and run['metrics']['completed_epochs']==400
  result['runs'][rid]=run;result['reused_completed_group_run_roots'][rid]=str(REUSED_PARENT)
assert len(result['reused_completed_group_run_roots'])==3
result['preserved_failed_group']={'root':str(REUSED_PARENT),'source_job':snapshots[str(REUSED_PARENT)]['scheduler_jobs']['explicit_gru__historical_capacity'],'runs':{k:v for k,v in snapshots[str(REUSED_PARENT)]['runs'].items() if k.startswith('explicit_gru__historical_capacity__tune_branch__')}}
for snap in snapshots.values():result['read_errors']+=snap['read_errors']
result['root_snapshots_identity']={r:{'actual_code_identity':v['actual_code_identity'],'identities':v['identities'],'checked_at_beijing':v['checked_at_beijing']} for r,v in snapshots.items()}
result['historical_source_cases']={case:{'root':str(ORIGINAL),'source_job':original['scheduler_jobs'][case],'progress':original['cases'][case]['progress'],'runs':{k:{'failure':v['failure'],'metrics':v['metrics'],'continuation_checkpoint_stat':v['continuation_checkpoint_stat']} for k,v in original['runs'].items() if k.startswith(case+'__')}} for case in ('legacy_lstm__small','explicit_gru__historical_capacity')}
result['recovery_records']={}
for case,folder in ROOTS.items():
 if folder==ORIGINAL:continue
 rows={}
 for n in ('recovery_preparation_complete.json','source_stop_confirmed.json','recovery_submission_response.json','gpu_compatibility_admission.json','completed_group_reuse.json','gradient_recovery_intent.json','covariance_recovery_intent_20261015.json','covariance_recovery_cpu_admitted_20261015.json'):
  p=folder/'records'/n
  if p.exists():rows[n]=json.loads(p.read_text())
 for p in sorted((folder/'records').glob('gpu_*.json')):
  rows[p.name]=json.loads(p.read_text())
 result['recovery_records'][case]=rows
ids=','.join(sorted(set(result['scheduler_jobs'].values()),key=int));result['own_job_ids']=ids.split(',');result['scheduler_queries']=[]
for command in (['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%R|%M|%N|%b'],['sacct','-n','-X','-j',ids,'--format=JobID,JobName,State,ExitCode,Elapsed,NodeList,Reason','-P']):
 r=subprocess.run(command,capture_output=True,text=True,timeout=30);result['scheduler_queries'].append({'command':command,'returncode':r.returncode,'stdout':r.stdout,'stderr':r.stderr})
result['summary']={'case_count':len(result['cases']),'run_directories':len(result['runs']),'runs_with_completed_epoch_history':sum(bool(v['metrics'].get('completed_epochs')) for v in result['runs'].values()),'completed_member_epochs':sum(v['metrics'].get('completed_epochs',0) for v in result['runs'].values()),'runs_with_failure_file':sum(v['failure']['stat'].get('exists') is True for v in result['runs'].values()),'complete_case_records':sum(v['training_complete']['stat'].get('exists') is True for v in result['cases'].values())}
now=datetime.datetime.now(datetime.timezone.utc);result['checked_at_utc']=now.isoformat();result['checked_at_beijing']=now.astimezone(datetime.timezone(datetime.timedelta(hours=8))).isoformat();result['scope']='current_registered_four_cases_across_original_and_three_authenticated_recovery_roots_with_completed_parent_reuse'
print(json.dumps(result,ensure_ascii=True,sort_keys=True))
PY
python3 - <<'PY'
"""Lightweight allocation/checkpoint watch; no source changes or GPU jobs."""
import datetime,hashlib,json,pathlib,re,subprocess
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_004')
case='explicit_gru__historical_capacity'
job=str(json.loads((root/'records/scheduler_jobs.json').read_text())[case])
def query(c):
    p=subprocess.run(c,capture_output=True,text=True,timeout=30)
    return {'command':c,'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr}
members={}
for folder in sorted(root.joinpath('runs').glob('*__tune_branch__*')):
    metric=folder/'metrics.json';point=folder/'continuation.pt'
    prefix=metric.open('rb').read(131072).decode('utf-8')
    m=re.search(r'"validation_mae_cm"\s*:\s*',prefix)
    values=json.JSONDecoder().raw_decode(prefix[m.end():])[0]
    stat=point.stat()
    members[folder.name]={'completed_epochs':len(values),'history_sha256':hashlib.sha256(json.dumps(values,separators=(',',':')).encode()).hexdigest(),'continuation_bytes':stat.st_size,'continuation_mtime_ns':stat.st_mtime_ns,'failure_exists':folder.joinpath('failure.json').exists()}
queries=[query(['squeue','-h','-u','sunyiq','-o','%i|%T|%Z|%e|%l|%P|%C|%b|%N']),query(['sacct','-n','-X','-j',job,'--format=JobID,State,ExitCode,Elapsed,NodeList,Reason','-P'])]
record={'status':'registered_covariance_formal_recovery_queue_detail','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'root':str(root),'case':case,'job_id':job,'queries':queries,'members':members,'formal_complete_exists':root.joinpath('records',case,'training_complete.json').exists(),'scientific_configuration_changed':False,'evaluation_values_read':False,'checkpoints_loaded':False}
for n in ('recovery_backfill_adjustment_20261012.response.json','gpu_binding_'+job+'.json','gpu_acceptance_'+job+'.json'):
    p=root/'records'/n
    if p.exists():record[n]=json.loads(p.read_text())
for p in root.joinpath('logs').glob('*_'+job+'.out'):
    with p.open('rb') as f:f.seek(max(0,p.stat().st_size-12000));record['log_tail']=f.read().decode('utf-8',errors='replace')
columns=['JobID','State','ExitCode','Start','End','Elapsed','Timelimit','NodeList','AllocTRES']
terminal=query(['sacct','-n','-X','-j',job,'--format='+','.join(columns),'-P'])
record['queries'].append(terminal)
if terminal['returncode']==0:
    line=next((line for line in terminal['stdout'].splitlines() if line.startswith(job+'|')),None)
    if line:
        fields=dict(zip(columns,line.split('|')))
        if fields['State'].split()[0] in ('FAILED','COMPLETED','TIMEOUT','CANCELLED'):
            record['terminal_accounting_fields']=fields
record['failure_records']={}
for rid in record['members']:
    p=root/'runs'/rid/'failure.json'
    if p.exists():record['failure_records'][rid]=json.loads(p.read_text())
critical=root/'runs'/('explicit_gru__historical_capacity__tune_branch__filter_joint__s101__lr0p003')
record['failure_artifact_inventory']=[{'name':p.name,'bytes':p.stat().st_size,'mtime_ns':p.stat().st_mtime_ns} for p in sorted(critical.iterdir()) if p.is_file()]
print(json.dumps(record,sort_keys=True))
PY

set +u
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'FAILURE_CP'
"""CPU audit of complete member histories, parameters, Adam and source identity.

No model or data loader runs. Source failures and all old artifacts stay intact.
Run before every scheduler continuation; each immutable audit is retained.
"""
import datetime
import hashlib
import json
from pathlib import Path

import torch
import sys
sys.path.insert(0,'/data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_004/hpc')

import prepare_covariance_recovery_20261015 as h

ROOT = Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261015_recovery_004')
CASE = 'explicit_gru__historical_capacity'


def tensor_list(value):
    if isinstance(value, torch.Tensor):
        return [value]
    if isinstance(value, dict):
        return sum([tensor_list(value[k]) for k in sorted(value, key=repr)], [])
    if isinstance(value, (list, tuple)):
        return sum([tensor_list(x) for x in value], [])
    return []


def main():
    prep = h.read(ROOT/'records/recovery_preparation_complete.json')
    intent = h.read(ROOT/'records/covariance_recovery_intent_20261015.json')
    auth = h.read(ROOT/'records/authorization.json')
    assert h.code_identity() == auth['code_hash'] == prep['recovery_code_hash']
    assert h.sha(ROOT/'configs/protocol-v3.json') == auth['protocol_sha256']
    assert h.code_identity(h.PARENT) == intent['source_code_hash']
    assert all(h.sha(Path(p)) == digest for p, digest in intent['pinned_source_files'].items())
    assert str(h.read(ROOT/'records/scheduler_jobs.json')[CASE])=='242609'
    import subprocess
    q=subprocess.run(['squeue','-h','-u','sunyiq','-o','%i|%T'],capture_output=True,text=True,check=True)
    assert not any(line.startswith('242609|') for line in q.stdout.splitlines()), 'failed source still active'
    rows = []
    for m in prep['migrations']:
        source = Path(m['source_root'])/'runs'/m['run']
        target = ROOT/'runs'/m['run']
        assert all(h.sha(source/name) == expected for name, expected in m['source_files'].items())
        old = torch.load(source/'continuation.pt', map_location='cpu', weights_only=True)
        raw = (target/'continuation.pt').read_bytes()
        import io
        new = torch.load(io.BytesIO(raw), map_location='cpu', weights_only=True)
        h.finite(new)
        n, count = len(old['values']), len(new['values'])
        assert count >= n and n == m['epochs_preserved']
        assert all(new[k][:n] == old[k] and len(new[k]) == count for k in ('values', 'train_metrics', 'shuffle_hashes'))
        assert new['config_sha256'] == m['recovery_config_sha256'] == h.sha(target/'config.json')
        before = [float(s['step']) for s in old['optimizer']['state'].values()]
        after = [float(s['step']) for s in new['optimizer']['state'].values()]
        assert len(before) == len(after) and min(b-a for a, b in zip(before, after)) >= 0
        changed = any(not torch.equal(a, b) for a, b in zip(tensor_list(old['current']), tensor_list(new['current'])))
        if count > n:
            assert changed and min(b-a for a, b in zip(before, after)) > 0
        else:
            assert h.state_hash({k:v for k,v in new.items() if k != 'config_sha256'}) == m['training_state_semantic_sha256']
        failure_path=target/'failure.json'
        failure=h.read(failure_path)
        assert failure['status']=='failed' and failure['reason']=='invalid covariance'
        assert failure['evidence']['shape']==[16,128,128] and failure['epochs_completed']==count
        rows.append({'run':m['run'], 'source_epochs':n, 'current_saved_epochs':count,
                     'added_complete_epochs':count-n, 'minimum_added_optimizer_steps':min(b-a for a,b in zip(before,after)),
                     'current_parameters_differ':changed, 'current_checkpoint_sha256':hashlib.sha256(raw).hexdigest(),
                     'checkpoint_bytes':len(raw), 'source_files_unchanged':True, 'all_source_histories_preserved':True,
                     'configuration_binding_verified':True, 'all_saved_tensors_finite':True, 'failure':failure, 'failure_sha256':h.sha(failure_path)})
        del old, new, raw
    at = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8)))
    jobs_path = ROOT/'records/scheduler_jobs.json'
    jobs = h.read(jobs_path) if jobs_path.exists() else {}
    audit = {'status':'covariance_failed_checkpoint_audit_preserved', 'checked_at_beijing':at.isoformat(),
             'case':CASE, 'root':str(ROOT), 'job_id':jobs.get(CASE), 'members':rows,
             'additional_complete_member_epochs':sum(x['added_complete_epochs'] for x in rows),
             'code_hash':auth['code_hash'], 'source_code_hash':intent['source_code_hash'],
             'all_source_bytes_unchanged':True, 'any_new_failure_file':True, 'continuation_admitted':False,
             'scientific_protocol_unchanged':True, 'training_or_checkpoint_files_written':False,
             'evaluation_values_read':False}
    path = ROOT/'records'/('covariance_failed_checkpoint_audit_'+at.strftime('%Y%m%d_%H%M%S_%f')+'.json')
    h.write(path, audit)
    latest = ROOT/'records/covariance_failed_checkpoint_audit_latest.json'
    temporary = latest.with_name(latest.name+'.tmp')
    h.write(temporary, dict(audit, immutable_record=str(path), immutable_record_sha256=h.sha(path)))
    temporary.replace(latest)
    print(json.dumps(audit, sort_keys=True), flush=True)


if __name__ == '__main__':
    main()

FAILURE_CP

python3 -B /data1/home/sunyiq/zhenjiang_validation_covariance_diagnostic_20261015_001/hpc/probe_covariance_diagnostic.py

python3 -B /data1/home/sunyiq/zhenjiang_validation_sigma_gpu_audit_20261015_001/hpc/probe_covariance_diagnostic.py

python3 -B /data1/home/sunyiq/zhenjiang_validation_cholesky_guard_diagnostic_20261015_001/hpc/probe_covariance_diagnostic.py

python3 -B /data1/home/sunyiq/zhenjiang_validation_posterior_diagnostic_20261015_001/hpc/probe_covariance_diagnostic.py

python3 -B /data1/home/sunyiq/zhenjiang_validation_joseph_compensation_20261015_001/hpc/probe_covariance_diagnostic.py
