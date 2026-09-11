#!/usr/bin/env bash
# USER-AUTHORIZED JOB MODIFICATION (2026-09-11 “没有别的机器你换一下”): relax the node pin of the queued A800 retry
# array 224389 from ReqNodeList=ngu201 to any hgpu8 node except ngu203 (reserved/maint). Nothing else changes:
# same job id, same partition hgpu8, same gres/cpus/time/array throttle, same frozen batch script and manifest,
# accumulated queue age is kept. The retry launcher's own gate (partition hgpu8 AND GPU >= 75 GiB) still protects
# every task before any data/training step, so an unexpected GPU on ngu202 fails fast without producing results.
# Refuses to act unless all 12 tasks are still PENDING and the job still carries the expected pin.
set -uo pipefail
python3 -I -B - <<'PY'
import base64, datetime, gzip, json, re, subprocess
def run(argv, timeout=60):
    p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False)
    return {'command': argv, 'returncode': p.returncode, 'stdout': p.stdout[:200000], 'stderr': p.stderr[:4000]}
def show():
    return run(['scontrol', 'show', 'job', '224389'])
def field(text, name):
    m = re.search(r'(?<![A-Za-z])' + re.escape(name) + r'=(\S*)', text)
    return m.group(1) if m else None
q = {}
q['before_show'] = show()
q['before_squeue'] = run(['squeue', '-r', '-j', '224389', '-h', '-o', '%i|%T|%r|%Q|%N'])
before = q['before_show']['stdout']
states = [l.split('|')[1] for l in q['before_squeue']['stdout'].splitlines() if l.strip()]
ok = (q['before_show']['returncode'] == 0 and field(before, 'JobState') == 'PENDING'
      and field(before, 'ReqNodeList') == 'ngu201' and field(before, 'Partition') == 'hgpu8'
      and field(before, 'ArrayTaskId') == '0-11%6' and len(states) == 12 and all(s == 'PENDING' for s in states))
q['preconditions'] = {'all_12_pending': len(states) == 12 and all(s == 'PENDING' for s in states),
                      'req_node_list_is_ngu201': field(before, 'ReqNodeList') == 'ngu201',
                      'partition_hgpu8': field(before, 'Partition') == 'hgpu8',
                      'array_intact': field(before, 'ArrayTaskId') == '0-11%6', 'proceed': ok}
if ok:
    q['update'] = run(['scontrol', 'update', 'JobId=224389', 'ReqNodeList=', 'ExcNodeList=ngu203'])
    q['after_show'] = show()
    q['after_squeue'] = run(['squeue', '-r', '-j', '224389', '-h', '-o', '%i|%T|%r|%Q|%N'])
    after = q['after_show']['stdout']
    q['result'] = {'update_returncode': q['update']['returncode'],
                   'req_node_list_after': field(after, 'ReqNodeList'), 'exc_node_list_after': field(after, 'ExcNodeList'),
                   'partition_after': field(after, 'Partition'), 'priority_after': field(after, 'Priority'),
                   'eligible_time_after': field(after, 'EligibleTime'), 'job_state_after': field(after, 'JobState'),
                   'tres_per_node_after': field(after, 'TresPerNode'), 'array_after': field(after, 'ArrayTaskId')}
else:
    q['update'] = None
    q['result'] = {'skipped': 'preconditions not met; no scontrol update executed'}
report = {'kind': 'USER_AUTHORIZED_NODE_PIN_RELAXATION_224389', 'observed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'queries': q, 'new_jobs_submitted': 0, 'jobs_cancelled': 0, 'data_or_checkpoint_tensors_loaded': False}
blob = json.dumps(report, sort_keys=True, separators=(',', ':')).encode()
print('NODE_PIN_RELAX_GZIP_BASE64=' + base64.b64encode(gzip.compress(blob, mtime=0)).decode())
print('PRECONDITIONS=' + json.dumps(q['preconditions']))
print('RESULT=' + json.dumps(q['result']))
if q['update']:
    print('UPDATE_RC=%d stdout=%r stderr=%r' % (q['update']['returncode'], q['update']['stdout'].strip(), q['update']['stderr'].strip()))
    print('--- after_show'); print(q['after_show']['stdout'].rstrip())
    print('--- after_squeue'); print(q['after_squeue']['stdout'].rstrip())
else:
    print('--- before_show'); print(before.rstrip())
PY
