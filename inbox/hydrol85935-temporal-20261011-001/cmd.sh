#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'RELEASE'
import hashlib, importlib.util, json, os, subprocess
from pathlib import Path

ROOT = Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001')
TARGET = ROOT / 'attempts/infeasible_recovery_v002_20261015_001'
CONTROL = ROOT / 'control/queue_priority_20261014_001'
SCRIPT = CONTROL / 'queue_priority.py'
SCRIPT_SHA = 'a3de8ee97281cb5b1ff7ab745bd8b4506abf3da932d35869b08eec3d0631fe6e'
PINS = {'REPORT_SHA': '2186f4e45a2547f7a5c87894b671fca17a9cca07ac0d821caccef82e9d388835', 'CROSS_SHA': '09c2890985170770cee0283217ef2e469ae450f2f8ce76f3761d8f90347000b4', 'AMEND_SHA': '1cedad209ce88e6c578ea42046295292317f011786c5d70dbf641145dffd88fe'}

def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p): return json.loads(Path(p).read_text())
def emit(k, v): print(k + ' ' + json.dumps(v), flush=True)
def run(a): return subprocess.run(a, capture_output=True, text=True, timeout=60)

assert not (CONTROL / 'parent_released.json').exists(), 'parent already released; inspect, never repeat'
assert sha(SCRIPT) == SCRIPT_SHA, 'queue_priority.py changed'
reg = read(CONTROL / 'coordinator_start_registration.json') if (CONTROL / 'coordinator_start_registration.json').exists() else None
proc = Path('/proc/14633')
assert not proc.exists() or proc.joinpath('stat').read_text().split()[21] != '9910500053', 'old coordinator still alive'
# the reviewed final audit evidence
assert sha(TARGET / 'reports/coverage_and_summary.json') == PINS['REPORT_SHA']
assert sha(TARGET / 'reports/cross_environment_reconstruction.json') == PINS['CROSS_SHA']
assert sha(TARGET / 'amendment_20261017_001/registered_amendment.json') == PINS['AMEND_SHA']
rep = read(TARGET / 'reports/coverage_and_summary.json')
assert rep['status'] == 'COMPLETE_WITH_UNCOMPUTABLE' and rep['complete_pairs'] == 1590 and rep['expected_pairs'] == 1593
assert rep['uncomputable_search_records'] == 6 and not rep['issues'] and not rep['unknown_failures'] and rep['scheduler_job_id'] == '244315'
assert read(TARGET / 'reports/cross_environment_reconstruction.json')['status'] == 'COMPLETE'
# every registered / amended recovery job terminal, none queued
ids = '242751,242752,242753,242754,244315,242488,242597'
assert not run(['squeue', '-h', '-r', '-j', ids, '-o', '%i']).stdout.strip(), 'a recovery job is still queued'
acct = {l.split('|')[0]: l.split('|')[1:] for l in run(['sacct', '-X', '-j', ids, '-n', '-P', '-o', 'JobID,State,ExitCode']).stdout.splitlines()}
assert acct['244315'] == ['COMPLETED', '0:0'] and acct['242753'] == ['FAILED', '1:0'] and acct['242754'][0].startswith('CANCELLED'), acct
emit('RELEASE_PRECHECK', dict(report_sha256=PINS['REPORT_SHA'], accounting=acct))
spec = importlib.util.spec_from_file_location('queue_priority_deployed', SCRIPT)
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
result = module.release_parent('Additional computation and final coverage audit completed (replacement report job 244315); scientific interpretation still to audit')
emit('PARENT_RELEASE_RESULT', dict(released=len(result['released_job_ids']), ids_head=result['released_job_ids'][:3], ids_tail=result['released_job_ids'][-3:]))
q = [l.split('|') for l in run(['squeue', '-r', '-h', '-u', 'sunyiq', '-o', '%i|%T|%r']).stdout.splitlines()]
held = set(read(CONTROL / 'applied.json')['held_parent_ids'])
emit('PARENT_AFTER', dict(rows=[r for r in q if r[0] in held][:6], states={k: sum(1 for r in q if r[0] in held and r[1] + '/' + r[2] == k) for k in sorted({r[1] + '/' + r[2] for r in q if r[0] in held})}))
emit('OLDER_HELD_UNCHANGED', dict(count=sum(1 for r in q if r[0].split('_')[0] in {'240076', '240077', '240078', '241691'} and r[2] == 'JobHeldUser')))
RELEASE
