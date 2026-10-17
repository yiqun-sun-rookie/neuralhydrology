#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export CUDA_VISIBLE_DEVICES=""
export OMP_NUM_THREADS=1
export MKL_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
python -B - <<'DEPLOY_SQRT_CPU'
import hashlib,json,os,pathlib,tarfile,subprocess,sys
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_sqrt_covariance_repair_20261017_001')
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf')
sequence=int((inbox/'seq').read_text())
assert sequence==575
payload=inbox/f'payload_complete_comparison_20261006_{sequence}.tar.gz'
assert hashlib.sha256(payload.read_bytes()).hexdigest()=='fcd39b5a971ed5467be714757e702318616ce66aa55c00276851842def6b7f00'
assert not root.exists(), 'existing candidate must be reconciled, never overwritten'
with tarfile.open(payload,'r:gz') as archive:
 members=archive.getmembers()
 assert len(members)==45
 assert all(m.isfile() and not pathlib.PurePosixPath(m.name).is_absolute() and '..' not in pathlib.PurePosixPath(m.name).parts for m in members)
 root.mkdir(exist_ok=False)
 for member in members:
  target=root/member.name;target.parent.mkdir(parents=True,exist_ok=True)
  with target.open('xb') as stream:stream.write(archive.extractfile(member).read())
manifest=json.loads((root/'package_manifest.json').read_bytes())
assert all(hashlib.sha256((root/name).read_bytes()).hexdigest()==entry['sha256'] for name,entry in manifest['files'].items())
print(json.dumps({'status':'sqrt_isolated_candidate_deployed','root':str(root),'package_manifest_sha256':hashlib.sha256((root/'package_manifest.json').read_bytes()).hexdigest(),'gpu_submissions':0,'formal_epochs_added':0}),flush=True)
(root/'records').mkdir()
p=subprocess.run([sys.executable,'-B',str(root/'hpc/check_stored_operands.py')],cwd=root,capture_output=True,text=True,timeout=1500)
with (root/'records/stored_operand_cpu_process.json').open('x') as stream:json.dump({'returncode':p.returncode,'stdout':p.stdout,'stderr':p.stderr},stream,sort_keys=True)
if p.stdout:print(p.stdout,flush=True)
if p.returncode:
 print(json.dumps({'status':'sqrt_CPU_error_preserved','root':str(root),'returncode':p.returncode,'stderr':p.stderr,'formal_epochs_added':0}),flush=True)
 raise SystemExit(p.returncode)
DEPLOY_SQRT_CPU
