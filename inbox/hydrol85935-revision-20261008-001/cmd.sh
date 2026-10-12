#!/usr/bin/env bash
set -eo pipefail
ROOT=/data1/home/sunyiq/hydrol85935_revision_20261008_001
FOLDER=/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v009_20261012_001
PAYLOAD="$HOME/hpc_mailbox/inbox/hydrol85935-revision-20261008-001/payload/hybrid_v009_20261012_001.tar.gz"
test "$(readlink -f "$ROOT")" = "$ROOT"
test "$(cat "$ROOT/OWNER")" = hydrol85935_revision_20261008_001
test ! -e "$FOLDER"
test ! -e "$ROOT/execution/hpc_v009"
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python - "$PAYLOAD" <<'PY'
import hashlib,json,sys,tarfile,subprocess
from pathlib import Path
root=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001');folder=Path('/data1/home/sunyiq/hydrol85935_revision_20261008_001/control/hybrid_v009_20261012_001');payload=Path(sys.argv[1])
assert hashlib.sha256(payload.read_bytes()).hexdigest()=='68ad28fca0eec29807a9e415ed8001eec9f92ca43e75c5506b6c916e7c739e20'
expected={'train':240076,'attacks':240077,'report':240078}
assert json.loads((root/'control/full_v004/jobs.json').read_text())==expected
before={}
for name,jid in expected.items():
 r=subprocess.run(['scontrol','show','job','-o',str(jid)],capture_output=True,text=True,timeout=30);assert r.returncode==0
 s=r.stdout
 for token in [f'JobId={jid} ', 'JobState=PENDING ', 'Priority=0 ', 'Reason=JobHeldUser ', 'RunTime=00:00:00 ', f'Command={root}/control/full_v004/{name}.sbatch ',f'WorkDir={root}/control/continuation_v004 ']:assert token in s,token
 before[name]=s
assert not list((root/'execution/v004/training').glob('s*/complete.json'))
assert not list((root/'execution/v004/training').rglob('model_epoch*.pt'))
folder.mkdir();(folder/'logs').mkdir();(folder/'stage_results').mkdir()
with tarfile.open(payload,'r:gz') as t:
 for member in t.getmembers():
  assert member.isfile() and len(Path(member.name).parts)==1
  with (folder/member.name).open('xb') as f:f.write(t.extractfile(member).read())
for line in (folder/'FILES.sha256').read_text().splitlines():
 expected_hash,name=line.split(None,1);assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==expected_hash
assignment=json.loads((folder/'assignment.json').read_text())
assert hashlib.sha256((folder/'assignment.json').read_bytes()).hexdigest()=='b044450cc6a5ab723c7b470423d0dedb0b581d7f6e00efd53f07fb9613068c6c'
for name,index in [('local_cpu_partial_20261012_001',0),('local_gpu_partial_20261012_001',1)]:
 old=json.loads((root/'control'/name/'ownership.json').read_text())
 assert old['owner']=='local' and old['assignment_sha256']==assignment['local_assignments'][index]['sha256']
owner=dict(owner='split_local_hpc',version='hybrid_v009_20261012_001',assignment_sha256='b044450cc6a5ab723c7b470423d0dedb0b581d7f6e00efd53f07fb9613068c6c',old_jobs_remain_held=expected,
           local_reserved_attacks=550,hpc_reserved_attacks=27062,local_training=False,hpc_training_seeds=[100,200,300],
           hpc_max_gpus=1,hpc_max_cpu_cores=4,local_max_gpus=1,local_max_cpu_cores=4,other_experiments_modified=False)
(folder/'ownership.json').write_text(json.dumps(owner,indent=2));(folder/'old_jobs_before.json').write_text(json.dumps(before,indent=2))
print('SPLIT_OWNERSHIP '+json.dumps(owner),flush=True)
PY
cd "$FOLDER"
/data1/home/sunyiq/miniconda3/envs/nh_final/bin/python "$FOLDER/submit.py"
