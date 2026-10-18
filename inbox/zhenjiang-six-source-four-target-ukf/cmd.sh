#!/usr/bin/env bash
set -euo pipefail
python3 - <<'PY'
import contextlib,datetime,io,json,os,pathlib,subprocess
ORIGINAL=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261006_002')
ROOTS={'legacy_lstm__small':pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261008_recovery_002'),'explicit_gru__historical_capacity':pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261017_sqrt_recovery_001'),'explicit_gru__small':ORIGINAL,'legacy_lstm__historical_capacity':ORIGINAL}
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
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261017_sqrt_recovery_001')
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
for n in ('recovery_backfill_adjustment_20261012.response.json','gpu_binding_'+job+'.json','sqrt_hardware_'+job+'.json','bootstrap_original39_'+job+'.json','sqrt_bootstrap_'+job+'.json'):
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
export CUDA_VISIBLE_DEVICES=""
python -B - <<'JOSEPH_CPU'
import datetime,json,pathlib,subprocess,sys
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261017_sqrt_recovery_001')
p=subprocess.run([sys.executable,'-B',str(root/'hpc/audit_sqrt_formal_20261017.py')],capture_output=True,text=True)
if p.returncode==0:
    docs=[json.loads(line) for line in p.stdout.splitlines() if line.startswith('{')]
    assert len(docs)==1 and docs[0]['status']=='covariance_recovery_continuation_checkpoint_audit_passed'
    print(json.dumps(docs[0],sort_keys=True))
else:
    jobs=json.loads((root/'records/scheduler_jobs.json').read_text())
    print(json.dumps({'status':'covariance_checkpoint_audit_failed_preserved','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'root':str(root),'job_id':jobs['explicit_gru__historical_capacity'],'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr,'continuation_admitted':False,'formal_recovery_confirmed':False,'evaluation_values_read':False},sort_keys=True))
JOSEPH_CPU

python -B - <<'SAVED_MINIMUM_EVIDENCE'
"""Read saved evidence only; no model, data arrays, or optimizer execution."""
import datetime
import hashlib
import io
import json
import math
import os
from pathlib import Path
import re
import statistics

BASE = Path('/data1/home/sunyiq')
ROOT = BASE / 'zhenjiang_complete_comparison_20261017_sqrt_recovery_001'
EARLY = BASE / 'zhenjiang_complete_comparison_20261006_recovery_001'
RUNS = {m: 'explicit_gru__historical_capacity__tune_branch__' + m + '__s101__lr0p003'
        for m in ('encoder_joint', 'filter_joint')}
EXPECTED = {'encoder_joint': '6ce7c639d80ce5c5ca7b5e6c46da2943b8cac2d800b6b285557f78822f323108',
            'filter_joint': '707e2a3c547b5d01fb7ab0ab87316750335c32247aa14c5fa46b0e3237504efe'}


def semantic_hash(value, torch):
    # Exact preserved 540/582/embedded238 algorithm.
    h = hashlib.sha256()
    def visit(x):
        if isinstance(x, torch.Tensor):
            assert x.device.type == 'cpu'
            x = x.detach().contiguous()
            h.update(str((str(x.dtype), tuple(x.shape))).encode())
            h.update(x.reshape(-1).view(torch.uint8).numpy().tobytes())
        elif isinstance(x, dict):
            for key in sorted(x, key=repr):
                h.update(repr(key).encode())
                visit(x[key])
        elif isinstance(x, (list, tuple)):
            h.update(str(len(x)).encode())
            for item in x:
                visit(item)
        else:
            h.update(json.dumps(x, sort_keys=True, allow_nan=False).encode())
    visit(value)
    return h.hexdigest()


def stats(values):
    finite = [v for v in values if math.isfinite(v)]
    return {'count': len(values), 'nonfinite_count': len(values)-len(finite),
            'min': min(finite, default=None),
            'median': statistics.median(finite) if finite else None,
            'max': max(finite, default=None)}


def batch_row(epoch, index, row):
    ledger = row.get('stability', {})
    return {'epoch': epoch, 'effective_batch_index_1based': index+1,
            **{k: row.get(k) for k in ('actual_batch_size', 'loss_cm', 'gradient_norm_before_clip')},
            'stability': {k: ledger.get(k) for k in
                          ('analysis_steps', 'max_jitter', 'large_jitter_fraction')}}


def summarize_epochs(metrics, epochs):
    out = []
    for epoch in epochs:
        if epoch > len(metrics.get('train_metrics', [])):
            out.append({'epoch': epoch, 'status': 'missing_saved_formal_batches'})
            continue
        rows = metrics['train_metrics'][epoch-1]
        losses = [r['loss_cm'] for r in rows]
        norms = [r['gradient_norm_before_clip'] for r in rows]
        n = sum(r['actual_batch_size'] for r in rows)
        jitters = [j for r in rows for j in r.get('stability', {}).get('step_jitters', [])]
        windows, hits = set(), []
        for threshold in (100, 1e6):
            first = next((i for i, r in enumerate(rows) if r['loss_cm'] > threshold), None)
            hits.append({'descriptive_loss_threshold_cm': threshold,
                         'first_batch_1based': None if first is None else first+1})
            if first is not None:
                windows.update(range(max(0, first-2), min(len(rows), first+3)))
        out.append({'epoch': epoch, 'saved_effective_batch_count': len(rows),
                    'training_window_count': n, 'loss_cm': stats(losses),
                    'gradient_norm_before_clip': stats(norms),
                    'batch_size_weighted_mean_of_batch_losses_cm':
                        math.fsum(r['loss_cm']*r['actual_batch_size'] for r in rows)/n
                        if n and all(math.isfinite(v) for v in losses) else None,
                    'mean_interpretation': 'batch-local loss summary, not recomputed global training MAE',
                    'stability': {'analysis_steps_from_saved_jitters': len(jitters),
                                  'max_jitter': max(jitters, default=None),
                                  'large_jitter_steps_gt1e_6': sum(j > 1e-6 for j in jitters)},
                    'actual_shuffle_sha256': metrics.get('shuffle_hashes', [])[epoch-1]
                        if epoch <= len(metrics.get('shuffle_hashes', [])) else None,
                    'first_anomaly_thresholds': hits,
                    'near_first_anomaly_batches': [batch_row(epoch, i, rows[i]) for i in sorted(windows)]})
    return out


def load_saved_checkpoint(path, torch):
    raw = path.read_bytes()
    state = torch.load(io.BytesIO(raw), map_location='cpu', weights_only=True)
    return state, hashlib.sha256(raw).hexdigest()


def finite_state(value, torch):
    if isinstance(value, torch.Tensor):
        return bool(torch.isfinite(value).all())
    if isinstance(value, dict):
        return all(finite_state(v, torch) for v in value.values())
    if isinstance(value, (list, tuple)):
        return all(finite_state(v, torch) for v in value)
    return True


def original_epoch_inventory(torch):
    prefixes = ('zhenjiang_complete_comparison_', 'zhenjiang_sqrt_covariance_repair_',
                'zhenjiang_training_covariance_failure_006_guarded_')
    folders, hits, errors = [], [], []
    for root in sorted(p for p in BASE.iterdir() if p.is_dir() and p.name.startswith(prefixes)):
        for method, run in RUNS.items():
            target = 31 if method == 'encoder_joint' else 33
            for folder in (root/'runs'/run, root/'source/runs'/run):
                if not folder.is_dir():
                    continue
                files = sorted(p for p in folder.iterdir() if p.is_file())
                info = {'run': run, 'folder': str(folder),
                        'state_and_identity_file_names': [p.name for p in files if p.suffix in ('.pt','.pth','.ckpt')
                            or any(w in p.name.lower() for w in ('hash','sha256','sha1','identity','manifest','provenance'))],
                        'saved_complete_epochs': None}
                metrics = folder/'metrics.json'
                if metrics.exists():
                    try:
                        with metrics.open('rb') as stream:
                            prefix = stream.read(131072).decode('utf-8')
                        match = re.search(r'"validation_mae_cm"\s*:\s*', prefix)
                        values, _ = json.JSONDecoder().raw_decode(prefix[match.end():])
                        info['saved_complete_epochs'] = len(values)
                    except Exception as exc:
                        errors.append({'path': str(metrics), 'error': type(exc).__name__})
                folders.append(info)
                for p in files:
                    # Only epoch-labelled copies or identity metadata qualify for inspection.
                    explicit_epoch = bool(re.search(r'(?:epoch|ep)[_-]?0*'+str(target)+r'(?:\D|$)', p.name, re.I))
                    exact_continuation = p.name == 'continuation.pt' and info['saved_complete_epochs'] == target
                    hash_metadata = p.suffix == '.json' and any(w in p.name.lower() for w in ('hash', 'sha256', 'sha1', 'identity', 'manifest', 'provenance'))
                    if not (explicit_epoch or exact_continuation or hash_metadata):
                        continue
                    row = {'path': str(p), 'run': run, 'target_epoch': target,
                           'bytes': p.stat().st_size, 'explicit_epoch_name': explicit_epoch,
                           'exact_epoch_continuation': exact_continuation}
                    if p.suffix in ('.pt', '.pth', '.ckpt') and p.stat().st_size <= 128*1024*1024:
                        try:
                            state, digest = load_saved_checkpoint(p, torch)
                            row['file_sha256'] = digest
                            row['semantic_sha256'] = semantic_hash(state.get('current', state), torch)
                            row['embedded_complete_epochs'] = len(state['values']) if 'values' in state else None
                            row['independence_requires_source_time_and_run_binding'] = True
                        except Exception as exc:
                            row['error'] = type(exc).__name__
                    elif hash_metadata and p.stat().st_size <= 1024*1024:
                        raw = p.read_bytes(); row['file_sha256'] = hashlib.sha256(raw).hexdigest()
                        row['text_epoch_and_hash_label_match'] = bool(re.search(
                            r'(?:epoch|ep)["\s_:-]*0*'+str(target)+r'\b', raw.decode('utf-8', errors='replace'), re.I))
                        candidates = []
                        def find_hashes(obj, pointer=''):
                            if len(candidates) >= 12:
                                return
                            if isinstance(obj, dict):
                                epoch_fields = {k:v for k,v in obj.items() if k in
                                                ('epoch','best_epoch','complete_epochs','completed_epochs')}
                                if target in epoch_fields.values():
                                    hashes = {k:v for k,v in obj.items() if ('hash' in k.lower() or 'sha' in k.lower())
                                              and isinstance(v,str) and re.fullmatch(r'[a-fA-F0-9]{40,64}',v)}
                                    if hashes:
                                        candidates.append({'pointer':pointer,'epoch_fields':epoch_fields,'hashes':hashes})
                                for key,value in obj.items():
                                    find_hashes(value,pointer+'/'+str(key))
                            elif isinstance(obj,list):
                                for i,value in enumerate(obj):
                                    find_hashes(value,pointer+'/'+str(i))
                        try:
                            find_hashes(json.loads(raw))
                            row['target_epoch_labelled_hash_records'] = candidates
                        except ValueError:
                            row['json_valid'] = False
                    elif explicit_epoch and p.suffix in ('.sha256','.sha1','.sha','.txt') and p.stat().st_size <= 4096:
                        raw=p.read_bytes();row['file_sha256']=hashlib.sha256(raw).hexdigest()
                        row['existing_text_hash_tokens']=re.findall(r'\b[a-fA-F0-9]{40,64}\b',raw.decode('utf-8',errors='replace'))[:12]
                    hits.append(row)
    return {'scope': 'registered related project roots; exact runs and source/runs directories; direct saved files only',
            'folders': folders, 'candidate_epoch_copies_or_hash_metadata': hits, 'read_errors': errors,
            'strict_independent_epoch_identity_confirmed': False,
            'limit': 'No proof of global absence; archive interiors and unrelated projects not searched. A later embedded best is not an independent original-epoch copy.'}


def safe_json(x):
    if isinstance(x, float) and not math.isfinite(x):
        return str(x)
    if isinstance(x, dict):
        return {k: safe_json(v) for k, v in x.items()}
    if isinstance(x, (list, tuple)):
        return [safe_json(v) for v in x]
    return x


def main():
    os.environ['CUDA_VISIBLE_DEVICES'] = ''
    import torch
    torch.set_num_threads(1)
    torch.set_num_interop_threads(1)
    report = {'status': 'saved_branch_minimum_evidence_readonly',
              'checked_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'model_constructed': False, 'forward_backward_or_optimizer_step': False,
              'training_input_arrays_read': False, 'filter_epochs38_40_rerequested': False,
              'checkpoint_load_mode': 'cpu weights_only=True', 'branches': {}, 'errors': []}
    for method, run in RUNS.items():
        folder = ROOT/'runs'/run
        row = {'run': run, 'path': str(folder/'continuation.pt')}
        try:
            state, digest = load_saved_checkpoint(folder/'continuation.pt', torch)
            raw_config = (folder/'config.json').read_bytes(); config = json.loads(raw_config)
            values = state['values']; best_hash = semantic_hash(state['best'], torch)
            row.update(checkpoint_sha256=digest, complete_saved_epochs=len(values),
                       config_sha256=hashlib.sha256(raw_config).hexdigest(),
                       protocol_sha256=config.get('protocol_sha256'),
                       registration_run_id=config.get('registration',{}).get('exp_id'),
                       registration_seed=config.get('registration',{}).get('seed'),
                       learning_rate=config.get('effective_config',{}).get('learning_rate'),
                       best_state_semantic_sha256=best_hash,
                       current_state_semantic_sha256=semantic_hash(state['current'], torch),
                       best_equals_independent540_source=best_hash == EXPECTED[method],
                       independent540_source_best_hash=EXPECTED[method],
                       earliest_validation_argmin_epoch=values.index(min(values))+1,
                       checkpoint_config_binding=state['config_sha256']==hashlib.sha256(raw_config).hexdigest(),
                       code_hash=config.get('effective_config',{}).get('code_hash'),
                       code_hash_matches_current_registered_root=config.get('effective_config',{}).get('code_hash')=='00ed010da5b881c4a49e649c3c8ccf5017dd684ed94dfd22fb242c0a3a975c4e',
                       all_current_and_best_tensors_finite=finite_state(state['current'],torch) and finite_state(state['best'],torch))
            if method == 'encoder_joint':
                metrics_raw = (folder/'metrics.json').read_bytes(); metrics = json.loads(metrics_raw)
                row['formal_metrics_sha256'] = hashlib.sha256(metrics_raw).hexdigest()
                row['encoder_formal_epochs40_42'] = summarize_epochs(metrics, (40,41,42))
                row['selected_metrics_equal_checkpoint'] = all(
                    metrics['train_metrics'][e-1] == state['train_metrics'][e-1]
                    and metrics['shuffle_hashes'][e-1] == state['shuffle_hashes'][e-1]
                    for e in (40,41,42))
                frozen_path = BASE/'zhenjiang_complete_comparison_20261016_recovery_006/runs'/run/'metrics.json'
                if frozen_path.exists():
                    frozen_raw=frozen_path.read_bytes();frozen=json.loads(frozen_raw)
                    row['frozen_source006_metrics_identity'] = {'path':str(frozen_path),
                        'sha256':hashlib.sha256(frozen_raw).hexdigest(),
                        'epochs40_42_batches_and_shuffle_match_current':all(
                            frozen['train_metrics'][e-1]==metrics['train_metrics'][e-1]
                            and frozen['shuffle_hashes'][e-1]==metrics['shuffle_hashes'][e-1] for e in (40,41,42))}
                early_path = EARLY/'runs'/run/'metrics.json'
                if early_path.exists():
                    early_raw=early_path.read_bytes();early=json.loads(early_raw)
                    row['frozen_early_metrics_identity'] = {'path': str(early_path),
                        'sha256':hashlib.sha256(early_raw).hexdigest(),
                        'equals_recorded217_sha256':hashlib.sha256(early_raw).hexdigest()=='2f73cc3ada6a36bdedd4b4caf53edf51e93f83c5dd2ec109e92d0f8bc6a445fd',
                        'epochs40_41_batches_and_shuffle_match_current':all(
                            early['train_metrics'][e-1]==metrics['train_metrics'][e-1]
                            and early['shuffle_hashes'][e-1]==metrics['shuffle_hashes'][e-1] for e in (40,41))}
        except Exception as exc:
            row['error'] = type(exc).__name__+': '+str(exc)[:400]
            report['errors'].append({'run':run, 'error':row['error']})
        report['branches'][method] = row
    try:
        report['original_epoch31_33_inventory'] = original_epoch_inventory(torch)
    except Exception as exc:
        report['original_epoch31_33_inventory'] = {'status':'inventory_incomplete',
            'error':type(exc).__name__+': '+str(exc)[:400],
            'strict_independent_epoch_identity_confirmed':False}
    report['finished_at_utc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    print(json.dumps(safe_json(report),sort_keys=True,allow_nan=False))


if __name__ == '__main__':
    try:
        main()
    except Exception as exc:
        print(json.dumps({'status':'saved_branch_minimum_evidence_unavailable',
            'checked_at_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'error':type(exc).__name__+': '+str(exc)[:400],
            'model_constructed':False,'forward_backward_or_optimizer_step':False}))

SAVED_MINIMUM_EVIDENCE
