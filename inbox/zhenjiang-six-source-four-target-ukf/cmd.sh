#!/usr/bin/env bash
set -eo pipefail
source /data1/home/sunyiq/miniconda3/etc/profile.d/conda.sh
conda activate nh_final
set -u
export PYTHONDONTWRITEBYTECODE=1
export CUDA_VISIBLE_DEVICES=""
export OMP_NUM_THREADS=4
export MKL_NUM_THREADS=4
python -B - <<'FORMAL007_DEPLOY'
import datetime,hashlib,io,json,pathlib,subprocess,tarfile
inbox=pathlib.Path('inbox/zhenjiang-six-source-four-target-ukf')
sequence=int((inbox/'seq').read_text());assert sequence==582
raw=(inbox/f'payload_complete_comparison_20261006_{sequence}.tar.gz').read_bytes()
assert hashlib.sha256(raw).hexdigest()=='bc7ba074d6afc15a1891dd97d0769d3db1c0f182b843044450b23333c10ba7f8'
root=pathlib.Path('/data1/home/sunyiq/zhenjiang_complete_comparison_20261017_sqrt_recovery_001');assert not root.exists(),'preserve existing root; read-only reconciliation required'
with tarfile.open(fileobj=io.BytesIO(raw),mode='r:gz') as archive:
    members=archive.getmembers();assert len(members)==64 and all(m.isfile() for m in members)
    assert len({m.name for m in members})==len(members)
    for member in members:
        relative=pathlib.PurePosixPath(member.name)
        assert not relative.is_absolute() and '..' not in relative.parts
        assert root in (root/member.name).resolve().parents
    content={m.name:archive.extractfile(m).read() for m in members}
manifest=json.loads(content['release_manifest.json'])
assert hashlib.sha256(content['release_manifest.json']).hexdigest()=='56348aa43addd3001edbd1c52888dea56261c03ee04e75e75a63af513d9c7e61'
assert set(content)==set(manifest['files'])|{'release_manifest.json'}
for name,item in manifest['files'].items():
    assert len(content[name])==item['bytes'] and hashlib.sha256(content[name]).hexdigest()==item['sha256']
intent=json.loads(content['records/covariance_recovery_intent_20261015.json'])
assert intent['recovery_root']==str(root) and intent['source_failed_job']=='243692'
assert intent['source_code_hash']=='4232fbb467341b6332f91e9289cdb975613babb5d29e2079b66d55f7822c3757'
assert intent['recovery_code_hash']==manifest['code_hash']=='00ed010da5b881c4a49e649c3c8ccf5017dd684ed94dfd22fb242c0a3a975c4e'
assert all(hashlib.sha256(pathlib.Path(path).read_bytes()).hexdigest()==expected for path,expected in intent['pinned_source_files'].items())
candidate_path=pathlib.Path(intent['candidate_result_path'])
assert hashlib.sha256(candidate_path.read_bytes()).hexdigest()==intent['candidate_result_sha256']
candidate=json.loads(candidate_path.read_bytes())
assert candidate['status']=='sqrt_gpu_epoch47_and_original2021_passed'
assert candidate['successful_in_memory_batches']==154 and candidate['final_in_memory_optimizer_steps']==[7214]
assert candidate['exit_code']==0 and candidate['source_bytes_unchanged']
assert candidate['original_2021_validation_completed'] and candidate['validation_windows']==7804 and candidate['validation_batches']==488
assert candidate['formal_epochs_added']==0 and not candidate['formal_recovery_confirmed']
assert hashlib.sha256(pathlib.Path(intent['candidate_bootstrap_path']).read_bytes()).hexdigest()==intent['candidate_bootstrap_sha256']
bootstrap=json.loads(pathlib.Path(intent['candidate_bootstrap_path']).read_bytes())
assert bootstrap['original_tests']==39 and bootstrap['candidate_code_hash']==intent['recovery_code_hash']
q=subprocess.run(['squeue','-h','-u','sunyiq','-o','%i|%j|%T|%Z'],capture_output=True,text=True,timeout=30)
assert q.returncode==0,q.stderr
assert not any(line.split('|')[1].startswith(('zj_gru_','zj_sqrt_')) for line in q.stdout.splitlines() if line.strip())
root.mkdir(exist_ok=False)
for name,data in content.items():
    path=root/name;path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('xb') as stream:stream.write(data)
for name in ('logs','runs'):(root/name).mkdir(exist_ok=True)
print(json.dumps({'status':'sqrt_formal_release_deployed','checked_at_beijing':datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).isoformat(),'root':str(root),'code_hash':manifest['code_hash'],'payload_sha256':hashlib.sha256(raw).hexdigest(),'release_manifest_sha256':hashlib.sha256(content['release_manifest.json']).hexdigest(),'files_authenticated':len(manifest['files']),'formal_training_submitted':False,'evaluation_values_read':False},sort_keys=True),flush=True)
FORMAL007_DEPLOY
python -B /data1/home/sunyiq/zhenjiang_complete_comparison_20261017_sqrt_recovery_001/hpc/prepare_sqrt_formal_20261017.py
python -B /data1/home/sunyiq/zhenjiang_complete_comparison_20261017_sqrt_recovery_001/hpc/audit_sqrt_formal_20261017.py
