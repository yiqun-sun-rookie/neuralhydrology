#!/usr/bin/env bash
# Short scheduler allocations for GPU metadata only; no model/data/training.
set -euo pipefail
python3 -I -B - <<'PY'
import base64
import datetime
import gzip
import json
import os
import pathlib
import subprocess

root = pathlib.Path('/data1/home/sunyiq/kalmannet_wrr_model_selection_20260908/resource_recovery_20260909')
assert root.parent.is_dir() and root.parent.resolve() == root.parent
assert not os.path.lexists(root), 'Hardware probe already claimed; inspect previous outputs'
root.mkdir()
intent = {'purpose': 'GPU metadata only for authorized 12 B memory retries',
          'started_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'partitions': ['hgpu4', 'hgpu8', 'hgpu2'], 'training_runs': 0}
with (root / 'HARDWARE_PROBE_INTENT.json').open('x') as stream:
    json.dump(intent, stream, indent=2)
probe = '''import json,os,platform,subprocess
import torch
print(json.dumps({'job_id':os.environ.get('SLURM_JOB_ID'),'node':platform.node(),'partition':os.environ.get('SLURM_JOB_PARTITION'),'cuda_visible_devices':os.environ.get('CUDA_VISIBLE_DEVICES'),'gpu':torch.cuda.get_device_name(0),'total_memory_bytes':torch.cuda.get_device_properties(0).total_memory,'torch_version':torch.__version__,'cuda_version':torch.version.cuda,'cudnn_version':torch.backends.cudnn.version(),'host_memory':next(line.strip() for line in open('/proc/meminfo') if line.startswith('MemTotal:')),'nvidia_smi':subprocess.check_output(['nvidia-smi','--query-gpu=index,name,memory.total,driver_version','--format=csv,noheader,nounits'],text=True),'training_started':False}))'''
results = []
for partition in intent['partitions']:
    argv = ['srun', '--immediate=15', '--time=00:02:00', '--partition=' + partition,
            '--nodes=1', '--ntasks=1', '--cpus-per-task=1', '--gres=gpu:1',
            '--job-name=ngf-memory-hardware',
            '/data1/home/sunyiq/miniconda3/envs/knet_clean/bin/python', '-I', '-B', '-c', probe]
    response = subprocess.run(argv, capture_output=True, text=True, check=False)
    row = {'command': argv, 'returncode': response.returncode,
           'stdout': response.stdout, 'stderr': response.stderr,
           'finished_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
    results.append(row)
    with (root / ('HARDWARE_' + partition + '.json')).open('x') as stream:
        json.dump(row, stream, indent=2)
report = {'kind': 'ALTERNATIVE_GPU_HARDWARE_PROBE', 'root': str(root), 'queries': results,
          'training_runs_started': 0, 'data_or_checkpoint_tensors_loaded': False,
          'observed_at_utc': datetime.datetime.now(datetime.timezone.utc).isoformat()}
blob = json.dumps(report, sort_keys=True, separators=(',', ':')).encode()
with (root / 'HARDWARE_PROBE_RESULT.json').open('x') as stream:
    json.dump(report, stream, indent=2)
print('HARDWARE_PROBE_GZIP_BASE64=' + base64.b64encode(gzip.compress(blob, mtime=0)).decode())
print('HARDWARE_PROBE_SUMMARY=' + json.dumps({'returncodes': [r['returncode'] for r in results], 'training_runs_started': 0}))
PY
