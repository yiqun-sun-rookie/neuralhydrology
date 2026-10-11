#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
python -B - <<'PY'
import hashlib,io,json,pathlib,subprocess,tarfile
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf');seq=int((inbox/'seq').read_text());assert seq==222
raw=(inbox/('payload_complete_comparison_20261006_'+str(seq)+'.tar.gz')).read_bytes()
assert hashlib.sha256(raw).hexdigest()=='a6941007b5aff979204b2d10e9210c31e4268dbeedc1890a982186572d930ffc'
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_gradient_diagnostic_20261011_001')
assert root.is_dir()
for n in ['records/diagnostic_submission_attempt.json','records/diagnostic_submission_response.json','records/scheduler_jobs.json','hpc/gradient_diagnostic.slurm']:
    if (root/n).exists():raise FileExistsError('prior submission evidence exists: inspect it without repeating ' + n)
assert hashlib.sha256((root/'hpc/submit_gradient_diagnostic_20261011.py').read_bytes()).hexdigest()=='46e7a788f3cc178c3cf5e3f5deb6fe3a1a0fba6b2babec45cbe3deca97bd4b07'
assert hashlib.sha256((root/'hpc/submit_gradient_diagnostic_20261011_v2.py').read_bytes()).hexdigest()=='9a03153d5c906fe0730f32f925329902bfc64f703f8ac7cc304b6f827f6e8d8a'
assert hashlib.sha256((root/'hpc/replay_gradient_diagnostic_20261011.py').read_bytes()).hexdigest()=='7b39e92b45e4f41ec5cb9078dbd885bd2df53e0dd3eaa73cfa1b3f0099d94421'
assert hashlib.sha256((root/'diagnostic_spec.json').read_bytes()).hexdigest()=='91e62243c4d06d4540c2a9ca032ca7288755aed7bad67cbbbf69d8087709d2d1'
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as tar:
    members=tar.getmembers();assert len({m.name for m in members})==len(members)
    for m in members:
        p=pathlib.PurePosixPath(m.name);assert not p.is_absolute() and '..' not in p.parts and m.isfile()
    content={m.name:tar.extractfile(m).read() for m in members}
manifest_raw=content.pop('accounting_fix_manifest.json');manifest=json.loads(manifest_raw)
assert manifest['root']==str(root) and set(content)==set(manifest['files'])
assert set(content)=={'hpc/submit_gradient_diagnostic_20261011_v3.py','records/submission_accounting_format_fix_v3.json','records/no_submission_proof_221.json','records/submission_v3_local_checks.json'}
for n in content:
    if (root/n).exists():raise FileExistsError('new version destination already exists: '+n)
for n,b in content.items():
    identity=manifest['files'][n];assert len(b)==identity['bytes'] and hashlib.sha256(b).hexdigest()==identity['sha256']
spec=json.loads((root/'diagnostic_spec.json').read_text())
p=subprocess.run(['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%N'],capture_output=True,text=True,timeout=30)
assert p.returncode==0
assert not any(line.split('|')[0]==str(spec['source_job']) or line.split('|')[1]==spec['job_name'] for line in p.stdout.splitlines())
for n,b in content.items():
    p=root/n;p.parent.mkdir(parents=True,exist_ok=True)
    with p.open('xb') as f:f.write(b)
with (root/'records/accounting_fix_payload_manifest_v3.json').open('xb') as f:f.write(manifest_raw)
print(json.dumps({'status':'diagnostic_submission_accounting_fix_v3_deployed','root':str(root),'archive_sha256':hashlib.sha256(raw).hexdigest(),'original_submitter_preserved':True,'formal_training_sources_changed':False}),flush=True)
subprocess.run(['python','-B',str(root/'hpc/submit_gradient_diagnostic_20261011_v3.py')],cwd=root,check=True)
PY
