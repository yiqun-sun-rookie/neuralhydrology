#!/bin/bash
# Prepared only: do not publish until the existing127 has been closed separately.
# Hard limit75s; scheduler subprocesses at most10s each; output at most196608 bytes.
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
timeout 75 /data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
import base64, datetime, fcntl, hashlib, json, os, re, socket, subprocess
from pathlib import Path

ROOT = Path('/data1/home/sunyiq/precip_smallfit_hpc_20261012_v01/20261016T145315Z_af5f130f_v04')
NONCE = 'af5f130f182c4c38ab020520c5374004'
JOB = '244110'
HOST = socket.gethostname().split('.')[0]
now = lambda: datetime.datetime.now(datetime.timezone.utc).isoformat()
out = dict(schema='precip_smallfit_readonly_site_check_v01', job_id=int(JOB), nonce=NONCE,
           remote_root=str(ROOT), sampled_begin_utc=now(), collecting_host=HOST,
           training_or_deployment_started_by_check=False, files_written=False)

def project(value, depth=0):
    if depth > 5:
        return {'omitted_deeper_metadata': True}
    if isinstance(value, dict):
        return {str(k): project(v, depth+1) for k,v in list(value.items())[:40]}
    if isinstance(value, list):
        return dict(length=len(value), first=project(value[:3], depth+1)) if len(value)>3 else [project(v, depth+1) for v in value]
    return value[:2048] if isinstance(value, str) else value

def record(relative):
    p = ROOT / relative
    if not p.exists():
        return dict(present=False)
    if p.is_symlink() or not p.resolve().is_relative_to(ROOT) or not p.is_file():
        return dict(present=True, error='Nonregular_or_escaping_path')
    st = p.stat()
    item = dict(present=True, bytes=st.st_size, mtime_ns=st.st_mtime_ns,
                mtime_utc=datetime.datetime.fromtimestamp(st.st_mtime, datetime.timezone.utc).isoformat())
    with p.open('rb') as stream:
        raw = stream.read(65537)
    if len(raw)>65536:
        return dict(item, content_not_read_reason='Above64KiB_metadata_limit_requires_original_delivery')
    item['sha256'] = hashlib.sha256(raw).hexdigest()
    item['value_is_metadata_projection_not_complete_original'] = True
    try:
        value = json.loads(raw)
        if relative == 'runtime/budget.json':
            value = dict(total_seconds=value.get('total_seconds'), event_count=len(value.get('events',[])),
                         last_three_events=value.get('events',[])[-3:])
        item['value'] = project(value)
    except Exception as error:
        item['error'] = type(error).__name__+': '+str(error)[:512]
    return item

def command(args):
    try:
        q = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=10)
        return dict(args=args, exit_code=q.returncode, stdout_base64=base64.b64encode(q.stdout[:16384]).decode(),
                    stdout_bytes=len(q.stdout), truncated=len(q.stdout)>16384,
                    stdout_text=q.stdout[:16384].decode(errors='replace'))
    except subprocess.TimeoutExpired as error:
        raw = (error.output or b'')[:16384]
        return dict(args=args, timed_out=True, stdout_base64=base64.b64encode(raw).decode())

if ROOT.resolve() != ROOT:
    raise SystemExit('Owned_root_identity_differs')
submission = record('records/submission.json')
identity = submission.get('value', {})
out['submission'] = submission
if str(identity.get('job_id')) != JOB or identity.get('nonce') != NONCE:
    raise SystemExit('Owned_submission_identity_differs')
queue = command(['squeue','-j',JOB,'-h','-o','%i|%T|%N|%R'])
accounting = command(['sacct','-S','2026-10-16','-X','-j',JOB,'-n','-P','-o',
                      'JobIDRaw,State,ExitCode,Submit,Start,End,ElapsedRaw,NodeList'])
out['scheduler'] = [queue, accounting, command(['scontrol','show','job',JOB,'-o'])]
rows = [s.split('|') for s in queue.get('stdout_text','').splitlines() if s.startswith(JOB+'|')]
acct = [s.split('|') for s in accounting.get('stdout_text','').splitlines() if s.startswith(JOB+'|')]
state = rows[0][1] if len(rows)==1 else (acct[0][1].split()[0].rstrip('+') if len(acct)==1 else 'UNKNOWN')
out['scheduler_state'] = state
node = rows[0][2] if len(rows)==1 else (acct[0][-1] if len(acct)==1 else '')
if state == 'PENDING':
    out['scheduler'].append(command(['squeue','--start','-j',JOB]))
if state == 'RUNNING' and re.fullmatch(r'[A-Za-z][A-Za-z0-9-]*', node or ''):
    out['allocated_node_process_query'] = command(['scontrol','listpids',JOB,node])
names = ['owner.json','numerical_worker_identity.json','supervisor_progress.json','worker_failure.json',
         'supervisor_failure.json','final_supervisor_report.json','fit_execution_complete.json',
         'direct_control_recheck/independent_fit_audit.json',
         'network/independent_fit_audit.json','network/seed_1001/fit_result.json',
         'counters/operation_counters_v04.json','budget.json']
out['records'] = {name:record('runtime/'+name) for name in names}
step_dir = ROOT/'runtime/network/seed_1001'
steps = sorted(step_dir.glob('step_[0-9][0-9][0-9][0-9].json')) if step_dir.is_dir() else []
out['network_step_record_count'] = len(steps)
if steps:
    out['first_network_step'] = record(str(steps[0].relative_to(ROOT)))
    out['latest_network_step'] = record(str(steps[-1].relative_to(ROOT)))
out['large_stage_records'] = {'runtime/network/stage_result.json':dict(present=(ROOT/'runtime/network/stage_result.json').is_file())}
out['log_tails'] = {}
for name in ['numerical_worker.log','slurm-'+JOB+'.out','slurm-'+JOB+'.err']:
    p = ROOT/'logs'/name
    if p.is_file() and not p.is_symlink() and p.resolve().is_relative_to(ROOT):
        st = p.stat()
        with p.open('rb') as stream:
            stream.seek(max(0,st.st_size-8192)); raw = stream.read(8192)
        out['log_tails'][name] = dict(bytes=st.st_size,mtime_ns=st.st_mtime_ns,
            tail_base64=base64.b64encode(raw).decode(),tail_sha256=hashlib.sha256(raw).hexdigest())
lock = ROOT.parent/'exclusive.lock'
try:
    with lock.open('r+b') as stream:
        st = os.fstat(stream.fileno())
        probe = dict(host=HOST,device=st.st_dev,inode=st.st_ino,allocated_node=node,
                     same_host_as_allocation=(HOST==node),conclusive_compute_node_ownership=False)
        try:
            fcntl.flock(stream.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:
            probe['free_on_collecting_host'] = False
        else:
            probe['free_on_collecting_host'] = True
            fcntl.flock(stream.fileno(),fcntl.LOCK_UN)
        out['family_lock_probe'] = probe
except OSError as error:
    out['family_lock_probe'] = dict(host=HOST,error=str(error))
out['process_creation_identity'] = {}
for name in ['owner.json','numerical_worker_identity.json']:
    identity = out['records'][name].get('value',{})
    if HOST != node:
        out['process_creation_identity'][name] = dict(inspected=False,reason='Collector_is_not_allocated_node_not_evidence_of_process_exit')
        continue
    try:
        proc = Path('/proc')/str(int(identity['pid']))
        ticks = proc.joinpath('stat').read_text().rsplit(')',1)[1].split()[19]
        raw = proc.joinpath('cmdline').read_bytes()[:4096]
        out['process_creation_identity'][name] = dict(inspected=True,creation_ticks=ticks,
            expected_creation_ticks=identity.get('creation_ticks'),creation_matches=ticks==str(identity.get('creation_ticks')),
            cmdline_base64=base64.b64encode(raw).decode())
    except Exception as error:
        out['process_creation_identity'][name] = dict(inspected=True,error=str(error))
out['stop_flags'] = dict(root=(ROOT/'STOP').exists(),family=(ROOT.parent/'STOP').exists())
out['terminal_candidate'] = (state in {'COMPLETED','FAILED','TIMEOUT','CANCELLED','OUT_OF_MEMORY','NODE_FAIL','BOOT_FAIL','PREEMPTED','DEADLINE','REVOKED'}
    and queue.get('exit_code')==0 and not rows and accounting.get('exit_code')==0)
out['current_health_or_science_accepted'] = False
out['sampled_end_utc'] = now()
encoded = json.dumps(out,sort_keys=True,allow_nan=False).encode()
if len(encoded)>196608:
    print(json.dumps(dict(error='Explicit_output_limit_exceeded',bytes=len(encoded),complete_snapshot=False)))
    raise SystemExit(3)
print(encoded.decode(),flush=True)
PY
