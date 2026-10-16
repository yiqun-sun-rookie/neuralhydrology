#!/usr/bin/env bash
set -eo pipefail
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import base64, datetime, hashlib, json, re, subprocess
from pathlib import Path
home = Path.home()
root = home / 'hydrol85935_revision_20261008_001'
assert (root / 'OWNER').read_text().strip() == 'hydrol85935_revision_20261008_001'
channel = 'hydrol85935-revision-20261008-001'
stage = home / '.hpc_mailbox_staging' / channel
def emit(label, value):
    print(label + ' ' + json.dumps(value), flush=True)
def query(command):
    r = subprocess.run(command, capture_output=True, text=True, timeout=30)
    return dict(returncode=r.returncode, stdout=r.stdout, stderr=r.stderr)
emit('DIAGNOSTIC_TIME', datetime.datetime.now().astimezone().isoformat())
emit('DIAGNOSTIC_HOST', query(['hostname']))
emit('MAIN_INBOX_SEQUENCE', (home / 'hpc_mailbox/inbox' / channel / 'seq').read_text())
emit('MAIN_INBOX_COMMAND_SHA256', hashlib.sha256((home / 'hpc_mailbox/inbox' / channel / 'cmd.sh').read_bytes()).hexdigest())
for name in ['cmd_326.sh', 'result_326.txt']:
    path = stage / name
    value = dict(path=str(path), exists=path.exists())
    if path.exists():
        body = path.read_bytes()
        value.update(size=len(body), sha256=hashlib.sha256(body).hexdigest(), modified=path.stat().st_mtime)
        if name.startswith('result'):
            complete = body.startswith(('### channel=' + channel + ' seq=326\n').encode()) and bool(re.search(rb'\n### exit_code=-?\d+\n### finished=[^\n]+\n?$', body))
            value.update(complete=complete, tail=body[-2000:].decode('utf8', errors='replace'))
            if complete and len(body) <= 2000000:
                value['original_bytes_base64'] = base64.b64encode(body).decode()
    emit('EXACT_MAIN_STAGING', value)
for job in [241335, 241336, 241337, 241344, 242752, 242753, 242754]:
    emit('LIVE_JOB', dict(job_id=job, **query(['scontrol', 'show', 'job', '-o', str(job)])))
emit('LIVE_ACCOUNTING', query(['sacct', '-X', '-j', '241335,241336,241337,241344,242752,242753,242754', '-n', '-P', '-o', 'JobID,State,ExitCode,Elapsed,Start,End,NodeList']))
processes = query(['ps', '-eo', 'pid,ppid,etime,args'])
processes['stdout'] = '\n'.join(line for line in processes['stdout'].splitlines() if any(s in line for s in ['runner2.sh', channel, 'git fetch', 'git push', 'pack-objects']))[-12000:]
emit('RECEIVER_PROCESS_OBSERVATION', processes)
emit('DIAGNOSTIC_END', dict(scientific_job_modified=False, main_command_reexecuted=False, shared_runner_modified=False))
PY
