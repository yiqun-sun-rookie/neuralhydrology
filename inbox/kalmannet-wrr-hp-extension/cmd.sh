#!/usr/bin/env bash
# USER-AUTHORIZED (RETRY2_A40_AUTHORIZATION_20260911.md, item 3): once retry2 (225178) is fully terminal, restore the
# first attempt's array throttle from %3 back to %6. Guard: every 225178 task row in sacct must be terminal; otherwise
# no update is issued. Exactly one scontrol update; no cancel/submit.
set -uo pipefail
python3 -I -B - <<'PY'
import base64, datetime, gzip, json, re, subprocess
R1_JOB, R2_JOB = '224389', '225178'
TERMINAL = {'COMPLETED', 'FAILED', 'CANCELLED', 'TIMEOUT', 'OUT_OF_MEMORY', 'NODE_FAIL'}
def run(argv, timeout=45):
    p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False)
    return {'command': argv, 'returncode': p.returncode, 'stdout': p.stdout[:100000], 'stderr': p.stderr[:4000]}
def field(text, name):
    m = re.search(r'(?<![A-Za-z])' + re.escape(name) + r'=(\S*)', text)
    return m.group(1) if m else None
q = {}
q['retry2_sacct'] = run(['sacct', '-j', R2_JOB, '-X', '-n', '-P', '--format=JobID,State,ExitCode,Start,End'])
rows = [l.split('|') for l in q['retry2_sacct']['stdout'].splitlines() if l.strip()]
states = {r[0]: r[1].split()[0] for r in rows}
expected = [f'{R2_JOB}_{i}' for i in (3, 4, 5, 9, 10, 11)]
all_terminal = q['retry2_sacct']['returncode'] == 0 and all(states.get(k) in TERMINAL for k in expected) and not any('[' in r[0] for r in rows)
q['before_show'] = run(['scontrol', 'show', 'job', R1_JOB])
before = q['before_show']['stdout']
q['preconditions'] = {'retry2_states': {k: states.get(k) for k in expected}, 'retry2_all_terminal': all_terminal,
                      'retry1_throttle_before': field(before, 'ArrayTaskThrottle'), 'retry1_state_before': field(before, 'JobState')}
if all_terminal and q['before_show']['returncode'] == 0:
    q['update'] = run(['scontrol', 'update', f'JobId={R1_JOB}', 'ArrayTaskThrottle=6'])
    q['after_show'] = run(['scontrol', 'show', 'job', R1_JOB])
    q['result'] = {'update_returncode': q['update']['returncode'], 'update_stderr': q['update']['stderr'].strip(),
                   'retry1_throttle_after': field(q['after_show']['stdout'], 'ArrayTaskThrottle'),
                   'retry1_state_after': field(q['after_show']['stdout'], 'JobState')}
else:
    q['update'] = None
    q['result'] = {'skipped': 'retry2 not fully terminal or retry1 not visible; no scontrol update executed'}
report = {'kind': 'USER_AUTHORIZED_RESTORE_RETRY1_THROTTLE', 'observed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'queries': q, 'new_jobs_submitted': 0, 'jobs_cancelled': 0}
blob = json.dumps(report, sort_keys=True, separators=(',', ':')).encode()
print('RESTORE_THROTTLE_GZIP_BASE64=' + base64.b64encode(gzip.compress(blob, mtime=0)).decode())
print('PRECONDITIONS=' + json.dumps(q['preconditions']))
print('RESULT=' + json.dumps(q['result']))
print('--- retry2 sacct'); print(q['retry2_sacct']['stdout'].rstrip())
PY
