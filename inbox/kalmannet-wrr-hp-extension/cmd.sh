#!/usr/bin/env bash
# READ-ONLY queue/priority diagnostic for the A800 retry array 224389 (hgpu8 / ngu201).
# Why is it PENDING (Priority) for >29 h with zero startups? Only scheduler *query* commands are used:
# sinfo / squeue / sprio / sshare / sacct / scontrol show. No sbatch, scancel, scontrol update/hold/release.
set -uo pipefail
python3 -I -B - <<'PY'
import base64
import datetime
import gzip
import hashlib
import json
import pathlib
import subprocess

ROOT = pathlib.Path('/data1/home/sunyiq/kalmannet_wrr_model_selection_20260908/resource_recovery_20260909/B_retry1')
LIMIT = 200_000  # bytes of stdout kept per query

def run(argv, timeout=60):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False)
        out, err, rc = p.stdout, p.stderr, p.returncode
    except Exception as exc:  # timeout / missing binary: record, never abort the diagnostic
        out, err, rc = '', f'{type(exc).__name__}: {exc}', -1
    return {'command': argv, 'returncode': rc,
            'stdout': out[:LIMIT], 'stdout_truncated': len(out) > LIMIT, 'stderr': err[:4000]}

queries = {}
# 1. the retry array itself
queries['squeue_retry'] = run(['squeue', '-r', '-j', '224389', '-h', '-o', '%i|%T|%r|%Q|%p|%R|%S|%l|%b|%D|%C|%m'])
queries['squeue_retry_start_estimate'] = run(['squeue', '--start', '-r', '-j', '224389'])
queries['scontrol_show_job_retry'] = run(['scontrol', 'show', 'job', '224389'])
queries['sprio_retry'] = run(['sprio', '-j', '224389', '-o', '%i|%u|%Y|%A|%F|%J|%P|%Q|%T|%N'])
# 2. the target node and partition
queries['sinfo_node_ngu201'] = run(['sinfo', '-N', '-n', 'ngu201', '-o', '%N|%P|%T|%C|%G|%m|%e|%E'])
queries['scontrol_show_node_ngu201'] = run(['scontrol', 'show', 'node', 'ngu201'])
queries['squeue_jobs_on_ngu201'] = run(['squeue', '-w', 'ngu201', '-o', '%i|%u|%j|%P|%T|%M|%l|%b|%N|%Q'])
queries['sinfo_partition_hgpu8'] = run(['sinfo', '-p', 'hgpu8', '-N', '-o', '%N|%T|%C|%G|%m|%e|%E'])
queries['sinfo_partition_hgpu8_summary'] = run(['sinfo', '-p', 'hgpu8', '-s', '-o', '%P|%a|%l|%F|%G'])
queries['scontrol_show_partition_hgpu8'] = run(['scontrol', 'show', 'partition', 'hgpu8'])
queries['squeue_partition_hgpu8'] = run(['squeue', '-p', 'hgpu8', '-r', '-o', '%i|%u|%j|%T|%M|%l|%D|%b|%Q|%r|%N|%S'])
queries['sprio_partition_hgpu8'] = run(['sprio', '-p', 'hgpu8', '-o', '%i|%u|%Y|%A|%F|%J|%P|%Q|%T|%N'])
queries['scontrol_show_reservation'] = run(['scontrol', 'show', 'reservation'])
# 3. fairshare / account context
queries['sshare_self'] = run(['sshare', '-u', 'sunyiq', '-o', 'Account,User,RawShares,NormShares,RawUsage,EffectvUsage,FairShare'])
queries['sacct_ngu201_recent'] = run(['sacct', '-a', '-N', 'ngu201', '-S', '2026-09-09T00:00:00', '-X', '-n', '-P',
                                     '--format=JobID,User,Partition,State,Start,End,Elapsed,AllocTRES,ReqNodes'])
queries['squeue_self_all'] = run(['squeue', '-u', 'sunyiq', '-r', '-o', '%i|%j|%P|%T|%M|%b|%N|%r'])

# 4. what exactly the retry requested (read-only look at the pinned batch script header)
sbatch_lines = None
try:
    data = (ROOT / 'retry.slurm').read_bytes()
    sbatch_lines = {'sha256': hashlib.sha256(data).hexdigest(),
                    'sbatch_directives': [l for l in data.decode(errors='replace').splitlines() if l.startswith('#SBATCH')]}
except Exception as exc:
    sbatch_lines = {'error': f'{type(exc).__name__}: {exc}'}

report = {'kind': 'READ_ONLY_RETRY_QUEUE_DIAGNOSTIC_NOT_ADMISSION',
          'observed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'retry_job_id': '224389', 'partition': 'hgpu8', 'required_node': 'ngu201',
          'queries': queries, 'retry_slurm_header': sbatch_lines,
          'new_jobs_submitted': 0, 'jobs_modified_or_cancelled': 0, 'data_or_checkpoint_tensors_loaded': False}
blob = json.dumps(report, sort_keys=True, separators=(',', ':')).encode()
print('QUEUE_DIAGNOSTIC_GZIP_BASE64=' + base64.b64encode(gzip.compress(blob, mtime=0)).decode())

# human-readable summary (plain text, so the receipt is legible without decoding)
def section(name):
    q = queries[name]
    print(f'--- {name} rc={q["returncode"]}' + (' (truncated)' if q['stdout_truncated'] else ''))
    print(q['stdout'].rstrip() if q['stdout'].strip() else '(empty)')
    if q['stderr'].strip():
        print('stderr: ' + q['stderr'].strip()[:1000])
print('=== RETRY SLURM HEADER ===')
print(json.dumps(sbatch_lines, ensure_ascii=False))
for name in ['squeue_retry', 'squeue_retry_start_estimate', 'sprio_retry', 'sinfo_node_ngu201', 'scontrol_show_node_ngu201',
             'squeue_jobs_on_ngu201', 'sinfo_partition_hgpu8', 'sinfo_partition_hgpu8_summary', 'scontrol_show_partition_hgpu8',
             'scontrol_show_reservation', 'sshare_self', 'squeue_self_all']:
    section(name)
q = queries['squeue_partition_hgpu8']
print(f'--- squeue_partition_hgpu8 rc={q["returncode"]} lines={len(q["stdout"].splitlines())} (full text in gzip payload)')
print('\n'.join(q['stdout'].splitlines()[:60]))
q = queries['sprio_partition_hgpu8']
print(f'--- sprio_partition_hgpu8 rc={q["returncode"]} lines={len(q["stdout"].splitlines())} (full text in gzip payload)')
print('\n'.join(q['stdout'].splitlines()[:60]))
q = queries['sacct_ngu201_recent']
print(f'--- sacct_ngu201_recent rc={q["returncode"]} lines={len(q["stdout"].splitlines())} (full text in gzip payload)')
print('\n'.join(q['stdout'].splitlines()[:40]))
q = queries['scontrol_show_job_retry']
print(f'--- scontrol_show_job_retry rc={q["returncode"]}')
print(q['stdout'].rstrip()[:6000])
PY
