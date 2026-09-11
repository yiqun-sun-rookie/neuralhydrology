#!/usr/bin/env bash
# USER-AUTHORIZED (RETRY2_A40_AUTHORIZATION_20260911.md, item 4): cancel exactly those retry1 (224389) array tasks whose
# cell has been CLAIMED by retry2 (225178) and is RUNNING there, so no cell is trained twice. Per-task scancel by
# explicit job id only; never scancel -u. Each cancellation requires, at the moment of the check:
#   retry2 task for that index RUNNING  AND  retry2 claim file present  AND  no FAILED marker  AND  retry1 task PENDING.
# CANDIDATES is the explicit list this request is allowed to touch.
set -uo pipefail
python3 -I -B - <<'PY'
import base64, datetime, gzip, json, pathlib, subprocess
CANDIDATES = [3, 4, 5]
R1_JOB, R2_JOB = '224389', '225178'
R2 = pathlib.Path('/data1/home/sunyiq/kalmannet_wrr_model_selection_20260908/resource_recovery_20260911/B_retry2')
EXP = R2 / 'repo/experiments/optimize_hyper_parameters/wrr_hp_extension_20260902'
def run(argv, timeout=45):
    p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False)
    return {'command': argv, 'returncode': p.returncode, 'stdout': p.stdout[:100000], 'stderr': p.stderr[:4000]}
def states(job):
    q = run(['squeue', '-r', '-j', job, '-h', '-o', '%i|%T|%M|%N'])
    assert q['returncode'] == 0 and not q['stderr'], q
    return q, {l.split('|')[0]: l.split('|')[1:] for l in q['stdout'].splitlines() if l.strip()}
assert (R2 / 'array_job_id.txt').read_text().strip() == R2_JOB
combos = [json.loads(l) for l in (EXP / 'combos.jsonl').read_text().splitlines() if l.strip()]
before_q1, s1 = states(R1_JOB)
before_q2, s2 = states(R2_JOB)
actions = []
for i in CANDIDATES:
    r2 = s2.get(f'{R2_JOB}_{i}')
    r1 = s1.get(f'{R1_JOB}_{i}')
    claim = R2 / 'claims' / ('index%04d.json' % i)
    dirs = list(EXP.glob('runs/formal_seed%d_gpu/idx%04d_*' % (combos[i]['seed'], i)))
    failed = any((d / 'FAILED').is_file() for d in dirs)
    cond = {'retry2_running': bool(r2) and r2[0] == 'RUNNING', 'retry2_elapsed': r2[1] if r2 else None,
            'retry2_claimed': claim.is_file(), 'retry2_failed_marker': failed,
            'retry1_pending': bool(r1) and r1[0] == 'PENDING'}
    ok = cond['retry2_running'] and cond['retry2_claimed'] and not cond['retry2_failed_marker'] and cond['retry1_pending']
    entry = {'index': i, 'conditions': cond, 'cancelled': False}
    if ok:
        c = run(['scancel', f'{R1_JOB}_{i}'])
        entry['scancel'] = c
        entry['cancelled'] = c['returncode'] == 0
    actions.append(entry)
after_q1, _ = states(R1_JOB)
acct = run(['sacct', '-j', R1_JOB, '-X', '-n', '-P', '--format=JobID,State,ExitCode,Start,End'])
report = {'kind': 'USER_AUTHORIZED_CANCEL_SUPERSEDED_RETRY1_TASKS', 'observed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'candidates': CANDIDATES, 'actions': actions, 'retry1_queue_before': before_q1, 'retry2_queue_before': before_q2,
          'retry1_queue_after': after_q1, 'retry1_sacct_after': acct, 'new_jobs_submitted': 0}
blob = json.dumps(report, sort_keys=True, separators=(',', ':')).encode()
print('CANCEL_SUPERSEDED_GZIP_BASE64=' + base64.b64encode(gzip.compress(blob, mtime=0)).decode())
for a in actions:
    print('INDEX %d: cancelled=%s conditions=%s' % (a['index'], a['cancelled'], json.dumps(a['conditions'])))
print('--- retry1 queue after'); print(after_q1['stdout'].rstrip())
print('--- retry1 sacct after'); print(acct['stdout'].rstrip())
PY
