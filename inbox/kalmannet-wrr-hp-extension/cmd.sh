#!/usr/bin/env bash
# READ-ONLY: identify the GPU model/memory on ngu202 (and ngu203) without submitting any job.
# Tries passwordless ssh to the compute node and runs nvidia-smi query only. If ssh is refused, that is the answer.
# Also tests whether other users' pending jobs on hgpu8 are visible to scontrol/sprio. No sbatch/srun/scancel/update.
set -uo pipefail
python3 -I -B - <<'PY'
import base64, datetime, gzip, json, subprocess
LIMIT = 100_000
def run(argv, timeout=40):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False)
        out, err, rc = p.stdout, p.stderr, p.returncode
    except Exception as exc:
        out, err, rc = '', f'{type(exc).__name__}: {exc}', -1
    return {'command': argv, 'returncode': rc, 'stdout': out[:LIMIT], 'stderr': err[:4000]}
q = {}
SSH = ['ssh', '-o', 'BatchMode=yes', '-o', 'ConnectTimeout=10', '-o', 'StrictHostKeyChecking=no']
for node in ['ngu202', 'ngu203', 'ngu201']:
    q[f'ssh_nvidia_smi_{node}'] = run(SSH + [node, 'nvidia-smi', '--query-gpu=index,name,memory.total,driver_version', '--format=csv,noheader,nounits'])
    q[f'ssh_lspci_{node}'] = run(SSH + [node, 'bash', '-lc', 'lspci 2>/dev/null | grep -i -E "nvidia|3d controller" | head -8'])
q['scontrol_show_job_dengc_pending'] = run(['scontrol', 'show', 'job', '224397,224398'])
q['sprio_dengc_pending'] = run(['sprio', '-j', '224397,224398', '-o', '%i|%u|%Y|%A|%Q|%N'])
q['squeue_dengc_pending'] = run(['squeue', '-j', '224397,224398', '-r', '-o', '%i|%u|%T|%r|%Q|%E|%V'])
q['sprio_all_hgpu8_long'] = run(['sprio', '-p', 'hgpu8', '-l'])
q['squeue_retry_now'] = run(['squeue', '-r', '-j', '224389', '-h', '-o', '%i|%T|%r|%Q|%R'])
q['sinfo_hgpu8'] = run(['sinfo', '-N', '-p', 'hgpu8', '-o', '%N|%T|%C|%G|%E'])
report = {'kind': 'READ_ONLY_NGU202_GPU_IDENTITY_PROBE_NOT_ADMISSION',
          'observed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'queries': q, 'new_jobs_submitted': 0, 'jobs_modified_or_cancelled': 0, 'data_or_checkpoint_tensors_loaded': False}
blob = json.dumps(report, sort_keys=True, separators=(',', ':')).encode()
print('NGU202_PROBE_GZIP_BASE64=' + base64.b64encode(gzip.compress(blob, mtime=0)).decode())
for name, item in q.items():
    lines = item['stdout'].rstrip().splitlines()
    print(f'--- {name} rc={item["returncode"]} lines={len(lines)}')
    print('\n'.join(lines[:60]) if lines else '(empty)')
    if item['stderr'].strip():
        print('stderr: ' + item['stderr'].strip()[:500])
PY
