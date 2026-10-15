#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
SPEC={'root': '/data1/home/sunyiq/hydrol85935_revision_20261008_001', 'new': '/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v017_20261014_001', 'previous': '/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v016_20261014_001', 'payload': '/data1/home/sunyiq/hpc_mailbox/inbox/hydrol85935-revision-20261008-001/payload/hybrid_v017_20261014_001.tar.gz', 'payload_sha256': '6b8b4cebb0b0a3238d3a0d618414149a9ed39a2e3996af6ab5cf91317c64cebd', 'anchor': {'parent_job_id': '241336', 'JobId': '242302', 'ArrayJobId': '241336', 'ArrayTaskId': '6', 'ArrayTaskThrottle': '1', 'JobName': 'hydrol85935-v009-attacks', 'UserId': 'sunyiq(2272)', 'GroupId': 'g_sunyiq(2269)', 'MCS_label': 'N/A', 'Priority': '294959', 'Nice': '0', 'Account': 'g_sunyiq', 'QOS': 'qos_sunyiq', 'JobState': 'RUNNING', 'Reason': 'None', 'Dependency': '(null)', 'Requeue': '0', 'Restarts': '0', 'BatchFlag': '1', 'Reboot': '0', 'ExitCode': '0:0', 'RunTime': '00:46:24', 'TimeLimit': '06:00:00', 'TimeMin': 'N/A', 'SubmitTime': '2026-10-12T20:18:32', 'EligibleTime': '2026-10-14T19:27:48', 'AccrueTime': '2026-10-14T03:30:36', 'StartTime': '2026-10-14T19:27:53', 'EndTime': '2026-10-15T01:27:53', 'Deadline': 'N/A', 'SuspendTime': 'None', 'SecsPreSuspend': '0', 'LastSchedEval': '2026-10-14T19:27:53', 'Partition': 'hgpu2p', 'AllocNode:Sid': 'login04:46471', 'ReqNodeList': '(null)', 'ExcNodeList': 'ngu002', 'NodeList': 'ngu010', 'BatchHost': 'ngu010', 'NumNodes': '1', 'NumCPUs': '4', 'NumTasks': '1', 'CPUs/Task': '4', 'ReqB:S:C:T': '0:0:*:*', 'TRES': 'cpu=4,node=1,billing=4', 'Socks/Node': '*', 'NtasksPerN:B:S:C': '0:0:*:*', 'CoreSpec': '*', 'MinCPUsNode': '4', 'MinMemoryNode': '0', 'MinTmpDiskNode': '0', 'Features': '(null)', 'DelayBoot': '00:00:00', 'OverSubscribe': 'OK', 'Contiguous': '0', 'Licenses': '(null)', 'Network': '(null)', 'Command': '/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v009_20261012_001/attacks.sbatch', 'WorkDir': '/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v009_20261012_001', 'StdErr': '/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v009_20261012_001/logs/attacks-241336_6.err', 'StdIn': '/dev/null', 'StdOut': '/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v009_20261012_001/logs/attacks-241336_6.out', 'Power': '', 'TresPerNode': 'gpu:1'}, 'running_source': {'control': '/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v013_20261014_001', 'worker_sha256': '877457ca47010ad0da8999ed156154a469808b1a8af89c99709ae82c97ec9783', 'assignment_sha256': 'dacdf8b29545581d27f148aff65153458c9a063f6915635da64937cdb8503db2'}, 'authorized_held_window': True, 'source_audit_sequence': 289, 'source_audit_sha256': '718d6be74926ec2d1e522e6452dab9b3a854a8de06484981311c1c706aa69374'}
"""Serialized transfer of an unstarted prefix, protected by a running array member.

The generated command supplies SPEC. No scheduler mutation or scientific work.
An interrupted deployment is UNKNOWN until reconciled; never replay it.
"""
import datetime
import hashlib
import json
import os
import re
import subprocess
import tarfile
from pathlib import Path

def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()

def emit(k, v):
    print(k + ' ' + json.dumps(v), flush=True)

def save(p, value):
    with Path(p).open('x') as stream:
        json.dump(value, stream, indent=2)

def query(cmd):
    r = subprocess.run(cmd, text=True, capture_output=True, timeout=45)
    assert r.returncode == 0, (cmd, r.stdout, r.stderr)
    return r.stdout

def indices(value):
    out = set()
    for part in value.strip('[]').split('%')[0].split(','):
        if '-' in part:
            a, b = map(int, part.split('-')); out.update(range(a, b + 1))
        else:
            out.add(int(part))
    return out

def allocated(a):
    union = set()
    for group in a['local_assignments'] + a['hpc_tasks']:
        slots = {(c, b) for c in group['combinations'] for b in group['basins']}
        assert not union & slots, 'Overlapping ownership'
        union |= slots
    assert len(union) == 27612
    return union


def verify_completed_preflight(expected, proof, accounting):
    assert proof['identity'] == {k: v for k, v in expected.items() if k != 'Dependency'}
    assert expected['Dependency'] == 'afterany:241336_6'
    found = [r for r in accounting if r[0] == '241345']
    assert len(found) == 1 and found[0] == proof['terminal_row']
    assert found[0][1:3] == ['COMPLETED', '0:0']
    assert found[0][4] not in ('Unknown', '') and found[0][5] not in ('Unknown', '')
    return dict(JobId='241345', JobState='COMPLETED', identity_basis='Prior verified identity and exact current terminal accounting', terminal_row=found[0])

def check_temporal_continuation(proof):
    observations = []
    running = 0
    for job in proof['supplementary_temporal_jobs']:
        jid = job['job_id']
        assert str(job['submission']['job_id']) == jid and job['submission']['status'] == 'SUBMITTED'
        assert job['array_tasks'] == job['submission']['array_tasks']
        result = subprocess.run(['scontrol','show','job','-o',jid], text=True, capture_output=True, timeout=45)
        history = query(['sacct','-X','-j',jid,'-n','-P','-o','JobID,State,ExitCode,Elapsed,Start,End,NodeList'])
        terminal = set()
        for line in history.splitlines():
            row = line.split('|')
            match = re.fullmatch(re.escape(jid)+r'_(\d+)', row[0])
            if match and row[1] in ('COMPLETED','FAILED','CANCELLED','TIMEOUT','NODE_FAIL','OUT_OF_MEMORY','PREEMPTED','BOOT_FAIL','DEADLINE'):
                terminal.add(int(match[1]))
        fields = [dict(re.findall(r'(\S+?)=(\S*)',line)) for line in result.stdout.splitlines() if line.startswith('JobId=')]
        observed = set()
        if result.returncode:
            assert 'invalid job id' in result.stderr.lower() and not fields
        else:
            assert fields
            for f in fields:
                assert f.get('ArrayJobId', f['JobId']) == jid
                assert all(f.get(k) == v for k, v in job['expected'].items()), (jid, f)
                slots = indices(f['ArrayTaskId'])
                assert not observed & slots and slots <= set(range(job['array_tasks']))
                observed |= slots
                running += f['JobState'] in ('RUNNING','COMPLETING')
        assert observed | terminal == set(range(job['array_tasks']))
        observations.append(dict(job_id=jid, scheduler=fields, accounting=history, controller='automation8', parent_control_authorized=False))
    assert running <= 1
    return observations, running

def main(spec):
    root, new, previous = map(Path, (spec['root'], spec['new'], spec['previous']))
    sched = root/'control/hybrid_v009_20261012_001'
    wf = root/'control/workflow_v010_20261012_001'
    execution = root/'execution/hpc_v009'
    assert root.resolve() == root and (root/'OWNER').read_text().strip() == 'hydrol85935_revision_20261008_001'
    payload = Path(spec['payload'])
    assert sha(payload) == spec['payload_sha256']
    assert not new.exists(), 'Existing transaction: reconcile, never replay'
    with tarfile.open(payload) as archive:
        members = archive.getmembers()
        assert all(m.isfile() and Path(m.name).name == m.name for m in members)
        blobs = {m.name: archive.extractfile(m).read() for m in members}
    manifest = json.loads(blobs['payload_files.json'])
    assert set(blobs) == set(manifest) | {'payload_files.json'}
    for name, digest in manifest.items():
        assert hashlib.sha256(blobs[name]).hexdigest() == digest
    old, assignment = [json.loads(blobs[n]) for n in ('previous_assignment.json', 'assignment.json')]
    assert sha(previous/'assignment.json') == manifest['previous_assignment.json']
    assert allocated(old) == allocated(assignment)
    assert old['local_assignments'] == assignment['local_assignments'][:-1]
    scope = json.loads(blobs['delegation_scope.json']); index = scope['hpc_task_index']
    assert old['hpc_tasks'][:index] == assignment['hpc_tasks'][:index]
    assert old['hpc_tasks'][index+1:] == assignment['hpc_tasks'][index+1:]
    oldtask, task = old['hpc_tasks'][index], assignment['hpc_tasks'][index]
    assert oldtask['model'] == scope['model'] == 'original_s100'
    assert oldtask['combinations'] == task['combinations'] == scope['combinations']
    assert oldtask['basins'] == scope['basins'] + task['basins']
    assert (task['basin_start'], task['basin_count']) == (oldtask['basin_start']+len(scope['basins']), len(task['basins']))
    if not task['basins']:
        assert task['delegated_to'] == scope['endpoint'] and task['original_task'] == oldtask
    else:
        assert not task.get('delegated_to')
    local = json.loads(blobs['claimed_local_assignment.json'])
    assert local['basins'] == scope['basins'] and local['combinations'] == scope['combinations']
    assert assignment['local_assignments'][-1]['sha256'] == manifest['claimed_local_assignment.json']
    assert assignment['hpc_training_seeds'] == old['hpc_training_seeds'] == [100, 200, 300]
    assert assignment['resource_limits']['local_cpu_cores'] == 8
    assert assignment['hpc_counts']['attacks'] + assignment['local_counts']['attacks'] == 27612
    assert assignment['hpc_counts']['clean'] + assignment['local_counts']['clean'] == 3186
    assert assignment['hpc_counts']['restore_series'] + assignment['local_counts']['restore_series'] == 12744
    registered = json.loads(blobs['effective_registered_job_identity.json'])
    anchor = spec['anchor']
    anchor_index = int(anchor['ArrayTaskId'])
    assert index != anchor_index and old['hpc_tasks'][anchor_index] == assignment['hpc_tasks'][anchor_index]
    held_window = spec.get('authorized_held_window', False)
    terminal_proof = json.loads(blobs['held_window_terminal_proof.json'])
    assert held_window and terminal_proof['sequence'] == spec['source_audit_sequence']
    assert terminal_proof['receipt_sha256'] == spec['source_audit_sha256']

    def jobs_check():
        history = query(['sacct','-X','-j','241335,241336,241345','-n','-P','-o','JobID,State,ExitCode,Elapsed,Start,End,NodeList'])
        accounting = [line.split('|') for line in history.splitlines() if line.strip()]
        for i in range(3):
            assert any(r[0] == '241335_'+str(i) and r[1:3] == ['COMPLETED','0:0'] for r in accounting)
        rows = {}
        for jid, expected in registered.items():
            if jid == '241335':
                continue
            result = subprocess.run(['scontrol','show','job','-o',jid], text=True, capture_output=True, timeout=45)
            if jid == '241345':
                completed = verify_completed_preflight(expected, terminal_proof['preflight'], accounting)
                if result.returncode:
                    assert 'invalid job id' in result.stderr.lower() and not result.stdout.strip()
                    rows[jid] = [completed]
                    continue
            assert result.returncode == 0, (jid, result.stdout, result.stderr)
            raw = result.stdout
            fields = [dict(re.findall(r'(\S+?)=(\S*)',line)) for line in raw.splitlines() if line.startswith('JobId=')]
            assert fields
            for f in fields:
                assert f.get('ArrayJobId', f['JobId']) == jid
                for key, want in expected.items():
                    if key == 'ArrayTaskId':
                        assert indices(f[key]) <= indices(want)
                    elif key == 'Dependency' and jid in ('241336', '241345'):
                        assert f[key] in (want, '(null)')
                    else:
                        assert f.get(key) == want, (jid, key, f.get(key), want)
                if int(jid) < 241000:
                    assert f['JobState'] == 'PENDING' and f['Reason'] == 'JobHeldUser' and f['Priority'] == '0'
                elif jid == '241345' and held_window:
                    assert f['JobState'] == 'COMPLETED'
                elif jid != '241336':
                    assert f['JobState'] == 'PENDING'
            rows[jid] = fields
        running = [f for f in rows['241336'] if f['JobState'] == 'RUNNING']
        assert len(running) <= 1
        current = running[0] if running else None
        if not held_window:
            assert current is not None
        if current:
            for key in ('JobId','ArrayTaskId','StartTime','SubmitTime','Command','WorkDir','NodeList','Restarts','Requeue','ArrayTaskThrottle'):
                assert current[key] == anchor[key], ('Running anchor changed', key)
            assert current['Restarts'] == current['Requeue'] == '0' and current['ArrayTaskThrottle'] == '1'
        if held_window and current is None:
            terminal = {'COMPLETED','FAILED','CANCELLED','TIMEOUT','NODE_FAIL','OUT_OF_MEMORY','PREEMPTED','BOOT_FAIL','DEADLINE'}
            prior = [r for r in accounting if r[0] == '241336_'+str(anchor_index)]
            assert len(prior)==1 and prior[0][1].split()[0].rstrip('+') in terminal
            assert prior[0][4] == anchor['StartTime'] and prior[0][6] == anchor['NodeList']
        if held_window:
            for f in rows['241336']:
                if f['JobState'] == 'PENDING':
                    assert f['Reason'] == 'JobHeldUser' and f['Priority'] == '0'
                    assert f['StartTime'] == 'Unknown' and f['Restarts'] == '0'
            assert all(rows[j][0]['Reason'] == 'JobHeldUser' for j in ('241337','241344'))
        pending = set().union(*(indices(f['ArrayTaskId']) for f in rows['241336'] if f['JobState'] == 'PENDING'))
        assert index in pending, 'Candidate started or no longer pending'
        for r in accounting:
            if r[0].startswith('241336_') and index in indices(r[0].split('_',1)[1]):
                assert r[1] == 'PENDING' and r[3:6] == ['00:00:00','Unknown','Unknown'], r
        secondary, secondary_running = check_temporal_continuation(terminal_proof)
        assert len(running) + secondary_running <= 1
        return dict(scheduler=rows, accounting=history, anchor=current, pending_indices=sorted(pending), supplementary_temporal_jobs=secondary)

    def unused(task_index):
        t = old['hpc_tasks'][task_index]
        if t['model'] != 'original_s100' or not t['basins']:
            return False
        for b in t['basins']:
            if (execution/'records/clean'/t['model']/b).exists(): return False
            if any((execution/'records/attacks'/c/b).exists() for c in t['combinations']): return False
        ledger = execution/'records/ledger.jsonl'
        if ledger.exists():
            for line in ledger.open():
                if not line.strip(): continue
                r = json.loads(line)
                if str(r.get('basin_id')) in t['basins'] and (r.get('combination_id') in t['combinations'] or r.get('model_id') == t['model']): return False
        for control in (root/'control').glob('hybrid_v*'):
            if list((control/'stage_results').glob('attacks_'+str(task_index)+'_*.json')): return False
            assert not (control/'hpc_packet_001').exists(), 'Existing HPC packet requires reconciliation'
        assert not (wf/'hpc_packet_001').exists()
        return not list((sched/'logs').glob('attacks-241336_'+str(task_index)+'.*'))

    def candidate_check(jobs):
        eligible = [i for i in jobs['pending_indices'] if unused(i)]
        assert eligible and min(eligible) == index, ('Candidate is not lowest eligible', eligible, index)
        return dict(index=index, whole_task_never_started=True, no_output=True, no_ledger_failure_uncomputable_history=True,
                    no_scheduler_log_or_stage_history=True, scope=scope)

    # The running process has loaded the immutable source version before inference.
    # Its source and scope stay untouched; %1 and a stable physical running member
    # prevent any future candidate from starting during the replacement window.
    proof = spec['running_source']
    source = Path(proof['control'])
    assert sha(source/'worker.py') == proof['worker_sha256'] and sha(source/'assignment.json') == proof['assignment_sha256']
    source_assignment = json.loads((source/'assignment.json').read_text())
    assert source_assignment['hpc_tasks'][anchor_index] == old['hpc_tasks'][anchor_index]
    started = datetime.datetime.fromisoformat(anchor['StartTime']).timestamp()
    progress = [p for b in old['hpc_tasks'][anchor_index]['basins'] for c in old['hpc_tasks'][anchor_index]['combinations']
                for p in [execution/'records/attacks'/c/b/'complete.json'] if p.exists() and p.stat().st_mtime >= started]
    assert progress, 'No output evidence that the protected task has entered frozen scientific execution'
    for row in json.loads(blobs['training_stage_proofs.json']):
        assert sha(row['path']) == row['sha256'] and row['value']['status'] == 'PASS'
    assert len(json.loads(blobs['training_stage_proofs.json'])) >= 3
    before = jobs_check(); empty_before = candidate_check(before)
    assert sha(sched/'worker.py') == manifest['previous_worker_bridge.py']
    assert sha(wf/'federated_v010.py') == manifest['previous_export_bridge.py']
    emit('BACKFILL_PRECHECK', dict(anchor=before['anchor'], candidate=empty_before, running_source=proof))
    new.mkdir()
    for name, data in blobs.items():
        with (new/name).open('xb') as f: f.write(data)
    save(new/'scheduler_before.json', before)
    save(new/'candidate_before.json', empty_before)
    entries = [dict(path=str(sched/'worker.py'),original_sha256=manifest['previous_worker_bridge.py'],new_sha256=manifest['worker_bridge.py'],source='worker_bridge.py'),
               dict(path=str(wf/'federated_v010.py'),original_sha256=manifest['previous_export_bridge.py'],new_sha256=manifest['export_bridge.py'],source='export_bridge.py')]
    save(new/'deployment_transaction.json', dict(status='PREPARED',entrypoints=entries,assignment_sha256=manifest['assignment.json'],no_scheduler_mutation=True))
    candidate_check(jobs_check())
    for entry in reversed(entries):
        target = Path(entry['path'])
        assert sha(target) == entry['original_sha256']
        temp = target.with_name(target.name+'.'+new.name+'.tmp')
        with temp.open('xb') as f: f.write(blobs[entry['source']])
        os.replace(temp, target)
        assert sha(target) == entry['new_sha256']
    after = jobs_check(); empty_after = candidate_check(after)
    save(new/'scheduler_after.json', after)
    save(new/'candidate_after.json', empty_after)
    confirmation = dict(status='DEPLOYMENT_CONFIRMED',assignment_sha256=manifest['assignment.json'],delegation_scope=scope,
                        entrypoints=entries,mutually_exclusive=True,union_count=27612,no_scheduler_mutation=True,
                        dependencies_resources_submit_times_unchanged=True,terminal_training_seeds=[100,200,300],
                        running_anchor_before=before['anchor'],running_anchor_after=after['anchor'],running_source=proof,
                        candidate_before=empty_before,candidate_after=empty_after,scientific_code_modified=False,
                        remote_utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
    save(new/'deployment_confirmation.json', confirmation)
    emit('ROLLING_BACKFILL_DEPLOYMENT', confirmation)

if __name__ == '__main__':
    main(SPEC)

PY
#!/usr/bin/env bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
test "$(readlink -f "$ROOT")" = "$ROOT"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import datetime
import json
import re
import subprocess
from pathlib import Path

root = Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')

def output(label, value):
    print(label + ' ' + json.dumps(value, ensure_ascii=False), flush=True)

def query(label, command):
    result = subprocess.run(command, capture_output=True, text=True, timeout=45)
    output(label, dict(returncode=result.returncode, stdout=result.stdout, stderr=result.stderr))
    if result.returncode:
        raise RuntimeError('Cannot verify ' + label)
    return result.stdout

output('OBSERVATION', dict(time=datetime.datetime.now().astimezone().isoformat(),
       scope='read-only GPU inventory and registered scheduler state; not a full experiment audit'))
jobs = json.loads((root / 'control/full_v004/jobs.json').read_text())
if jobs != dict(train=240076, attacks=240077, report=240078):
    raise ValueError('Job registry changed; review version and ownership before using a new probe')
probe_path = root / 'control/migration_probe_20261012_002/jobs.json'
if probe_path.exists():
    probe_registry = json.loads(probe_path.read_text())
    if probe_registry['formal_jobs'] != jobs or probe_registry['probes'] != dict(ngu201=241239, ngu002=241240):
        raise ValueError('Compatibility job registry changed; review identity before querying')
    jobs = dict(jobs, compatibility_ngu201=241239, compatibility_ngu002=241240)
output('REGISTERED_JOBS', jobs)
query('SQUEUE', ['squeue', '-j', ','.join(str(j) for j in jobs.values()), '-o',
                 '%.24i %.10T %.12M %.6C %.16b %.30R'])
query('SACCT', ['sacct', '-X', '-j', ','.join(str(j) for j in jobs.values()),
               '-n', '-P', '-o', 'JobID,State,ExitCode,Elapsed,Start,End,NodeList'])
query('ALL_PARTITIONS', ['sinfo', '-h', '-o', '%P|%a|%l|%D|%t|%G|%N'])
result = subprocess.run(['sinfo', '-N', '-h', '-O',
    'partitionname:20,nodelist:20,statelong:20,gres:20,gresused:30,cpusstate:22'],
    capture_output=True, text=True, timeout=45)
if result.returncode:
    output('ALL_GPU_NODES', dict(returncode=result.returncode, stdout=result.stdout, stderr=result.stderr))
    raise RuntimeError('Cannot enumerate GPU resources')

def has_accelerator(line):
    fields = line.split()
    if len(fields) < 6:
        raise ValueError('Malformed node inventory row')
    return any(re.fullmatch(r'(?:gpu|dcu):(?:[^:,]+:)?[1-9][0-9]*(?:[(].*[)])?', item)
               for item in fields[3].split(','))

rows = [line for line in result.stdout.splitlines() if has_accelerator(line)]
output('ALL_GPU_NODES', dict(returncode=0, stdout='\n'.join(rows)+'\n', stderr=result.stderr,
       all_node_rows=len(result.stdout.splitlines()), gpu_node_rows=len(rows)))
folder = root / 'control/hybrid_v017_20261014_001'
scheduler_folder = root / 'control/hybrid_v009_20261012_001'
import hashlib
owner = json.loads((folder/'ownership.json').read_text())
assignment_raw=(folder/'assignment.json').read_bytes()
if owner['owner']!='split_local_hpc' or hashlib.sha256(assignment_raw).hexdigest()!=owner['assignment_sha256']:
    raise RuntimeError('Hybrid assignment or owner identity changed')
bridges=json.loads((folder/'deployment_transaction.json').read_text())['entrypoints']
for entry in bridges:
    if hashlib.sha256(Path(entry['path']).read_bytes()).hexdigest()!=entry['new_sha256']:
        raise RuntimeError('Active orchestration bridge changed: '+entry['path'])
output('ACTIVE_ORCHESTRATION',bridges)
output('HYBRID_OWNER',owner)
current=json.loads((folder/'jobs.json').read_text())
output('HYBRID_JOBS',current)
for label,job in dict(train=240076,attacks=240077,report=240078).items():
    result=query('OLD_HELD_JOB_'+label,['scontrol','show','job','-o',str(job)])
    for token in ['JobState=PENDING ','Reason=JobHeldUser ','Priority=0 ',f'Command={root}/control/full_v004/{label}.sbatch ',f'WorkDir={root}/control/continuation_v004 ']:
        if token not in result:raise RuntimeError('Old full-job hold or path identity changed: '+label)
if current:
    ids=','.join(str(j) for j in current.values())
    query('HYBRID_SQUEUE',['squeue','-j',ids,'-o','%.24i %.10T %.12M %.6C %.16b %.40R'])
    query('HYBRID_SACCT',['sacct','-X','-j',ids,'-n','-P','-o','JobID,State,ExitCode,Elapsed,Start,End,NodeList'])
    for label,job in current.items():
        r=subprocess.run(['scontrol','show','job','-o',str(job)],capture_output=True,text=True,timeout=45)
        output('HYBRID_JOB_'+label,dict(returncode=r.returncode,stdout=r.stdout,stderr=r.stderr))
        if r.returncode==0:
            for token in [f'Command={scheduler_folder}/{label}.sbatch ',f'WorkDir={scheduler_folder} ','CPUs/Task=4 ','TresPerNode=gpu:1']:
                if token not in r.stdout:raise RuntimeError('New job identity/resource mismatch: '+label)
            if label in ('train','attacks') and 'ArrayTaskThrottle=1 ' not in r.stdout:raise RuntimeError('Array concurrency changed')
PY
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import json,subprocess
from pathlib import Path
root=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
folder=root/'control/hybrid_v017_20261014_001';scheduler_folder=root/'control/hybrid_v009_20261012_001';execution=root/'execution/hpc_v009'
def emit(label,value):print(label+' '+json.dumps(value),flush=True)
for name in ['submission_attempt.json','jobs.json','ownership.json']:
    path=folder/name;emit('HYBRID_CONTROL',dict(path=str(path),value=json.loads(path.read_text()) if path.exists() else None))
for seed in (100,200,300):
    files=list((execution/f'training/s{seed}').rglob('model_epoch*.pt'))
    emit('HYBRID_TRAINING',dict(seed=seed,checkpoint_count=len(files),complete=(execution/f'training/s{seed}/complete.json').exists(),latest=[dict(path=str(p),bytes=p.stat().st_size,mtime=p.stat().st_mtime) for p in sorted(files,key=lambda q:q.stat().st_mtime)[-3:]]))
for label,pattern in [('attacks','records/attacks/*/*/complete.json'),('clean','records/clean/*/*/complete.json')]:
    files=list(execution.glob(pattern));emit('HYBRID_OUTPUT_METADATA',dict(kind=label,marker_count=len(files),not_full_slot_validation=True))
for p in sorted((folder/'stage_results').glob('*.json'),key=lambda q:q.stat().st_mtime)[-8:]:
    value=json.loads(p.read_text());emit('HYBRID_STAGE',dict(path=str(p),bytes=p.stat().st_size,status=value.get('status'),stage=value.get('stage'),index=value.get('index'),exit_code=value.get('exit_code'),counts=value.get('counts'),failures_count=len(value.get('failures',[])),traceback=value.get('traceback'),global_science_complete=False))
for p in sorted((scheduler_folder/'logs').glob('*'),key=lambda q:q.stat().st_mtime)[-6:]:
    with p.open('rb') as f:
        f.seek(max(0,p.stat().st_size-3500));tail=f.read().decode('utf8',errors='replace')
    emit('HYBRID_LOG',dict(path=str(p),bytes=p.stat().st_size,mtime=p.stat().st_mtime,tail=tail))
PY

/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - <<'PY'
import json,subprocess,hashlib
from pathlib import Path
root=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
f=root/'control/workflow_v010_20261012_001'
t=Path('/data1/home/sunyiq/hydrol85935_temporal_attempts/hpc_v009_001/hydrol85935_temporal_persistence_20261011_001')
def emit(k,v):print(k+' '+json.dumps(v),flush=True)
registry=f/'registration.json'
if not registry.exists():
 emit('WORKFLOW_V010',dict(status='REGISTRATION_NOT_CONFIRMED',folder=str(f)))
else:
 reg=json.loads(registry.read_text());emit('WORKFLOW_V010',reg)
 jobs=[('endpoint_export',reg['export_job'],f/'export.sbatch')]
 for p in sorted((t/'control/submissions').glob('*.json')):
  if '.attempt.' in p.name:continue
  data=json.loads(p.read_text())
  if 'job_id' not in data:continue
  emit('TEMPORAL_SUBMISSION',data)
  jobs.append(('temporal_'+data['stage'],data['job_id'],p.with_suffix('.sbatch')))
 for name,jid,script in jobs:
  r=subprocess.run(['scontrol','show','job','-o',str(jid)],capture_output=True,text=True,timeout=45)
  emit('WORKFLOW_JOB',dict(name=name,job_id=jid,returncode=r.returncode,stdout=r.stdout,stderr=r.stderr))
  if r.returncode==0:
   for token in [f'Command={script} ','CPUs/Task=4 ','TresPerNode=gpu:1'] + (['WorkDir=/data1/home/sunyiq/hpc_mailbox '] if jid in (241344,241345) else []):
    if token not in r.stdout:raise RuntimeError('Registered workflow identity changed: '+name+' '+token)
   if name.startswith('temporal_main') and 'ArrayTaskThrottle=1 ' not in r.stdout:raise RuntimeError('Temporal concurrency changed')
  a=subprocess.run(['sacct','-X','-j',str(jid),'-n','-P','-o','JobID,State,ExitCode,Elapsed,Start,End,NodeList'],capture_output=True,text=True,timeout=45)
  emit('WORKFLOW_ACCOUNTING',dict(name=name,job_id=jid,returncode=a.returncode,stdout=a.stdout,stderr=a.stderr))
 for p in [root/'control/hybrid_v017_20261014_001/hpc_packet_001/index.json',t/'control/parent_binding_v010.json',t/'control/new_models_verified.json',t/'control/resource_pilot.json',t/'reports/coverage_and_summary.json']:
  if p.is_file():emit('WORKFLOW_RESULT',dict(path=str(p),sha256=hashlib.sha256(p.read_bytes()).hexdigest(),value=json.loads(p.read_text())))
PY
