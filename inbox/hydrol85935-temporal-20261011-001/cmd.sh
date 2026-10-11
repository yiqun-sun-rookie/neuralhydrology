#!/bin/bash
set -eo pipefail
export PYTHONDONTWRITEBYTECODE=1
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B - <<'PY'
from pathlib import Path, PurePosixPath
import datetime, hashlib, json, os, re, shutil, subprocess, tarfile
root=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001')
addon=Path('/data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001')
cont=root/'control/continuation_v004'
version=root/'versions/v004'
full=root/'control/full_v004'
validation=root/'control/runtime_revalidation_v004'
python='/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python'
payload=Path('/data1/home/sunyiq/hpc_mailbox/inbox/hydrol85935-temporal-20261011-001/payload/acceptance_v004_37f5f046b62a.tar.gz')
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1048576), b''):h.update(b)
    return h.hexdigest()
def check_manifest(folder,name):
    for line in (folder/name).read_text().splitlines():
        expected,rel=line.split(None,1)
        p=(folder/rel.lstrip('*')).resolve(strict=True)
        assert p.is_relative_to(folder.resolve()) and sha(p)==expected, str(p)
def extract(path, target, overlay=False):
    with tarfile.open(path) as archive:
        for m in archive.getmembers():
            assert m.isfile() and not PurePosixPath(m.name).is_absolute()
            p=target/m.name
            assert p.resolve().is_relative_to(target.resolve())
            p.parent.mkdir(parents=True,exist_ok=True)
            with p.open('wb' if overlay else 'xb') as out:out.write(archive.extractfile(m).read())
for owned in [root,addon]:
    assert owned.resolve(strict=True)==owned and (owned/'OWNER').read_text().strip()==owned.name
assert sha(payload)=='37f5f046b62a0a39b7775f2fb47ae8ab68feb42bb6294fe6da7b9f209e4a6f71'
assert sorted(p.name for p in (root/'versions').iterdir() if re.fullmatch(r'v\d{3}',p.name))==['v001','v002','v003']
assert not (root/'control/full_v003/jobs.json').exists()
assert not (root/'execution/v003').exists()
assert not (root/'control/formal_v003_attempt.json').exists()
assert not (addon/'control/submissions').exists() and not (addon/'frozen').exists()
assert not (addon/'versions/v002').exists()
for p in [cont,version,full,validation,root/'preflight/v004',root/'execution/v004',root/'diagnostics/accepted_runtime_v004_20261011']:
    assert not p.exists(), 'Preserve existing attempt: '+str(p)
old_status=json.loads((root/'control/continuation_v003/status.json').read_text())
assert old_status['phase']=='STOPPED_WITHOUT_RETRY'
pid=int((root/'control/continuation_v003/coordinator_pid').read_text())
try:os.kill(pid,0)
except ProcessLookupError:pass
else:raise RuntimeError('Previous coordinator PID is alive; no new submission')
check_manifest(root/'versions/v003','CODE.sha256')
check_manifest(root/'control/full_v003','FULL.sha256')
inventory=json.loads((addon/'deployment_manifest.json').read_text())
for rel,expected in inventory['sha256'].items():assert sha(addon/rel)==expected
protected=[root/'versions/v003/CODE.sha256',root/'control/full_v003/FULL.sha256',root/'control/continuation_v003/status.json',root/'diagnostics/matched_runtime_20261009/summary.json',addon/'deployment_manifest.json']
before={str(p):sha(p) for p in protected}
cont.mkdir();extract(payload,cont);check_manifest(cont,'RECOVERY.sha256')
assert sha(cont/'authorization.json')=='42bdfc07c8429c276bcadfece20d1ddb217bd5d4862ddf2c2ee4114449437842'
version.mkdir();shutil.copytree(root/'versions/v003/code',version/'code')
extract(cont/'runner_v004.tar.gz',version,overlay=True);check_manifest(version,'CODE.sha256')
full.mkdir();extract(cont/'full_v004.tar.gz',full);check_manifest(full,'FULL.sha256')
new_controller=addon/'versions/v002';new_controller.mkdir(parents=True)
shutil.copyfile(cont/'temporal_advance_v002.py',new_controller/'advance.py')
shutil.copyfile(cont/'authorization.json',new_controller/'authorization.json')
shutil.copyfile(cont/'controller_manifest.json',new_controller/'controller_manifest.json')
for name,expected in json.loads((new_controller/'controller_manifest.json').read_text())['sha256'].items():assert sha(new_controller/name)==expected
assert before=={str(p):sha(p) for p in protected}
validation.mkdir()
attempt={'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'version':'v004','authorization_sha256':sha(cont/'authorization.json'),'script_sha256':sha(cont/'revalidation.sbatch'),'protected_before_sha256':before}
with (validation/'attempt.json').open('x') as f:json.dump(attempt,f,indent=2)
try:
    result=subprocess.run(['sbatch',str(cont/'revalidation.sbatch')],capture_output=True,text=True,timeout=120)
except subprocess.TimeoutExpired as error:
    with (validation/'submission_uncertain.json').open('x') as f:json.dump({'error':'timeout','stdout':str(error.stdout),'stderr':str(error.stderr)},f)
    raise
output=result.stdout+result.stderr
(validation/'submission.txt').write_text(output)
jobs=re.findall(r'(?m)^Submitted batch job ([0-9]+)$',output)
assert result.returncode==0 and len(jobs)==1, 'Unconfirmed submission; do not repeat: '+output
with (validation/'job_id').open('x') as f:f.write(jobs[0]+'\n')
with (cont/'coordinator.log').open('xb') as log:
    child=subprocess.Popen([python,'-u',str(cont/'continue_after_runtime.py')],stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,start_new_session=True,env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1'))
with (cont/'coordinator_pid').open('x') as f:f.write(str(child.pid)+'\n')
receipt=dict(status='REVALIDATION_SUBMITTED_WITH_FINITE_CONTINUATION',version='v004',job_id=int(jobs[0]),coordinator_pid=child.pid,acceptance_tolerance=0.0001,policy_sha256=sha(cont/'authorization.json'),previous_evidence_preserved=True,temporal_controller='versions/v002/advance.py',max_simultaneous_gpus=1,cpu_cores=4)
with (cont/'deployment_receipt.json').open('x') as f:json.dump(receipt,f,indent=2)
print(json.dumps(receipt),flush=True)

PY
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python -B /data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001/versions/v002/advance.py --root /data1/home/sunyiq/hydrol85935_temporal_persistence_20261011_001 --parent /data1/home/sunyiq/hydrol85935_revision_20261008_001 --version v004
