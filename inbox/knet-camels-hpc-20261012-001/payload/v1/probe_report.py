"""Compute-node import probe. Produces zero trajectories and optimizer updates."""
import datetime
import hashlib
import importlib.metadata
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

TASK_ROOT = Path(__file__).resolve().parent
TEMPLATE = TASK_ROOT / 'template'
job = os.environ.get('SLURM_JOB_ID', '')
if not job.isdigit():
    raise RuntimeError('SLURM compute job required')
spec = importlib.util.spec_from_file_location('safe_io', TEMPLATE / 'safe_io.py')
s = importlib.util.module_from_spec(spec)
sys.modules['safe_io'] = s
spec.loader.exec_module(s)
manifest = json.loads(s.read_checked(TEMPLATE / 'bundle_manifest.json'))
for row in manifest['files']:
    p = TEMPLATE / row['path']
    s.read_checked(p, row['sha256'])
child = subprocess.run([sys.executable, '-u', '-B', str(TEMPLATE / 'recipe/hpc_worker.py'), 'imports', '04105700'],
                       cwd=str(TEMPLATE), capture_output=True, text=True, timeout=180)
print(child.stdout, end='', flush=True)
print(child.stderr, end='', file=sys.stderr, flush=True)
result = {'status': 'PASS' if child.returncode == 0 else 'FAILED', 'job_id': job,
          'node': os.uname().nodename, 'completed_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
          'exit_code': child.returncode, 'scientific_forwards': 0, 'optimizer_updates': 0,
          'payload_files_verified': len(manifest['files']), 'scientific_source_files_byte_identical': manifest['scientific_source_files_byte_identical'],
          'versions': {key: importlib.metadata.version(key) for key in ('torch', 'numpy', 'pandas', 'scipy', 'psutil')},
          'worker_stdout': child.stdout, 'worker_stderr': child.stderr}
path = TASK_ROOT / 'receipts' / ('compatibility_probe_' + job + '.json')
with path.open('x', encoding='utf-8') as handle:
    json.dump(result, handle, ensure_ascii=False, indent=2)
print(json.dumps(result), flush=True)
raise SystemExit(child.returncode)
