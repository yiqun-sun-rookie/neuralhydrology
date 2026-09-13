#!/usr/bin/env bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'ZJ_CUKF_STATUS_PY'
import base64, hashlib, json, os, stat, subprocess
from pathlib import Path
from datetime import datetime, timezone, timedelta
root = Path('/data1/home/sunyiq/zhenjiang_continuous_ukf_20260913_003')
job_id = '225485'
expected_manifest = 'c54b7ff1c92818bd9aef1461aba943c475cd6ae9981401e1d2bf7f5d88773d08'
def safe(path):
    if '..' in path.parts or not path.is_absolute() or any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError('unsafe evidence path')
    return path
def read(path):
    path = safe(path)
    with path.open('rb') as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode): raise ValueError('not regular evidence')
        return stream.read()
def digest(data): return hashlib.sha256(data).hexdigest()
def file_record(relative, include=False, tail_bytes=None):
    path = safe(root / relative)
    if not path.exists(): return {'path': relative, 'exists': False}
    before = path.stat()
    if not stat.S_ISREG(before.st_mode): raise ValueError('not regular evidence')
    hasher = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1048576), b''): hasher.update(chunk)
    after = path.stat()
    result = {'path': relative, 'exists': True, 'size_bytes': after.st_size,
              'sha256': hasher.hexdigest(), 'mtime_ns': after.st_mtime_ns,
              'stable_during_hash': (before.st_size, before.st_mtime_ns)==(after.st_size, after.st_mtime_ns)}
    if include:
        content = read(path)
        if len(content) > 2000000: raise ValueError('metadata inclusion exceeds fixed limit')
        result['raw_utf8'] = content.decode('utf-8')
        result['included_content_sha256'] = digest(content)
    elif tail_bytes is not None:
        with path.open('rb') as stream:
            stream.seek(max(0, before.st_size - tail_bytes))
            result['tail_utf8'] = stream.read(tail_bytes).decode('utf-8', errors='replace')
    return result
manifest = read(root / 'bundle_manifest.json')
if digest(manifest) != expected_manifest: raise ValueError('release manifest mismatch')
receipt = json.loads(read(root / 'evidence/submission/attempt_001/submission_receipt.json'))
if str(receipt['job_id']) != job_id: raise ValueError('submission receipt job mismatch')
report = {'schema_version': 'zhenjiang-cukf-readonly-status-v3', 'job_id': job_id,
    'remote_root': str(root), 'observed_at_beijing': datetime.now(timezone(timedelta(hours=8))).isoformat(),
    'manifest_sha256': digest(manifest), 'formal_input_or_checkpoint_reads': 0, 'remote_writes_by_query': 0}
report['scheduler'] = []
for command in (
    ['squeue','-h','-j',job_id,'-o','%i|%T|%M|%R|%N'],
    ['sacct','-j',job_id,'-X','--noheader','--parsable2','--format=JobIDRaw,State,ExitCode,Start,End,Elapsed,NodeList'],
    ['scontrol','show','job',job_id]):
    response = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    report['scheduler'].append({'command': command, 'returncode': response.returncode,
        'stdout': response.stdout.decode('utf-8', errors='replace'), 'stderr': response.stderr.decode('utf-8', errors='replace')})
names = [
'evidence/submission/attempt_001/requested.json','evidence/submission/attempt_001/stdout.txt',
'evidence/submission/attempt_001/stderr.txt','evidence/submission/attempt_001/exit_status.json',
'evidence/submission/attempt_001/submission_receipt.json',
'evidence/job_attempt/attempt_001/requested.json','evidence/job_attempt/attempt_001/nvidia_smi_exit_status.json',
'evidence/job_attempt/attempt_001/symlink_check.json','evidence/job_attempt/attempt_001/runner_exit_status.json',
'evidence/job_attempt/attempt_001/completion.json','evidence/job_attempt/attempt_001/failure.json',
'evidence/continuous_attempt_001/attempt.json','evidence/continuous_attempt_001/failure.json','evidence/continuous_attempt_001/completion.json',
'runs/continuous_2022/completion.json','runs/continuous_2022/summary.json','runs/continuous_2022/block_statistics.json']
report['files'] = [file_record(name, include=True) for name in names]
for name in ['runs/continuous_2022/evaluation_arrays.npz','evidence/continuous_input_usage.sqlite3',
             'runs/continuous_2022/seed_17/noise_A_best.pt','runs/continuous_2022/seed_29/noise_A_best.pt','runs/continuous_2022/seed_43/noise_A_best.pt']:
    report['files'].append(file_record(name))
for name in ['logs/slurm-'+job_id+'.out','logs/slurm-'+job_id+'.err']:
    report['files'].append(file_record(name, tail_bytes=40000))
for seed in ('17','29','43'):
    for tag in ('A','B0','B1','B2','B3','B4'):
        report['files'].append(file_record('runs/continuous_2022/seed_'+seed+'/seed'+seed+'_'+tag+'_batch_updates.jsonl', tail_bytes=6000))
report['source_identity_checks'] = []
for entry in json.loads(manifest)['source_files']:
    record = file_record(entry['relative_path'])
    report['source_identity_checks'].append({'path': entry['relative_path'],
        'matched': record.get('sha256')==entry['sha256'] and record.get('size_bytes')==entry['byte_count']
                   and record.get('stable_during_hash') is True})
report['finished_at_beijing'] = datetime.now(timezone(timedelta(hours=8))).isoformat()
print('ZJ_CUKF_STATUS_JSON_BEGIN')
print(json.dumps(report, sort_keys=True, ensure_ascii=False, separators=(',',':')))
print('ZJ_CUKF_STATUS_JSON_END')
ZJ_CUKF_STATUS_PY
