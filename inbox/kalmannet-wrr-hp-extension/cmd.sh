#!/usr/bin/env bash
# READ-ONLY: which other nodes could host the 12 A800 retries? Current GPU-node occupancy, GPU types from
# cluster config files (if readable), and our own competing jobs. Query commands only: sinfo/squeue/scontrol show/
# sacct/cat/grep. No sbatch/srun/scancel/scontrol update.
set -uo pipefail
python3 -I -B - <<'PY'
import base64, datetime, gzip, json, os, subprocess

LIMIT = 200_000
def run(argv, timeout=60):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False)
        out, err, rc = p.stdout, p.stderr, p.returncode
    except Exception as exc:
        out, err, rc = '', f'{type(exc).__name__}: {exc}', -1
    return {'command': argv, 'returncode': rc, 'stdout': out[:LIMIT], 'stdout_truncated': len(out) > LIMIT, 'stderr': err[:4000]}

q = {}
q['sinfo_gpu_nodes'] = run(['sinfo', '-a', '-N', '-p', 'hgpu8,hgpu4,hgpu2,hgpu2p', '-o', '%N|%P|%T|%C|%G|%e|%E'])
q['sinfo_gpu_partitions'] = run(['sinfo', '-a', '-s', '-p', 'hgpu8,hgpu4,hgpu2,hgpu2p', '-o', '%P|%a|%l|%F|%G|%N'])
for n in ['ngu202', 'ngu203', 'ngu101', 'ngu102', 'ngu103', 'ngu104']:
    q[f'scontrol_show_node_{n}'] = run(['scontrol', 'show', 'node', n])
q['scontrol_config_gres'] = run(['bash', '-c', "scontrol show config | grep -iE 'GresTypes|SelectType|SLURM_CONF|PriorityWeight|PriorityMaxAge|PriorityDecay|AccountingStorageTRES|PreemptType'"])
# config files, if readable (most sites allow reading gres.conf / slurm.conf on login nodes)
conf = q['scontrol_config_gres']['stdout']
q['gres_conf'] = run(['bash', '-c', 'for f in /etc/slurm/gres.conf /etc/slurm-llnl/gres.conf /opt/slurm/etc/gres.conf /usr/local/etc/slurm/gres.conf $(dirname "$(scontrol show config 2>/dev/null | awk -F= \'/SLURM_CONF/{gsub(/ /,"",$2);print $2}\')")/gres.conf; do [ -r "$f" ] && { echo "== $f"; cat "$f"; }; done; true'])
q['slurm_conf_gpu_nodes'] = run(['bash', '-c', 'for f in /etc/slurm/slurm.conf /etc/slurm-llnl/slurm.conf /opt/slurm/etc/slurm.conf $(scontrol show config 2>/dev/null | awk -F= \'/SLURM_CONF/{gsub(/ /,"",$2);print $2}\'); do [ -r "$f" ] && { echo "== $f"; grep -iE "NodeName=.*ngu|PartitionName=.*hgpu|Gres|Priority|Preempt" "$f"; }; done; true'])
# occupancy on hgpu4 now: who is running there (sacct -a shows other users' running jobs even if squeue hides them)
q['sacct_running_hgpu4'] = run(['sacct', '-a', '-r', 'hgpu4', '-s', 'RUNNING,PENDING', '-X', '-n', '-P', '--format=JobID,User,State,Start,End,Elapsed,Timelimit,AllocTRES,NodeList,ReqNodes'])
q['sacct_running_hgpu8'] = run(['sacct', '-a', '-r', 'hgpu8', '-s', 'RUNNING,PENDING', '-X', '-n', '-P', '--format=JobID,User,State,Start,End,Elapsed,Timelimit,AllocTRES,NodeList,ReqNodes,Priority'])
q['squeue_self'] = run(['squeue', '-u', 'sunyiq', '-r', '-o', '%i|%j|%P|%T|%M|%l|%b|%N|%r|%Q'])
q['scontrol_show_job_224505'] = run(['scontrol', 'show', 'job', '224505'])
q['sacct_hgpu4_recent'] = run(['sacct', '-a', '-r', 'hgpu4', '-S', '2026-09-09T00:00:00', '-X', '-n', '-P', '--format=JobID,User,State,Start,End,Elapsed,AllocTRES,NodeList'])

report = {'kind': 'READ_ONLY_ALTERNATIVE_NODE_PROBE_NOT_ADMISSION',
          'observed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'queries': q, 'new_jobs_submitted': 0, 'jobs_modified_or_cancelled': 0, 'data_or_checkpoint_tensors_loaded': False}
blob = json.dumps(report, sort_keys=True, separators=(',', ':')).encode()
print('ALT_NODE_PROBE_GZIP_BASE64=' + base64.b64encode(gzip.compress(blob, mtime=0)).decode())
for name, item in q.items():
    body = item['stdout'].rstrip()
    lines = body.splitlines()
    print(f'--- {name} rc={item["returncode"]} lines={len(lines)}')
    print('\n'.join(lines[:80]) if lines else '(empty)')
    if item['stderr'].strip():
        print('stderr: ' + item['stderr'].strip()[:600])
PY
