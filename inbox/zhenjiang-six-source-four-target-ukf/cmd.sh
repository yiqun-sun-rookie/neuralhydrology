#!/usr/bin/env bash
# current-observation evaluation read-only query sequence 109
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'ZJ_ALIGNED_STATUS_PY'
ROOT_TEXT = '/data1/home/sunyiq/zhenjiang_latest_observation_reencoding_20260914_001'
JOB_ID = '225727'
MANIFEST_HASH = 'd6bce1789dd2daf2057c742a4dba2682fa47c8c2f7a8907ed518acf72cdc3583'

import hashlib, json, os, re, stat, subprocess
from pathlib import Path
from datetime import datetime, timezone
root = Path(ROOT_TEXT)
def digest(raw): return hashlib.sha256(raw).hexdigest()
def safe(path):
    if not path.is_absolute() or '..' in path.parts or any(p.is_symlink() for p in (path,*path.parents)):
        raise ValueError('unsafe evidence path')
    if root not in path.parents:
        raise ValueError('query outside new root')
    return path
def read(path):
    with safe(path).open('rb') as handle:
        if not stat.S_ISREG(os.fstat(handle.fileno()).st_mode):
            raise ValueError('regular evidence file required')
        raw = handle.read(12000001)
    if len(raw)>12000000: raise ValueError('evidence exceeds fixed read limit')
    return raw
def file_record(name,include=False,tail=None):
    try:
        path = safe(root/name)
        if not path.exists(): return {'path':name,'exists':False}
        before = path.stat()
        if not stat.S_ISREG(before.st_mode): raise ValueError('not a regular file')
        raw = read(path)
        after = path.stat()
        record = {'path':name,'exists':True,'size_bytes':len(raw),'sha256':digest(raw),
                  'stable_during_read':(before.st_size,before.st_mtime_ns)==(after.st_size,after.st_mtime_ns)}
        if include: record['raw_utf8']=raw.decode('utf-8')
        elif tail is not None: record['tail_utf8']=raw[-tail:].decode('utf-8',errors='replace')
        return record
    except Exception as error:
        return {'path':name,'error':type(error).__name__+': '+str(error)}
manifest_raw = read(root/'bundle_manifest.json')
if digest(manifest_raw)!=MANIFEST_HASH: raise ValueError('manifest trust anchor differs')
manifest = json.loads(manifest_raw)
if manifest['remote_root'] != ROOT_TEXT: raise ValueError('root identity differs')
receipt = json.loads(read(root/'evidence/submission/attempt_001/submission_receipt.json'))
if receipt['job_id']!=JOB_ID: raise ValueError('job identity differs')
report = {'schema_version':'zhenjiang-aligned-readonly-status-v1','job_id':JOB_ID,
          'remote_root':ROOT_TEXT,'manifest_sha256':MANIFEST_HASH,
          'observed_at_utc':datetime.now(timezone.utc).isoformat(),
          'formal_input_or_checkpoint_reads':0,'remote_writes_by_query':0}
report['scheduler']=[]
for command in (
    ['squeue','-h','-j',JOB_ID,'-o','%i|%T|%M|%R|%N'],
    ['sacct','-j',JOB_ID,'-X','--noheader','--parsable2','--format=JobIDRaw,State,ExitCode,Start,End,Elapsed,NodeList'],
    ['scontrol','show','job',JOB_ID]):
    response = subprocess.run(command,capture_output=True,check=False,timeout=20)
    report['scheduler'].append({'command':command,'returncode':response.returncode,
                               'stdout':response.stdout.decode(errors='replace'),
                               'stderr':response.stderr.decode(errors='replace')})
names = [
    'evidence/submission/attempt_001/requested.json','evidence/submission/attempt_001/stdout.txt',
    'evidence/submission/attempt_001/stderr.txt','evidence/submission/attempt_001/exit_status.json',
    'evidence/submission/attempt_001/submission_receipt.json','evidence/submission/attempt_001/failure.json',
    'evidence/evaluation_attempt_001/requested.json','evidence/evaluation_attempt_001/gpu_preflight.json',
    'evidence/evaluation_attempt_001/completion.json','evidence/evaluation_attempt_001/failure.json',
    'evidence/runner_exit_status.json',
    'runs/evaluation_2022/summary.json','runs/evaluation_2022/block_statistics.json',
    'runs/evaluation_2022/completion.json']
report['files']=[file_record(name,include=True) for name in names]
report['files'].append(file_record('evidence/formal_input_usage.sqlite3'))
for suffix in ('out','err'):
    report['files'].append(file_record('logs/slurm-'+JOB_ID+'.'+suffix,tail=40000))
report['source_identity_checks']=[]
for spec in manifest['source_files']:
    name=spec['relative_path']
    if not name or '\\' in name or ':' in name or any(p in ('','.','..') for p in name.split('/')):
        raise ValueError('invalid registered source path')
    record=file_record(name)
    report['source_identity_checks'].append({'path':name,
        'matched':record.get('sha256')==spec['sha256'] and record.get('size_bytes')==spec['byte_count']
                  and record.get('stable_during_read') is True})
print('ZJ_ALIGNED_STATUS_JSON_BEGIN')
print(json.dumps(report,sort_keys=True,separators=(',',':')))
print('ZJ_ALIGNED_STATUS_JSON_END')

ZJ_ALIGNED_STATUS_PY
