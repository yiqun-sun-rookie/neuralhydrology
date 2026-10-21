"""Read-only export of four already-produced files; never run a scientific model."""
from pathlib import Path
import sys,json,hashlib,tarfile,io,base64
ROOT=Path('/data1/home/sunyiq/knet_camels_hpc_20261012_001/attempts/knet_baseline_20261021_001')
sys.dont_write_bytecode=True;sys.path.insert(0,str(ROOT));import safe_io as s
identity=json.loads(s.read_checked(ROOT/'execution_identity.json'));assert identity['job_id']=='245934' and identity['submission_count']==1
raw_result=s.read_checked(ROOT/'runs/02092500/attempt_001/result.json');result=json.loads(raw_result);assert result['status']=='BASELINE_COMPLETE' and result['job_id']==identity['job_id']
stream=io.BytesIO();rows=[]
with tarfile.open(fileobj=stream,mode='w:gz') as tar:
    for label in ['HBV','UKF_sampling','UKF_backprop','KNet_selected']:
        expected=result['trajectories'][label]['arrays'];rel=f'runs/02092500/attempt_001/{label}/evaluation.npz';assert expected['path']==rel
        raw=s.read_checked(ROOT/rel,expected['sha256']);assert len(raw)==expected['bytes']
        entry=tarfile.TarInfo(rel);entry.size=len(raw);entry.mtime=0;tar.addfile(entry,io.BytesIO(raw));rows.append(expected)
payload=stream.getvalue();meta=dict(job_id=identity['job_id'],bytes=len(payload),sha256=hashlib.sha256(payload).hexdigest(),source_result_sha256=hashlib.sha256(raw_result).hexdigest(),files=rows,new_scientific_calls=0,new_training_calls=0)
print('SUPPLEMENT_MANIFEST='+json.dumps(meta),flush=True)
print('ARTIFACT_ARCHIVE_METADATA='+json.dumps(meta),flush=True)
print('ARTIFACT_ARCHIVE_BASE64='+base64.b64encode(payload).decode(),flush=True)
